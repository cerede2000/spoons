------------------------------------------------------------
-- LastWindowQuits Spoon
--
-- Version : 1.7.0
--
-- Ferme automatiquement une application quand sa derniere
-- fenetre est fermee, avec delai, blacklist, pause temporaire
-- et journalisation.
--
-- Interactions :
--
--   Simple clic :
--       ouvre le menu
--
--   Double clic :
--       active / desactive temporairement
--
--   Raccourcis :
--       configurables via bindHotkeys()
--
------------------------------------------------------------


local obj = {}

obj.__index = obj



------------------------------------------------------------
-- METADONNEES
------------------------------------------------------------

obj.name = "LastWindowQuits"

obj.version = "1.7.0"

obj.author = "Benjamin Cerede / OpenAI"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

-- Interrupteur de session. L'etat durable appartient a SpoonManager,
-- qui decide d'appeler start() ou stop() : le dupliquer dans
-- hs.settings ferait deux interrupteurs capables de se contredire.
-- Cette valeur n'est donc pas persistee et repart d'init.lua a chaque
-- demarrage.
obj.enabled = true

obj.quitDelay = 2

obj.scanAfterLaunchDelay = 3

obj.startupGracePeriod = 5

-- Double-clic sur l'icone de la barre des menus : active/desactive.
-- Sans effet quand showMenuBar est false.
obj.doubleClickInterval = 0.25

-- Icone dans la barre des menus. Le menu reste accessible sans icone,
-- via le raccourci "menu" de bindHotkeys() : l'icone n'est qu'une
-- option d'affichage.
obj.showMenuBar = false

-- init.lua fait autorite sur les reglages simples. Sans cela, une
-- valeur figee dans hs.settings lors d'une session precedente gagne
-- pour toujours et la configuration devient decorative.
obj.forceConfiguredSettingsOnStart = true

-- Raccourcis clavier, desactives par defaut. A false, aucun raccourci
-- n'est lie meme si bindHotkeys() en declare : le mapping est memorise
-- et reapplique des la reactivation. Pour n'en desactiver qu'un seul,
-- il suffit de l'omettre du mapping passe a bindHotkeys().
obj.hotkeysEnabled = false

-- Duree de la pause declenchee par le raccourci "pause".
obj.hotkeyPauseDuration = 15 * 60

-- Duree d'affichage du resume d'etat (raccourci "status").
obj.statusAlertDuration = 4

obj.showNotifications = true

obj.verboseLogging = false

obj.logToFile = true

obj.logFile = os.getenv("HOME") .. "/.hammerspoon/LastWindowQuits.log"

obj.maxLogAgeSeconds = 24 * 60 * 60

obj.logCleanupInterval = 60 * 60

obj.useIgnoredBundlesFile = true

obj.ignoredBundlesFile = nil

obj.persistMenuChanges = true

obj.trackOnlyAppsAfterWindowClose = true

obj.windowTransitionFallbackEnabled = true

-- Periode du scan de secours. Le filtre de fenetres couvre deja les
-- creations et fermetures : ce scan ne rattrape que les evenements
-- manques, il n'a pas besoin d'etre rapide.
obj.windowTransitionScanInterval = 5

-- Periode du balayage complet.
--
-- Entre deux balayages, le scan n'interroge que les applications qu'il
-- sait avoir des fenetres : ce sont les seules qui peuvent en perdre
-- la derniere. Les autres sont decouvertes par l'evenement
-- windowCreated, et le balayage complet sert de rattrapage si cet
-- evenement a ete manque.
obj.windowTransitionFullScanInterval = 30

-- Nombre maximum d'applications qu'un seul scan peut condamner.
-- Au-dela, la cause n'est pas l'utilisateur qui ferme des fenetres
-- mais un evenement systeme : le scan renonce au lieu de fermer.
obj.maxSimultaneousScanQuits = 2

-- Suspend la surveillance pendant la veille, le verrouillage et
-- l'economiseur d'ecran. L'API d'accessibilite y devient muette et
-- rend des listes de fenetres vides pour toutes les applications.
obj.suspendOnPowerEvents = true

-- Delai laisse a macOS pour se stabiliser au reveil avant de
-- recompter et de reprendre la surveillance.
obj.wakeGracePeriod = 15

-- Delai avant de recompter les fenetres apres un evenement de retrait.
-- Laisse a macOS le temps de mettre a jour la liste AX.
obj.windowRemovalRecheckDelay = 0.15


obj.blacklistBundleIDs = {}


obj.blacklistAppNames = {
}


obj.backgroundBundleIDs = {
    ["com.apple.controlcenter"] = true,
    ["com.apple.securityagent"] = true,
    ["com.apple.systemevents"] = true,
    ["com.hammerspoon.Hammerspoon"] = true,
}


obj.backgroundAppNames = {
    ["Hammerspoon"] = true,
}



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.windowFilter =
    nil


obj.windowCreatedCallback =
    nil


obj.windowDestroyedCallback =
    nil


obj.windowRejectedCallback =
    nil


obj.windowsChangedCallback =
    nil


obj.appWatcher =
    nil


obj.windowTransitionTimer =
    nil


obj.menuBar =
    nil


obj.hotkeys =
    {}


obj.hotkeyMapping =
    nil


obj.pendingQuits =
    {}


obj.ignoredBundlesFileEntries =
    {}


obj.seenApps =
    {}


obj.windowCounts =
    {}


obj.pendingRecounts =
    {}


obj.running =
    false


obj.powerWatcher =
    nil


obj.powerSuspended =
    false


obj.wakeTimer =
    nil


obj.pausedUntil =
    nil


obj.startedAt =
    nil


obj.clickCount =
    0


obj.clickTimer =
    nil


obj.lastLogCleanupAt =
    0


obj.lastFullScanAt =
    nil


obj.logCleanupInProgress =
    false


obj.settingsKey =
    "LastWindowQuits.settings"



------------------------------------------------------------
-- OUTILS TABLES
------------------------------------------------------------

function obj:sortedKeys(source)

    local keys =
        {}


    for key, value in pairs(source or {}) do

        if value then

            table.insert(
                keys,
                key
            )

        end

    end


    table.sort(keys)


    return keys

end


function obj:trim(value)

    if not value then

        return ""

    end


    return (
        tostring(value)
            :gsub("^%s+", "")
            :gsub("%s+$", "")
    )

end


function obj:defaultIgnoredBundlesFile()

    local source =
        debug.getinfo(1, "S").source or ""


    local spoonDirectory =
        source:match("^@(.+)/[^/]+$")


    if spoonDirectory then

        return spoonDirectory .. "/ignored-bundles.txt"

    end


    return os.getenv("HOME")
        .. "/.hammerspoon/Spoons/LastWindowQuits.spoon/ignored-bundles.txt"

end


function obj:ensureIgnoredBundlesFilePath()

    if not self.ignoredBundlesFile then

        self.ignoredBundlesFile =
            self:defaultIgnoredBundlesFile()

    end


    return self

end


function obj:readIgnoredBundlesFile()

    self:ensureIgnoredBundlesFilePath()


    local entries =
        {}


    local file =
        io.open(
            self.ignoredBundlesFile,
            "r"
        )


    if not file then

        return entries

    end


    for line in file:lines() do

        local value =
            self:trim(
                line:gsub("#.*$", "")
            )


        if value ~= "" then

            entries[value] =
                true

        end

    end


    file:close()


    return entries

end


function obj:writeIgnoredBundlesFile(entries)

    self:ensureIgnoredBundlesFilePath()


    local file =
        io.open(
            self.ignoredBundlesFile,
            "w"
        )


    if not file then

        self:log(
            "Impossible d'ecrire "
            .. tostring(self.ignoredBundlesFile),
            true
        )


        return false

    end


    for _, bundleID in ipairs(self:sortedKeys(entries)) do

        file:write(
            bundleID .. "\n"
        )

    end


    file:close()


    return true

end


