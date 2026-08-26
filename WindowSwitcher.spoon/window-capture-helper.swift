import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

enum RequestKind: String {
    case capture
    case audio
}

struct CaptureRequest {
    let token: String
    let kind: RequestKind
    let windowID: CGWindowID
    let outputURL: URL?
    let pixelHeight: Int
    let appName: String
    let title: String
}

struct CaptureSession {
    let directory: URL
    let secret: String

    var requestDirectory: URL {
        directory.appendingPathComponent("requests", isDirectory: true)
    }

    var captureDirectory: URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }

    func isPathInsideCaptureDirectory(_ url: URL) -> Bool {
        let capturePath = captureDirectory.standardizedFileURL.path + "/"
        let outputPath = url.standardizedFileURL.path

        return outputPath.hasPrefix(capturePath)
    }
}

@main
@MainActor
final class WindowCaptureHelper: NSObject, NSApplicationDelegate {
    private let session: CaptureSession
    private let fileManager = FileManager.default
    private var timer: Timer?
    private var timerInterval = 0.35
    private var inFlight = Set<String>()
    private var lastActivity = Date()

    private let activePollInterval = 0.05
    private let idlePollInterval = 0.35
    private let idleQuitDelay: TimeInterval = 30

    init(session: CaptureSession) {
        self.session = session
        super.init()
    }

    static func main() {
        let arguments = CommandLine.arguments

        if arguments.count >= 3 && arguments[1] == "--service" {
            let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let secretURL = directory.appendingPathComponent("secret")

            guard let secret = try? String(contentsOf: secretURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  secret.count >= 32
            else {
                fputs("missing capture session secret\n", stderr)
                exit(65)
            }

            let session = CaptureSession(
                directory: directory,
                secret: secret
            )

            runService(session: session)
            return
        }

        fputs("usage: window-capture-helper --service <session-dir>\n", stderr)
        exit(64)
    }

    private static func runService(session: CaptureSession) {
        let app = NSApplication.shared
        let delegate = WindowCaptureHelper(session: session)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createDirectories()
        setPollingInterval(idlePollInterval)
    }

    private func createDirectories() {
        [session.directory, session.requestDirectory, session.captureDirectory].forEach { url in
            try? fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )

            try? fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        }
    }

