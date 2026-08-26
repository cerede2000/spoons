-- Charge le init.lua du dépôt tel quel, avec le bouchon hs, et vérifie
-- qu'il s'assemble : Spoons chargés, entrées valides, raccourcis sans
-- conflit, accesseurs d'icône fonctionnels, dégradation propre.
package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install({ virtualFS = true, spoonRoot = "." })
hs.keycodes = { map = setmetatable({ x = 7, c = 8, v = 9, w = 13, m = 46,
                                     delete = 51, escape = 53 },
                                   { __index = function() return 0 end }) }
hs.osascript = { applescript = function() return true, 3 end }
hs.axuielement = { applicationElement = function() return nil end }
hs.eventtap.keyStroke = function() end
hs.pathwatcher = { new = function() return { start = function() end, stop = function() end } end }
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end

local ok, err = pcall(dofile, arg[1] or "init.lua")

R.section("Le fichier s'exécute sans erreur")
R.check("chargé", ok, true)
if not ok then out("  " .. tostring(err)) end

R.section("Tous les Spoons du dépôt répondent présent")
local attendus = { "ActivityKeeper", "WireGuardVPN", "LastWindowQuits",
                   "WindowSwitcher", "FinderCutPaste", "FinderPermanentDelete",
                   "SpoonManager" }
for _, nom in ipairs(attendus) do
    R.check(nom .. " chargé", spoon[nom] ~= nil, true)
end

R.section("SpoonManager a reçu les six Spoons pilotables")
R.check("six entrées", #spoon.SpoonManager.spoons, 6)

R.section("Chaque entrée passe le contrôle du gestionnaire")
local vus = {}
for i, item in ipairs(spoon.SpoonManager.spoons) do
    local valide, motif = spoon.SpoonManager:validateSpoonEntry(item, i, vus)
    vus[item.id] = true
    R.check(tostring(item.id) .. " valide", valide, true)
    if not valide then out("  " .. tostring(motif)) end
end

R.section("Les accesseurs d'icône fonctionnent")
for _, nom in ipairs({ "ActivityKeeper", "WireGuardVPN", "LastWindowQuits" }) do
    local entree
    for _, item in ipairs(spoon.SpoonManager.spoons) do
        if item.id == nom then entree = item end
    end
    R.check(nom .. " expose une icône", entree.icon ~= nil, true)
    if entree.icon then
        local avant = spoon.SpoonManager:isIconVisible(entree)
        spoon.SpoonManager:setIconVisible(entree, not avant)
        R.check(nom .. " : l'état bascule",
            spoon.SpoonManager:isIconVisible(entree), not avant)
        spoon.SpoonManager:setIconVisible(entree, avant)
    end
end

R.section("Les Spoons sans icône n'en déclarent pas")
for _, item in ipairs(spoon.SpoonManager.spoons) do
    if item.id:find("Finder") or item.id == "WindowSwitcher" then
        R.check(item.id .. " sans sous-menu d'icône", item.icon, nil)
    end
end

R.section("Aucun conflit de raccourci")
local source = ctl.realOpen(arg[1] or "init.lua"):read("*a")
local combos, conflits = {}, 0
for mods, key in source:gmatch('{%s*{([^}]*)}%s*,%s*"([^"]+)"%s*}') do
    local liste = {}
    for m in mods:gmatch('"([^"]+)"') do table.insert(liste, m) end
    table.sort(liste)
    local cle = table.concat(liste, "+") .. "+" .. key:lower()
    combos[cle] = (combos[cle] or 0) + 1
    if combos[cle] == 2 then conflits = conflits + 1 end
end
local total = 0
for _ in pairs(combos) do total = total + 1 end
R.check("raccourcis déclarés", total > 10, true)
R.check("conflits", conflits, 0)

R.section("Un Spoon manquant n'emporte pas la configuration")
local lib2 = require("lib_hs")
local ctl2 = lib2.install({ virtualFS = true, spoonRoot = "." })
hs.keycodes = { map = setmetatable({}, { __index = function() return 0 end }) }
hs.osascript = { applescript = function() return true, 3 end }
hs.axuielement = { applicationElement = function() return nil end }
hs.eventtap.keyStroke = function() end
ctl2.spoonFailures["WireGuardVPN"] = true
local ok2 = pcall(dofile, arg[1] or "init.lua")
R.check("le fichier s'exécute quand même", ok2, true)
R.check("les autres Spoons sont là", spoon.LastWindowQuits ~= nil, true)
R.check("le manquant est absent des entrées", (function()
    for _, item in ipairs(spoon.SpoonManager.spoons) do
        if item.id == "WireGuardVPN" then return true end
    end
    return false
end)(), false)
R.check("cinq entrées au lieu de six", #spoon.SpoonManager.spoons, 5)

R.finish()