function obj:reloadIgnoredBundlesFile()

    if not self.useIgnoredBundlesFile then

        return self

    end


    self:ensureIgnoredBundlesFilePath()


    for bundleID in pairs(self.ignoredBundlesFileEntries or {}) do

        self.blacklistBundleIDs[bundleID] =
            nil

    end


    self.ignoredBundlesFileEntries =
        self:readIgnoredBundlesFile()


    for bundleID in pairs(self.ignoredBundlesFileEntries) do

        self.blacklistBundleIDs[bundleID] =
            true

    end


    self:updateMenuBar()


    self:log(
        "Fichier bundles ignore recharge : "
        .. tostring(self.ignoredBundlesFile),
        true
    )


    return self

end


function obj:addBundleIDToIgnoredFile(bundleID)

    if not bundleID then

        return false

    end


    local entries =
        self:readIgnoredBundlesFile()


    entries[bundleID] =
        true


    if self:writeIgnoredBundlesFile(entries) then

        self:reloadIgnoredBundlesFile()

        return true

    end


    return false

end


function obj:removeBundleIDFromIgnoredFile(bundleID)

    if not bundleID then

        return false

    end


    local entries =
        self:readIgnoredBundlesFile()


    entries[bundleID] =
        nil


    if self:writeIgnoredBundlesFile(entries) then

        self:reloadIgnoredBundlesFile()

        return true

    end


    return false

end


function obj:applyConfiguredSettingDefaults()

    -- Quand la persistance est coupee, hs.settings n'est ni lu ni
    -- ecrit : init.lua est alors la seule source, et il n'y a rien a
    -- realigner.

    if not self.persistMenuChanges
        or not self.forceConfiguredSettingsOnStart then

        return self

    end


    -- Realignement de hs.settings sur la configuration avant toute
    -- lecture. Seules les valeurs simples sont concernees : les listes
    -- se cumulent avec la configuration au lieu de la remplacer, donc
    -- elles restent la propriete de l'utilisateur.

    local stored =
        hs.settings.get(self.settingsKey)


    if type(stored) ~= "table" then

        stored =
            {}

    end


    -- Cle heritee d'une version ou l'etat etait persiste ici.
    stored.enabled =
        nil


    stored.quitDelay =
        self.quitDelay


    stored.verboseLogging =
        self.verboseLogging


    stored.logToFile =
        self.logToFile


    stored.showMenuBar =
        self.showMenuBar


    stored.hotkeysEnabled =
        self.hotkeysEnabled


    stored.windowTransitionFallbackEnabled =
        self.windowTransitionFallbackEnabled


    hs.settings.set(
        self.settingsKey,
        stored
    )


    self:log(
        "Reglages realignes sur la configuration",
        true
    )


    return self

end


function obj:mergePersistentSettings()

    if not self.persistMenuChanges then

        return self

    end


    local settings =
        hs.settings.get(self.settingsKey)


    if type(settings) ~= "table" then

        return self

    end


    if type(settings.quitDelay) == "number" then

        self.quitDelay =
            settings.quitDelay

    end


    if type(settings.verboseLogging) == "boolean" then

        self.verboseLogging =
            settings.verboseLogging

    end


    if type(settings.logToFile) == "boolean" then

        self.logToFile =
            settings.logToFile

    end


    if type(settings.windowTransitionFallbackEnabled) == "boolean" then

        self.windowTransitionFallbackEnabled =
            settings.windowTransitionFallbackEnabled

    end


    if type(settings.showMenuBar) == "boolean" then

        self.showMenuBar =
            settings.showMenuBar

    end


    if type(settings.hotkeysEnabled) == "boolean" then

        self.hotkeysEnabled =
            settings.hotkeysEnabled

    end


    if not self.useIgnoredBundlesFile
        and type(settings.blacklistBundleIDs) == "table" then

        self.blacklistBundleIDs =
            settings.blacklistBundleIDs

    end


    -- Fusion et non remplacement : un nom declare dans init.lua ne doit
    -- pas disparaitre a la premiere sauvegarde faite depuis le menu.

    if type(settings.blacklistAppNames) == "table" then

        for name, value in pairs(settings.blacklistAppNames) do

            if value == true then

                self.blacklistAppNames[name] =
                    true

            end

        end

    end


    return self

end


function obj:savePersistentSettings()

    if not self.persistMenuChanges then

        return self

    end


    local settings = {
        quitDelay = self.quitDelay,
        verboseLogging = self.verboseLogging,
        logToFile = self.logToFile,
        showMenuBar = self.showMenuBar,
        hotkeysEnabled = self.hotkeysEnabled,
        windowTransitionFallbackEnabled = self.windowTransitionFallbackEnabled,
        blacklistAppNames = self.blacklistAppNames,
    }


    if not self.useIgnoredBundlesFile then

        settings.blacklistBundleIDs =
            self.blacklistBundleIDs

    end


    hs.settings.set(
        self.settingsKey,
        settings
    )


    return self

end



------------------------------------------------------------
-- LOG
------------------------------------------------------------

function obj:timestampFromLogLine(line)

    local year,
          month,
          day,
          hour,
          minute,
          second =
        tostring(line or ""):match(
            "^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)"
        )


    if not year then

        return nil

    end


    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    })

end


function obj:cleanLogFile(force)

    if not self.logToFile
        or not self.maxLogAgeSeconds
        or self.maxLogAgeSeconds <= 0
        or self.logCleanupInProgress then

        return self

    end


    local now =
        self:now()


    if force ~= true
        and self.lastLogCleanupAt
        and now - self.lastLogCleanupAt < self.logCleanupInterval then

        return self

    end


    self.lastLogCleanupAt =
        now


    local file =
        io.open(
            self.logFile,
            "r"
        )


    if not file then

        return self

    end


    self.logCleanupInProgress =
        true


    local keepAfter =
        now - self.maxLogAgeSeconds


    local lines =
        {}


    for line in file:lines() do

        local timestamp =
            self:timestampFromLogLine(line)


        if not timestamp
            or timestamp >= keepAfter then

            table.insert(
                lines,
                line
            )

        end

    end


    file:close()


    file =
        io.open(
            self.logFile,
            "w"
        )


    if file then

        for _, line in ipairs(lines) do

            file:write(
                line .. "\n"
            )

        end


        file:close()

    end


    self.logCleanupInProgress =
        false


    return self

end


function obj:log(message, always)

    if always ~= true
        and not self.verboseLogging then

        return

    end


    local line =
        string.format(
            "%s - LastWindowQuits %s - %s",
            os.date("%Y-%m-%d %H:%M:%S"),
            self.version,
            tostring(message)
        )


    print(line)


    if not self.logToFile then

        return

    end


    self:cleanLogFile(false)


    local file =
        io.open(
            self.logFile,
            "a"
        )


    if file then

        file:write(
            line .. "\n"
        )

        file:close()

    end

end


function obj:notify(title, message)

    if not self.showNotifications then

        return

    end


    hs.notify.new({
        title = title,
        informativeText = message,
    }):send()

end



------------------------------------------------------------
-- FORMATAGE
------------------------------------------------------------

function obj:now()

    return hs.timer.secondsSinceEpoch()

end


function obj:formatDuration(seconds)

    seconds =
        math.max(
            0,
            math.floor(seconds or 0)
        )


    if seconds < 60 then

        return tostring(seconds) .. " sec"

    end


    local minutes =
        math.floor(seconds / 60)


    if minutes < 60 then

        return tostring(minutes) .. " min"

    end


    local hours =
        math.floor(minutes / 60)


    local remainingMinutes =
        minutes % 60


    return string.format(
        "%d h %02d min",
        hours,
        remainingMinutes
    )

end


function obj:appDisplayName(appInfo)

    if not appInfo then

        return "Application inconnue"

    end


    return appInfo.name
        or appInfo.bundleID
        or "Application inconnue"

end



------------------------------------------------------------
-- INFORMATIONS APPLICATION
------------------------------------------------------------

-- Libelle destine au journal. Le bundleID est deja en memoire a ce
-- moment-la : l'afficher ne coute rien, et evite d'avoir a le
-- retrouver a la main pour alimenter ignored-bundles.txt.