    private func setPollingInterval(_ interval: TimeInterval) {
        if timer != nil && abs(timerInterval - interval) < 0.001 {
            return
        }

        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.drainRequests()
            }
        }
    }

    private func drainRequests() {
        createDirectories()

        guard let files = try? fileManager.contentsOfDirectory(
            at: session.requestDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let requests = files.filter { $0.pathExtension == "request" }

        if requests.isEmpty {
            if inFlight.isEmpty {
                setPollingInterval(idlePollInterval)

                if Date().timeIntervalSince(lastActivity) > idleQuitDelay {
                    NSApplication.shared.terminate(nil)
                }
            }

            return
        }

        lastActivity = Date()
        setPollingInterval(activePollInterval)

        for requestURL in requests {
            let token = requestURL.deletingPathExtension().lastPathComponent

            if inFlight.contains(token) {
                continue
            }

            let processingURL = session.requestDirectory
                .appendingPathComponent(token)
                .appendingPathExtension("processing")

            do {
                try fileManager.moveItem(at: requestURL, to: processingURL)
            } catch {
                continue
            }

            let parsedRequest = readRequest(processingURL, token: token)


            guard let request = parsedRequest.request else {
                writeStatus(
                    token: token,
                    state: "error",
                    message: parsedRequest.error ?? "bad request"
                )
                try? fileManager.removeItem(at: processingURL)
                lastActivity = Date()
                continue
            }

            // L'inventaire audio ne touche ni ScreenCaptureKit ni le
            // disque : on repond tout de suite, sans passer par une
            // tache asynchrone.
            if request.kind == .audio {
                writeStatus(token: token, state: "ok", message: Self.audioSnapshot())
                try? fileManager.removeItem(at: processingURL)
                lastActivity = Date()
                continue
            }

            inFlight.insert(token)

            Task {
                do {
                    guard let outputURL = request.outputURL else {
                        throw NSError(domain: "WindowCaptureHelper", code: 7,
                                      userInfo: [NSLocalizedDescriptionKey: "missing output path"])
                    }
                    let image = try await Self.capture(request)
                    try Self.writePNG(image, to: outputURL)

                    await MainActor.run {
                        self.writeStatus(token: token, state: "ok", message: "")
                        self.inFlight.remove(token)
                        self.lastActivity = Date()
                        try? self.fileManager.removeItem(at: processingURL)
                    }
                } catch {
                    await MainActor.run {
                        self.writeStatus(
                            token: token,
                            state: "error",
                            message: Self.cleanStatusMessage(String(describing: error))
                        )
                        self.inFlight.remove(token)
                        self.lastActivity = Date()
                        try? self.fileManager.removeItem(at: processingURL)
                    }
                }
            }
        }
    }

    private func readRequest(_ url: URL, token: String) -> (request: CaptureRequest?, error: String?) {
        guard token.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil else {
            return (nil, "bad token")
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, "request unreadable")
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 9 else {
            return (nil, "bad request line count: \(lines.count)")
        }

        guard lines[0] == "4" else {
            return (nil, "bad request version")
        }

        guard lines[1] == token else {
            return (nil, "bad request token")
        }

        guard lines[8] == session.secret else {
            return (nil, "bad request token")
        }

        guard let kind = RequestKind(rawValue: lines[2]) else {
            return (nil, "bad request kind")
        }

        if kind == .audio {
            return (CaptureRequest(
                token: token,
                kind: kind,
                windowID: 0,
                outputURL: nil,
                pixelHeight: 0,
                appName: "",
                title: ""
            ), nil)
        }

        guard let rawWindowID = UInt32(lines[3]) else {
            return (nil, "bad window id")
        }

        guard let pixelHeight = Int(lines[5]) else {
            return (nil, "bad pixel height")
        }

        let outputURL = URL(fileURLWithPath: lines[4])

        guard session.isPathInsideCaptureDirectory(outputURL) else {
            return (nil, "bad output path")
        }

        guard pixelHeight > 0 && pixelHeight <= 1200 else {
            return (nil, "pixel height out of range")
        }

        return (CaptureRequest(
            token: token,
            kind: kind,
            windowID: CGWindowID(rawWindowID),
            outputURL: outputURL,
            pixelHeight: pixelHeight,
            appName: lines[6],
            title: lines[7]
        ), nil)
    }

    private func writeStatus(token: String, state: String, message: String) {
        let cleanMessage = Self.cleanStatusMessage(message)
        let statusText = "4\n\(token)\n\(state)\n\(cleanMessage)\n\(session.secret)\n"
        let statusURL = session.requestDirectory
            .appendingPathComponent(token)
            .appendingPathExtension("status")
        let tmpURL = statusURL
            .deletingLastPathComponent()
            .appendingPathComponent(statusURL.lastPathComponent + ".tmp")

        do {
            try statusText.write(to: tmpURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )

            if fileManager.fileExists(atPath: statusURL.path) {
                try? fileManager.removeItem(at: statusURL)
            }

            try fileManager.moveItem(at: tmpURL, to: statusURL)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
        }
    }

    /// Quels processus produisent du son, et lesquels captent le micro.
    ///
    /// API publique CoreAudio des objets de processus, macOS 14.4+.
    /// Lecture seule : les six proprietes exposees sont informatives, il
    /// n'existe aucune coupure par application dans l'API publique.
    ///
    /// La camera n'a pas d'equivalent : CMIO expose les peripheriques,
    /// pas l'application qui les utilise.
    private static func audioProperty<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ fallback: T
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        var value = fallback

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }

        return value
    }

    private static func audioSnapshot() -> String {
        guard #available(macOS 14.4, *) else { return "out=;in=" }

        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0
        else {
            return "out=;in="
        }

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )

        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
            return "out=;in="
        }

        var playing: [String] = []
        var recording: [String] = []

        for object in objects {
            guard let pid = audioProperty(object, kAudioProcessPropertyPID, pid_t(0)) else {
                continue
            }
            if (audioProperty(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0 {
                playing.append(String(pid))
            }
            if (audioProperty(object, kAudioProcessPropertyIsRunningInput, UInt32(0)) ?? 0) != 0 {
                recording.append(String(pid))
            }
        }

        return "out=\(playing.joined(separator: ","));in=\(recording.joined(separator: ","))"
    }

    private static func cleaned(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanStatusMessage(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(_ request: CaptureRequest) async throws -> CGImage {
        guard #available(macOS 14.0, *) else {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "macOS 14 required"]
            )
        }

        return try await withThrowingTaskGroup(of: CGImage.self) { group in
            group.addTask {
                try await captureWithScreenCaptureKit(request)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw NSError(
                    domain: "WindowCaptureHelper",
                    code: 70,
                    userInfo: [NSLocalizedDescriptionKey: "capture timed out"]
                )
            }

            guard let image = try await group.next() else {
                throw NSError(
                    domain: "WindowCaptureHelper",
                    code: 71,
                    userInfo: [NSLocalizedDescriptionKey: "capture failed"]
                )
            }

            group.cancelAll()
            return image
        }
    }

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit(_ request: CaptureRequest) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        var targetWindow = content.windows.first(where: { $0.windowID == request.windowID })
        let expectedAppName = cleaned(request.appName)
        let expectedTitle = cleaned(request.title)

        // Repli lorsque le windowID n'est plus dans l'inventaire : la
        // fenetre a pu etre recreee entre la demande et la capture.
        //
        // La correspondance est stricte, et les deux champs sont
        // exiges. La version precedente acceptait les correspondances
        // partielles dans les deux sens, avec un titre vide traite
        // comme un joker : une demande pour "mail" sans titre capturait
        // la premiere fenetre d'une application nommee "mailbox", quel
        // que soit son contenu. Un identifiant introuvable devenait
        // ainsi une capture arbitraire.
        if targetWindow == nil, !expectedTitle.isEmpty, !expectedAppName.isEmpty {
            targetWindow = content.windows.first(where: { window in
                cleaned(window.title ?? "") == expectedTitle
                    && cleaned(window.owningApplication?.applicationName ?? "") == expectedAppName
            })
        }

        guard let targetWindow else {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "sck window not found: \(request.windowID), inventory=\(content.windows.count)"
                ]
            )
        }

        let frame = targetWindow.frame

        guard frame.width > 1, frame.height > 1 else {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "window has no usable frame"]
            )
        }

        let height = max(1, min(request.pixelHeight, Int((frame.height * 2).rounded())))
        let width = max(1, Int((Double(height) * frame.width / frame.height).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        if looksUnavailable(image) {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "capture looks unavailable"]
            )
        }

        return image
    }

    private static func looksUnavailable(_ image: CGImage) -> Bool {
        let sampleWidth = min(48, max(1, image.width))
        let sampleHeight = min(48, max(1, image.height))
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var samples = 0
        var brightSamples = 0
        var maxLuminance = 0.0

        stride(from: 0, to: pixels.count, by: bytesPerPixel).forEach { offset in
            let red = Double(pixels[offset]) / 255.0
            let green = Double(pixels[offset + 1]) / 255.0
            let blue = Double(pixels[offset + 2]) / 255.0
            let alpha = Double(pixels[offset + 3]) / 255.0

            guard alpha > 0.05 else {
                return
            }

            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

            samples += 1
            maxLuminance = max(maxLuminance, luminance)

            if luminance > 0.065 {
                brightSamples += 1
            }
        }

        return samples > 0 && brightSamples == 0 && maxLuminance < 0.08
    }

    private static func writePNG(_ image: CGImage, to outputURL: URL) throws {
        let tmpURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(outputURL.lastPathComponent + ".tmp")

        guard let destination = CGImageDestinationCreateWithURL(
            tmpURL as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "png destination failed"]
            )
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(
                domain: "WindowCaptureHelper",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "png encoding failed"]
            )
        }

        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tmpURL.path
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try FileManager.default.moveItem(at: tmpURL, to: outputURL)
    }
}
