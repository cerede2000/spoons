package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
local W = lib.window

-- Une confirmation n'est retenue que si la précédente est assez
-- ancienne : le temps doit avancer entre deux observations.
local function plusTard(n)
    ctl.now = ctl.now + (n or 5)
end

local function fresh(names)
    ctl.runningApps = {}
    for _, n in ipairs(names) do
        table.insert(ctl.runningApps,
            lib.app(ctl, {name=n, bundle="com.t."..n:gsub("%s",""), kind=1, windows={W{id=1}}}))
    end
    ctl.timers={}; ctl.killed={}; ctl.axMode="ok"; ctl.axCalls=0
    obj.logToFile=false; obj.logFile="/dev/null"; obj.verboseLogging=false
    obj.enabled=true; obj.running=true; obj.quitDelay=5
    obj.startupGracePeriod=0; obj.startedAt=0
    obj.pendingQuits={}; obj.pendingRecounts={}; obj.windowCounts={}
    obj.powerSuspended=false; obj.wakeTimer=nil; obj.powerWatcher=nil
    obj.suspendOnPowerEvents=true; obj.wakeGracePeriod=15
    obj.windowTransitionFallbackEnabled=true; obj.windowTransitionScanInterval=5
    obj.blacklistBundleIDs={}; obj.blacklistAppNames={}
    obj.seenApps={}
    obj.zeroStreak={}; obj.zeroStreakAt={}
    obj.undecidable={}; obj.undecidableSince={}
    obj:createPowerWatcher()
    obj:scanWindowTransitions(true)
end
local function armed() local c=0 for _ in pairs(obj.pendingQuits) do c=c+1 end return c end

