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
    ctl.activeSpacesBroken = false
    ctl.managedDisplays = { { ["Display Identifier"] = "ECRAN-1",
                              ["Current Space"] = { ManagedSpaceID = 1 },
                              Spaces = { { ManagedSpaceID = 1, type = 0 },
                                         { ManagedSpaceID = 2, type = 0 } } } }
    ctl.activeSpaces = { ["ECRAN-1"] = 1 }
    ctl.activeSpaceOnScreen = 1
    ctl.windowSpaces = { [1] = { 1 }, [2] = { 2 }, [3] = { 1 } }
    obj.spacesUsable = true
    obj.activeSpaceIDs = nil
    obj.showSpaceBadges = true
    obj.currentSpaceFirst = false
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

R.section("Une fenêtre réduite garde son bureau")
-- Mesuré sur une vraie NSWindow :
--   ouverte, visible   spaces=[1]
--   RÉDUITE (Dock)     spaces=[1]
--   restaurée          spaces=[1]
-- unminimize la rend à son bureau d'origine : qui tabule dessus se
-- retrouve ailleurs. C'est ce que la pastille doit annoncer, et ce que
-- le mode « bring » doit pouvoir éviter.
R.check("réduite et ailleurs", obj:isOnOtherSpace({ id = 2, minimized = true }), true)
R.check("masquée et ailleurs", obj:isOnOtherSpace({ id = 2, hidden = true }), true)
R.check("réduite mais ici", obj:isOnOtherSpace({ id = 1, minimized = true }), false)

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

R.check("réduite ET ailleurs : les deux pastilles",
    #obj:stateBadges({ id = 2, minimized = true }), 2)
R.check("la réduction passe en premier",
    obj:stateBadges({ id = 2, minimized = true })[1].glyph, obj.badges.minimized.glyph)
R.check("le bureau ensuite",
    obj:stateBadges({ id = 2, minimized = true })[2].glyph, obj.badges.otherSpace.glyph)

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
R.section("Activation : macOS bascule, rien ne bouge")
------------------------------------------------------------
nouvelleSession()
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
R.section("Moniteurs sans espaces séparés : la lecture directe sauve tout")
------------------------------------------------------------
-- hs.spaces.activeSpaces() passe par activeSpaceOnScreen(), qui remplace
-- l'UUID de l'écran par la chaîne « Main » quand
-- NSScreen.screensHaveSeparateSpaces vaut faux, puis cherche un écran
-- nommé « Main » dans une liste qui n'en contient que des UUID. Mesuré
-- sur la machine :
--
--   NSScreen.screensHaveSeparateSpaces = false
--   hs.screen:getUUID()                = 37D8832A-2D66-...
--   Display Identifier                 = 37D8832A-2D66-...
--
-- Elle renvoyait nil, et TOUT ce qui concerne les bureaux s'éteignait
-- sans un mot. data_managedDisplaySpaces() donne la même information
-- sans cette identification d'écran.
nouvelleSession()
ctl.activeSpacesBroken = true
obj:refreshActiveSpaces()
R.check("les bureaux sont quand même relevés", obj.activeSpaceIDs and obj.activeSpaceIDs[1], true)
R.check("le switcher reste utilisable", obj.spacesUsable, true)
R.check("la pastille apparaît toujours", #obj:stateBadges({ id = 2 }), 1)

R.section("Repli sur l'API documentée si la lecture directe disparaît")
nouvelleSession()
ctl.managedDisplays = nil
obj:refreshActiveSpaces()
R.check("l'inventaire vient de activeSpaces()", obj.activeSpaceIDs[1], true)

R.section("Les deux sources muettes : on éteint proprement")
nouvelleSession()
ctl.managedDisplays = nil
ctl.activeSpacesBroken = true
obj:refreshActiveSpaces()
R.check("indisponible", obj.spacesUsable, false)
R.check("aucun bureau", obj.activeSpaceIDs, nil)

------------------------------------------------------------
R.section("Aucune fenêtre n'est jamais déplacée")
------------------------------------------------------------
-- Mesuré sur la machine, même binaire, mêmes permissions :
--
--                                  ma fenêtre   fenêtre d'une
--                                               autre application
--   CGSMoveWindowsToManagedSpace   RÉUSSI       échec
--   SLSSetWindowListWorkspace      ÉCHEC 1006   échec
--
-- Un processus ne déplace que SES PROPRES fenêtres : Dock.app détient
-- la seule connexion au window server autorisée à le faire pour les
-- autres. Et depuis macOS 14.5, hs.spaces.moveWindowToSpace appelle
-- SLSSetWindowListWorkspace, qui renvoie 1006 et ne fait rien — même
-- sur la fenêtre du processus appelant — tout en renvoyant true.
--
-- Le switcher ne s'y essaie donc plus du tout.
nouvelleSession()
obj:step(1)
R.check("sélection sur la fenêtre d'ailleurs", obj.entries[obj.selectedIndex].id, 2)
obj:commit()
R.check("rien n'a été déplacé", #ctl.movedToSpace, 0)
R.check("le focus est demandé", focus[#focus], 2)

R.section("Et rien n'est déplacé non plus pour une fenêtre d'ici")
nouvelleSession()
obj:step(1)
obj.selectedIndex = 1
obj:commit()
R.check("aucun déplacement", #ctl.movedToSpace, 0)

R.finish()