function obj:appLogLabel(appInfo)

    if not appInfo then

        return "Application inconnue"

    end


    if appInfo.bundleID then

        return (appInfo.name or appInfo.bundleID)
            .. " ["
            .. appInfo.bundleID
            .. "]"

    end


    return appInfo.name
        or "Application inconnue"

end


function obj:appInfoFromWindow(window, appName)

    local application =
        nil


    if window then

        local ok,
              result =
            pcall(
                function()

                    return window:application()

                end
            )


        if ok then

            application =
                result

        end

    end


    local bundleID =
        nil


    local name =
        appName


    if application then

        local refreshed =
            self:appInfoFromApplication(application)


        if refreshed then

            bundleID =
                refreshed.bundleID

            name =
                refreshed.name or name

        end

    end


    return {
        app = application,
        bundleID = bundleID,
        name = name,
    }

end


function obj:appInfoFromApplication(application)

    if not application then

        return nil

    end


    -- Une application peut disparaitre entre l'enumeration et cette
    -- lecture : sans pcall, l'erreur remonterait et interromprait le
    -- scan en cours pour toutes les applications suivantes.

    local ok,
          bundleID =
        pcall(
            function()

                return application:bundleID()

            end
        )


    if not ok then

        bundleID =
            nil

    end


    local okName,
          name =
        pcall(
            function()

                return application:name()

            end
        )


    if not okName then

        name =
            nil

    end


    return {
        app = application,
        bundleID = bundleID,
        name = name,
    }

end


function obj:appInfoFromBundleID(bundleID, name)

    local application =
        nil


    if bundleID then

        application =
            hs.application.get(bundleID)

    end


    if not application
        and name then

        application =
            hs.application.get(name)

    end


    if not application then

        return {
            app = nil,
            bundleID = bundleID,
            name = name,
        }

    end


    return self:appInfoFromApplication(
        application
    )

end


function obj:appKey(appInfo)

    if not appInfo then

        return nil

    end


    return appInfo.bundleID
        or appInfo.name

end


function obj:markSeen(appInfo)

    local key =
        self:appKey(appInfo)


    if key then

        self.seenApps[key] =
            true

    end

end


function obj:hasSeen(appInfo)

    if not self.trackOnlyAppsAfterWindowClose then

        return true

    end


    local key =
        self:appKey(appInfo)


    return key
        and self.seenApps[key] == true

end



------------------------------------------------------------
-- FILTRAGE APPLICATIONS / FENETRES
------------------------------------------------------------

function obj:isPaused()

    return self.pausedUntil
        and self.pausedUntil > self:now()

end


function obj:isInStartupGrace()

    return self.startedAt
        and self.startupGracePeriod
        and self.startupGracePeriod > 0
        and self:now() - self.startedAt < self.startupGracePeriod

end


function obj:pauseFor(seconds)

    self.pausedUntil =
        self:now() + seconds


    self:updateMenuBar()


    self:log(
        "Pause temporaire : "
        .. self:formatDuration(seconds),
        true
    )


    self:notify(
        "Last Window Quits en pause",
        "Reprise dans " .. self:formatDuration(seconds)
    )


    return self

end


function obj:resume()

    self.pausedUntil =
        nil


    self:updateMenuBar()


    self:log(
        "Reprise",
        true
    )


    return self

end


function obj:isAppBlacklisted(appInfo)

    if not appInfo then

        return true

    end


    if appInfo.bundleID
        and self.blacklistBundleIDs[appInfo.bundleID] then

        return true

    end


    if appInfo.name
        and self.blacklistAppNames[appInfo.name] then

        return true

    end


    return false

end


function obj:isBackgroundApp(appInfo)

    if not appInfo then

        return true

    end


    if appInfo.bundleID
        and self.backgroundBundleIDs[appInfo.bundleID] then

        return true

    end


    if appInfo.name
        and self.backgroundAppNames[appInfo.name] then

        return true

    end


    return false

end


function obj:isApplicationAllowed(appInfo)

    if not appInfo then

        return false,
            "application inconnue"

    end


    if self:isAppBlacklisted(appInfo) then

        return false,
            "blacklist"

    end


    if self:isBackgroundApp(appInfo) then

        return false,
            "app de fond exclue"

    end


    return true,
        "eligible"

end


function obj:isCountableWindow(window)

    if not window then

        return false

    end


    local okStandard,
          standard =
        pcall(
            function()

                return window:isStandard()

            end
        )


    if not okStandard
        or standard ~= false then

        return true

    end


    -- Pas standard : soit ce n'est pas une vraie fenetre, soit macOS
    -- lui a retire son subrole parce qu'elle n'est plus visible.
    -- Une fenetre reduite, ou celle d'une application masquee (Cmd+H),
    -- existe toujours et doit rester comptee : sans ce test, une
    -- reduction serait prise pour une fermeture.

    local okRole,
          role =
        pcall(
            function()

                return window:role()

            end
        )


    -- Role illisible : on ne peut pas affirmer que ce n'est pas une
    -- fenetre, donc on la compte. Le doute doit toujours empecher une
    -- fermeture, jamais la provoquer.

    if not okRole then

        return true

    end


    if role ~= "AXWindow" then

        return false

    end


    local okVisible,
          visible =
        pcall(
            function()

                return window:isVisible()

            end
        )


    return okVisible
        and visible == false

end


function obj:isWindowStillPresent(window)

    if not window then

        return false

    end


    local okID,
          id =
        pcall(
            function()

                return window:id()

            end
        )


    if not okID
        or not id then

        return false

    end


    local okApp,
          application =
        pcall(
            function()

                return window:application()

            end
        )


    if not okApp
        or not application then

        return false

    end


    local okWindows,
          windows =
        pcall(
            function()

                return application:allWindows()

            end
        )


    if not okWindows then

        return false

    end


    for _, candidate in ipairs(windows or {}) do

        local okCandidate,
              candidateID =
            pcall(
                function()

                    return candidate:id()

                end
            )


        if okCandidate
            and candidateID == id then

            return true

        end

    end


    return false

end


-- Optimisation pure, sans effet sur ce qui est fermable.
--
-- kind() < 0 : process sans aucune interface possible. Il ne peut pas
-- avoir de fenetre, donc l'interroger coute une requete AX pour un
-- resultat connu d'avance. C'est le meme filtre que hs.window.allWindows.
--
-- Les utilitaires de barre de menus (kind 0) sont bien pris en compte :
-- pour en proteger un, il faut l'ajouter a ignored-bundles.txt, comme
-- n'importe quelle autre application.

function obj:canHaveWindows(application)

    if not application then

        return false

    end


    local ok,
          kind =
        pcall(
            function()

                return application:kind()

            end
        )


    return ok
        and kind ~= nil
        and kind >= 0

end


-- Renvoie nil quand la liste des fenetres n'a pas pu etre obtenue.
-- Rendre 0 dans ce cas confondait "cette application n'a plus de
-- fenetre" avec "je n'ai pas pu savoir" : pendant une mise en veille,
-- l'API d'accessibilite ne repond plus et toutes les applications
-- paraissaient vides. Les appelants doivent traiter nil comme une
-- absence d'information, jamais comme une autorisation de fermer.

function obj:countWindows(application)

    if not application then

        return nil

    end


    local ok,
          windows =
        pcall(
            function()

                return application:allWindows()

            end
        )


    if not ok
        or type(windows) ~= "table" then

        return nil

    end


    local count =
        0


    for _, window in ipairs(windows or {}) do

        if self:isCountableWindow(window) then

            count =
                count + 1

        end

    end


    return count

end


function obj:rememberWindowCount(appInfo, count)

    if count == nil then

        return self

    end


    local key =
        self:appKey(appInfo)


    if key then

        self.windowCounts[key] =
            math.max(
                0,
                count or 0
            )

    end


    return self

end


function obj:windowTransitionScanPeriod()

    local interval =
        tonumber(self.windowTransitionScanInterval) or 1


    return math.max(
        0.5,
        interval
    )

end


function obj:windowTransitionFullScanPeriod()

    local interval =
        tonumber(self.windowTransitionFullScanInterval) or 30


    -- Un balayage complet plus frequent que le scan lui-meme n'aurait
    -- aucun sens : tous les ticks deviendraient complets.

    return math.max(
        self:windowTransitionScanPeriod(),
        interval
    )

