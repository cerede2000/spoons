-- WindowSwitcher : cycle de vie du helper, caches, fichiers temporaires.
package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install({ virtualFS = true })
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.verboseLogging = false
obj.showNotifications = false
obj.logScreenCaptureFailures = false

local HELPER = "/fake/WindowSwitcherCapture.app/Contents/MacOS/window-capture-helper"
local APP    = "/fake/WindowSwitcherCapture.app"
obj.screenCaptureHelperPath = HELPER
obj.screenCaptureHelperAppPath = APP
obj.defaultBase = obj.screenCaptureSessionBaseDirectory
obj.screenCaptureSessionBaseDirectory = "/tmp/ws-test"
ctl.files[HELPER] = { data = "", mtime = 1 }
ctl.dirs[APP] = { mtime = 1 }

local helperApp = lib.app(ctl, { name = "WindowSwitcherCapture",
                                bundle = obj.screenCaptureHelperBundleID })

local function descriptor(id, opts)
    opts = opts or {}
    return { id = id, appName = opts.appName or "Safari",
             title = opts.title or "Page", minimized = opts.minimized == true,
             hidden = opts.hidden == true, bundleID = "com.apple.Safari" }
end

local function reset()
    obj.screenCaptureQueue = {}
    obj.queuedScreenCaptures = {}
    obj.runningScreenCaptures = {}
    obj.screenCaptureFailureCache = {}
    obj.snapshotCache = {}
    obj.captureFiles = {}
    obj.screenCaptureDisabledReason = nil
    obj.screenCaptureHelperAppStarted = false
    obj.screenCaptureSessionID = nil
    obj.screenCaptureSessionSecret = nil
    obj.screenCaptureSessionDirectory = nil
    obj.entries = nil
    ctl.launchedApps = {}
    ctl.runningApps = { helperApp }
    helperApp._dead = false
end

