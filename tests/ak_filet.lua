package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showStateNotifications=false; obj.verboseLogging=false

local KEY = "ActivityKeeper.pendingRestore"
local function clean()
    ctl.store={}; ctl.shell={}; ctl.kbIndex=0
    obj.keyboardBacklightModified=false; obj.savedKeyboardBrightness=nil
    obj.lastKnownNonZeroKeyboardBrightness=nil
    obj.keyboardAutoBrightnessModified=false; obj.savedKeyboardAutoBrightness=nil
    obj.screenBrightnessModified=false; obj.savedScreenBrightness=nil; obj.savedScreenId=nil
    obj.lowPowerBatteryModified=false; obj.lowPowerACModified=false
    obj.lastPendingRestoreSignature=nil
    obj.keyboardBrightnessBackend="mac-brightnessctl"
    obj.keyboardBrightnessTool="/opt/homebrew/bin/mac-brightnessctl"
end

R.section("Consignation de l'état modifié")
clean()
obj.keyboardBacklightModified=true; obj.savedKeyboardBrightness=0.42
obj:persistPendingRestore()
R.check("enregistré dans hs.settings", ctl.store[KEY] ~= nil, true)
R.check("avec la valeur à rendre", ctl.store[KEY].savedKeyboardBrightness, 0.42)

R.section("Coût d'une consignation répétée")
local sets=0
local realSet = hs.settings.set
hs.settings.set = function(k,v) sets=sets+1; realSet(k,v) end
obj.lastPendingRestoreSignature = nil     -- premier passage sur cet état
for i=1,20 do obj:persistPendingRestore() end
R.check("20 appels identiques : 1 seule écriture", sets, 1)
sets=0; obj.savedKeyboardBrightness=0.77
obj:persistPendingRestore()
R.check("une vraie modification est écrite", sets, 1)
hs.settings.set = realSet

R.section("Capture asynchrone rattrapée par le tick")
clean(); ctl.kbSequence={0.0, 0.0, 0.42}
obj.isKeyboardBacklightEnabled=function() return true end
obj.isScreenDimmingEnabled=function() return false end
obj.isLowPowerModeEnabled=function() return false end
obj.isAutomaticLowPowerModeEnabled=function() return false end
obj.currentState=obj.STATE.KEEPALIVE
obj:applyEnergySavingState()
R.check("capture non finie au retour", obj.keyboardBacklightModified, false)
ctl.fireTimers()
R.check("capture aboutie", obj.keyboardBacklightModified, true)
R.check("valeur trouvée", obj.savedKeyboardBrightness, 0.42)
R.check("pas encore consignée", (ctl.store[KEY] or {}).savedKeyboardBrightness, nil)
ctl.idle = 200
obj.lastKeepAliveTime = os.time()
obj:checkIdleState()
R.check("toujours en vert", obj.currentState, obj.STATE.KEEPALIVE)
R.check("le tick a rattrapé la consignation", (ctl.store[KEY] or {}).savedKeyboardBrightness, 0.42)

R.section("Reprise après un arrêt brutal")
local saved = ctl.store[KEY]
clean(); ctl.store[KEY] = saved
obj.currentState = obj.STATE.OFF
ctl.shell = {}
R.check("la reprise agit même en OFF", obj:recoverPendingRestore(), true)
R.check("des commandes ont été émises", #ctl.shell > 0, true)
R.check("consigne effacée", ctl.store[KEY], nil)
R.check("rien à reprendre ensuite", obj:recoverPendingRestore(), false)

R.section("Enregistrement corrompu ou périmé")
clean()
ctl.store[KEY] = { keyboardBacklightModified=true, savedKeyboardBrightness="pas un nombre",
                   screenBrightnessModified=true, savedScreenBrightness={}, savedScreenId="abc" }
R.check("ne lève pas", pcall(function() obj:recoverPendingRestore() end), true)
R.check("valeur clavier assainie", obj.savedKeyboardBrightness, nil)
R.check("identifiant écran assaini", obj.savedScreenId, nil)

R.section("Hook d'arrêt")
clean()
R.check("aucun hook au départ", hs.shutdownCallback, nil)
obj:installShutdownGuard()
R.check("hook installé", type(hs.shutdownCallback), "function")
obj.keyboardBacklightModified=true; obj.savedKeyboardBrightness=0.33
ctl.store[KEY]={keyboardBacklightModified=true}
ctl.shell={}
ctl.shutdown()
R.check("le hook restaure", #ctl.shell > 0, true)
R.check("le hook efface la consigne", ctl.store[KEY], nil)
local prevCalled=false
hs.shutdownCallback = function() prevCalled=true end
obj.shutdownGuardInstalled=false
obj:installShutdownGuard()
ctl.shutdown()
R.check("hook préexistant chaîné", prevCalled, true)

R.finish()
