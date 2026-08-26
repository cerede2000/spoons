package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.logToFile=false; obj.logFile="/dev/null"; obj.verboseLogging=false

local W = lib.window

R.section("isCountableWindow : une réduction n'est pas une fermeture")
R.check("fenêtre normale visible",          obj:isCountableWindow(W{id=1}), true)
R.check("fenêtre RÉDUITE (subrole perdu)",  obj:isCountableWindow(W{id=2, visible=false, standard=false}), true)
R.check("application masquée (Cmd+H)",      obj:isCountableWindow(W{id=3, visible=false, standard=true}), true)
R.check("bureau Finder (AXScrollArea)",     obj:isCountableWindow(W{id=4, role="AXScrollArea", standard=false}), false)
R.check("palette visible non standard",     obj:isCountableWindow(W{id=5, standard=false}), false)
-- AX qui ne répond plus sur le rôle : le doute ne doit jamais
-- provoquer une fermeture.
local muette = { id=function() return 6 end,
                 role=function() error("AX muette") end,
                 isStandard=function() return false end,
                 isVisible=function() return true end }
R.check("rôle illisible : on compte quand même", obj:isCountableWindow(muette), true)
R.check("nil",                              obj:isCountableWindow(nil), false)

R.section("countWindows distingue zéro et inconnu")
local app = lib.app(ctl, {name="App", bundle="com.t.app", windows={W{id=1}}})
ctl.axMode="ok";     R.check("une fenêtre",              obj:countWindows(app), 1)
-- un zéro isolé ne conclut plus : il faut quitConfirmations observations
ctl.axMode="vide"
R.check("premier zéro : indécidable", obj:countWindows(app), nil)
for _ = 2, obj.quitConfirmations - 1 do obj:countWindows(app) end
R.check("aucune fenêtre, une fois confirmé : 0", obj:countWindows(app), 0)
ctl.axMode="erreur"; R.check("AX muette : nil, pas 0",   obj:countWindows(app), nil)
ctl.axMode="ok";     R.check("application absente : nil", obj:countWindows(nil), nil)

R.section("canHaveWindows : optimisation, pas une règle")
R.check("application du Dock",  obj:canHaveWindows(lib.app(ctl,{name="S",bundle="b",kind=1})), true)
R.check("utilitaire de barre de menus : suivi lui aussi",
                                obj:canHaveWindows(lib.app(ctl,{name="A",bundle="b",kind=0})), true)
R.check("daemon sans interface : écarté",
                                obj:canHaveWindows(lib.app(ctl,{name="D",bundle="b",kind=-1})), false)
R.check("nil",                  obj:canHaveWindows(nil), false)

R.section("Aucune application n'est protégée par son type")
obj.blacklistBundleIDs={}; obj.blacklistAppNames={}
local dock    = { app=lib.app(ctl,{name="Safari",bundle="com.apple.Safari",kind=1}), bundleID="com.apple.Safari", name="Safari" }
local menulet = { app=lib.app(ctl,{name="WARP",bundle="com.cloudflare.1dot1dot1dot1.macos",kind=0}), bundleID="com.cloudflare.1dot1dot1dot1.macos", name="WARP" }
R.check("application du Dock : éligible", (obj:isApplicationAllowed(dock)), true)
R.check("utilitaire de barre de menus : éligible aussi", (obj:isApplicationAllowed(menulet)), true)
R.check("app introuvable : pas d'exclusion abusive", (obj:isApplicationAllowed({bundleID="x", name="X"})), true)

-- la protection passe par la liste d'exclusion, comme pour tout le reste
obj.blacklistBundleIDs = { ["com.cloudflare.1dot1dot1dot1.macos"] = true }
local ok2, why2 = obj:isApplicationAllowed(menulet)
R.check("protégeable via ignored-bundles.txt", ok2, false)
R.check("motif", why2, "blacklist")
obj.blacklistBundleIDs = {}

