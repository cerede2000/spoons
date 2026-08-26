package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
local W = lib.window

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
obj:scanWindowTransitions(false)
ctl.fireTimers()
R.check("une application fermée", #ctl.killed, 1)
R.check("la bonne", ctl.killed[1], "Edge")

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

R.finish()
