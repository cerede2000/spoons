package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.logToFile=false; obj.logFile="/dev/null"; obj.verboseLogging=false
local KEY = "LastWindowQuits.settings"

obj.running = true          -- bindHotkeys ne lie que si le Spoon tourne

R.section("init.lua fait autorité sur les réglages simples")
ctl.store[KEY] = { enabled=true, logToFile=false, quitDelay=5,
                   verboseLogging=false, blacklistAppNames={["App Persistee"]=true} }
obj.logToFile=true; obj.quitDelay=2
obj.blacklistAppNames={["App De InitLua"]=true}
obj.forceConfiguredSettingsOnStart=true; obj.persistMenuChanges=true
obj:applyConfiguredSettingDefaults()
obj:mergePersistentSettings()
R.check("logToFile respecté",            obj.logToFile, true)
R.check("quitDelay respecté",            obj.quitDelay, 2)
R.check("nom blacklisté par init.lua gardé", obj.blacklistAppNames["App De InitLua"], true)
R.check("nom persisté gardé aussi",       obj.blacklistAppNames["App Persistee"], true)
obj.logToFile=false

R.section("enabled n'est plus persisté")
ctl.store[KEY] = { enabled=false, quitDelay=2 }
obj.enabled=true
obj:applyConfiguredSettingDefaults()
R.check("clé enabled purgée", ctl.store[KEY].enabled, nil)
ctl.store[KEY] = { enabled=false, quitDelay=2 }
obj.enabled=true
obj:mergePersistentSettings()
R.check("un enabled=false résiduel n'éteint plus rien", obj.enabled, true)
obj.enabled=false
obj:savePersistentSettings()
R.check("savePersistentSettings ne l'écrit pas", ctl.store[KEY].enabled, nil)
obj.enabled=true

R.section("persistMenuChanges gouverne lecture ET écriture")
ctl.store={}
obj.persistMenuChanges=false; obj.quitDelay=2
obj:applyConfiguredSettingDefaults()
R.check("persistance coupée : rien d'écrit", ctl.store[KEY], nil)
ctl.store[KEY]={quitDelay=99}
obj:mergePersistentSettings()
R.check("persistance coupée : rien de relu", obj.quitDelay, 2)
obj.persistMenuChanges=true
obj:applyConfiguredSettingDefaults()
R.check("persistance active : écrit", ctl.store[KEY].quitDelay, 2)

R.section("Menu accessible sans icône")
obj.showMenuBar=false; obj.menuBar=nil; obj.pendingQuits={}; obj.enabled=true
obj:createMenuBar()
R.check("objet menu créé malgré showMenuBar=false", obj.menuBar ~= nil, true)
R.check("absent de la barre des menus", obj.menuBar.inMenuBar, false)
local first = obj.menuBar
obj:setMenuBarVisible(true)
R.check("icône activable", obj.menuBar.inMenuBar, true)
R.check("objet recréé, pas réutilisé", obj.menuBar ~= first, true)
obj:setMenuBarVisible(false)
R.check("icône redésactivable", obj.menuBar.inMenuBar, false)
R.check("choix persisté", ctl.store[KEY].showMenuBar, false)

R.section("Actions atteignables sans le menu")
local stopped = 0
obj.pendingQuits = {
    a={name="Safari", startedAt=998, timer={stop=function() stopped=stopped+1 end}},
    b={name="Notes",  startedAt=999, timer={stop=function() stopped=stopped+1 end}},
}
R.check("cancelAllPendingQuits renvoie le compte", obj:cancelAllPendingQuits(), 2)
R.check("timers arrêtés", stopped, 2)
R.check("file vidée", next(obj.pendingQuits), nil)
obj.pendingQuits={a={name="Safari", startedAt=999}}
local summary = obj:statusSummary()
R.check("le résumé cite le quit armé", summary:find("Safari") ~= nil, true)

R.section("Raccourcis : désactivés par défaut")
R.check("hotkeysEnabled par défaut", obj.hotkeysEnabled, false)
local MAP = { toggle={{"ctrl","alt","cmd"},"Q"}, menu={{"ctrl","alt","cmd"},"L"},
              status={{"ctrl","alt","cmd"},"I"}, blacklist={{"ctrl","alt","cmd"},"B"},
              cancel={{"ctrl","alt","cmd"},"K"} }
local function nb() local c=0 for _ in pairs(obj.hotkeys) do c=c+1 end return c end
obj.hotkeys={}
obj:bindHotkeys(MAP)
R.check("aucun raccourci lié", nb(), 0)
obj:setHotkeysEnabled(true)
R.check("réactivation sans repasser par bindHotkeys", nb(), 5)
obj:setHotkeysEnabled(false)
R.check("désactivation délie tout", nb(), 0)
obj:toggleHotkeys()
R.check("toggleHotkeys rebascule", nb(), 5)
R.check("choix persisté", ctl.store[KEY].hotkeysEnabled, true)
obj:bindHotkeys({toggle=MAP.toggle, menu=MAP.menu})
R.check("seules les actions déclarées sont liées", nb(), 2)
R.check("action absente non liée", obj.hotkeys.cancel, nil)

R.section("init.lua l'emporte dans les deux sens")
ctl.store[KEY]={hotkeysEnabled=false}
obj.hotkeysEnabled=true; obj.hotkeys={}
obj:bindHotkeys(MAP)
obj:applyConfiguredSettingDefaults(); obj:mergePersistentSettings(); obj:applyHotkeys()
R.check("init.lua peut les activer", nb(), 5)
ctl.store[KEY]={hotkeysEnabled=true}
obj.hotkeysEnabled=false; obj.hotkeys={}
obj:bindHotkeys(MAP)
obj:applyConfiguredSettingDefaults(); obj:mergePersistentSettings(); obj:applyHotkeys()
R.check("init.lua peut les couper", nb(), 0)

R.section("État transitoire remis à zéro par stop()")
obj.pausedUntil=99999; obj.seenApps={foo=true}; obj.startedAt=1; obj.clickCount=1
obj.pendingQuits={}; obj.menuBar=nil; obj.windowFilter=nil; obj.appWatcher=nil
obj.clickTimer=nil; obj.hotkeys={}
obj:stop()
R.check("pausedUntil effacé", obj.pausedUntil, nil)
R.check("startedAt effacé", obj.startedAt, nil)
R.check("seenApps vidé", next(obj.seenApps), nil)
R.check("clickCount remis à zéro", obj.clickCount, 0)
R.check("copyTable retirée", type(obj.copyTable), "nil")



------------------------------------------------------------
R.section("Un Spoon arrêté ne lie aucun raccourci")
-- Déclarer les raccourcis depuis SpoonManager ne doit pas les rendre
-- actifs alors que le Spoon est désactivé : ses touches piloteraient
-- un Spoon éteint.
------------------------------------------------------------
obj:deleteHotkeys()
obj.running = false
obj.hotkeysEnabled = true
obj:bindHotkeys(MAP)
R.check("rien n'est lié", nb(), 0)
R.check("mais le mapping est mémorisé", obj.hotkeyMapping ~= nil, true)

obj.running = true
obj:applyHotkeys()
R.check("le démarrage les applique", nb(), 5)

obj:stop()
R.check("l'arrêt les délie", nb(), 0)

R.finish()
