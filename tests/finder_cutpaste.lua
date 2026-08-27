package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
hs.keycodes = { map = { x = 7, c = 8, v = 9, delete = 51 } }
hs.osascript = { applescript = function() return true, 3 end }
hs.axuielement = { applicationElement = function() return nil end }
local strokes = {}
hs.eventtap.keyStroke = function(mods, key) table.insert(strokes, table.concat(mods, "+") .. "+" .. key) end
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.verboseLogging = false

R.section("Le marqueur de copie synthétique expire")
obj.cutPending = false
obj:disarmSyntheticCopy()
obj:armSyntheticCopy()
R.check("armé après un couper", obj.ignoreSyntheticCopy, true)
R.check("un minuteur d'expiration existe", obj.syntheticCopyTimer ~= nil, true)
ctl.fireTimers()
R.check("désarmé tout seul après le délai", obj.ignoreSyntheticCopy, false)
R.check("minuteur nettoyé", obj.syntheticCopyTimer, nil)

R.section("Un vrai Cmd+C annule bien le couper")
obj.cutPending = true
obj:armSyntheticCopy()
obj:disarmSyntheticCopy()          -- le Cmd+C synthétique a été vu
R.check("désarmé", obj.ignoreSyntheticCopy, false)
R.check("le couper est toujours en attente", obj.cutPending, true)
obj:cancelCut()
R.check("un vrai Cmd+C l'annule", obj.cutPending, false)

R.section("stop() ne laisse pas le marqueur armé")
obj:armSyntheticCopy()
obj.tap = { stop = function() end }
obj:stop()
R.check("marqueur désarmé", obj.ignoreSyntheticCopy, false)
R.check("minuteur arrêté", obj.syntheticCopyTimer, nil)
R.check("couper annulé", obj.cutPending, false)

R.section("L'indicateur est recréé, jamais réinséré")
ctl.canvases = {}
obj.menuBar = nil
obj:showIndicator()
R.check("indicateur créé", obj.menuBar ~= nil, true)
R.check("directement dans la barre", obj.menuBar.inMenuBar, true)
local first = obj.menuBar
obj:hideIndicator()
R.check("détruit, pas retiré", obj.menuBar, nil)
obj:showIndicator(3)
R.check("recréé au couper suivant", obj.menuBar ~= nil, true)
R.check("objet neuf", obj.menuBar ~= first, true)



------------------------------------------------------------
R.section("Le tap n'existe que pendant que le Finder est au premier plan")
------------------------------------------------------------
-- Un eventtap fait passer chaque frappe du système par le thread
-- principal de Hammerspoon, et macOS attend la réponse. Tant que ce tap
-- existe, le moindre blocage de ce thread — un balayage d'accessibilité,
-- un autre Spoon — retarde la saisie PARTOUT. Le callback commençait de
-- toute façon par vérifier que le Finder est au premier plan : hors du
-- Finder, le tap n'a aucune raison d'exister.
local finder = lib.app(ctl, { name = "Finder", bundle = "com.apple.finder" })
local autre  = lib.app(ctl, { name = "Safari", bundle = "com.apple.Safari" })

ctl.frontmost = autre
obj:start()
R.check("hors du Finder : le tap ne tourne pas", obj.tapRunning, false)
R.check("un veilleur d'application est en place", ctl.appWatcherRunning, true)

ctl.frontmost = finder
ctl.appWatcherFn()
R.check("le Finder passe devant : le tap démarre", obj.tapRunning, true)

ctl.frontmost = autre
ctl.appWatcherFn()
R.check("on quitte le Finder : le tap s'arrête", obj.tapRunning, false)

R.section("Aucune application au premier plan")
ctl.frontmost = nil
ctl.appWatcherFn()
R.check("pas de Finder, pas de tap", obj.tapRunning, false)

R.section("Le veilleur est démonté à l'arrêt")
ctl.frontmost = finder
ctl.appWatcherFn()
R.check("tap actif", obj.tapRunning, true)
obj:stop()
R.check("veilleur arrêté", ctl.appWatcherRunning, false)
R.check("tap arrêté", obj.tapRunning, false)

R.section("On peut revenir au tap permanent")
obj.followFrontmostApp = false
ctl.frontmost = autre
obj:start()
R.check("tap permanent malgré l'application au premier plan", obj.tapRunning, true)
R.check("aucun veilleur", ctl.appWatcherRunning, false)
obj:stop()
obj.followFrontmostApp = true

R.finish()
