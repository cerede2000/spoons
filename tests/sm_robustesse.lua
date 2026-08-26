package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showNotifications = true

local notified = {}
local realNew = hs.notify.new
hs.notify.new = function(t) table.insert(notified, t.informativeText or ""); return {send=function() end} end

local function find(menu, pattern)
    for _, e in ipairs(menu or {}) do
        if type(e.title)=="string" and e.title:match(pattern) then return e end
    end
end
local function count(t) local c=0 for _ in ipairs(t or {}) do c=c+1 end return c end
local function safe(m, ...)
    if type(obj[m]) ~= "function" then return "<absent>" end
    local ok, r = pcall(obj[m], obj, ...)
    if not ok then return "<erreur>" end
    return r
end
local function good(id, label)
    return { id=id, label=label, defaultEnabled=true, start=function() end, stop=function() end }
end

R.section("Une entrée mal formée n'emporte plus le gestionnaire")
ctl.store={}; notified={}
local r = safe("registerSpoons", {
    good("OK1","Bon Spoon"),
    { label="Sans identifiant", start=function() end },
    { id="PASTART" },
    "une chaîne au lieu d'une table",
    { id="OK1", label="Doublon", start=function() end },
    { id="TYPO", label="Typo", start=nil, stop=function() end },
    good("OK2","Autre bon Spoon"),
})
R.check("registerSpoons ne lève pas", r ~= "<erreur>", true)
R.check("seules les entrées valides gardées", count(obj.spoons), 2)
R.check("chargement des états ne lève pas", safe("loadEnabledSpoons") ~= "<erreur>", true)
R.check("construction du menu ne lève pas", safe("buildMenu") ~= "<erreur>", true)
local menu = obj:buildMenu()
R.check("le bon Spoon est là", find(menu, "^Bon Spoon") ~= nil, true)
R.check("le doublon est écarté", find(menu, "Doublon"), nil)
R.check("l'utilisateur est prévenu", #notified > 0, true)

R.section("Un échec est visible, quel que soit le chemin")
ctl.store={}; notified={}
obj:registerSpoons({ { id="KO", label="Casse", defaultEnabled=false,
                       start=function() error("boum") end, stop=function() end } })
obj:loadEnabledSpoons()
obj:setSpoonEnabled(obj.spoons[1], true)
local e = find(obj:buildMenu(), "^Casse")
R.check("entrée marquée en échec", e and e.state, "mixed")
R.check("libellé explicite", (e and e.title or ""):match("echec") ~= nil, true)
R.check("préférence non enregistrée", ctl.store["SpoonManager.enabledSpoons"], nil)

R.section("Un échec transitoire ne devient pas permanent")
obj.spoons[1].start = function() end
obj:toggleSpoon(obj.spoons[1])
local e2 = find(obj:buildMenu(), "^Casse")
R.check("après succès : cochée", e2 and e2.checked, true)
R.check("après succès : plus d'état mixed", e2 and e2.state, nil)
R.check("marque d'échec effacée", obj.failedSpoons.KO, nil)

R.section("Le démarrage n'écrase pas la préférence")
ctl.store={}; obj.enabledSpoons=nil; obj.failedSpoons={}
obj:registerSpoons({ good("A","A"), { id="KO2", label="Casse2", defaultEnabled=true,
                                      start=function() error("boum") end, stop=function() end } })
obj:startEnabledSpoons()
R.check("la préférence reste activée", obj:isEnabled(obj.spoons[2]), true)
R.check("le démarrage n'écrit rien", ctl.store["SpoonManager.enabledSpoons"], nil)
R.check("l'échec est retenu pour l'affichage", obj.failedSpoons.KO2, true)

R.section("stop() arrête les Spoons gérés")
local stopped = {}
obj:registerSpoons({
    { id="A", label="A", defaultEnabled=true, start=function() end, stop=function() stopped.A=true end },
    { id="B", label="B", defaultEnabled=true, start=function() end, stop=function() stopped.B=true end },
})
obj:loadEnabledSpoons()
obj.menuBar = nil
obj:stop()
R.check("Spoon A arrêté", stopped.A, true)
R.check("Spoon B arrêté", stopped.B, true)
R.check("préférence conservée pour le prochain start", obj:isEnabled(obj.spoons[1]), true)

R.section("Accesseur d'icône incomplet : sous-menu perdu, Spoon gardé")
obj:registerSpoons({ { id="I", label="Icone cassee", start=function() end,
                       icon={ get=function() return true end } } })
R.check("le Spoon est conservé", count(obj.spoons), 1)
R.check("le sous-menu est retiré", obj.spoons[1].icon, nil)
R.check("aucun sous-menu dans le menu", find(obj:buildMenu(), "Icone cassee").menu, nil)

R.section("Non-régression : liste entièrement valide")
ctl.store={}
obj:registerSpoons({ good("X","Spoon X"), good("Y","Spoon Y") })
obj:loadEnabledSpoons()
R.check("les deux enregistrés", count(obj.spoons), 2)
R.check("actifs par défaut", obj:isEnabled(obj.spoons[1]), true)
obj:startEnabledSpoons()
R.check("aucun échec", next(obj.failedSpoons), nil)

hs.notify.new = realNew
R.finish()