end


function obj:isWindowTransitionFallbackEnabled()

    local interval =
        tonumber(self.windowTransitionScanInterval) or 0


    return self.windowTransitionFallbackEnabled == true
        and interval > 0

end


function obj:scanWindowTransitions(initial)

    if not self:isWindowTransitionFallbackEnabled() then

        return self

    end


    if self.powerSuspended then

        return self

    end


    local previousCounts =
        self.windowCounts or {}


    local currentCounts =
        {}


    local dropped =
        {}


    --------------------------------------------------------
    -- Un balayage complet interroge toutes les applications pour
    -- etablir les references. Les ticks intermediaires se limitent a
    -- celles qui ont des fenetres : une application sans fenetre
    -- connue ne peut pas perdre sa derniere, et son apparition est
    -- deja signalee par windowCreated.
    --------------------------------------------------------

    local now =
        self:now()


    local fullScan =
        initial == true
        or self.lastFullScanAt == nil
        or (now - self.lastFullScanAt)
            >= self:windowTransitionFullScanPeriod()


    if fullScan then

        self.lastFullScanAt =
            now

    end


    for _, application in ipairs(hs.application.runningApplications()) do

        local appInfo =
            nil


        local key =
            nil


        if self:canHaveWindows(application) then

            appInfo =
                self:appInfoFromApplication(application)


            key =
                self:appKey(appInfo)


            -- Une application blacklistee ou de fond ne sera jamais
            -- fermee : inutile d'interroger ses fenetres.

            if key
                and not self:isApplicationAllowed(appInfo) then

                key =
                    nil

            end

        end


        if key then

            local previous =
                previousCounts[key]


            --------------------------------------------------
            -- Hors balayage complet, une application sans fenetre
            -- connue n'a rien a nous apprendre : elle ne peut pas
            -- perdre une derniere fenetre qu'elle n'a pas, et son
            -- apparition passe par windowCreated. On garde sa
            -- reference sans payer la requete AX.
            --------------------------------------------------

            if not fullScan
                and (previous == nil or previous == 0) then

                currentCounts[key] =
                    previous

            else

                local count =
                    self:countWindows(application)


                currentCounts[key] =
                    count


                if count == nil then

                    -- Comptage indisponible : on ne conclut rien et
                    -- on conserve le dernier etat connu.

                    currentCounts[key] =
                        previous

                elseif count > 0 then

                    self:markSeen(appInfo)

                    self:cancelPendingQuit(
                        appInfo,
                        "nouvelle fenetre detectee par scan"
                    )

                elseif initial ~= true
                    and previous
                    and previous > 0 then

                    -- Candidat a la fermeture. On ne decide pas ici :
                    -- la decision depend du nombre total de candidats
                    -- de ce scan.

                    table.insert(
                        dropped,
                        appInfo
                    )

                end

            end

        end

    end


    self.windowCounts =
        currentCounts


    -- Plusieurs applications qui perdent toutes leurs fenetres dans le
    -- meme scan, ce n'est pas un utilisateur qui ferme des fenetres :
    -- c'est une mise en veille, un verrouillage, un changement de
    -- session ou une API d'accessibilite momentanement muette. On
    -- renonce, et l'etat recompte sert de nouvelle reference.

    local limit =
        tonumber(self.maxSimultaneousScanQuits) or 2


    if #dropped > limit then

        self:log(
            string.format(
                "Scan ignore : %d applications ont perdu toutes leurs"
                .. " fenetres simultanement (limite %d), cause"
                .. " systeme probable",
                #dropped,
                limit
            ),
            true
        )


        self:notify(
            "Last Window Quits",
            string.format(
                "%d fermetures simultanees ignorees",
                #dropped
            )
        )


        return self

    end


    for _, appInfo in ipairs(dropped) do

        self:scheduleQuit(
            appInfo,
            "derniere fenetre fermee (scan)"
        )

    end


    return self

end



------------------------------------------------------------
-- VEILLE / VERROUILLAGE
------------------------------------------------------------

function obj:suspendForPower(label)

    if self.powerSuspended then

        return self

    end


    self.powerSuspended =
        true


    if self.wakeTimer then

        self.wakeTimer:stop()

        self.wakeTimer =
            nil

    end


    -- Un quit arme juste avant la veille ne doit pas se declencher
    -- pendant celle-ci : au reveil l'utilisateur retrouverait des
    -- applications fermees sans avoir rien fait.

    local cancelled =
        self:cancelAllPendingQuits()


    self:log(
        string.format(
            "Surveillance suspendue (%s), %d quit(s) annule(s)",
            tostring(label),
            cancelled or 0
        ),
        true
    )


    self:updateMenuBar()


    return self

end


function obj:resumeFromPower(label)

    if self.wakeTimer then

        self.wakeTimer:stop()

        self.wakeTimer =
            nil

    end


    -- La liste des fenetres n'est pas fiable immediatement apres un
    -- reveil. On laisse macOS se stabiliser, puis on repart d'un etat
    -- entierement recompte plutot que du dernier connu, qui date
    -- d'avant la veille.

    self.wakeTimer =
        hs.timer.doAfter(
            self.wakeGracePeriod,
            function()

                self.wakeTimer =
                    nil


                self.windowCounts =
                    {}


                self.pendingRecounts =
                    {}


                self.powerSuspended =
                    false


                self:scanWindowTransitions(true)


                self:log(
                    "Surveillance reprise ("
                    .. tostring(label)
                    .. ")",
                    true
                )


                self:updateMenuBar()

            end
        )


    return self

end


function obj:onPowerEvent(event)

    local watcher =
        hs.caffeinate.watcher


    if event == watcher.systemWillSleep
        or event == watcher.screensDidSleep
        or event == watcher.screensDidLock
        or event == watcher.sessionDidResignActive
        or event == watcher.systemWillPowerOff
        or event == watcher.screensaverDidStart then

        return self:suspendForPower(event)

    end


    if event == watcher.systemDidWake
        or event == watcher.screensDidWake
        or event == watcher.screensDidUnlock
        or event == watcher.sessionDidBecomeActive
        or event == watcher.screensaverDidStop then

        return self:resumeFromPower(event)

    end


    return self

end


function obj:createPowerWatcher()

    if self.powerWatcher
        or not self.suspendOnPowerEvents then

        return self

    end


    self.powerWatcher =
        hs.caffeinate.watcher.new(

            function(event)

                self:onPowerEvent(event)

            end

        )


    if self.powerWatcher then

        self.powerWatcher:start()

    end


    return self

end



------------------------------------------------------------
-- QUIT DIFFERE
------------------------------------------------------------

function obj:cancelPendingQuit(appInfo, reason)

    local key =
        self:appKey(appInfo)


    if not key then

        return self

    end


    local pending =
        self.pendingQuits[key]


    if not pending then

        return self

    end


    if pending.timer then

        pending.timer:stop()

    end


    self.pendingQuits[key] =
        nil


    self:log(
        string.format(
            "Quit annule pour %s (%s)",
            self:appDisplayName(appInfo),
            reason or "raison inconnue"
        ),
        true
    )


    self:updateMenuBar()


    return self

end


function obj:cancelPendingQuitForPID(pid)

    if not pid then

        return self

    end


    for key, pending in pairs(self.pendingQuits) do

        if pending.pid == pid then

            if pending.timer then

                pending.timer:stop()

            end


            self.pendingQuits[key] =
                nil


            self:log(
                "Quit annule pour "
                .. tostring(pending.name or key)
                .. " (application terminee)",
                true
            )


            self:updateMenuBar()

        end

    end


    return self

end


