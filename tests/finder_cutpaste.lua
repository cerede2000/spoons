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

R.finish()