------------------------------------------------------------
R.section("Le service est lancé à la première capture")
------------------------------------------------------------
reset()
obj:queueScreenCapture(descriptor(1, { minimized = true }))
R.check("service lancé une fois", #ctl.launchedApps, 1)
R.check("lancé en mode --service", ctl.launchedApps[1][5], "--service")
R.check("une requête est en vol", obj.runningScreenCaptures[1] ~= nil, true)

R.section("Il n'est pas relancé tant qu'il tourne")
obj:queueScreenCapture(descriptor(2, { minimized = true }))
R.check("toujours un seul lancement", #ctl.launchedApps, 1)

------------------------------------------------------------
R.section("Le service qui s'est arrêté seul est relancé")
-- C'est le défaut principal de la 0.8.5 : passé 30 s d'inactivité le
-- helper se termine, mais screenCaptureHelperAppStarted restait vrai
-- pour toujours et les vignettes ne revenaient plus jamais.
------------------------------------------------------------
reset()
obj:queueScreenCapture(descriptor(1, { minimized = true }))
R.check("premier lancement", #ctl.launchedApps, 1)
helperApp._dead = true
ctl.runningApps = {}
obj.runningScreenCaptures = {}
obj.queuedScreenCaptures = {}
obj:queueScreenCapture(descriptor(3, { minimized = true }))
R.check("relancé après extinction du service", #ctl.launchedApps, 2)
R.check("la capture repart", obj.runningScreenCaptures[3] ~= nil, true)

R.section("Un dépassement de délai marque le service comme mort")
reset()
obj:queueScreenCapture(descriptor(4, { minimized = true }))
R.check("marqué démarré", obj.screenCaptureHelperAppStarted, true)
obj.runningScreenCaptures[4].startedAt = 0   -- très ancien
obj:pollScreenCaptureRequests()
R.check("plus considéré comme démarré", obj.screenCaptureHelperAppStarted, false)
R.check("le travail est terminé en échec", obj.runningScreenCaptures[4], nil)
R.check("échec mis en quarantaine", obj.screenCaptureFailureCache[4] ~= nil, true)

R.section("Le délai laisse au service le temps de répondre")
R.check("délai supérieur au timeout interne du helper (5 s)",
    obj.screenCaptureRequestTimeoutSeconds > 5.35, true)

------------------------------------------------------------
R.section("La requête respecte le protocole du helper")
------------------------------------------------------------
reset()
obj:createScreenCaptureSession()
local job = { id = 7, token = "abc", pixelHeight = "420",
              appName = "Mail", title = "Boîte" }
job.outputPath = obj:screenCaptureOutputPath(job)
obj:writeScreenCaptureRequest(job)
local payload = ctl.files[obj:screenCaptureRequestPath(job)].data
local lignes = {}
for l in payload:gmatch("[^\n]*") do table.insert(lignes, l) end
R.check("version 3", lignes[1], "3")
R.check("jeton en deuxième ligne", lignes[2], "abc")
R.check("identifiant de fenêtre", lignes[3], "7")
R.check("secret de session en huitième ligne", lignes[8], obj.screenCaptureSessionSecret)
R.check("le PNG est écrit sous captures/",
    job.outputPath:find(obj:screenCaptureCaptureDirectory(), 1, true) == 1, true)

R.section("Un statut au mauvais secret est refusé")
local statusPath = obj:screenCaptureStatusPath(job)
ctl.files[statusPath] = { data = "3\nabc\nok\n\nmauvais-secret\n", mtime = 1 }
local state, message = obj:readScreenCaptureStatus(job)
R.check("état rejeté", state, "error")
R.check("motif explicite", message, "jeton statut capture invalide")

ctl.files[statusPath] = { data = "3\nautre-jeton\nok\n\n" .. obj.screenCaptureSessionSecret .. "\n", mtime = 1 }
R.check("jeton étranger rejeté", (obj:readScreenCaptureStatus(job)), "error")

ctl.files[statusPath] = { data = "3\nabc\nok\n\n" .. obj.screenCaptureSessionSecret .. "\n", mtime = 1 }
R.check("statut valide accepté", (obj:readScreenCaptureStatus(job)), "ok")

------------------------------------------------------------
R.section("Un PNG par fenêtre, pas un par rafraîchissement")
------------------------------------------------------------
reset()
obj:createScreenCaptureSession()
local vieux = { id = 9, token = "t1", outputPath = "/tmp/ws-test/vieux.png" }
ctl.files[vieux.outputPath] = { data = "png", mtime = 1 }
obj.runningScreenCaptures[9] = { job = vieux, startedAt = 1000 }
obj:finishScreenCaptureJob(vieux, { _image = 1 })
R.check("le fichier est retenu", obj.captureFiles[9], vieux.outputPath)

local neuf = { id = 9, token = "t2", outputPath = "/tmp/ws-test/neuf.png" }
ctl.files[neuf.outputPath] = { data = "png", mtime = 1 }
obj.runningScreenCaptures[9] = { job = neuf, startedAt = 1000 }
obj:finishScreenCaptureJob(neuf, { _image = 2 })
R.check("l'ancien PNG est supprimé", ctl.files[vieux.outputPath], nil)
R.check("seul le nouveau reste référencé", obj.captureFiles[9], neuf.outputPath)

R.section("Un échec ne laisse pas de fichier partiel")
local rate = { id = 10, token = "t3", outputPath = "/tmp/ws-test/rate.png" }
ctl.files[rate.outputPath] = { data = "partiel", mtime = 1 }
obj.runningScreenCaptures[10] = { job = rate, startedAt = 1000 }
obj:finishScreenCaptureJob(rate, nil, "capture failed")
R.check("fichier partiel supprimé", ctl.files[rate.outputPath], nil)

------------------------------------------------------------
R.section("Le cache de vignettes ne grossit plus sans fin")
------------------------------------------------------------
reset()
obj.snapshotCacheMaxEntries = 3
obj.snapshotCacheMaxAgeSeconds = 600
for i = 1, 6 do
    obj.snapshotCache[i] = { image = { _i = i }, time = 900 + i }
end
obj:trimSnapshotCache()
local restants = 0
for _ in pairs(obj.snapshotCache) do restants = restants + 1 end
R.check("plafonné au maximum", restants, 3)
R.check("les plus anciennes partent", obj.snapshotCache[1], nil)
R.check("les plus récentes restent", obj.snapshotCache[6] ~= nil, true)

R.section("Les vignettes périmées partent avec leur fichier")
obj.snapshotCache = { [20] = { image = {}, time = 1 } }   -- très ancienne
obj.captureFiles[20] = "/tmp/ws-test/vieille.png"
ctl.files["/tmp/ws-test/vieille.png"] = { data = "png", mtime = 1 }
obj:trimSnapshotCache()
R.check("entrée périmée retirée", obj.snapshotCache[20], nil)
R.check("son PNG aussi", ctl.files["/tmp/ws-test/vieille.png"], nil)
obj.snapshotCacheMaxEntries = 200

------------------------------------------------------------
R.section("Chemins de capture : le visible ne dérange pas le service")
------------------------------------------------------------
reset()
obj.instantVisibleSnapshots = true
obj.snapshotBudgetSeconds = 10          -- budget large : tout doit passer
ctl.snapshotIDs = {}
obj.entries = { descriptor(30), descriptor(31), descriptor(32) }
obj.selectedIndex = 1
obj:warmSnapshots(1, 3)
R.check("les trois sont capturées par le WindowServer",
    (ctl.snapshotIDs[30] or 0) + (ctl.snapshotIDs[31] or 0) + (ctl.snapshotIDs[32] or 0), 3)
R.check("aucune requête au service", #ctl.launchedApps, 0)
R.check("l'image est ensuite disponible", obj:windowSnapshot(obj.entries[1]) ~= nil, true)

R.section("windowSnapshot ne capture plus lui-même")
reset()
ctl.snapshotIDs = {}
R.check("rien en cache, rien renvoyé", obj:windowSnapshot(descriptor(33)), nil)
R.check("le WindowServer n'est pas sollicité par le rendu", ctl.snapshotIDs[33], nil)

R.section("Le cache évite une seconde capture")
reset()
ctl.snapshotIDs = {}
obj.snapshotBudgetSeconds = 10
obj.entries = { descriptor(34) }
obj.selectedIndex = 1
obj:warmSnapshots(1, 1)
obj.entries[1].snapshotAttempted = nil
obj:warmSnapshots(1, 1)
R.check("toujours une seule capture", ctl.snapshotIDs[34], 1)

R.section("Le budget borne ce qu'on capture avant d'afficher")
reset()
ctl.snapshotIDs = {}
obj.snapshotBudgetSeconds = 0            -- budget épuisé d'entrée
obj.entries = { descriptor(35), descriptor(36), descriptor(37) }
obj.selectedIndex = 1
obj.redrawTimer = nil
obj:warmSnapshots(1, 3)
local faites = 0
for _, id in ipairs({35, 36, 37}) do faites = faites + (ctl.snapshotIDs[id] or 0) end
R.check("aucune capture au-delà du budget", faites, 0)
R.check("un rendu de rattrapage est programmé", obj.redrawTimer ~= nil, true)
obj.snapshotBudgetSeconds = 0.045

R.section("La tuile sélectionnée est servie en premier")
local ordre = obj:warmOrder(1, 5, 3)
R.check("commence par la sélection", ordre[1], 3)
R.check("puis la voisine de droite", ordre[2], 4)
R.check("puis celle de gauche", ordre[3], 2)
R.check("toutes les tuiles sont couvertes", #ordre, 5)
R.check("sélection hors page : on repart du début", obj:warmOrder(4, 6, 1)[1], 4)

R.section("Une fenêtre incapturable n'est tentée qu'une fois")
reset()
obj.snapshotBudgetSeconds = 10
ctl.snapshotIDs = {}
ctl.snapshotFails[38] = true
obj.entries = { descriptor(38) }
obj.selectedIndex = 1
obj:warmSnapshots(1, 1)
R.check("marquée comme tentée", obj.entries[1].snapshotAttempted, true)
R.check("le service prend le relais", obj.runningScreenCaptures[38] ~= nil, true)
obj.runningScreenCaptures = {}
obj:warmSnapshots(1, 1)
R.check("pas de seconde tentative synchrone", obj.runningScreenCaptures[38], nil)
ctl.snapshotFails[38] = nil
obj.snapshotBudgetSeconds = 0.045

R.section("Une fenêtre réduite passe par le service, hors budget")
reset()
ctl.snapshotIDs = {}
obj.snapshotBudgetSeconds = 0            -- même sans budget
obj.entries = { descriptor(39, { minimized = true }) }
obj.selectedIndex = 1
obj:warmSnapshots(1, 1)
R.check("le WindowServer n'est pas sollicité", ctl.snapshotIDs[39], nil)
R.check("le service est sollicité", obj.runningScreenCaptures[39] ~= nil, true)
obj.snapshotBudgetSeconds = 0.045

------------------------------------------------------------
R.section("Une capture qui échoue est mise en quarantaine")
reset()
obj.screenCaptureFailureCache[40] = 1000   -- vient d'échouer
obj:queueScreenCapture(descriptor(40, { minimized = true }))
R.check("pas de nouvelle tentative immédiate", obj.runningScreenCaptures[40], nil)
obj.screenCaptureFailureCache[40] = 1000 - obj.screenCaptureFailureBackoffSeconds - 1
obj:queueScreenCapture(descriptor(40, { minimized = true }))
R.check("nouvelle tentative après le délai", obj.runningScreenCaptures[40] ~= nil, true)

R.section("Un refus d'autorisation coupe proprement le service")
reset()
local tcc = { id = 50, token = "t", outputPath = "/tmp/ws-test/x.png" }
obj.screenCaptureQueue = { { id = 51 }, { id = 52 } }
obj:finishScreenCaptureJob(tcc, nil, "TCC denied")
R.check("motif enregistré", obj.screenCaptureDisabledReason ~= nil, true)
R.check("la file est vidée", #obj.screenCaptureQueue, 0)
obj:queueScreenCapture(descriptor(53, { minimized = true }))
R.check("plus aucune mise en file", obj.runningScreenCaptures[53], nil)

------------------------------------------------------------
R.section("Sécurité : l'emplacement des captures est vérifié")
-- /tmp est inscriptible par tous. Sans contrôle, il suffisait de créer
-- le répertoire de base avant nous pour lire toutes les captures.
------------------------------------------------------------
reset()
ctl.dirs = {}
ctl.links = {}
local BASE = "/tmp/ws-test"
obj.screenCaptureSessionBaseDirectory = BASE
-- l'uid courant est lu sur le dossier personnel
ctl.dirs[os.getenv("HOME")] = { uid = ctl.uid, permissions = "rwx------" }
obj.cachedUserID = nil
R.check("uid courant reconnu", obj:currentUserID(), ctl.uid)

R.check("un répertoire à nous, fermé, est accepté",
    (function() ctl.dirs[BASE] = { uid = ctl.uid, permissions = "rwx------" }
       return obj:isPrivateDirectory(BASE) end)(), true)

ctl.dirs[BASE] = { uid = 502, permissions = "rwx------" }
local ok, motif = obj:isPrivateDirectory(BASE)
R.check("un répertoire d'un autre compte est refusé", ok, false)
R.check("le motif le dit", motif:find("uid 502", 1, true) ~= nil, true)

ctl.dirs[BASE] = { uid = ctl.uid, permissions = "rwxrwxrwx" }
ok, motif = obj:isPrivateDirectory(BASE)
R.check("un répertoire ouvert à tous est refusé", ok, false)
R.check("le motif le dit", motif:find("ouvert", 1, true) ~= nil, true)

ctl.dirs[BASE] = { uid = ctl.uid, permissions = "rwx--x---" }
R.check("un simple bit de groupe suffit à refuser",
    (obj:isPrivateDirectory(BASE)), false)

ctl.dirs[BASE] = { uid = ctl.uid, permissions = "rwx------" }
ctl.links[BASE] = "/ailleurs"
ok, motif = obj:isPrivateDirectory(BASE)
R.check("un lien symbolique est refusé", ok, false)
R.check("le motif le dit", motif, "lien symbolique")
ctl.links = {}

ctl.dirs[BASE] = nil
R.check("un répertoire absent est refusé", (obj:isPrivateDirectory(BASE)), false)

R.section("Une base non sûre coupe les captures, sans casser le switcher")
reset()
ctl.dirs = {}
ctl.dirs[os.getenv("HOME")] = { uid = ctl.uid, permissions = "rwx------" }
ctl.dirs[BASE] = { uid = 502, permissions = "rwxrwxrwx" }
obj.screenCaptureSessionDirectory = nil
obj.screenCaptureSessionSecret = nil
R.check("la session est refusée", obj:createScreenCaptureSession(), false)
R.check("aucun répertoire de session retenu", obj.screenCaptureSessionDirectory, nil)
R.check("aucun secret en mémoire", obj.screenCaptureSessionSecret, nil)
R.check("motif enregistré", obj.screenCaptureDisabledReason, "emplacement de capture non sur")
obj:queueScreenCapture(descriptor(60, { minimized = true }))
R.check("plus aucune requête n'est écrite", obj.runningScreenCaptures[60], nil)
R.check("aucun service n'est lancé", #ctl.launchedApps, 0)

R.section("Le répertoire de base est privé à l'utilisateur")
R.check("il n'est pas dans /tmp partagé",
    obj.defaultBase:find("^/tmp/") == nil, true)

R.section("L'ancien emplacement /tmp est nettoyé, s'il est bien à nous")
reset()
ctl.dirs = {}
ctl.dirs[os.getenv("HOME")] = { uid = ctl.uid, permissions = "rwx------" }
obj.screenCaptureSessionBaseDirectory = "/prive/ws"
ctl.dirs["/tmp/WindowSwitcher"] = { uid = ctl.uid, permissions = "rwx------" }
ctl.tasks = {}
obj:cleanupLegacySessionDirectories()
R.check("supprimé", #ctl.tasks, 1)
R.check("par /bin/rm sans shell", ctl.tasks[1].cmd, "/bin/rm")

ctl.dirs["/tmp/WindowSwitcher"] = { uid = 502, permissions = "rwxrwxrwx" }
ctl.tasks = {}
ctl.printed = {}
obj:cleanupLegacySessionDirectories()
R.check("un répertoire qui n'est pas à nous n'est pas supprimé", #ctl.tasks, 0)
R.check("mais il est signalé",
    table.concat(ctl.printed, " "):find("laisse en place", 1, true) ~= nil, true)
obj.screenCaptureSessionBaseDirectory = BASE

R.section("Un binaire de helper périmé est signalé")
reset()
ctl.files["/fake/src.swift"] = { data = "", mtime = 100 }
local vraiSource = obj.helperSourcePath
obj.helperSourcePath = function() return "/fake/src.swift" end
ctl.files[HELPER].mtime = 200
ctl.printed = {}
R.check("binaire plus récent : rien à signaler", obj:checkHelperFreshness(), true)
R.check("aucun message", #ctl.printed, 0)

ctl.files["/fake/src.swift"].mtime = 300
ctl.printed = {}
R.check("source plus récente : signalé", obj:checkHelperFreshness(), false)
R.check("le message dit quoi faire",
    table.concat(ctl.printed, " "):find("Recompiler", 1, true) ~= nil, true)
R.check("et prévient de la perte d'autorisation",
    table.concat(ctl.printed, " "):find("Enregistrement de l'ecran", 1, true) ~= nil, true)
obj.helperSourcePath = vraiSource
ctl.files[HELPER].mtime = 1

------------------------------------------------------------
R.section("Les sessions temporaires ne s'empilent plus")
------------------------------------------------------------
reset()
ctl.dirs = {}                       -- repartir d'un /tmp vierge
obj:createScreenCaptureSession()
local base = obj.screenCaptureSessionBaseDirectory
ctl.dirs[base] = { mtime = 1 }
ctl.dirs[base .. "/session-vieille1"] = { mtime = 1 }
ctl.dirs[base .. "/session-vieille2"] = { mtime = 1 }
ctl.dirs[base .. "/" .. obj.screenCaptureSessionID] = { mtime = 1 }
ctl.tasks = {}
obj:cleanupScreenCaptureSessions()
local supprimes = 0
for _, t in ipairs(ctl.tasks) do
    if t.cmd == "/bin/rm" then supprimes = supprimes + 1 end
end
R.check("les deux sessions étrangères sont supprimées", supprimes, 2)
R.check("aucun appel à hs.execute (shell de login)", #ctl.shell, 0)

R.finish()