R.section("Mise en veille : cinq applications d'un coup")
fresh({"Edge","Spark","Claude","ChatGPT","Firefox"})
ctl.axMode="vide"
obj:scanWindowTransitions(false)
ctl.fireTimers()
R.check("aucune application fermée", #ctl.killed, 0)
R.check("aucun quit armé", armed(), 0)

R.section("Deux applications seulement : le veilleur prend le relais")
fresh({"Edge","Firefox"})
ctl.power(hs.caffeinate.watcher.systemWillSleep)
R.check("surveillance suspendue", obj.powerSuspended, true)
ctl.axMode="vide"
obj:scanWindowTransitions(false)
ctl.fireTimers()
R.check("aucune fermeture", #ctl.killed, 0)

R.section("Un quit déjà armé est annulé par le verrouillage")
fresh({"Edge","Firefox"})
obj:scheduleQuit({app=ctl.runningApps[1], bundleID="com.t.Edge", name="Edge"}, "test")
R.check("quit armé avant", armed(), 1)
ctl.power(hs.caffeinate.watcher.screensDidLock)
R.check("annulé au verrouillage", armed(), 0)
ctl.fireTimers()
R.check("rien de fermé", #ctl.killed, 0)

R.section("Réveil : délai de grâce avant reprise")
fresh({"Edge","Firefox"})
ctl.power(hs.caffeinate.watcher.systemWillSleep)
ctl.power(hs.caffeinate.watcher.systemDidWake)
R.check("encore suspendu juste après", obj.powerSuspended, true)
ctl.axMode="ok"; ctl.fireTimers()
R.check("reprise effective", obj.powerSuspended, false)
R.check("aucune fermeture pendant la reprise", #ctl.killed, 0)

R.section("Non-régression : une fermeture légitime ferme bien")
fresh({"Edge","Firefox"})
ctl.runningApps[1]._windows = {}
-- il faut quitConfirmations observations à zéro pour conclure : un
-- aveuglement passager de l'accessibilité ne doit pas suffire
for _ = 1, obj.quitConfirmations do obj:scanWindowTransitions(false); plusTard() end
ctl.fireTimers()
R.check("une application fermée", #ctl.killed, 1)
R.check("la bonne", ctl.killed[1], "Edge")

R.section("Une seule observation ne suffit pas")
fresh({"Edge","Firefox"})
ctl.runningApps[1]._windows = {}
obj:scanWindowTransitions(false)
ctl.fireTimers()
R.check("rien de fermé sur un seul zéro", #ctl.killed, 0)

R.section("Une rafale de scans dans le même instant ne suffit pas non plus")
-- Mesuré chez l'utilisateur : la fermeture d'une fenêtre déclenche
-- plusieurs chemins d'analyse dans la même seconde. Si chacun comptait
-- pour une confirmation, la garde ne protégeait de rien.
fresh({"Edge","Firefox"})
ctl.runningApps[1]._windows = {}
for _ = 1, 20 do obj:scanWindowTransitions(false) end
ctl.fireTimers()
R.check("vingt scans instantanés ne ferment rien", #ctl.killed, 0)
R.check("aucun quit armé", armed(), 0)

R.section("AX en erreur : on ne conclut rien")
fresh({"Edge","Firefox"})
ctl.axMode="erreur"
obj:scanWindowTransitions(false)
ctl.fireTimers()
R.check("aucune fermeture", #ctl.killed, 0)
R.check("dernier état connu conservé", obj.windowCounts["com.t.Edge"], 1)

R.section("Aucun quit ne survit à l'arrêt du Spoon")
fresh({"Victime"})
ctl.runningApps[1]._windows = {}
obj.seenApps={["com.t.Victime"]=true}
obj:onWindowDestroyed(W{id=7, app=ctl.runningApps[1]}, "Victime")
R.check("un recomptage est en vol", #ctl.timers, 1)
obj.menuBar=nil; obj.windowFilter=nil; obj.appWatcher=nil
obj.clickTimer=nil; obj.hotkeys={}
obj:stop()
ctl.fireTimers()
R.check("rien n'a été fermé après stop()", #ctl.killed, 0)

R.section("Application terminée : seul le pid est interrogeable")
fresh({"App"})
obj:scheduleQuit({app=ctl.runningApps[1], bundleID="com.t.App", name="App"}, "test")
R.check("quit armé", armed(), 1)
local dead = ctl.runningApps[1]
dead._dead = true
ctl.deadCalls = {}
obj:onApplicationEvent(dead, hs.application.watcher.terminated)
R.check("aucun appel interdit sur l'app morte", #ctl.deadCalls, 0)
R.check("quit annulé par le pid", armed(), 0)
ctl.deadCalls = {}
for _, e in ipairs({"activated","deactivated","hidden","unhidden"}) do
    obj:onApplicationEvent(dead, e)
end
R.check("événements sans intérêt : rien interrogé", #ctl.deadCalls, 0)

------------------------------------------------------------
R.section("Les applications à fenêtres transitoires ne sont jamais quittées")
-- Hammerspoon classe Spotlight, le Centre de notifications et les
-- menulets comme ayant des fenêtres transitoires, et les écarte de son
-- filtre par défaut. Ce Spoon utilise un filtre qui laisse tout passer :
-- sans reprendre cette liste, refermer le champ de recherche Spotlight
-- était vu comme la fermeture de sa dernière fenêtre, et Spotlight était
-- quitté.
------------------------------------------------------------
R.check("Spotlight est écarté",
    obj:isAppBlacklisted({ name = "Spotlight", bundleID = "com.apple.Spotlight" }), true)
R.check("le Centre de notifications aussi",
    obj:isAppBlacklisted({ name = "Notification Center" }), true)
R.check("une application ordinaire ne l'est pas",
    obj:isAppBlacklisted({ name = "Safari", bundleID = "com.apple.Safari" }), false)

R.check("le test isole bien ce motif",
    obj:isTransientWindowApp({ name = "Spotlight" }), true)
R.check("et ne se déclenche pas sur les autres",
    obj:isTransientWindowApp({ name = "Safari" }), false)
R.check("une application sans nom ne déclenche rien",
    obj:isTransientWindowApp({ bundleID = "com.exemple" }), false)

obj.honourTransientWindowApps = false
R.check("désactivable",
    obj:isTransientWindowApp({ name = "Spotlight" }), false)
R.check("et alors Spotlight redevient candidate",
    obj:isAppBlacklisted({ name = "Spotlight", bundleID = "com.apple.Spotlight" }), false)
obj.honourTransientWindowApps = true


------------------------------------------------------------
R.section("Le balayage complet est étalé, jamais abandonné")
------------------------------------------------------------
-- Il établit la référence : combien de fenêtres chaque application
-- possède. L'abandonner laisse cette référence incomplète, et une
-- application qui n'y figure pas n'est plus interrogée par les
-- balayages partiels — elle devient invisible.
--
-- Mais il ne peut pas non plus monopoliser le thread principal :
-- mesuré chez l'utilisateur, 570 ms toutes les trente secondes,
-- pendant lesquelles aucune frappe n'était transmise.
--
-- Il reprend donc là où il s'est arrêté, jusqu'à couvrir tout le
-- monde. Même référence établie, en morceaux.
fresh({"Edge","Firefox","Claude","Notes"})
obj.scanTimeBudget = 0.15
obj.fullScanCursor = nil
obj.windowCounts = {}

local vraiCount = obj.countWindows
local function lent()
    obj.countWindows = function(self, app)
        ctl.now = ctl.now + 0.1        -- chaque application coûte 0,1 s
        return vraiCount(self, app)
    end
end

lent()
ctl.printed = {}
obj:scanWindowTransitions(true)          -- balayage de démarrage
R.check("il s'interrompt sur le budget",
    table.concat(ctl.printed, " "):find("complet interrompu", 1, true) ~= nil, true)
R.check("et retient où reprendre", obj.fullScanCursor ~= nil, true)

local connus = 0
for _ in pairs(obj.windowCounts) do connus = connus + 1 end
R.check("une partie seulement est vue pour l'instant", connus < 4, true)

-- Les ticks suivants reprennent et complètent.
local tours = 0
while obj.fullScanCursor and tours < 10 do
    obj:scanWindowTransitions(false)
    tours = tours + 1
end
obj.countWindows = vraiCount

R.check("le balayage finit par se terminer", obj.fullScanCursor, nil)
connus = 0
for _ in pairs(obj.windowCounts) do connus = connus + 1 end
R.check("la référence couvre les quatre applications", connus, 4)
R.check("et chacune avec sa fenêtre", obj.windowCounts["com.t.Notes"], 1)

R.section("Une fermeture est donc bien vue après le démarrage")
-- Test de bout en bout : référence complète, puis perte de la dernière
-- fenêtre, puis fermeture.
ctl.runningApps[4]._windows = {}          -- Notes perd sa fenêtre
obj.seenApps["com.t.Notes"] = true
obj.lastFullScanAt = ctl.now
for _ = 1, obj.quitConfirmations do
    obj:scanWindowTransitions(false)
    plusTard()
end
ctl.fireTimers()
R.check("Notes est fermée", #ctl.killed, 1)
R.check("la bonne", ctl.killed[1], "Notes")

R.section("Un balayage rapide n'est jamais interrompu")
fresh({"Edge","Firefox"})
obj.scanTimeBudget = 0.15
obj.fullScanCursor = nil
ctl.printed = {}
obj:scanWindowTransitions(true)
R.check("aucune interruption",
    table.concat(ctl.printed, " "):find("interrompu", 1, true) ~= nil, false)
R.check("aucune reprise en attente", obj.fullScanCursor, nil)

R.section("Un balayage partiel lent rend la main sans rien perdre")
fresh({"Edge","Firefox","Claude","Notes"})
obj.scanTimeBudget = 0.15
obj.fullScanCursor = nil
obj.windowCounts = { ["com.t.Edge"] = 1, ["com.t.Firefox"] = 1,
                     ["com.t.Claude"] = 1, ["com.t.Notes"] = 1 }
obj.lastFullScanAt = ctl.now             -- force un balayage partiel
lent()
ctl.printed = {}
obj:scanWindowTransitions(false)
obj.countWindows = vraiCount
R.check("l'interruption est journalisée",
    table.concat(ctl.printed, " "):find("partiel interrompu", 1, true) ~= nil, true)
R.check("un partiel ne laisse pas de reprise", obj.fullScanCursor, nil)
R.check("aucune fermeture programmée", armed(), 0)
connus = 0
for _ in pairs(obj.windowCounts) do connus = connus + 1 end
R.check("les quatre comptages sont conservés", connus, 4)
R.check("y compris ceux qu'on n'a pas eu le temps de voir",
    obj.windowCounts["com.t.Notes"], 1)

R.section("Budget désactivable")
fresh({"Edge","Firefox","Claude","Notes"})
obj.scanTimeBudget = 0
obj.fullScanCursor = nil
lent()
ctl.printed = {}
obj:scanWindowTransitions(true)
obj.countWindows = vraiCount
R.check("sans budget, le balayage va jusqu'au bout",
    table.concat(ctl.printed, " "):find("interrompu", 1, true) ~= nil, false)
connus = 0
for _ in pairs(obj.windowCounts) do connus = connus + 1 end
R.check("et couvre tout le monde", connus, 4)
obj.scanTimeBudget = 0.15

------------------------------------------------------------
R.section("Le démarrage ne balaie qu'une fois")
------------------------------------------------------------
-- primeSeenApps interroge toutes les applications pour retenir celles
-- qui ont des fenêtres. Le balayage initial les interroge toutes à
-- nouveau, et appelle markSeen dans exactement les mêmes cas. Mesuré :
-- 2626 ms par balayage à froid, pour 57 applications. En faire deux au
-- démarrage, c'est cinq secondes de thread principal pris juste après
-- un rechargement — donc autant de frappes perdues.
fresh({"Edge","Firefox"})
obj.windowTransitionFallbackEnabled = true
obj.seenApps = {}
obj.windowCounts = {}
ctl.axCalls = 0
obj:start()
local avecFilet = ctl.axCalls
R.check("les applications avec fenêtres sont connues",
    obj.seenApps["com.t.Edge"], true)
R.check("et leur compte est établi", obj.windowCounts["com.t.Edge"], 1)
obj:stop()

-- Sans le filet, personne d'autre n'établit la liste : primeSeenApps
-- reste indispensable.
fresh({"Edge","Firefox"})
obj.windowTransitionFallbackEnabled = false
obj.seenApps = {}
ctl.axCalls = 0
obj:start()
R.check("sans filet, la liste est quand même établie",
    obj.seenApps["com.t.Edge"], true)
obj:stop()
obj.windowTransitionFallbackEnabled = true

R.check("un seul balayage suffit désormais", avecFilet > 0, true)


------------------------------------------------------------
R.section("Le filet n'est jamais affamé par un balayage étalé")
------------------------------------------------------------
-- Le parcours repartait du curseur. Pendant qu'un balayage complet
-- s'étalait sur plusieurs ticks, les applications situées AVANT le
-- curseur n'étaient plus visitées du tout — y compris celles qui ont
-- des fenêtres connues, c'est-à-dire exactement celles qui peuvent en
-- perdre une dernière. Le filet était éteint, et plus rien ne se
-- fermait.
fresh({"Edge","Firefox","Claude","Notes"})
obj.scanTimeBudget = 0.15
obj.fullScanCursor = 3          -- un balayage complet est en cours
obj.windowCounts = { ["com.t.Edge"] = 1, ["com.t.Firefox"] = 1,
                     ["com.t.Claude"] = 1, ["com.t.Notes"] = 1 }
obj.seenApps = { ["com.t.Edge"] = true }

ctl.runningApps[1]._windows = {}          -- Edge, en 1re position, perd tout
for _ = 1, obj.quitConfirmations do
    obj:scanWindowTransitions(false)
    plusTard()
end
ctl.fireTimers()
R.check("Edge est fermée malgré le curseur en position 3", #ctl.killed, 1)
R.check("la bonne", ctl.killed[1], "Edge")

R.section("Un balayage étalé progresse toujours d'au moins une application")
-- Sans cette garantie, les applications à fenêtres connues consomment
-- tout le budget et le curseur piétine indéfiniment : la référence ne
-- se complète jamais.
fresh({"Edge","Firefox","Claude","Notes"})
obj.scanTimeBudget = 0.15
obj.fullScanCursor = nil
obj.windowCounts = {}
local vraiCount2 = obj.countWindows
obj.countWindows = function(self, app)
    ctl.now = ctl.now + 0.2       -- chaque application dépasse le budget
    return vraiCount2(self, app)
end
local positions = {}
local tours2 = 0
repeat
    obj:scanWindowTransitions(tours2 == 0)
    positions[#positions + 1] = obj.fullScanCursor
    tours2 = tours2 + 1
until obj.fullScanCursor == nil or tours2 > 12
obj.countWindows = vraiCount2

R.check("le curseur finit par se libérer", obj.fullScanCursor, nil)
R.check("il n'a jamais piétiné", tours2 <= 6, true)
local connus2 = 0
for _ in pairs(obj.windowCounts) do connus2 = connus2 + 1 end
R.check("et la référence est complète", connus2, 4)

R.section("Le cas nominal : fermeture de la dernière fenêtre, quit après le délai")
-- C'est le but du Spoon, testé de bout en bout dans les conditions de
-- l'utilisateur : délai de 5 s, exclusions respectées.
fresh({"Edge","Firefox"})
obj.quitDelay = 5
obj.scanTimeBudget = 0.15
obj.fullScanCursor = nil
obj.seenApps = { ["com.t.Edge"] = true }
obj:scanWindowTransitions(true)
R.check("référence établie", obj.windowCounts["com.t.Edge"], 1)

ctl.runningApps[1]._windows = {}
obj.lastFullScanAt = ctl.now
for _ = 1, obj.quitConfirmations do
    obj:scanWindowTransitions(false)
    plusTard()
end
R.check("un quit est armé", armed(), 1)
R.check("rien n'est encore fermé", #ctl.killed, 0)
ctl.fireTimers()
R.check("puis l'application est fermée", ctl.killed[1], "Edge")

R.section("Une application exclue n'est jamais fermée")
fresh({"Edge","Firefox"})
obj.blacklistBundleIDs = { ["com.t.Edge"] = true }
obj.seenApps = { ["com.t.Edge"] = true }
obj.fullScanCursor = nil
obj:scanWindowTransitions(true)
ctl.runningApps[1]._windows = {}
obj.lastFullScanAt = ctl.now
for _ = 1, obj.quitConfirmations do
    obj:scanWindowTransitions(false)
    plusTard()
end
ctl.fireTimers()
R.check("l'exclusion tient", #ctl.killed, 0)
obj.blacklistBundleIDs = {}


------------------------------------------------------------
R.section("Exigence proportionnelle à la preuve")
------------------------------------------------------------
-- Deux situations qui ne se valent pas :
--   « Fenetre fermee » puis liste vide  -> on a VU la fenêtre mourir
--   liste vide sans événement           -> on le DÉDUIT d'un balayage
--
-- Les fermetures abusives — Claude et Notes quittées pendant qu'une
-- autre application était en plein écran — venaient toutes du second
-- cas. Exiger trois confirmations dans le premier ajoutait neuf
-- secondes à un délai réglé à cinq.
fresh({"Edge","Firefox"})
obj.quitConfirmations = 3
obj.quitConfirmationsAfterCloseEvent = 1
obj.closeEventTrustSeconds = 30
obj.closeEventAt = {}
obj.seenApps = { ["com.t.Edge"] = true }
obj.fullScanCursor = nil
obj:scanWindowTransitions(true)

local pidEdge = ctl.runningApps[1]:pid()
ctl.runningApps[1]._windows = {}
ctl.runningApps[1].mainWindow = function() return nil end

-- Sans événement : la série complète reste exigée.
obj.lastFullScanAt = ctl.now
R.check("déduit : premier zéro indécidable",
    obj:countWindows(ctl.runningApps[1]), nil)
plusTard()
R.check("deuxième aussi", obj:countWindows(ctl.runningApps[1]), nil)
plusTard()
R.check("il en faut bien trois", obj:countWindows(ctl.runningApps[1]), 0)

-- Avec événement : une seule suffit.
obj.zeroStreak = {}
obj.zeroStreakAt = {}
obj.undecidable = {}
obj.undecidableSince = {}
obj.closeEventAt[pidEdge] = ctl.now
R.check("observé : le premier zéro conclut",
    obj:countWindows(ctl.runningApps[1]), 0)

R.section("Un vieil événement ne dit plus rien du présent")
obj.zeroStreak = {}
obj.zeroStreakAt = {}
obj.undecidable = {}
obj.undecidableSince = {}
obj.closeEventAt[pidEdge] = ctl.now - 120     -- au-delà de la confiance
R.check("la série complète revient",
    obj:countWindows(ctl.runningApps[1]), nil)

R.section("La garde de la fenêtre principale passe toujours avant")
-- C'est elle qui protégeait Claude : tant qu'une fenêtre principale
-- répond, aucun raccourci n'est permis, même avec un événement observé.
obj.zeroStreak = {}
obj.zeroStreakAt = {}
obj.undecidable = {}
obj.undecidableSince = {}
obj.closeEventAt[pidEdge] = ctl.now
ctl.runningApps[1].mainWindow = function() return lib.window({ id = 4242 }) end
R.check("indécidable malgré l'événement",
    obj:countWindows(ctl.runningApps[1]), nil)

R.section("Le journal dit laquelle des deux règles s'applique")
obj.zeroStreak = {}
obj.zeroStreakAt = {}
obj.undecidable = {}
obj.undecidableSince = {}
obj.quitConfirmationsAfterCloseEvent = 2
ctl.runningApps[1].mainWindow = function() return nil end
obj.closeEventAt[pidEdge] = ctl.now
ctl.printed = {}
obj:countWindows(ctl.runningApps[1])
R.check("la preuve directe est signalée",
    table.concat(ctl.printed, " "):find("fermeture observee", 1, true) ~= nil, true)
obj.quitConfirmationsAfterCloseEvent = 1


------------------------------------------------------------
R.section("Bout en bout : fermeture vue, quit au délai réglé")
------------------------------------------------------------
-- Le scénario de l'utilisateur, chronométré. Avant : quatorze secondes,
-- dont neuf de confirmations pour un délai réglé à cinq.
fresh({"Edge","Firefox"})
obj.quitDelay = 5
obj.quitConfirmations = 3
obj.quitConfirmationsAfterCloseEvent = 1
obj.closeEventAt = {}
obj.seenApps = { ["com.t.Edge"] = true }
obj.fullScanCursor = nil
obj:scanWindowTransitions(true)

local depart = ctl.now
ctl.runningApps[1]._windows = {}
ctl.runningApps[1].mainWindow = function() return nil end
ctl.timers = {}
ctl.killed = {}

-- L'événement de fermeture arrive, puis le recomptage qu'il programme.
obj:onWindowDestroyed(W{ id = 7, app = ctl.runningApps[1] }, "Edge")
ctl.fireOnly(obj.windowRemovalRecheckDelay)
R.check("le quit est armé sans attendre les confirmations", armed(), 1)

ctl.fireTimers()
R.check("l'application est fermée", ctl.killed[1], "Edge")
R.check("et le délai total est celui réglé",
    ctl.now - depart <= obj.quitDelay + 1, true)

R.finish()