function obj:scheduleQuit(appInfo, reason)

    local key =
        self:appKey(appInfo)


    if not key then

        return self

    end


    self:markSeen(appInfo)


    -- Une meme fermeture produit plusieurs evenements : macOS emet
    -- systematiquement windowRejected apres windowDestroyed, et le
    -- scan de secours peut arriver en plus. Replanifier relancerait
    -- le delai depuis zero a chaque fois, donc le quit partirait plus
    -- tard que la valeur configuree.

    if self.pendingQuits[key] then

        self:log(
            string.format(
                "Quit deja arme pour %s, planification ignoree (%s)",
                self:appDisplayName(appInfo),
                reason or "sans raison"
            )
        )


        return self

    end


    if not self.running then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : Spoon arrete",
            true
        )

        return self

    end


    if self.powerSuspended then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : veille ou verrouillage",
            true
        )

        return self

    end


    if not self.enabled then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : Spoon desactive",
            true
        )

        return self

    end


    if self:isPaused() then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : pause temporaire",
            true
        )

        return self

    end


    local allowed,
          allowedReason =
        self:isApplicationAllowed(appInfo)


    if not allowed then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : "
            .. allowedReason,
            true
        )

        return self

    end


    if self:isInStartupGrace() then

        self:log(
            "Pas de quit pour "
            .. self:appDisplayName(appInfo)
            .. " : grace de demarrage",
            true
        )


        return self

    end


    -- Le pid est le seul identifiant encore lisible quand macOS
    -- signale la fin d'une application : on le releve tant qu'elle
    -- est vivante.

    local okPID,
          pid =
        pcall(
            function()

                return appInfo.app
                    and appInfo.app:pid()

            end
        )


    self.pendingQuits[key] =
        {
            bundleID = appInfo.bundleID,
            name = appInfo.name,
            pid = okPID and pid or nil,
            reason = reason,
            startedAt = self:now(),
            timer = hs.timer.doAfter(
                self.quitDelay,
                function()

                    self:confirmAndQuit(
                        appInfo.bundleID,
                        appInfo.name
                    )

                end
            ),
        }


    self:log(
        string.format(
            "Quit programme pour %s dans %s (%s)",
            self:appDisplayName(appInfo),
            self:formatDuration(self.quitDelay),
            reason or "derniere fenetre fermee"
        ),
        true
    )


    self:updateMenuBar()


    return self

end


function obj:confirmAndQuit(bundleID, name)

    local appInfo =
        self:appInfoFromBundleID(
            bundleID,
            name
        )


    local key =
        self:appKey(appInfo)


    if key then

        self.pendingQuits[key] =
            nil

    end


    local application =
        appInfo and appInfo.app


    if not application then

        self:log(
            "Quit ignore pour "
            .. tostring(name or bundleID)
            .. " : app deja fermee",
            true
        )

        self:updateMenuBar()

        return self

    end


    if not self.running
        or self.powerSuspended
        or not self.enabled
        or self:isPaused() then

        self:log(
            "Quit ignore pour "
            .. self:appDisplayName(appInfo)
            .. " : arrete, desactive ou en pause",
            true
        )

        self:updateMenuBar()

        return self

    end


    local allowed,
          allowedReason =
        self:isApplicationAllowed(appInfo)


    if not allowed then

        self:log(
            "Quit ignore pour "
            .. self:appDisplayName(appInfo)
            .. " : "
            .. allowedReason,
            true
        )

        self:updateMenuBar()

        return self

    end


    local count =
        self:countWindows(application)


    if count == nil then

        self:log(
            "Quit ignore pour "
            .. self:appDisplayName(appInfo)
            .. " : comptage des fenetres indisponible",
            true
        )

        self:updateMenuBar()

        return self

    end


    if count > 0 then

        self:log(
            string.format(
                "Quit ignore pour %s : %d fenetre(s) encore ouverte(s)",
                self:appDisplayName(appInfo),
                count
            ),
            true
        )

        self:updateMenuBar()

        return self

    end


    if not self:hasSeen(appInfo) then

        self:log(
            "Quit ignore pour "
            .. self:appDisplayName(appInfo)
            .. " : app jamais vue avec fenetre",
            true
        )

        self:updateMenuBar()

        return self

    end


    local ok,
          result =
        pcall(
            function()

                return application:kill()

            end
        )


    self:log(
        string.format(
            "Quit execute pour %s : %s",
            self:appLogLabel(appInfo),
            tostring(ok and result ~= false)
        ),
        true
    )


    self:updateMenuBar()


    return self

end



------------------------------------------------------------
-- EVENEMENTS
------------------------------------------------------------

function obj:onWindowCreated(window, appName)

    local appInfo =
        self:appInfoFromWindow(
            window,
            appName
        )


    self:markSeen(appInfo)


    if appInfo
        and appInfo.app then

        self:rememberWindowCount(
            appInfo,
            self:countWindows(appInfo.app)
        )

    end


    self:cancelPendingQuit(
        appInfo,
        "nouvelle fenetre"
    )


    self:log(
        "Fenetre creee : "
        .. self:appDisplayName(appInfo)
    )

end


function obj:onWindowRemoved(window, appName, eventLabel, quitReason)

    local appInfo =
        self:appInfoFromWindow(
            window,
            appName
        )


    local key =
        self:appKey(appInfo)


    self:markSeen(appInfo)


    -- Meme cause que dans scheduleQuit : plusieurs evenements pour une
    -- seule fermeture. Un recomptage est deja en vol, les suivants
    -- reliraient la meme liste AX pour rien.

    if key
        and self.pendingRecounts[key] then

        self:log(
            eventLabel
            .. " : "
            .. self:appDisplayName(appInfo)
            .. " (recomptage deja en cours)"
        )


        return

    end


    self:log(
        eventLabel
        .. " : "
        .. self:appDisplayName(appInfo),
        true
    )


    if key then

        self.pendingRecounts[key] =
            true

    end


    hs.timer.doAfter(
        self.windowRemovalRecheckDelay,
        function()

            if key then

                self.pendingRecounts[key] =
                    nil

            end


            local refreshed =
                self:appInfoFromBundleID(
                    appInfo.bundleID,
                    appInfo.name
                )


            if not refreshed
                or not refreshed.app then

                self:log(
                    "Analyse ignoree pour "
                    .. self:appDisplayName(appInfo)
                    .. " : app absente",
                    true
                )

                return

            end


            local count =
                self:countWindows(refreshed.app)


            self:rememberWindowCount(
                refreshed,
                count
            )


            if count == nil then

                self:log(
                    "Analyse ignoree pour "
                    .. self:appDisplayName(refreshed)
                    .. " : comptage des fenetres indisponible",
                    true
                )

            elseif count == 0 then

                self:scheduleQuit(
                    refreshed,
                    quitReason
                    or "derniere fenetre fermee"
                )

            else

                self:log(
                    string.format(
                        "%s conservee : %d fenetre(s) restante(s)",
                        self:appDisplayName(refreshed),
                        count
                    ),
                    true
                )

            end

        end
    )

end


function obj:onWindowDestroyed(window, appName)

    return self:onWindowRemoved(
        window,
        appName,
        "Fenetre fermee",
        "derniere fenetre fermee"
    )

end


function obj:onWindowRejected(window, appName)

    local appInfo =
        self:appInfoFromWindow(
            window,
            appName
        )


    local key =
        self:appKey(appInfo)


    -- Un recomptage deja en vol reglera le cas de cette application :
    -- inutile de parcourir sa liste de fenetres pour savoir si
    -- celle-ci existe encore.

    if key
        and self.pendingRecounts[key] then

        self:log(
            "Fenetre retiree du filtre : "
            .. self:appDisplayName(appInfo)
            .. " (recomptage deja en cours)"
        )


        return self

    end


    -- windowRejected signifie "ne correspond plus au filtre", pas
    -- "fermee" : une reduction, un masquage ou un changement de Space
    -- le declenchent aussi. On ne poursuit que si la fenetre a
    -- reellement disparu de l'application.

    if self:isWindowStillPresent(window) then

        self:log(
            "Fenetre retiree du filtre mais toujours presente : "
            .. self:appDisplayName(appInfo)
        )


        return self

    end


    return self:onWindowRemoved(
        window,
        appName,
        "Fenetre retiree du filtre",
        "derniere fenetre fermee/rejetee"
    )

end


