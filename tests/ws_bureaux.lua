-- WindowSwitcher : bureaux (Spaces).
--
-- Le WindowServer repond fidelement a « sur quels bureaux se trouve
-- cette fenetre » pour une fenetre vivante. Il ne repond PAS a « cette
-- fenetre existe-t-elle encore » : une fenetre fermee garde sa ligne
-- tant que son application tourne, ce qui a rendu des applications
-- infermables dans LastWindowQuits. Le switcher ne pose que la premiere
-- question, et il ne liste que des fenetres vivantes.
package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install({ virtualFS = true })
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.verboseLogging = false
obj.showNotifications = false
obj.screenCaptureHelperEnabled = false
obj.completeWithAllWindows = false

local safari = lib.app(ctl, { name = "Safari", bundle = "com.apple.Safari" })
local mail   = lib.app(ctl, { name = "Mail", bundle = "com.apple.mail" })
ctl.runningApps = { safari, mail }

-- w1 et w3 sur le bureau visible, w2 sur un autre.
local w1 = lib.window({ id = 1, app = safari, title = "Ici" })
local w2 = lib.window({ id = 2, app = mail,   title = "Ailleurs" })
local w3 = lib.window({ id = 3, app = safari, title = "Ici aussi" })

-- lib.window ne trace pas les focus : on les note ici.
local focus = {}
for _, w in ipairs({ w1, w2, w3 }) do
    local wid = w.id()
    w.focus = function() focus[#focus + 1] = wid end
end

local function nouvelleSession()
    obj.entries = nil
    obj.selectedIndex = nil
    obj.lastStepAt = nil
    obj.layoutCache = nil
    obj.titleCache = {}
    obj.snapshotCache = {}
    obj.modifierTap = nil
    obj.sessionKeyTap = nil
    obj.modifierTimer = nil
    obj.redrawTimer = nil
    obj.mouseIdleTimer = nil
    ctl.eventtaps = {}
    ctl.everyTimers = {}
    ctl.timers = {}
    focus = {}
    ctl.filterWindows = { w1, w2, w3 }
    ctl.allWindows = { w1, w2, w3 }
    ctl.modifierRaw = 524288
    ctl.mousePosition = { x = 400, y = 300 }
    ctl.spaceCalls = 0
    ctl.movedToSpace = {}
    ctl.moveSucceeds = true
    ctl.spacesBroken = false
    ctl.activeSpaces = { ["ECRAN-1"] = 1 }
    ctl.activeSpaceOnScreen = 1
    ctl.windowSpaces = { [1] = { 1 }, [2] = { 2 }, [3] = { 1 } }
    obj.spacesUsable = true
    obj.activeSpaceIDs = nil
    obj.showSpaceBadges = true
    obj.currentSpaceFirst = false
    obj.crossSpaceActivation = "switch"
    obj.loadedExcludedBundleIDs = {}
    obj.ignoredBundlesSignature = "fige"
end

------------------------------------------------------------
R.section("Reperer une fenêtre posée sur un autre bureau")
------------------------------------------------------------
nouvelleSession()
obj:refreshActiveSpaces()
R.check("les bureaux visibles sont relevés", obj.activeSpaceIDs[1], true)
R.check("un seul", obj.activeSpaceIDs[2], nil)

R.check("fenêtre du bureau courant", obj:isOnOtherSpace({ id = 1 }), false)
R.check("fenêtre d'un autre bureau", obj:isOnOtherSpace({ id = 2 }), true)

-- Une fenêtre collée à tous les bureaux répond plusieurs espaces dont
-- celui qui est visible : elle est ici.
ctl.windowSpaces[4] = { 1, 2, 3 }
R.check("fenêtre présente sur tous les bureaux : ici", obj:isOnOtherSpace({ id = 4 }), false)

R.section("Une fenêtre réduite ou masquée n'est sur aucun bureau")
-- Le WindowServer la situe encore sur son dernier bureau. Le dire à
-- l'utilisateur serait exact et trompeur : sa pastille dédiée dit déjà
-- l'essentiel, et une seconde pastille ferait croire à un simple
-- changement de bureau.
R.check("réduite", obj:isOnOtherSpace({ id = 2, minimized = true }), false)
R.check("masquée", obj:isOnOtherSpace({ id = 2, hidden = true }), false)

R.section("Sans réponse, on n'invente rien")
R.check("fenêtre inconnue du WindowServer", obj:isOnOtherSpace({ id = 99 }), false)
ctl.windowSpaces[98] = {}
R.check("liste vide", obj:isOnOtherSpace({ id = 98 }), false)

R.section("La réponse n'est demandée qu'une fois par fenêtre")
nouvelleSession()
obj:refreshActiveSpaces()
local avant = ctl.spaceCalls
local descripteur = { id = 2 }
for _ = 1, 10 do obj:isOnOtherSpace(descripteur) end
R.check("dix questions, une seule interrogation", ctl.spaceCalls - avant, 1)
R.check("et toujours la même réponse", obj:isOnOtherSpace(descripteur), true)

------------------------------------------------------------
R.section("La pastille apparaît sur la vignette")
------------------------------------------------------------
nouvelleSession()
obj:refreshActiveSpaces()
R.check("fenêtre d'ici : aucune pastille", #obj:stateBadges({ id = 1 }), 0)
R.check("fenêtre d'ailleurs : une pastille", #obj:stateBadges({ id = 2 }), 1)
R.check("le glyphe est celui des bureaux",
    obj:stateBadges({ id = 2 })[1].glyph, obj.badges.otherSpace.glyph)

R.check("réduite ET ailleurs : la réduction seule",
    #obj:stateBadges({ id = 2, minimized = true }), 1)
R.check("et c'est bien celle de la réduction",
    obj:stateBadges({ id = 2, minimized = true })[1].glyph, obj.badges.minimized.glyph)

obj.showSpaceBadges = false
R.check("désactivable", #obj:stateBadges({ id = 2 }), 0)
obj.showSpaceBadges = true

------------------------------------------------------------
R.section("hs.spaces indisponible : le switcher continue")
------------------------------------------------------------
-- Le module repose sur des API privées de SkyLight. Une mise à jour de
-- macOS peut le faire tomber : rien de ce qui précède ne doit alors
-- empêcher un Alt+Tab.
nouvelleSession()
ctl.spacesBroken = true
obj:refreshActiveSpaces()
R.check("l'indisponibilité est retenue", obj.spacesUsable, false)
R.check("aucun bureau relevé", obj.activeSpaceIDs, nil)
R.check("aucune pastille", #obj:stateBadges({ id = 2 }), 0)

obj:step(1)
R.check("la session s'ouvre quand même", obj.entries and #obj.entries, 3)
local vise = obj.entries[obj.selectedIndex].id
obj:commit()
R.check("et l'activation aboutit", focus[#focus], vise)

------------------------------------------------------------
R.section("Regrouper le bureau courant devant, sans casser l'ordre")
------------------------------------------------------------
nouvelleSession()
obj.currentSpaceFirst = true
obj:step(1)
local ordre = {}
for _, e in ipairs(obj.entries) do ordre[#ordre + 1] = e.id end
R.check("trois fenêtres", #ordre, 3)
R.check("les deux d'ici d'abord", ordre[1] .. "," .. ordre[2], "1,3")
R.check("celle d'ailleurs ensuite", ordre[3], 2)

nouvelleSession()
obj.currentSpaceFirst = false
obj:step(1)
ordre = {}
for _, e in ipairs(obj.entries) do ordre[#ordre + 1] = e.id end
R.check("désactivé : l'ordre d'usage est intact", ordre[1] .. "," .. ordre[2] .. "," .. ordre[3], "1,2,3")

------------------------------------------------------------
R.section("Activation en mode « switch » : macOS bascule, rien ne bouge")
------------------------------------------------------------
nouvelleSession()
obj.crossSpaceActivation = "switch"
obj:step(1)                          -- sélection sur w2, l'autre bureau
R.check("la sélection est bien celle d'ailleurs", obj.entries[obj.selectedIndex].id, 2)
obj:commit()
R.check("aucune fenêtre déplacée", #ctl.movedToSpace, 0)
R.check("le focus est demandé", focus[#focus], 2)

R.section("La vérification du focus attend la fin de l'animation")
-- Vérifier trop tôt trouve le focus sur la fenêtre précédente et
-- déclenche une reprise qui se bat contre la bascule en cours.
local delais = {}
for _, t in ipairs(ctl.timers) do delais[#delais + 1] = t.delay end
local trouve = false
for _, d in ipairs(delais) do
    if d == obj.crossSpaceFocusDelay then trouve = true end
end
R.check("le délai est celui des bureaux", trouve, true)
R.check("il est plus long que l'ordinaire",
    obj.crossSpaceFocusDelay > obj.focusReassertDelay, true)

R.section("Une fenêtre d'ici garde le délai ordinaire")
nouvelleSession()
obj:step(1)
obj.selectedIndex = 1
obj:commit()
local court = false
for _, t in ipairs(ctl.timers) do
    if t.delay == obj.focusReassertDelay then court = true end
end
R.check("délai ordinaire", court, true)

------------------------------------------------------------
R.section("Activation en mode « bring » : la fenêtre vient à nous")
------------------------------------------------------------
-- C'est ce que fait Sanyam-G/switch via CGSMoveWindowsToManagedSpace :
-- aucune animation, aucun détour par Mission Control. En échange la
-- fenêtre change de bureau pour de bon.
nouvelleSession()
obj.crossSpaceActivation = "bring"
obj:step(1)
R.check("sélection sur la fenêtre d'ailleurs", obj.entries[obj.selectedIndex].id, 2)
obj:commit()
R.check("la fenêtre a été déplacée", #ctl.movedToSpace, 1)
R.check("vers le bureau visible", ctl.movedToSpace[1].space, 1)
R.check("c'est la bonne fenêtre", ctl.movedToSpace[1].id, 2)
R.check("le focus suit", focus[#focus], 2)

R.section("Plus de bascule à attendre : délai ordinaire")
local long = false
for _, t in ipairs(ctl.timers) do
    if t.delay == obj.crossSpaceFocusDelay then long = true end
end
R.check("aucune attente d'animation", long, false)

R.section("Une fenêtre d'ici n'est jamais déplacée")
nouvelleSession()
obj.crossSpaceActivation = "bring"
obj:step(1)
obj.selectedIndex = 1
obj:commit()
R.check("rien n'a bougé", #ctl.movedToSpace, 0)

R.section("Un déplacement refusé retombe sur la bascule")
-- Une fenêtre en plein écran occupe son propre bureau et ne se déplace
-- pas. Il ne faut pas conclure qu'elle est arrivée.
nouvelleSession()
obj.crossSpaceActivation = "bring"
ctl.moveSucceeds = false
obj:step(1)
obj:commit()
R.check("aucun déplacement enregistré", #ctl.movedToSpace, 0)
R.check("le focus est quand même demandé", focus[#focus], 2)
local attente = false
for _, t in ipairs(ctl.timers) do
    if t.delay == obj.crossSpaceFocusDelay then attente = true end
end
R.check("et l'animation est de nouveau attendue", attente, true)

R.finish()