R.section("isWindowStillPresent")
local holder = lib.app(ctl, {name="H", bundle="com.h"})
local w1 = W{id=11, app=holder, visible=false, standard=false}
holder._windows = { w1 }
R.check("fenêtre réduite toujours présente", obj:isWindowStillPresent(w1), true)
local orphan = W{id=22, app=holder}
R.check("fenêtre absente de la liste",        obj:isWindowStillPresent(orphan), false)

R.section("windowRejected n'est pas une fermeture")
local removed = false
local realRemoved = obj.onWindowRemoved
obj.onWindowRemoved = function() removed = true end
obj.pendingRecounts = {}
obj:onWindowRejected(w1, "H")
R.check("fenêtre encore là : aucune fermeture", removed, false)
removed = false
obj:onWindowRejected(orphan, "H")
R.check("fenêtre disparue : fermeture", removed, true)
obj.onWindowRemoved = realRemoved

R.section("Une fermeture = un recomptage, un quit, un délai fixe")
ctl.axMode="ok"
local victim = lib.app(ctl, {name="Notes", bundle="com.t.notes", kind=1, windows={}})
ctl.runningApps = { victim }
obj.enabled=true; obj.running=true; obj.quitDelay=5
obj.startupGracePeriod=0; obj.startedAt=0; obj.powerSuspended=false
obj.pendingQuits={}; obj.pendingRecounts={}; obj.windowCounts={}
obj.seenApps={["com.t.notes"]=true}
obj.windowTransitionFallbackEnabled=true; obj.windowTransitionScanInterval=5
ctl.timers={}
local win = W{id=7, app=victim}
obj:onWindowDestroyed(win, "Notes")
obj:onWindowRejected(win, "Notes")
R.check("un seul recomptage programmé", #ctl.timers, 1)
ctl.fireOnly(obj.windowRemovalRecheckDelay)
-- il faut quitConfirmations observations à zéro pour conclure
for _ = 1, obj.quitConfirmations do
    obj.windowCounts = { ["com.t.notes"] = 1 }
    obj:scanWindowTransitions(false)
end
local armed, pending = 0, nil
for _, p in pairs(obj.pendingQuits) do armed = armed + 1; pending = p end
R.check("un seul quit armé", armed, 1)
R.check("délai ancré sur la première détection", pending and pending.startedAt, 1000)
R.check("pid mémorisé pour l'annulation", pending and pending.pid ~= nil, true)

R.section("Coût du scan : deux vitesses")
-- 3 applications avec fenêtres, 2 sans, 20 daemons
ctl.runningApps = {}
table.insert(ctl.runningApps, lib.app(ctl,{name="Safari",bundle="com.safari",kind=1,windows={W{id=1}}}))
table.insert(ctl.runningApps, lib.app(ctl,{name="Notes", bundle="com.notes", kind=1,windows={W{id=2}}}))
table.insert(ctl.runningApps, lib.app(ctl,{name="WARP",  bundle="com.warp",  kind=0,windows={W{id=3}}}))
table.insert(ctl.runningApps, lib.app(ctl,{name="Vide1", bundle="com.vide1", kind=0,windows={}}))
table.insert(ctl.runningApps, lib.app(ctl,{name="Vide2", bundle="com.vide2", kind=0,windows={}}))
for i = 1, 20 do
    table.insert(ctl.runningApps, lib.app(ctl,{name="d"..i, bundle="com.d"..i, kind=-1}))
end
obj.blacklistBundleIDs={}; obj.blacklistAppNames={}
obj.windowCounts={}; obj.pendingQuits={}
obj.windowTransitionFallbackEnabled=true
obj.windowTransitionScanInterval=5
obj.windowTransitionFullScanInterval=30
obj.lastFullScanAt=nil
obj.enabled=true; obj.running=true; obj.powerSuspended=false

ctl.axCalls = 0
obj:scanWindowTransitions(true)
R.check("balayage complet : 25 process, 5 requêtes", ctl.axCalls, 5)
R.check("les 20 daemons écartés d'office", ctl.axCalls, 5)

ctl.axCalls = 0
obj:scanWindowTransitions(false)
R.check("tick suivant : seules les 3 avec fenêtres", ctl.axCalls, 3)

-- une application qui gagne une fenêtre est vue par l'événement,
-- pas par le tick partiel
ctl.runningApps[4]._windows = { W{id=9} }
ctl.axCalls = 0
obj:scanWindowTransitions(false)
R.check("nouvelle fenêtre non vue par le tick partiel", ctl.axCalls, 3)
obj:onWindowCreated(W{id=9, app=ctl.runningApps[4]}, "Vide1")
ctl.axCalls = 0
obj:scanWindowTransitions(false)
R.check("windowCreated l'a fait entrer dans le suivi", ctl.axCalls, 4)

-- le balayage complet rattrape même sans événement
ctl.runningApps[5]._windows = { W{id=10} }
obj.lastFullScanAt = nil
ctl.axCalls = 0
obj:scanWindowTransitions(false)
R.check("balayage complet : tout le monde à nouveau", ctl.axCalls, 5)

R.section("Le filet fonctionne toujours")
-- Safari perd sa dernière fenêtre : détecté par le tick partiel
ctl.runningApps[1]._windows = {}
obj.seenApps={["com.safari"]=true}
obj.startupGracePeriod=0; obj.startedAt=0; obj.quitDelay=5
ctl.timers={}; ctl.killed={}
-- le scan conclut au bout de quitConfirmations passages
for _ = 1, obj.quitConfirmations do obj:scanWindowTransitions(false) end
local armed=0 for _ in pairs(obj.pendingQuits) do armed=armed+1 end
R.check("fermeture détectée par un tick partiel", armed, 1)

R.section("Le journal donne l'identifiant à la fermeture")
R.check("libellé avec bundleID",
        obj:appLogLabel({name="Cloudflare WARP", bundleID="com.cloudflare.1dot1dot1dot1.macos"}),
        "Cloudflare WARP [com.cloudflare.1dot1dot1dot1.macos]")
R.check("sans bundleID : nom seul", obj:appLogLabel({name="Sans bundle"}), "Sans bundle")
R.check("sans rien", obj:appLogLabel(nil), "Application inconnue")



------------------------------------------------------------
R.section("Plein écran : une liste de fenêtres vide ne prouve rien")
-- hs.window.filter le dit dans son propre code : « windows on a
-- different space aren't picked up by :allWindows() at first refresh ».
-- Quand une application passe en plein écran elle prend son propre
-- espace, et toutes les autres deviennent invisibles à cette liste.
-- Un zéro y était lu comme « dernière fenêtre fermée », et Notes ou
-- Claude étaient quittées sans que personne n'ait rien fermé.
------------------------------------------------------------
local fenetreAilleurs = lib.window({ id = 900 })
local surAutreEspace = lib.app(ctl, {
    name = "Notes", bundle = "com.apple.Notes",
    windows = {},                       -- allWindows() ne voit rien
    hiddenBySpace = fenetreAilleurs,    -- mais mainWindow() répond
})
R.check("comptage indécidable, pas zéro", obj:countWindows(surAutreEspace), nil)

local vraimentVide = lib.app(ctl, {
    name = "Vide", bundle = "com.exemple.vide", windows = {},
})
for _ = 1, obj.quitConfirmations - 1 do obj:countWindows(vraimentVide) end
R.check("une application réellement sans fenêtre compte zéro, une fois confirmé",
    obj:countWindows(vraimentVide), 0)

local avecFenetre = lib.app(ctl, {
    name = "Avec", bundle = "com.exemple.avec",
    windows = { lib.window({ id = 901 }) },
})
R.check("le comptage ordinaire est intact", obj:countWindows(avecFenetre), 1)

R.section("La vérification n'a lieu que sur un zéro")
ctl.axCalls = 0
obj:countWindows(avecFenetre)
R.check("aucun appel supplémentaire quand il y a des fenêtres", ctl.axCalls, 1)

R.section("Une API absente ne désactive pas le comptage")
local ancienne = lib.app(ctl, { name = "Ancienne", bundle = "com.x", windows = {} })
ancienne.mainWindow = nil
R.check("zéro conservé faute de recoupement", obj:countWindows(ancienne), 0)

R.section("Une erreur de lecture rend le comptage indécidable")
local muette = lib.app(ctl, { name = "Muette", bundle = "com.y", windows = {} })
muette.mainWindow = function() error("AX muette") end
R.check("indécidable plutôt que zéro", obj:countWindows(muette), nil)


------------------------------------------------------------
R.section("Un zéro isolé ne suffit pas à conclure")
-- Mesuré sur macOS 26 : le WindowServer garde une fenêtre fermée
-- exactement comme une vivante tant que son application tourne, donc il
-- ne peut pas servir de test d'existence. Ce qui reste sûr : un
-- aveuglement de l'accessibilité dure quelques secondes, une fermeture
-- est définitive. On demande plusieurs zéros de suite.
------------------------------------------------------------
obj.undecidable = {}
obj.undecidableSince = {}
obj.zeroStreak = {}
obj.quitConfirmations = 3

local cible = lib.app(ctl, { name = "IINA", bundle = "com.colliderli.iina",
                             windows = { lib.window({ id = 1600 }) }, pid = 9100 })
R.check("comptage normal", obj:countWindows(cible), 1)

cible._windows = {}
cible.mainWindow = function() return nil end
R.check("premier zéro : indécidable", obj:countWindows(cible), nil)
R.check("deuxième zéro : toujours", obj:countWindows(cible), nil)
R.check("troisième zéro : conclu", obj:countWindows(cible), 0)

R.section("Une fenêtre qui réapparaît remet la série à zéro")
cible._windows = { lib.window({ id = 1601 }) }
R.check("comptage normal", obj:countWindows(cible), 1)
R.check("série effacée", obj.zeroStreak[9100], nil)
cible._windows = {}
R.check("il faut tout recommencer", obj:countWindows(cible), nil)

R.section("La garde mainWindow tient toujours")
obj.zeroStreak = {}
local ailleurs = lib.app(ctl, { name = "Claude", bundle = "com.anthropic.x",
                                windows = {}, pid = 9200,
                                hiddenBySpace = lib.window({ id = 1700 }) })
R.check("indécidable tant que la fenêtre principale répond",
    obj:countWindows(ailleurs), nil)
for _ = 1, 5 do obj:countWindows(ailleurs) end
R.check("et elle ne cède pas à la répétition", obj:countWindows(ailleurs), nil)

R.section("Mais elle ne bloque pas indéfiniment")
ctl.now = ctl.now + obj.undecidableGraceSeconds + 1
ctl.printed = {}
R.check("passé le délai, la liste fait foi", obj:countWindows(ailleurs), nil)
R.check("l'abandon est journalisé",
    table.concat(ctl.printed, " "):find("Doute abandonne", 1, true) ~= nil, true)
R.check("puis la série de confirmations reprend la main",
    obj:countWindows(ailleurs), nil)

R.section("Le journal ne se répète pas")
obj.undecidable = {}
obj.undecidableSince = {}
obj.zeroStreak = {}
local muette2 = lib.app(ctl, { name = "Muette", bundle = "com.z", windows = {}, pid = 9300 })
muette2.mainWindow = function() return nil end
ctl.printed = {}
for _ = 1, 2 do obj:countWindows(muette2) end
local lignes = 0
for _, l in ipairs(ctl.printed) do
    if l:find("Comptage indecidable", 1, true) then lignes = lignes + 1 end
end
R.check("deux confirmations, deux motifs distincts, deux lignes", lignes, 2)

R.finish()
