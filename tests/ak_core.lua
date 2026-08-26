package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showStateNotifications=false; obj.verboseLogging=false

local function keepaliveSetup()
    obj.keyboardBrightnessBackend="mac-brightnessctl"
    obj.keyboardBrightnessTool="/opt/homebrew/bin/mac-brightnessctl"
    obj.keyboardBacklightEnforceAfterKeepAlive=true
    obj.isKeyboardBacklightEnabled=function() return true end
    obj.currentState=obj.STATE.KEEPALIVE
    obj.savedKeyboardBrightness=nil
    obj.lastKnownNonZeroKeyboardBrightness=nil
    obj.keyboardBacklightModified=false
    ctl.shell={}; ctl.kbIndex=0
end

R.section("Aucun appel shell dans le chemin d'événement")
keepaliveSetup(); obj.currentState=obj.STATE.MONITORING
obj.lastKeyboardBrightnessSampleAt=nil
ctl.shell={}
obj:handleRealUserActivity()
R.check("handleRealUserActivity ne lance rien", #ctl.shell, 0)

R.section("Un seul tap système à la fois")
obj.fastReturnWatcherEnabled=true
obj.inputWatcher=nil; obj.fastReturnWatcher=nil
obj.currentState=obj.STATE.OFF
obj:createInputWatcher(); obj.inputWatcher:start()
obj.currentState=obj.STATE.MONITORING
obj:setState(obj.STATE.KEEPALIVE)
R.check("inputWatcher arrêté en vert", obj.inputWatcher.running, false)
R.check("fastReturn actif", obj.fastReturnWatcher.running, true)
obj:setState(obj.STATE.MONITORING)
R.check("inputWatcher relancé en jaune", obj.inputWatcher.running, true)
R.check("fastReturn arrêté", obj.fastReturnWatcher.running, false)
obj.fastReturnWatcherEnabled=false
obj:setState(obj.STATE.KEEPALIVE)
R.check("sans fastReturn, inputWatcher reste seul détecteur", obj.inputWatcher.running, true)
obj.fastReturnWatcherEnabled=true
obj:setState(obj.STATE.MONITORING); obj.inputWatcher:stop()
obj:setState(obj.STATE.OFF)
R.check("OFF ne ressuscite pas le watcher", obj.inputWatcher.running, false)

R.section("Commandes shell")
keepaliveSetup(); ctl.kbSequence={0.42}
obj.lastKeyboardBrightnessSampleAt=nil
obj.currentState=obj.STATE.MONITORING
obj:sampleKeyboardBrightness(true)
R.check("chemin quoté en shell", (ctl.shell[1] or ""):match("^'/opt") ~= nil, true)
ctl.shell={}
obj:getLowPowerStates()
R.check("pmset quoté aussi", (ctl.shell[1] or ""):match("^'/usr/bin/pmset' %-g custom") ~= nil, true)
R.check("code mort retiré", type(obj.wakeKeyboardForBacklightProbe), "nil")

R.section("Rétroéclairage déjà éteint")
keepaliveSetup(); ctl.kbSequence={0.0}
obj:forceKeyboardBacklightOffAfterKeepAlive()
R.check("un seul appel shell", #ctl.shell, 1)
R.check("aucune modification revendiquée", obj.keyboardBacklightModified, false)
ctl.shell={}
obj:restoreKeyboardBacklight(false)
local litUp=false
for _,c in ipairs(ctl.shell) do if c:match("0%.5000") then litUp=true end end
R.check("le clavier n'est pas rallumé à 50 %", litUp, false)

R.section("Rétroéclairage allumé : inchangé")
keepaliveSetup(); ctl.kbSequence={0.42}
obj:forceKeyboardBacklightOffAfterKeepAlive()
R.check("valeur capturée", obj.savedKeyboardBrightness, 0.42)
R.check("modification revendiquée", obj.keyboardBacklightModified, true)
R.check("lecture + écriture", #ctl.shell, 2)

R.section("Message périodique sous verboseLogging")
obj.currentState=obj.STATE.KEEPALIVE
obj.keepAliveInProgress=false; obj.lastKeepAliveTime=nil
obj.sendUserActivity=function() return false end
obj.sendKeyboardActivity=function() return true end
obj.sendMouseActivity=function() return false end
obj.scheduleKeyboardBacklightEnforce=function() end
obj.verboseLogging=false; ctl.printed={}
obj:sendKeepAlive()
local noisy=0; for _,l in ipairs(ctl.printed) do if l:match("Keepalive #") then noisy=noisy+1 end end
R.check("silencieux par défaut", noisy, 0)
obj.verboseLogging=true; obj.keepAliveInProgress=false; obj.lastKeepAliveTime=nil
ctl.printed={}
obj:sendKeepAlive()
noisy=0; for _,l in ipairs(ctl.printed) do if l:match("Keepalive #") then noisy=noisy+1 end end
R.check("disponible en verbeux", noisy, 1)
obj.verboseLogging=false

R.section("Écran d'origine débranché")
ctl.screens={ {x=0,y=0,w=1512,h=944,fullH=982,id=1,brightness=0.9} }
obj.screenBrightnessModified=true
obj.savedScreenBrightness=0.75; obj.savedScreenId=99
R.check("restauration abandonnée", obj:restoreScreen(), false)
R.check("écran principal non écrasé", ctl.screens[1].brightness, 0.9)
R.check("drapeau remis à zéro", obj.screenBrightnessModified, false)
obj.screenBrightnessModified=true
obj.savedScreenBrightness=0.80; obj.savedScreenId=1
R.check("cas nominal : restauré", obj:restoreScreen(), true)
R.check("bonne valeur", ctl.screens[1].brightness, 0.80)

R.finish()
