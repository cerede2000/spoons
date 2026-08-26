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
-- Les methodes reelles sont restaurees ensuite : sans cela, les
-- sections suivantes testeraient les bouchons.
local realSenders = {
    sendUserActivity = obj.sendUserActivity,
    sendKeyboardActivity = obj.sendKeyboardActivity,
    sendMouseActivity = obj.sendMouseActivity,
    scheduleKeyboardBacklightEnforce = obj.scheduleKeyboardBacklightEnforce,
    sendKeepAlive = obj.sendKeepAlive,
    restoreEnergySavingState = obj.restoreEnergySavingState,
}
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

for name, fn in pairs(realSenders) do obj[name] = fn end

obj.running = true          -- bindHotkeys ne lie que si le Spoon tourne
R.section("Raccourcis pilotés par table")
local MAP = { toggle={{"ctrl","alt","cmd"},"J"}, menu={{"ctrl","alt","cmd"},"M"},
              status={{"ctrl","alt","cmd"},"U"}, test={{"ctrl","alt","cmd"},"T"} }
local function nb() local c=0 for _ in pairs(obj.hotkeys) do c=c+1 end return c end
R.check("actifs par défaut ici", obj.hotkeysEnabled, true)
obj.hotkeys = {}
obj:bindHotkeys(MAP)
R.check("les quatre actions liées", nb(), 4)
obj:setHotkeysEnabled(false)
R.check("désactivation délie tout", nb(), 0)
obj:setHotkeysEnabled(true)
R.check("réactivation sans repasser par bindHotkeys", nb(), 4)
obj:bindHotkeys({ toggle = MAP.toggle })
R.check("seules les actions déclarées", nb(), 1)
R.check("action absente non liée", obj.hotkeys.test, nil)
obj:bindHotkeys(MAP)

R.section("Le curseur ne saute pas en arrière")
obj.isMouseEnabled = function() return true end
obj.mouseMovePixels = 1
obj.returnMouseTimer = nil
local pos = { x = 100, y = 200 }
hs.mouse.absolutePosition = function(p) if p then pos = { x=p.x, y=p.y } end return { x=pos.x, y=pos.y } end
ctl.timers = {}
obj:sendMouseActivity()
R.check("curseur déplacé", pos.x, 101)
ctl.fireTimers()
R.check("curseur ramené si personne n'y a touché", pos.x, 100)

-- l'utilisateur bouge la souris pendant le délai de retour
obj.returnMouseTimer = nil
pos = { x = 500, y = 600 }
ctl.timers = {}
obj:sendMouseActivity()
pos = { x = 900, y = 400 }        -- mouvement réel de l'utilisateur
ctl.fireTimers()
R.check("le curseur reste là où l'utilisateur l'a mis (x)", pos.x, 900)
R.check("le curseur reste là où l'utilisateur l'a mis (y)", pos.y, 400)



------------------------------------------------------------
R.section("Un Spoon arrêté ne lie aucun raccourci")
------------------------------------------------------------
obj:deleteHotkeys()
obj.running = false
obj.hotkeysEnabled = true
obj:bindHotkeys({ toggle = {{"ctrl"}, "J"} })
local lies = 0
for _ in pairs(obj.hotkeys or {}) do lies = lies + 1 end
R.check("rien n'est lié", lies, 0)
R.check("mapping mémorisé", obj.hotkeyMapping ~= nil, true)

obj.running = true
obj:applyHotkeys()
lies = 0
for _ in pairs(obj.hotkeys or {}) do lies = lies + 1 end
R.check("le démarrage les applique", lies, 1)

R.finish()