function obj:onApplicationEvent(application, eventType)

    -- A la fin d'une application, macOS ne garantit plus que son pid,
    -- et passe meme un nom nul. Interroger bundleID() ou name() ici
    -- echoue et remplit la console d'erreurs LuaSkin.

    if eventType == hs.application.watcher.terminated then

        local ok,
              pid =
            pcall(
                function()

                    return application
                        and application:pid()

                end
            )


        return self:cancelPendingQuitForPID(
            ok and pid or nil
        )

    end


    -- Activation, masquage, changement de focus : rien a en tirer.
    -- Inutile d'interroger l'application a chaque evenement.

    if eventType ~= hs.application.watcher.launched then

        return self

    end


    local appInfo =
        self:appInfoFromApplication(
            application
        )


    if not appInfo then

        return self

    end


    hs.timer.doAfter(
        self.scanAfterLaunchDelay,
        function()

            local refreshed =
                self:appInfoFromBundleID(
                    appInfo.bundleID,
                    appInfo.name
                )


            if refreshed
                and refreshed.app
                and (self:countWindows(refreshed.app) or 0) > 0 then

                self:markSeen(refreshed)

            end

        end
    )


    return self

end



------------------------------------------------------------
-- CONTROLES
------------------------------------------------------------

function obj:enable()

    self.enabled =
        true


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Active",
        true
    )


    return self

end


function obj:disable()

    self.enabled =
        false


    for _, pending in pairs(self.pendingQuits) do

        if pending.timer then

            pending.timer:stop()

        end

    end


    self.pendingQuits =
        {}


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Desactive",
        true
    )


    return self

end


function obj:toggle()

    if self.enabled then

        return self:disable()

    end


    return self:enable()

end


function obj:setQuitDelay(seconds)

    self.quitDelay =
        math.max(
            0,
            tonumber(seconds) or 2
        )


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Delai de quit : "
        .. self:formatDuration(self.quitDelay),
        true
    )


    return self

end


function obj:cancelAllPendingQuits()

    local count =
        0


    for key, pending in pairs(self.pendingQuits) do

        if pending.timer then

            pending.timer:stop()

        end


        self.pendingQuits[key] =
            nil


        count =
            count + 1

    end


    self:updateMenuBar()


    self:log(
        "Quits en attente annules : "
        .. tostring(count),
        true
    )


    if count > 0 then

        self:notify(
            "Last Window Quits",
            tostring(count) .. " quit(s) annule(s)"
        )

    end


    return count

end


function obj:statusSummary()

    local lines =
        {}


    if not self.enabled then

        table.insert(
            lines,
            "Last Window Quits : desactive"
        )

    elseif self:isPaused() then

        table.insert(
            lines,
            "Last Window Quits : en pause "
            .. self:formatDuration(self.pausedUntil - self:now())
        )

    else

        table.insert(
            lines,
            "Last Window Quits : actif"
        )

    end


    table.insert(
        lines,
        "Delai de quit : "
        .. self:formatDuration(self.quitDelay)
    )


    local pending =
        0


    for _, item in pairs(self.pendingQuits) do

        pending =
            pending + 1


        local remaining =
            math.max(
                0,
                self.quitDelay - (self:now() - item.startedAt)
            )


        table.insert(
            lines,
            "> "
            .. tostring(item.name or item.bundleID)
            .. " dans "
            .. self:formatDuration(remaining)
        )

    end


    if pending == 0 then

        table.insert(
            lines,
            "Aucun quit en attente"
        )

    end


    return table.concat(
        lines,
        "\n"
    )

end


function obj:showStatus()

    hs.alert.show(
        self:statusSummary(),
        self.statusAlertDuration
    )


    return self

end


function obj:addAppToBlacklist(appInfo)

    if not appInfo then

        return self

    end


    if appInfo.bundleID then

        if self.useIgnoredBundlesFile then

            self:addBundleIDToIgnoredFile(
                appInfo.bundleID
            )

        else

            self.blacklistBundleIDs[appInfo.bundleID] =
                true

        end

    elseif appInfo.name then

        self.blacklistAppNames[appInfo.name] =
            true

    end


    self:cancelPendingQuit(
        appInfo,
        "ajout a la blacklist"
    )


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Ajout blacklist : "
        .. self:appDisplayName(appInfo),
        true
    )


    return self

end


function obj:removeBundleIDFromBlacklist(bundleID)

    if self.useIgnoredBundlesFile
        and self.ignoredBundlesFileEntries[bundleID] then

        self:removeBundleIDFromIgnoredFile(
            bundleID
        )

    else

        self.blacklistBundleIDs[bundleID] =
            nil

    end


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Retrait blacklist bundleID : "
        .. tostring(bundleID),
        true
    )


    return self

end


function obj:removeNameFromBlacklist(name)

    self.blacklistAppNames[name] =
        nil


    self:savePersistentSettings()


    self:updateMenuBar()


    self:log(
        "Retrait blacklist app : "
        .. tostring(name),
        true
    )


    return self

end


function obj:addFocusedAppToBlacklist()

    local application =
        hs.application.frontmostApplication()


    if application then

        self:addAppToBlacklist(
            self:appInfoFromApplication(application)
        )

    end


    return self

end


function obj:clearLogFile()

    local file =
        io.open(
            self.logFile,
            "w"
        )


    if file then

        file:write("")

        file:close()

    end


    self:log(
        "Log vide",
        true
    )


    return self

end


function obj:shellQuote(value)

    value =
        tostring(value or "")


    return "'"
        .. value:gsub(
            "'",
            "'\\''"
        )
        .. "'"

end


function obj:openLogFile()

    hs.execute(
        "/usr/bin/open "
        .. self:shellQuote(self.logFile)
    )


    return self

end


function obj:openIgnoredBundlesFile()

    self:ensureIgnoredBundlesFilePath()


    local file =
        io.open(
            self.ignoredBundlesFile,
            "a"
        )


    if file then

        file:close()

    end


    hs.execute(
        "/usr/bin/open "
        .. self:shellQuote(self.ignoredBundlesFile)
    )


    return self

end


function obj:toggleAutoLaunch()

    local current =
        hs.autoLaunch()


    hs.autoLaunch(
        not current
    )


    self:updateMenuBar()


    self:log(
        "Demarrage a l'ouverture de session : "
        .. tostring(not current),
        true
    )


    return self

end



------------------------------------------------------------
-- MENUBAR
------------------------------------------------------------

function obj:menuIcon()

    if not self.enabled then

        return "LWQ off"

    end


    if self:isPaused() then

        return "LWQ pause"

    end


    if next(self.pendingQuits) then

        return "LWQ ..."

    end


    return "LWQ"

end


function obj:updateMenuBar()

    if not self.menuBar then

        return self

    end


    self.menuBar:setTitle(
        self:menuIcon()
    )


    return self

end


function obj:setMenuBarVisible(visible)

    self.showMenuBar =
        visible == true


    -- Recreation complete plutot que returnToMenuBar() : un objet
    -- cree masque, ou remis dans la barre apres retrait, revient sans
    -- son cablage de clic et l'icone est inerte. hs.menubar.new()
    -- suivi de setClickCallback() est le seul etat verifiable.

    if self.menuBar then

        self.menuBar:setMenu(nil)

        self.menuBar:delete()

        self.menuBar =
            nil

    end


    self:createMenuBar()


    self:savePersistentSettings()

    self:updateMenuBar()


    self:log(
        "Icone barre des menus : "
        .. tostring(self.showMenuBar),
        true
    )


    return self

end


function obj:toggleWindowTransitionFallback()

    self.windowTransitionFallbackEnabled =
        not self.windowTransitionFallbackEnabled


    if self.windowTransitionFallbackEnabled then

        self:createWindowTransitionFallback()

    else

        self:stopWindowTransitionFallback()

    end


    self:savePersistentSettings()

    self:updateMenuBar()


    self:log(
        "Surveillance secours fenetres : "
        .. tostring(self.windowTransitionFallbackEnabled),
        true
    )


    return self

end


