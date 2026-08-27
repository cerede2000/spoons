-- FinderPermanentDelete : le tap ne doit exister que dans le Finder.
package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
hs.keycodes = { map = { delete = 51 } }
hs.osascript = { applescript = function() return true, 3 end }
hs.axuielement = { applicationElement = function() return nil end }
local strokes = {}
hs.eventtap.keyStroke = function(mods, key)
    table.insert(strokes, table.concat(mods, "+") .. "+" .. key)
end
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.verboseLogging = false
obj.showNotifications = false

local finder = lib.app(ctl, { name = "Finder", bundle = "com.apple.finder" })
local autre  = lib.app(ctl, { name = "Safari", bundle = "com.apple.Safari" })

------------------------------------------------------------
R.section("Le tap n'existe que pendant que le Finder est au premier plan")
------------------------------------------------------------
-- Un eventtap fait passer chaque frappe du système par le thread
-- principal de Hammerspoon, et macOS attend la réponse. Tant que ce tap
-- existe, tout blocage de ce thread retarde la saisie PARTOUT. Le
-- callback vérifiait de toute façon le Finder en premier : hors du
-- Finder, le tap n'a aucune raison d'exister.
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

ctl.frontmost = nil
ctl.appWatcherFn()
R.check("aucune application au premier plan : pas de tap", obj.tapRunning, false)

R.section("Le veilleur est démonté à l'arrêt")
ctl.frontmost = finder
ctl.appWatcherFn()
R.check("tap actif", obj.tapRunning, true)
obj:stop()
R.check("veilleur arrêté", ctl.appWatcherRunning, false)
R.check("tap arrêté", obj.tapRunning, false)
R.check("tap libéré", obj.tap, nil)

R.section("On peut revenir au tap permanent")
obj.followFrontmostApp = false
ctl.frontmost = autre
obj:start()
R.check("tap permanent", obj.tapRunning, true)
R.check("aucun veilleur", ctl.appWatcherRunning, false)
obj:stop()
obj.followFrontmostApp = true

------------------------------------------------------------
R.section("Shift+Suppr dans le Finder devient une suppression definitive")
------------------------------------------------------------
ctl.frontmost = finder
obj:start()
local tap
for _, t in ipairs(ctl.eventtaps) do
    if t.types and t.types[1] == "keyDown" then tap = t end
end
R.check("le tap ecoute les touches", tap ~= nil, true)

local function touche(code, flags)
    return tap.fn({
        getKeyCode = function() return code end,
        getFlags = function()
            return { containExactly = function(_, liste)
                if #liste ~= #flags then return false end
                for _, m in ipairs(liste) do
                    local vu = false
                    for _, f in ipairs(flags) do if f == m then vu = true end end
                    if not vu then return false end
                end
                return true
            end }
        end,
    })
end

strokes = {}
R.check("Shift+Suppr est consommee", touche(51, { "shift" }), true)
R.check("et remplacee par Cmd+Alt+Suppr", strokes[1], "cmd+alt+delete")

strokes = {}
R.check("Suppr seule passe", touche(51, {}), false)
R.check("rien d'emis", #strokes, 0)

R.check("Cmd+Shift+Suppr passe", touche(51, { "cmd", "shift" }), false)
R.check("Shift+autre touche passe", touche(8, { "shift" }), false)
obj:stop()

R.finish()
