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


------------------------------------------------------------
R.section("Surveillance du thread principal")
------------------------------------------------------------
-- Tout ce que fait Hammerspoon s'exécute sur un seul thread, et un
-- eventtap y fait passer chaque frappe et chaque clic. Tant que ce
-- thread est occupé, macOS attend : l'utilisateur perd le clavier et la
-- souris. Un timer périodique comparé à l'heure à laquelle il aurait dû
-- partir mesure exactement ces blocages.
obj.mainThreadWatchEnabled = true
obj.mainThreadWatchInterval = 0.5
obj.mainThreadStallThreshold = 0.25
obj.mainThreadStalls = 0
obj.mainThreadWorstStall = 0
ctl.everyTimers = {}
obj:startMainThreadWatch()
R.check("un timer périodique est en place", #ctl.everyTimers, 1)
R.check("à la bonne cadence", ctl.everyTimers[1].delay, 0.5)

-- À l'heure : rien à signaler.
ctl.now = ctl.now + 0.5
ctl.printed = {}
ctl.everyTimers[1].fn()
R.check("timer à l'heure : silence", #ctl.printed, 0)
R.check("aucun blocage compté", obj.mainThreadStalls, 0)

-- Un léger retard, sous le seuil : toujours silence.
ctl.now = ctl.now + 0.6
ctl.printed = {}
ctl.everyTimers[1].fn()
R.check("retard sous le seuil : silence", #ctl.printed, 0)

-- Un vrai blocage.
ctl.now = ctl.now + 1.25
ctl.printed = {}
ctl.everyTimers[1].fn()
R.check("blocage signalé", #ctl.printed, 1)
R.check("la durée est dite",
    table.concat(ctl.printed, " "):find("750 ms", 1, true) ~= nil, true)
R.check("et ce qu'elle coûte",
    table.concat(ctl.printed, " "):find("aucune frappe", 1, true) ~= nil, true)
R.check("compté", obj.mainThreadStalls, 1)
R.check("le pire est retenu", math.floor(obj.mainThreadWorstStall * 1000), 750)

-- Le retard ne se cumule pas : la référence repart de l'instant réel.
ctl.now = ctl.now + 0.5
ctl.printed = {}
ctl.everyTimers[1].fn()
R.check("pas de blocage fantôme au tour suivant", #ctl.printed, 0)

R.section("La surveillance s'arrête et se raconte")
local etat = obj:mainThreadStatus()
R.check("l'état dit qu'elle est active", etat:find("active", 1, true) ~= nil, true)
R.check("et donne le pire", etat:find("750 ms", 1, true) ~= nil, true)
obj:stopMainThreadWatch()
R.check("timer libéré", obj.mainThreadTimer, nil)

obj.mainThreadWatchEnabled = false
ctl.everyTimers = {}
obj:startMainThreadWatch()
R.check("désactivable : aucun timer", #ctl.everyTimers, 0)
obj.mainThreadWatchEnabled = true


------------------------------------------------------------
R.section("Les requêtes d'accessibilité sont bornées")
------------------------------------------------------------
-- Une requête d'accessibilité est un aller-retour vers une AUTRE
-- application. Si elle est occupée, l'appel bloque — et sans délai
-- fixé, aussi longtemps qu'elle le décide. Pendant ce temps, aucune
-- touche n'est transmise, puisqu'un eventtap fait passer chaque frappe
-- par ce même thread.
--
-- Mesuré sur la machine, 57 applications : 2626 ms à froid, 19 ms en
-- moyenne. Le cas normal coûte 0,3 ms par application ; le cas
-- pathologique n'avait aucune borne.
ctl.axTimeoutSet = nil
ctl.axTimeoutFails = false
obj.axTimeout = 0.10
obj:applyAXTimeout()
R.check("la borne est appliquée", ctl.axTimeoutSet, 0.10)

ctl.printed = {}
obj:applyAXTimeout()
R.check("et elle est annoncée",
    table.concat(ctl.printed, " "):find("bornees a 100 ms", 1, true) ~= nil, true)

R.section("Un refus du système est dit, pas avalé")
ctl.axTimeoutSet = nil
ctl.axTimeoutFails = true
ctl.printed = {}
obj:applyAXTimeout()
R.check("rien n'est appliqué", ctl.axTimeoutSet, nil)
R.check("l'échec est journalisé",
    table.concat(ctl.printed, " "):find("bloquer le clavier", 1, true) ~= nil, true)
ctl.axTimeoutFails = false

R.section("Réglable et désactivable")
obj.axTimeout = 1.5
obj:applyAXTimeout()
R.check("valeur personnalisée", ctl.axTimeoutSet, 1.5)

ctl.axTimeoutSet = nil
obj.axTimeout = nil
obj:applyAXTimeout()
R.check("nil : on ne touche à rien", ctl.axTimeoutSet, nil)
obj.axTimeout = -1
obj:applyAXTimeout()
R.check("négatif : on ne touche à rien non plus", ctl.axTimeoutSet, nil)
obj.axTimeout = 0.10

R.section("La borne est posée avant le démarrage des Spoons")
-- Les Spoons interrogent l'accessibilité dès leur démarrage : poser la
-- borne après les aurait laissés exposés pour leur première passe.
ctl.axTimeoutSet = nil
local ordre = {}
local vraiApply = obj.applyAXTimeout
local vraiStart = obj.startEnabledSpoons
obj.applyAXTimeout = function(self) ordre[#ordre+1] = "borne"; return vraiApply(self) end
obj.startEnabledSpoons = function(self) ordre[#ordre+1] = "spoons"; return self end
obj:start()
obj.applyAXTimeout = vraiApply
obj.startEnabledSpoons = vraiStart
R.check("la borne d'abord", ordre[1], "borne")
R.check("les Spoons ensuite", ordre[2], "spoons")
obj:stop()

R.finish()
