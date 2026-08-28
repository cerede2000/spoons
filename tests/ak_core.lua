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
R.check("handleRealUserActivity ne lance rien en surveillance", #ctl.shell, 0)

------------------------------------------------------------
R.section("Le tap ne restaure rien lui-même : c'est là qu'on perdait des touches")
------------------------------------------------------------
-- En KEEPALIVE, handleRealUserActivity restaure les états énergétiques :
-- mac-brightnessctl pour le clavier, « sudo pmset » pour l'économie
-- d'énergie -- tous par hs.execute, bloquant. Le faire dans le callback
-- d'un eventtap retenait chaque frappe pendant ce temps, et c'est
-- précisément l'instant où l'utilisateur recommence à taper.
--
-- Le test précédent passait à vide : il appelait handleRealUserActivity
-- en MONITORING, état où la restauration ne s'exécute pas.
obj.fastReturnWatcherEnabled=true
obj.inputWatcher=nil; obj.fastReturnWatcher=nil
ctl.eventtaps={}
obj:createFastReturnWatcher()
local tapRapide
for _, t in ipairs(ctl.eventtaps) do
    for _, ty in ipairs(t.types or {}) do
        if ty == "keyDown" then tapRapide = t end
    end
end
R.check("le tap rapide écoute bien les frappes", tapRapide ~= nil, true)

keepaliveSetup()
obj.currentState=obj.STATE.KEEPALIVE
obj.lastFastReturnEventAt = 0
obj.realActivityPending = false
obj.syntheticEventIgnoreUntil = 0
-- de quoi restaurer : c'est ce qui déclenche mac-brightnessctl
obj.keyboardBacklightModified = true
obj.savedKeyboardBrightness = 0.42
ctl.shell={}; ctl.timers={}
tapRapide.fn()
R.check("rien de bloquant dans le tap", #ctl.shell, 0)
R.check("l'état n'a pas encore basculé", obj.currentState, obj.STATE.KEEPALIVE)
R.check("un travail est programmé", obj.realActivityPending, true)

ctl.fireOnly(0)
R.check("le travail a bien eu lieu ensuite", obj.currentState, obj.STATE.MONITORING)
R.check("et la restauration aussi", #ctl.shell > 0, true)
R.check("le verrou est rendu", obj.realActivityPending, false)

R.section("Une rafale de frappes ne programme qu'un seul travail")
keepaliveSetup()
obj.currentState=obj.STATE.KEEPALIVE
obj.lastFastReturnEventAt = 0
obj.realActivityPending = false
obj.syntheticEventIgnoreUntil = 0
obj.fastReturnThrottle = 0
ctl.timers={}
for _ = 1, 20 do tapRapide.fn() end
R.check("vingt frappes, un seul travail programmé", #ctl.timers, 1)
ctl.fireOnly(0)

R.section("Le watcher ordinaire ne bloque pas davantage")
obj.inputWatcher=nil
ctl.eventtaps={}
obj:createInputWatcher()
local tapLent = ctl.eventtaps[#ctl.eventtaps]
keepaliveSetup()
obj.currentState=obj.STATE.KEEPALIVE
obj.fastReturnWatcherEnabled=false
obj.realActivityPending=false
obj.syntheticEventIgnoreUntil=0
ctl.shell={}; ctl.timers={}
tapLent.fn()
R.check("rien de bloquant dans le tap", #ctl.shell, 0)
ctl.fireOnly(0)
R.check("mais le travail se fait", obj.currentState, obj.STATE.MONITORING)
obj.fastReturnWatcherEnabled=true

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