function obj:appendBlacklistMenu(menu)

    table.insert(
        menu,
        {
            title = "Blacklist",
            disabled = true,
        }
    )


    table.insert(
        menu,
        {
            title = "Ajouter l'app active",
            fn = function()

                self:addFocusedAppToBlacklist()

            end,
        }
    )


    if self.useIgnoredBundlesFile then

        table.insert(
            menu,
            {
                title =
                    "Ouvrir ignored-bundles.txt",
                fn = function()

                    self:openIgnoredBundlesFile()

                end,
            }
        )


        table.insert(
            menu,
            {
                title =
                    "Recharger ignored-bundles.txt",
                fn = function()

                    self:reloadIgnoredBundlesFile()

                end,
            }
        )

    end


    local bundleIDs =
        self:sortedKeys(self.blacklistBundleIDs)


    local names =
        self:sortedKeys(self.blacklistAppNames)


    if #bundleIDs == 0
        and #names == 0 then

        table.insert(
            menu,
            {
                title = "Aucune app blacklistee",
                disabled = true,
            }
        )

    end


    for _, bundleID in ipairs(bundleIDs) do

        table.insert(
            menu,
            {
                title = "Retirer " .. bundleID,
                fn = function()

                    self:removeBundleIDFromBlacklist(bundleID)

                end,
            }
        )

    end


    for _, name in ipairs(names) do

        table.insert(
            menu,
            {
                title = "Retirer " .. name,
                fn = function()

                    self:removeNameFromBlacklist(name)

                end,
            }
        )

    end


    table.insert(
        menu,
        {
            title = "-",
        }
    )

end


function obj:appendDelayMenu(menu)

    table.insert(
        menu,
        {
            title =
                "Delai actuel : "
                .. self:formatDuration(self.quitDelay),
            disabled = true,
        }
    )


    for _, seconds in ipairs({ 0, 1, 2, 5, 10, 30 }) do

        table.insert(
            menu,
            {
                title =
                    "Delai "
                    .. self:formatDuration(seconds),
                checked = self.quitDelay == seconds,
                fn = function()

                    self:setQuitDelay(seconds)

                end,
            }
        )

    end


    table.insert(
        menu,
        {
            title = "-",
        }
    )

end


function obj:appendPendingMenu(menu)

    local hasPending =
        false


    for _, pending in pairs(self.pendingQuits) do

        hasPending =
            true


        local elapsed =
            self:now() - pending.startedAt


        local remaining =
            math.max(
                0,
                self.quitDelay - elapsed
            )


        table.insert(
            menu,
            {
                title =
                    "Quit en attente : "
                    .. tostring(pending.name or pending.bundleID)
                    .. " ("
                    .. self:formatDuration(remaining)
                    .. ")",
                disabled = true,
            }
        )

    end


    if hasPending then

        table.insert(
            menu,
            {
                title = "Annuler les quits en attente",
                fn = function()

                    self:cancelAllPendingQuits()

                end,
            }
        )


        table.insert(
            menu,
            {
                title = "-",
            }
        )

    end

end


function obj:buildMenu()

    local menu =
        {}


    table.insert(
        menu,
        {
            title =
                "LastWindowQuits "
                .. self.version,
            disabled = true,
        }
    )


    if self:isPaused() then

        table.insert(
            menu,
            {
                title =
                    "Pause restante : "
                    .. self:formatDuration(self.pausedUntil - self:now()),
                disabled = true,
            }
        )

    end


    table.insert(
        menu,
        {
            title = "-",
        }
    )


    table.insert(
        menu,
        {
            title = self.enabled and "Desactiver" or "Activer",
            fn = function()

                self:toggle()

            end,
        }
    )


    if self:isPaused() then

        table.insert(
            menu,
            {
                title = "Reprendre maintenant",
                fn = function()

                    self:resume()

                end,
            }
        )

    else

        table.insert(
            menu,
            {
                title = "Pause 15 min",
                fn = function()

                    self:pauseFor(15 * 60)

                end,
            }
        )


        table.insert(
            menu,
            {
                title = "Pause 1 h",
                fn = function()

                    self:pauseFor(60 * 60)

                end,
            }
        )

    end


    table.insert(
        menu,
        {
            title = "-",
        }
    )


    self:appendPendingMenu(menu)

    self:appendDelayMenu(menu)

    self:appendBlacklistMenu(menu)


    table.insert(
        menu,
        {
            title =
                "Surveillance secours fenetres"
                .. " ("
                .. self:formatDuration(self:windowTransitionScanPeriod())
                .. ")",
            checked = self.windowTransitionFallbackEnabled,
            fn = function()

                self:toggleWindowTransitionFallback()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Raccourcis clavier",
            checked = self.hotkeysEnabled,
            fn = function()

                self:toggleHotkeys()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Logs fichier",
            checked = self.logToFile,
            fn = function()

                self.logToFile =
                    not self.logToFile


                self:savePersistentSettings()


                if self.logToFile then

                    self:cleanLogFile(true)

                end


                self:updateMenuBar()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Logs verbeux",
            checked = self.verboseLogging,
            fn = function()

                self.verboseLogging =
                    not self.verboseLogging


                self:savePersistentSettings()


                self:log(
                    "Logs verbeux : "
                    .. tostring(self.verboseLogging),
                    true
                )

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Ouvrir le log",
            fn = function()

                self:openLogFile()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Vider le log",
            fn = function()

                self:clearLogFile()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "-",
        }
    )


    table.insert(
        menu,
        {
            title = "Cacher LWQ dans la barre",
            fn = function()

                self:setMenuBarVisible(false)

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "-",
        }
    )


    table.insert(
        menu,
        {
            title = "Hammerspoon au demarrage",
            checked = hs.autoLaunch(),
            fn = function()

                self:toggleAutoLaunch()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Ouvrir la console Hammerspoon",
            fn = function()

                hs.openConsole()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Recharger Hammerspoon",
            fn = function()

                hs.reload()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Quitter Hammerspoon",
            fn = function()

                local application =
                    hs.application.get("Hammerspoon")


                if application then

                    application:kill()

                end

            end,
        }
    )


    return menu

end


function obj:showMenu()

    if not self.menuBar then

        return

    end


    self.menuBar:setMenu(
        self:buildMenu()
    )


    -- frame() ne repond que si l'objet est dans la barre des menus.
    -- Sans icone, le menu s'ouvre sous le pointeur.

    local frame =
        self.menuBar:frame()


    local point =
        nil


    if frame then

        point =
            {
                x = frame.x,
                y = frame.y + frame.h,
            }

    else

        point =
            hs.mouse.absolutePosition()

    end


    self.menuBar:popupMenu(point)


    hs.timer.doAfter(
        0.1,
        function()

            if self.menuBar then

                self.menuBar:setMenu(nil)

            end

        end
    )

end


function obj:handleMenuBarClick()

    self.clickCount =
        self.clickCount + 1


    if self.clickCount == 1 then

        self.clickTimer =
            hs.timer.doAfter(
                self.doubleClickInterval,
                function()

                    if self.clickCount == 1 then

                        self:showMenu()

                    end


                    self.clickCount =
                        0


                    self.clickTimer =
                        nil

                end
            )


        return

    end


    if self.clickCount >= 2 then

        if self.clickTimer then

            self.clickTimer:stop()

            self.clickTimer =
                nil

        end


        self.clickCount =
            0


        self:toggle()

    end

end


function obj:createMenuBar()

    if self.menuBar then

        self:updateMenuBar()

        return self

    end


    -- new(false) cree un objet masque, absent de la barre des menus
    -- mais utilisable en menu contextuel via popupMenu(). L'icone
    -- n'est donc qu'une option d'affichage, pas une condition d'acces.

    self.menuBar =
        hs.menubar.new(
            self.showMenuBar == true
        )


    if not self.menuBar then

        self:log(
            "ERREUR creation menubar",
            true
        )

        return self

    end


    self:updateMenuBar()


    self.menuBar:setClickCallback(
        function()

            self:handleMenuBarClick()

        end
    )


    return self

end



------------------------------------------------------------
-- WATCHERS
------------------------------------------------------------

