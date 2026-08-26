package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showStateNotifications=false; obj.verboseLogging=false

local function ups()
    local c = 0
    for _, e in ipairs(ctl.keyEvents) do if e.down == false then c = c + 1 end end
    return c
end
local function downs()
    local c = 0
    for _, e in ipairs(ctl.keyEvents) do if e.down == true then c = c + 1 end end
    return c
end
local function ready()
    obj.currentState = obj.STATE.MONITORING
    obj.activityKeyDown = false
    obj.keyUpTimer = nil
    obj.keepAliveInProgress = false
    obj.returnMouseTimer=nil; obj.checkTimer=nil
    obj.keyboardBacklightProbeTimer=nil; obj.keyboardBacklightProbeRetryTimer=nil
    obj.keyboardBacklightEnforceTimer=nil; obj.initialKeepAliveTimer=nil
    obj.keyboardAutoRestoreTimer=nil; obj.inputWatcher=nil
    obj.keyboardBacklightModified=false; obj.keyboardAutoBrightnessModified=false
    obj.screenBrightnessModified=false
    obj.lowPowerBatteryModified=false; obj.lowPowerACModified=false
    ctl.keyEvents = {}; ctl.timers = {}
end

R.section("La touche Maj est toujours relâchée")
ready()
obj:postActivityKey()
R.check("appui envoyé", downs(), 1)
R.check("relâchement pas encore envoyé", ups(), 0)
R.check("touche notée comme enfoncée", obj.activityKeyDown, true)
ctl.fireTimers()
R.check("relâchement envoyé par le minuteur", ups(), 1)
R.check("touche notée relâchée", obj.activityKeyDown, false)

-- désactivation pendant les 50 ms : le relâchement ne doit pas être perdu
ready()
obj.currentState = obj.STATE.MONITORING
obj:postActivityKey()
R.check("appui envoyé, minuteur en vol", downs(), 1)
obj:disable()
R.check("disable() relâche la touche", ups(), 1)
ctl.fireTimers()
R.check("pas de relâchement en double", ups(), 1)

-- rechargement de Hammerspoon pendant les 50 ms
ready()
obj.shutdownGuardInstalled = false
obj:installShutdownGuard()
obj.currentState = obj.STATE.MONITORING
obj:postActivityKey()
ctl.shutdown()
R.check("le hook d'arrêt relâche la touche", ups(), 1)

-- stop()
ready()
obj.currentState = obj.STATE.MONITORING
obj:postActivityKey()
obj.menuBar=nil; obj.clickTimer=nil; obj.hotkeys={}; obj.toastCanvas=nil; obj.toastTimer=nil
obj:stop()
R.check("stop() relâche la touche", ups(), 1)

R.section("Le verrou de keepalive ne peut pas rester fermé")
ready()
obj.currentState = obj.STATE.KEEPALIVE
obj.sendUserActivity  = function() return false end
obj.sendKeyboardActivity = function() error("panne d'un moteur") end
obj.sendMouseActivity = function() return false end
obj:sendKeepAlive()
R.check("verrou relâché malgré l'erreur", obj.keepAliveInProgress, false)
-- le keepalive suivant doit repartir
local ran = false
obj.sendKeyboardActivity = function() ran = true; return true end
obj.scheduleKeyboardBacklightEnforce = function() end
obj:sendKeepAlive()
R.check("le keepalive suivant s'exécute", ran, true)

R.section("Le test manuel ne laisse pas d'état forcé")
ready()
obj.currentState = obj.STATE.MONITORING
obj.lastKeepAliveTime = 12345
obj.sendKeepAlive = function() error("panne") end
obj:testKeepAlive()
R.check("état restauré malgré l'erreur", obj.currentState, obj.STATE.MONITORING)
R.check("rythme des keepalives non décalé", obj.lastKeepAliveTime, 12345)

R.section("Idle illisible n'est pas un retour utilisateur")
ready()
obj.currentState = obj.STATE.KEEPALIVE
obj.keyboardBacklightModified = true
local restored = false
obj.restoreEnergySavingState = function() restored = true end
local realIdle = hs.host.idleTime
hs.host.idleTime = function() error("API muette") end
R.check("getIdleTime renvoie nil, pas 0", obj:getIdleTime(), nil)
obj:checkIdleState()
R.check("aucune restauration déclenchée", restored, false)
R.check("toujours en mode vert", obj.currentState, obj.STATE.KEEPALIVE)
hs.host.idleTime = realIdle

R.finish()
