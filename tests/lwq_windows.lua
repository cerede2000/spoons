package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.logToFile=false; obj.logFile="/dev/null"; obj.verboseLogging=false

local W = lib.window

R.section("isCountableWindow : une réduction n'est pas une fermeture")
R.check("fenêtre normale visible",          obj:isCountableWindow(W{id=1}), true)
R.check("fenêtre RÉDUITE (subrole perdu)",  obj:isCountableWindow(W{id=2, visible=false, standard=false}), true)
R.check("application masquée (Cmd+H)",      obj:isCountableWindow(W{id=3, visible=false, standard=true}), true)
R.check("bureau Finder (AXScrollArea)",     obj:isCountableWindow(W{id=4, role="AXScrollArea", standard=false}), false)
R.check("palette visible non standard",     obj:isCountableWindow(W{id=5, standard=false}), false)
-- AX qui ne répond plus sur le rôle : le doute ne doit jamais
-- provoquer une fermeture.
local muette = { id=function() return 6 end,
                 role=function() error("AX muette") end,
                 isStandard=function() return false end,
                 isVisible=function() return true end }
R.check("rôle illisible : on compte quand même", obj:isCountableWindow(muette), true)
R.check("nil",                              obj:isCountableWindow(nil), false)

R.section("countWindows distingue zéro et inconnu")
local app = lib.app(ctl, {name="App", bundle="com.t.app", windows={W{id=1}}})
ctl.axMode="ok";     R.check("une fenêtre",              obj:countWindows(app), 1)
ctl.axMode="vide";   R.check("aucune fenêtre : 0",       obj:countWindows(app), 0)
ctl.axMode="erreur"; R.check("AX muette : nil, pas 0",   obj:countWindows(app), nil)
ctl.axMode="ok";     R.check("application absente : nil", obj:countWindows(nil), nil)

R.section("isDockApplication : filtre kind()")
R.check("application du Dock",     obj:isDockApplication(lib.app(ctl,{name="S",bundle="b",kind=1})), true)
R.check("agent barre de menus",    obj:isDockApplication(lib.app(ctl,{name="A",bundle="b",kind=0})), false)
R.check("daemon",                  obj:isDockApplication(lib.app(ctl,{name="D",bundle="b",kind=-1})), false)
R.check("nil",                     obj:isDockApplication(nil), false)

R.section("Cohérence entre le scan et le chemin événementiel")
obj.blacklistBundleIDs={}; obj.blacklistAppNames={}
local dock    = { app=lib.app(ctl,{name="Safari",bundle="com.apple.Safari",kind=1}), bundleID="com.apple.Safari", name="Safari" }
local menulet = { app=lib.app(ctl,{name="Util",bundle="com.util",kind=0}), bundleID="com.util", name="Util" }
R.check("application du Dock : éligible", (obj:isApplicationAllowed(dock)), true)
local ok, why = obj:isApplicationAllowed(menulet)
R.check("utilitaire barre de menus : refusé", ok, false)
R.check("motif", why, "pas d'icone dans le Dock")
R.check("app introuvable : pas d'exclusion abusive", (obj:isApplicationAllowed({bundleID="x", name="X"})), true)

R.section("isWindowStillPresent")
local holder = lib.app(ctl, {name="H", bundle="com.h"})
local w1 = W{id=11, app=holder, visible=false, standard=false}
holder._windows = { w1 }
R.check("fenêtre réduite toujours présente", obj:isWindowStillPresent(w1), true)
local orphan = W{id=22, app=holder}
R.check("fenêtre absente de la liste",        obj:isWindowStillPresent(orphan), false)

R.section("windowRejected n'est pas une fermeture")
local removed = false
local realRemoved = obj.onWindowRemoved
obj.onWindowRemoved = function() removed = true end
obj.pendingRecounts = {}
obj:onWindowRejected(w1, "H")
R.check("fenêtre encore là : aucune fermeture", removed, false)
removed = false
obj:onWindowRejected(orphan, "H")
R.check("fenêtre disparue : fermeture", removed, true)
obj.onWindowRemoved = realRemoved

R.section("Une fermeture = un recomptage, un quit, un délai fixe")
ctl.axMode="ok"
local victim = lib.app(ctl, {name="Notes", bundle="com.t.notes", kind=1, windows={}})
ctl.runningApps = { victim }
obj.enabled=true; obj.running=true; obj.quitDelay=5
obj.startupGracePeriod=0; obj.startedAt=0; obj.powerSuspended=false
obj.pendingQuits={}; obj.pendingRecounts={}; obj.windowCounts={}
obj.seenApps={["com.t.notes"]=true}
obj.windowTransitionFallbackEnabled=true; obj.windowTransitionScanInterval=5
ctl.timers={}
local win = W{id=7, app=victim}
obj:onWindowDestroyed(win, "Notes")
obj:onWindowRejected(win, "Notes")
R.check("un seul recomptage programmé", #ctl.timers, 1)
ctl.fireOnly(obj.windowRemovalRecheckDelay)
obj.windowCounts = { ["com.t.notes"] = 1 }
obj:scanWindowTransitions(false)
local armed, pending = 0, nil
for _, p in pairs(obj.pendingQuits) do armed = armed + 1; pending = p end
R.check("un seul quit armé", armed, 1)
R.check("délai ancré sur la première détection", pending and pending.startedAt, 1000)
R.check("pid mémorisé pour l'annulation", pending and pending.pid, 4242)

R.section("Coût du scan")
ctl.runningApps = {
    lib.app(ctl,{name="Safari",bundle="com.apple.Safari",kind=1,windows={W{id=1}}}),
    lib.app(ctl,{name="Finder",bundle="com.apple.finder",kind=1,windows={W{id=2}}}),
    lib.app(ctl,{name="Agent", bundle="com.agent",       kind=0,windows={W{id=3}}}),
    lib.app(ctl,{name="Daemon",bundle="com.daemon",      kind=-1,windows={}}),
}
obj.blacklistBundleIDs={["com.apple.finder"]=true}
obj.windowCounts={}; obj.pendingQuits={}
ctl.axCalls = 0
obj:scanWindowTransitions(true)
R.check("1 requête AX pour 4 applications", ctl.axCalls, 1)

R.finish()