function obj:createWindowFilter()

    if self.windowFilter then

        return self

    end


    if hs.window.filter.new then

        self.windowFilter =
            hs.window.filter.new(true)

    else

        self.windowFilter =
            hs.window.filter.default

    end


    self.windowCreatedCallback =
        function(window, appName)

            self:onWindowCreated(
                window,
                appName
            )

        end


    self.windowDestroyedCallback =
        function(window, appName)

            self:onWindowDestroyed(
                window,
                appName
            )

        end


    self.windowRejectedCallback =
        function(window, appName)

            self:onWindowRejected(
                window,
                appName
            )

        end


    self.windowsChangedCallback =
        function()

            self:scanWindowTransitions(false)

        end


    self.windowFilter:subscribe(
        hs.window.filter.windowCreated,
        self.windowCreatedCallback
    )


    self.windowFilter:subscribe(
        hs.window.filter.windowDestroyed,
        self.windowDestroyedCallback
    )


    if hs.window.filter.windowRejected then

        self.windowFilter:subscribe(
            hs.window.filter.windowRejected,
            self.windowRejectedCallback
        )

    end


    if hs.window.filter.windowsChanged then

        self.windowFilter:subscribe(
            hs.window.filter.windowsChanged,
            self.windowsChangedCallback
        )

    end


    return self

end


function obj:createAppWatcher()

    if self.appWatcher then

        return self

    end


    self.appWatcher =
        hs.application.watcher.new(
            function(_, eventType, application)

                self:onApplicationEvent(
                    application,
                    eventType
                )

            end
        )


    self.appWatcher:start()


    return self

end


function obj:createWindowTransitionFallback()

    if not self:isWindowTransitionFallbackEnabled() then

        return self

    end


    if self.windowTransitionTimer then

        return self

    end


    self:scanWindowTransitions(true)


    self.windowTransitionTimer =
        hs.timer.doEvery(
            self:windowTransitionScanPeriod(),
            function()

                self:scanWindowTransitions(false)

            end
        )


    self:log(
        "Surveillance secours fenetres activee toutes les "
        .. self:formatDuration(self:windowTransitionScanPeriod()),
        true
    )


    return self

end


function obj:stopWindowTransitionFallback()

    if self.windowTransitionTimer then

        self.windowTransitionTimer:stop()

        self.windowTransitionTimer =
            nil

    end


    self.windowCounts =
        {}


    return self

end


function obj:primeSeenApps()

    for _, application in ipairs(hs.application.runningApplications()) do

        local appInfo =
            self:appInfoFromApplication(application)


        if appInfo
            and application
            and (self:countWindows(application) or 0) > 0 then

            self:markSeen(appInfo)

        end

    end


    return self

end



------------------------------------------------------------
-- HOTKEYS
------------------------------------------------------------

function obj:hotkeyActions()

    return {

        toggle = function()

            self:toggle()

        end,

        pause = function()

            self:pauseFor(self.hotkeyPauseDuration)

        end,

        resume = function()

            self:resume()

        end,

        menu = function()

            self:showMenu()

        end,

        status = function()

            self:showStatus()

        end,

        blacklist = function()

            self:addFocusedAppToBlacklist()

        end,

        cancel = function()

            self:cancelAllPendingQuits()

        end,

    }

end


function obj:deleteHotkeys()

    for _, hotkey in pairs(self.hotkeys) do

        if hotkey then

            hotkey:delete()

        end

    end


    self.hotkeys =
        {}


    return self

end


function obj:applyHotkeys()

    self:deleteHotkeys()


    if not self.hotkeysEnabled then

        self:log(
            "Raccourcis clavier desactives",
            true
        )


        return self

    end


    if not self.hotkeyMapping then

        return self

    end


    local bound =
        0


    for name, action in pairs(self:hotkeyActions()) do

        local binding =
            self.hotkeyMapping[name]


        if binding
            and binding[1]
            and binding[2] then

            self.hotkeys[name] =
                hs.hotkey.bind(
                    binding[1],
                    binding[2],
                    action
                )


            bound =
                bound + 1

        end

    end


    self:log(
        "Raccourcis clavier lies : "
        .. tostring(bound),
        true
    )


    return self

end


function obj:bindHotkeys(mapping)

    -- Le mapping est memorise et non consomme : desactiver puis
    -- reactiver les raccourcis les relie sans repasser par init.lua.

    self.hotkeyMapping =
        mapping


    return self:applyHotkeys()

end


function obj:setHotkeysEnabled(enabled)

    self.hotkeysEnabled =
        enabled == true


    self:applyHotkeys()


    self:savePersistentSettings()


    self:updateMenuBar()


    if not self.hotkeysEnabled
        and not self.showMenuBar then

        self:log(
            "Raccourcis et icone desactives : le menu n'est plus"
            .. " atteignable. Un rechargement de Hammerspoon"
            .. " retablit la configuration de init.lua.",
            true
        )

    end


    return self

end


function obj:toggleHotkeys()

    return self:setHotkeysEnabled(
        not self.hotkeysEnabled
    )

end



------------------------------------------------------------
-- START / STOP
------------------------------------------------------------

function obj:start()

    self.startedAt =
        self:now()


    self:ensureIgnoredBundlesFilePath()

    self:applyConfiguredSettingDefaults()

    self:mergePersistentSettings()

    -- bindHotkeys() est appele avant start() : on reapplique une fois
    -- les reglages connus, sinon hotkeysEnabled n'aurait aucun effet
    -- au demarrage.
    self:applyHotkeys()

    self:reloadIgnoredBundlesFile()

    self:cleanLogFile(true)

    self:createMenuBar()

    self:createWindowFilter()

    self:createAppWatcher()

    self:createPowerWatcher()

    self:primeSeenApps()

    self:createWindowTransitionFallback()

    self:updateMenuBar()

    self.running =
        true

    self:log(
        "Spoon initialise",
        true
    )

    return self

end


function obj:stop()

    -- Coupe d'abord : des recomptages differes peuvent etre en vol et
    -- armeraient un quit apres l'arret, avec execution quelques
    -- secondes plus tard sur une application qu'on ne surveille plus.

    self.running =
        false


    for _, pending in pairs(self.pendingQuits) do

        if pending.timer then

            pending.timer:stop()

        end

    end


    self.pendingQuits =
        {}


    if self.windowFilter then

        if self.windowCreatedCallback then

            self.windowFilter:unsubscribe(
                self.windowCreatedCallback
            )

        end


        if self.windowDestroyedCallback then

            self.windowFilter:unsubscribe(
                self.windowDestroyedCallback
            )

        end


        if self.windowRejectedCallback then

            self.windowFilter:unsubscribe(
                self.windowRejectedCallback
            )

        end


        if self.windowsChangedCallback then

            self.windowFilter:unsubscribe(
                self.windowsChangedCallback
            )

        end

        self.windowFilter =
            nil

    end


    self.windowCreatedCallback =
        nil


    self.windowDestroyedCallback =
        nil


    self.windowRejectedCallback =
        nil


    self.windowsChangedCallback =
        nil


    if self.appWatcher then

        self.appWatcher:stop()

        self.appWatcher =
            nil

    end


    if self.powerWatcher then

        self.powerWatcher:stop()

        self.powerWatcher =
            nil

    end


    if self.wakeTimer then

        self.wakeTimer:stop()

        self.wakeTimer =
            nil

    end


    self.powerSuspended =
        false


    self:stopWindowTransitionFallback()


    if self.clickTimer then

        self.clickTimer:stop()

        self.clickTimer =
            nil

    end


    -- Sans cela, un arret survenu entre les deux clics laisse le
    -- compteur a 1 : le premier clic suivant serait pris pour le
    -- second d'un double-clic.

    self.clickCount =
        0


    self:deleteHotkeys()


    if self.menuBar then

        self.menuBar:delete()

        self.menuBar =
            nil

    end


    -- Etat transitoire : une pause ou des applications deja vues ne
    -- doivent pas survivre a un arret, sinon le Spoon redemarre en
    -- pause silencieuse ou avec des references perimees.

    self.pausedUntil =
        nil


    self.startedAt =
        nil


    self.seenApps =
        {}


    self.windowCounts =
        {}


    self.pendingRecounts =
        {}


    self:log(
        "Spoon arrete",
        true
    )


    return self

end


return obj
