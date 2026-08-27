-- WindowSwitcher : session, modificateurs, souris, rendu, activation, arrêt.
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

local w1 = lib.window({ id = 1, app = safari, title = "Un" })
local w2 = lib.window({ id = 2, app = mail,   title = "Deux" })
local w3 = lib.window({ id = 3, app = safari, title = "Trois" })

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
    ctl.filterWindows = { w1, w2, w3 }
    ctl.allWindows = { w1, w2, w3 }
    ctl.modifierRaw = 524288        -- Option enfoncée
    ctl.mousePosition = { x = 400, y = 300 }
    obj.loadedExcludedBundleIDs = {}
    obj.ignoredBundlesSignature = "fige"
end

------------------------------------------------------------
R.section("Ouverture : la sélection part sur la fenêtre précédente")
------------------------------------------------------------
nouvelleSession()
obj:step(1)
R.check("trois fenêtres collectées", #obj.entries, 3)
R.check("sélection sur la deuxième", obj.selectedIndex, 2)
R.check("un panneau est affiché", ctl.canvases[#ctl.canvases].shown, true)

R.section("Le clavier fait défiler et boucle")
ctl.now = ctl.now + 1 ; obj:step(1)
R.check("troisième", obj.selectedIndex, 3)
ctl.now = ctl.now + 1 ; obj:step(1)
R.check("retour à la première", obj.selectedIndex, 1)
ctl.now = ctl.now + 1 ; obj:step(-1)
R.check("marche arrière boucle aussi", obj.selectedIndex, 3)

R.section("L'anti-rebond bloque les appuis trop rapprochés")
local avant = obj.selectedIndex
obj:step(1)                          -- même instant que le précédent
R.check("appui ignoré", obj.selectedIndex, avant)

------------------------------------------------------------
R.section("Les modificateurs : un eventtap, plus un sondage à 100 Hz")
------------------------------------------------------------
local function tapPour(type)
    for _, t in ipairs(ctl.eventtaps) do
        if t.types and t.types[1] == type then return t end
    end
end
local tapMods = tapPour("flagsChanged")
R.check("un eventtap écoute flagsChanged", tapMods ~= nil, true)
R.check("il tourne", tapMods.running, true)
R.check("un seul timer de secours", #ctl.everyTimers, 1)
R.check("timer de secours espacé, pas 0,01 s",
    ctl.everyTimers[1].delay, obj.modifierSafetyInterval)

R.section("Relâcher la touche valide, mais hors du tap")
-- Un eventtap fait passer chaque événement du système par le thread
-- principal, et macOS attend la réponse. commit() démasque, restaure et
-- donne le focus : trois appels d'accessibilité qui peuvent bloquer des
-- centaines de millisecondes sur une application qui ne répond pas.
-- Le tap doit rendre la main tout de suite.
ctl.modifierRaw = 0
ctl.eventtaps[1].fn()
R.check("le tap n'a rien fait de lourd", obj.entries ~= nil, true)
R.check("un commit est en attente", obj.commitPending, true)
ctl.fireOnly(0)
R.check("session fermée au tour suivant", obj.entries, nil)
R.check("eventtap arrêté", tapMods.running, false)
R.check("timer de secours arrêté", ctl.everyTimers[1].stopped, true)

R.section("Une rafale de flagsChanged ne programme qu'un commit")
nouvelleSession()
obj:step(1)
ctl.modifierRaw = 0
local avant = #ctl.timers
for _ = 1, 10 do ctl.eventtaps[1].fn() end
R.check("dix événements, un seul travail programmé", #ctl.timers - avant, 1)
ctl.fireOnly(0)

R.section("Sans eventtap, le filet devient réactif")
nouvelleSession()
local vraiNew = hs.eventtap.new
hs.eventtap.new = function() return nil end
obj:step(1)
R.check("aucun eventtap", #ctl.eventtaps, 0)
R.check("filet resserré", ctl.everyTimers[1].delay, obj.modifierFallbackInterval)
ctl.modifierRaw = 0
ctl.everyTimers[1].fn()
R.check("le filet valide quand même", obj.entries, nil)
hs.eventtap.new = vraiNew

R.section("Le verrou majuscules seul ne maintient pas le panneau")
ctl.modifierRaw = 65536
R.check("considéré comme relâché", obj:modifiersPressed(), false)
ctl.modifierRaw = 65536 + 524288
R.check("verrou + Option compte bien", obj:modifiersPressed(), true)

------------------------------------------------------------
R.section("La souris ne vole plus la sélection au clavier")
------------------------------------------------------------
nouvelleSession()
obj:step(1)
local choisi = obj.selectedIndex
obj:handleMouseEvent("mouseEnter", "tile:1")
R.check("survol ignoré, souris immobile", obj.selectedIndex, choisi)
ctl.mousePosition = { x = 402, y = 301 }         -- frémissement
obj:handleMouseEvent("mouseMove", "tile:1")
R.check("frémissement ignoré", obj.selectedIndex, choisi)
ctl.mousePosition = { x = 460, y = 340 }         -- vrai déplacement
obj:handleMouseEvent("mouseMove", "tile:1")
R.check("déplacement réel : la souris reprend la main", obj.selectedIndex, 1)
obj:handleMouseEvent("mouseEnter", "tile:3")
R.check("une fois armée, elle reste armée", obj.selectedIndex, 3)

R.section("Un clic est toujours une intention explicite")
nouvelleSession()
obj:step(1)
obj:handleMouseEvent("mouseUp", "tile:1")
R.check("le clic active sans attendre de mouvement", obj.entries, nil)

R.section("Un identifiant de tuile inconnu ne casse rien")
nouvelleSession()
obj:step(1)
local avantClic = obj.selectedIndex
obj:handleMouseEvent("mouseUp", "tile:99")
obj:handleMouseEvent("mouseUp", "autre-chose")
R.check("session intacte", obj.selectedIndex, avantClic)

------------------------------------------------------------
R.section("La géométrie n'est calculée qu'une fois par page")
------------------------------------------------------------
nouvelleSession()
local calculs = 0
local vraiLayout = obj.layout
obj.layout = function(self, a, b) calculs = calculs + 1 return vraiLayout(self, a, b) end
obj:step(1)
R.check("un calcul à l'ouverture", calculs, 1)
ctl.now = ctl.now + 1 ; obj:step(1)
ctl.now = ctl.now + 1 ; obj:step(1)
R.check("aucun recalcul quand seule la sélection change", calculs, 1)
obj.layout = vraiLayout

R.section("Les libellés stylés sont mémorisés")
local styles = 0
local vraiNewStyled = hs.styledtext.new
hs.styledtext.new = function(...) styles = styles + 1 return vraiNewStyled(...) end
nouvelleSession()
obj:step(1)
local premier = styles
obj:redraw()
R.check("aucun libellé reconstruit au second rendu", styles, premier)
hs.styledtext.new = vraiNewStyled

R.section("Les captures qui arrivent en rafale ne font qu'un rendu")
nouvelleSession()
obj:step(1)
local rendus = 0
local vraiRedraw = obj.redraw
obj.redraw = function(self) rendus = rendus + 1 return vraiRedraw(self) end
obj:scheduleRedraw() ; obj:scheduleRedraw() ; obj:scheduleRedraw()
R.check("rien n'est dessiné dans l'instant", rendus, 0)
ctl.fireTimers()
R.check("un seul rendu pour trois captures", rendus, 1)
obj.redraw = vraiRedraw

------------------------------------------------------------
R.section("Activation : démasquer, restaurer, puis donner le focus")
------------------------------------------------------------
nouvelleSession()
local cachee = lib.app(ctl, { name = "Notes", bundle = "com.apple.Notes", hidden = true })
local wc = lib.window({ id = 9, app = cachee, title = "Note" })
ctl.filterWindows = { wc }
ctl.allWindows = { wc }
local ordre = {}
wc.unminimize = function() table.insert(ordre, "unminimize") end
wc.focus = function() table.insert(ordre, "focus") end
cachee.unhide = function() table.insert(ordre, "unhide") ; cachee._hidden = false ; return true end
obj:step(1)
obj:commit()
R.check("l'application est démasquée", ordre[1], "unhide")
R.check("puis la fenêtre restaurée", ordre[2], "unminimize")
R.check("et seulement ensuite le focus", ordre[3], "focus")

R.section("Le focus est réaffirmé s'il n'a pas pris")
ctl.focusedWindow = nil
ctl.fireTimers()
R.check("seconde tentative", ordre[4], "focus")

R.section("Il ne l'est pas si la fenêtre a bien pris le focus")
ordre = {}
nouvelleSession()
ctl.filterWindows = { wc }
ctl.allWindows = { wc }
obj:step(1)
obj:commit()
local function compte(quoi)
    local n = 0
    for _, v in ipairs(ordre) do if v == quoi then n = n + 1 end end
    return n
end
R.check("un focus demandé", compte("focus"), 1)
ctl.focusedWindow = wc
ctl.fireTimers()
R.check("pas d'insistance inutile", compte("focus"), 1)

R.section("Une fenêtre sans application ne fait pas tomber la validation")
nouvelleSession()
obj:step(1)
obj.entries[obj.selectedIndex].application = nil
obj.entries[obj.selectedIndex].hidden = true
local ok = pcall(function() obj:commit() end)
R.check("validation sans erreur", ok, true)

------------------------------------------------------------
R.section("safeCall rend l'erreur exploitable")
------------------------------------------------------------
nouvelleSession()
obj:step(1)
local vraiLayout2 = obj.layout
obj.layout = function() error("géométrie impossible") end
obj.layoutCache = nil
ctl.printed = {}
obj:redraw()
obj.layout = vraiLayout2
local trace = table.concat(ctl.printed, " | ")
R.check("le motif réel est journalisé, pas nil",
    trace:find("géométrie impossible", 1, true) ~= nil, true)

------------------------------------------------------------
R.section("Arrêt : plus rien ne reste en mémoire")
------------------------------------------------------------
nouvelleSession()
obj.isStarted = true
obj:step(1)
obj.snapshotCache[77] = { image = {}, time = ctl.now }
obj.iconCache["com.apple.Safari"] = {}
obj:ensureWindowFilter()
ctl.filtersDeleted = 0
local canvasAvant = ctl.canvases[#ctl.canvases]
obj:stop()
R.check("le canvas est détruit, pas seulement masqué", canvasAvant.deleted, true)
R.check("l'objet canvas est relâché", obj.switcherCanvas, nil)
R.check("le filtre est supprimé", ctl.filtersDeleted, 1)
R.check("cache de vignettes vidé", next(obj.snapshotCache), nil)
R.check("cache d'icônes vidé", next(obj.iconCache), nil)
R.check("session close", obj.entries, nil)
R.check("eventtap relâché", obj.modifierTap, nil)

------------------------------------------------------------
R.section("Échap ferme sans rien activer")
------------------------------------------------------------
nouvelleSession()
local active = {}
for _, w in ipairs({ w1, w2, w3 }) do
    w.focus = function() table.insert(active, "focus") end
    w.unminimize = function() table.insert(active, "unminimize") end
end
obj:step(1)
R.check("session ouverte", obj.entries ~= nil, true)
local tapEchap
for _, t in ipairs(ctl.eventtaps) do
    if t.types and t.types[1] == "keyDown" then tapEchap = t end
end
R.check("un eventtap écoute les touches", tapEchap ~= nil, true)
R.check("il tourne pendant la session", tapEchap.running, true)

local consomme = tapEchap.fn({ getKeyCode = function() return 53 end })
R.check("la touche est consommée", consomme, true)
-- La réponse au tap doit être immédiate : c'est elle qui consomme la
-- touche. Le travail, lui, se fait hors du tap.
R.check("mais rien de lourd dans le tap", obj.entries ~= nil, true)
ctl.fireOnly(0)
R.check("session fermée au tour suivant", obj.entries, nil)
R.check("aucune fenêtre activée", #active, 0)
R.check("panneau masqué", obj.switcherCanvas.shown, false)
R.check("aperçu masqué", obj.previewVisible, false)
R.check("eventtap arrêté", tapEchap.running, false)

R.section("Une autre touche ne ferme rien et passe à l'application")
nouvelleSession()
obj:step(1)
local autre = tapEchap.fn({ getKeyCode = function() return 8 end })
R.check("la touche passe", autre, false)
R.check("session toujours ouverte", obj.entries ~= nil, true)
obj:commit()

R.section("Annuler deux fois ne fait rien de plus")
R.check("annulation à vide sans erreur", pcall(function() obj:cancel() end), true)

R.section("Échap désactivable")
nouvelleSession()
obj.enableCancelKey = false
obj:releaseSessionKeyTap()
ctl.eventtaps = {}
obj:step(1)
local presence = false
for _, t in ipairs(ctl.eventtaps) do
    if t.types and t.types[1] == "keyDown" and t.running then presence = true end
end
R.check("aucun eventtap clavier actif", presence, false)
obj.enableCancelKey = true
obj:commit()

------------------------------------------------------------
R.section("Pastilles d'état")
------------------------------------------------------------
R.check("fenêtre ordinaire : aucune pastille",
    #obj:stateBadges({ id = 1 }), 0)
R.check("réduite : une pastille",
    #obj:stateBadges({ id = 2, minimized = true }), 1)
R.check("le glyphe est celui configuré",
    obj:stateBadges({ id = 2, minimized = true })[1].glyph, obj.badges.minimized.glyph)
R.check("masquée : une pastille",
    obj:stateBadges({ id = 3, hidden = true })[1].glyph, obj.badges.hidden.glyph)
R.check("réduite et masquée : deux pastilles",
    #obj:stateBadges({ id = 4, minimized = true, hidden = true }), 2)

obj.showStateBadges = false
R.check("désactivées : aucune pastille",
    #obj:stateBadges({ id = 5, minimized = true }), 0)
obj.showStateBadges = true

R.section("Pastilles son et micro")
obj.audioPIDs = { [4242] = true }
obj.microphonePIDs = { [777] = true }
R.check("application qui joue : pastille son",
    obj:stateBadges({ id = 8, pid = 4242 })[1].glyph, obj.badges.audio.glyph)
R.check("application qui capte : pastille micro",
    obj:stateBadges({ id = 9, pid = 777 })[1].glyph, obj.badges.microphone.glyph)
R.check("une autre application : rien",
    #obj:stateBadges({ id = 10, pid = 1 }), 0)
R.check("sans pid : rien",
    #obj:stateBadges({ id = 11 }), 0)
R.check("réduite et sonore : deux pastilles",
    #obj:stateBadges({ id = 12, pid = 4242, minimized = true }), 2)
R.check("l'état de fenêtre passe avant le son",
    obj:stateBadges({ id = 13, pid = 4242, minimized = true })[1].glyph,
    obj.badges.minimized.glyph)

obj.showAudioBadges = false
R.check("pastilles son désactivables séparément",
    #obj:stateBadges({ id = 14, pid = 4242 }), 0)
R.check("celles d'état restent",
    #obj:stateBadges({ id = 15, pid = 4242, minimized = true }), 1)
obj.showAudioBadges = true
obj.audioPIDs = {}
obj.microphonePIDs = {}

R.section("Les pastilles sont dessinées dans la tuile")
local els = {}
obj:badgeElements(els, { id = 6, minimized = true, hidden = true },
    { x = 100, y = 50, w = 200, h = 150 })
R.check("deux pastilles, fond et glyphe pour chacune", #els, 4)
-- le coin supérieur gauche revient au bouton de fermeture
R.check("la première est calée à droite de la vignette",
    els[1].frame.x, 100 + 200 - obj.badgeSize - 6)
R.check("la seconde se pose à sa gauche",
    els[3].frame.x, 100 + 200 - 6 - (2 * obj.badgeSize) - obj.badgeGap)
R.check("elles restent dans la vignette", els[3].frame.x > 100, true)
R.check("chaque pastille a sa couleur", els[1].fillColor, obj.badges.minimized.color)
R.check("couleurs distinctes selon la nature",
    els[3].fillColor ~= els[1].fillColor, true)
R.check("un liseré la détache du fond", els[1].action, "strokeAndFill")

local vides = {}
obj:badgeElements(vides, { id = 7 }, { x = 0, y = 0, w = 100, h = 100 })
R.check("aucun élément pour une fenêtre ordinaire", #vides, 0)

------------------------------------------------------------
R.section("Fermer une fenêtre depuis le switcher")
------------------------------------------------------------
nouvelleSession()
local ferme = {}
for _, w in ipairs({ w1, w2, w3 }) do
    w.close = function() table.insert(ferme, w.id()) ; return true end
end
obj:step(1)
R.check("trois tuiles", #obj.entries, 3)
local cible = obj.entries[2].id
obj:closeEntry(2)
R.check("la fenêtre est fermée", ferme[1], cible)
R.check("la tuile disparaît", #obj.entries, 2)
R.check("la session continue", obj.entries ~= nil, true)
R.check("aucune de celles qui restent n'a été fermée", #ferme, 1)

R.section("Fermer la dernière ferme la session")
ferme = {}
obj:closeEntry(1)
obj:closeEntry(1)
R.check("plus de session", obj.entries, nil)
R.check("les deux ont été fermées", #ferme, 2)

R.section("Un refus de l'application laisse la tuile en place")
nouvelleSession()
for _, w in ipairs({ w1, w2, w3 }) do w.close = function() return false end end
obj:step(1)
local avant = #obj.entries
ctl.printed = {}
obj:closeEntry(1)
R.check("la tuile reste", #obj.entries, avant)
R.check("le refus est journalisé",
    table.concat(ctl.printed, " "):find("Fermeture refusee", 1, true) ~= nil, true)
obj:commit()

R.section("La sélection ne sort pas de la liste")
nouvelleSession()
for _, w in ipairs({ w1, w2, w3 }) do w.close = function() return true end end
obj:step(1)
obj.selectedIndex = 3
obj:closeEntry(3)
R.check("sélection ramenée dans la liste", obj.selectedIndex, 2)
R.check("deux tuiles restantes", #obj.entries, 2)
obj:commit()

R.section("W ferme au clavier")
nouvelleSession()
ferme = {}
for _, w in ipairs({ w1, w2, w3 }) do
    w.close = function() table.insert(ferme, w.id()) ; return true end
end
obj:step(1)
local tapClavier
for _, t in ipairs(ctl.eventtaps) do
    if t.types and t.types[1] == "keyDown" then tapClavier = t end
end
local vise = obj.entries[obj.selectedIndex].id
local mange = tapClavier.fn({ getKeyCode = function() return obj:closeKeyCode() end })
R.check("la touche est consommée", mange, true)
R.check("rien de fermé depuis le tap", ferme[1], nil)
ctl.fireOnly(0)
R.check("la fenêtre visée est fermée au tour suivant", ferme[1], vise)
R.check("la session continue", obj.entries ~= nil, true)

obj.enableCloseKey = false
local passe = tapClavier.fn({ getKeyCode = function() return obj:closeKeyCode() end })
R.check("désactivable : la touche passe", passe, false)
obj.enableCloseKey = true
obj:commit()

R.section("La croix n'apparaît que sur la tuile visée, à la souris")
local els2 = {}
obj.mouseArmed = false
obj:closeButtonElements(els2, { index = 1 }, { x = 0, y = 0, w = 200, h = 150 }, true)
R.check("souris inactive : aucune croix", #els2, 0)

obj.mouseArmed = true
obj:closeButtonElements(els2, { index = 1 }, { x = 0, y = 0, w = 200, h = 150 }, false)
R.check("tuile non visée : aucune croix", #els2, 0)

obj:closeButtonElements(els2, { index = 1 }, { x = 0, y = 0, w = 200, h = 150 }, true)
R.check("tuile visée : deux feux, soit 4 + 3 éléments", #els2, 7)

R.section("Le feu de fermeture, mesuré sur une vraie fenêtre")
R.check("c'est un disque, pas un carré arrondi", els2[1].type, "circle")
R.check("au remplissage relevé", els2[1].fillColor, obj.trafficLights.close.fill)
R.check("avec son liseré plus foncé", els2[1].strokeColor, obj.trafficLights.close.rim)
R.check("en haut à gauche, comme sur une fenêtre",
    els2[1].center.x, 6 + obj.trafficLightSize / 2)
R.check("la croix est faite de segments", els2[2].type, "segments")
R.check("à bouts arrondis", els2[2].strokeCapStyle, "round")
R.check("deux traits", els2[3].type, "segments")
R.check("croisés : le second part de l'autre coin",
    els2[3].coordinates[1].x > els2[2].coordinates[1].x, true)
R.check("le symbole est le disque assombri de moitié",
    els2[2].strokeColor, obj.trafficLightSymbolColor)
local epaisseur = obj.trafficLightSize * obj.trafficLightStrokeRatio
R.check("la croix couvre la moitié du disque, bouts arrondis compris",
    els2[2].coordinates[2].x - els2[2].coordinates[1].x + epaisseur,
    obj.trafficLightSize * obj.closeSymbolExtent)
R.check("le trait lui-même est plus court d'une épaisseur",
    els2[2].coordinates[2].x - els2[2].coordinates[1].x
        < obj.trafficLightSize * obj.closeSymbolExtent, true)
R.check("la cible porte son identifiant", els2[4].id, "close:1")
R.check("elle est cliquable", els2[4].trackMouseUp, true)

R.section("Le feu de réduction, jaune, à sa droite")
R.check("un disque aussi", els2[5].type, "circle")
R.check("au jaune relevé", els2[5].fillColor, obj.trafficLights.minimize.fill)
R.check("posé à l'écart standard",
    els2[5].center.x - els2[1].center.x,
    obj.trafficLightSize + math.floor(obj.trafficLightSize * obj.trafficLightGapRatio))
R.check("un seul trait, horizontal", els2[6].type, "segments")
R.check("il est bien horizontal",
    els2[6].coordinates[1].y, els2[6].coordinates[2].y)
R.check("même symbole assombri de moitié",
    els2[6].strokeColor, obj.trafficLightSymbolColor)
R.check("la barre est un peu plus large que la croix",
    els2[6].coordinates[2].x - els2[6].coordinates[1].x
        > els2[2].coordinates[2].x - els2[2].coordinates[1].x, true)
R.check("sa cible porte son identifiant", els2[7].id, "minimize:1")

R.section("La croix et les pastilles ne se marchent pas dessus")
local melange = {}
obj:badgeElements(melange, { id = 20, minimized = true, hidden = true },
    { x = 0, y = 0, w = 200, h = 150 })
local plusAGauche = math.min(melange[1].frame.x, melange[3].frame.x)
local largeurFeux = 6 + (2 * obj.trafficLightSize)
    + math.floor(obj.trafficLightSize * obj.trafficLightGapRatio)
R.check("les pastilles restent à droite des deux feux",
    plusAGauche > largeurFeux, true)

obj.showCloseButton = false
obj.showMinimizeButton = false
local els3 = {}
obj:closeButtonElements(els3, { index = 1 }, { x = 0, y = 0, w = 200, h = 150 }, true)
R.check("les deux désactivables", #els3, 0)

obj.showCloseButton = true
local els4 = {}
obj:closeButtonElements(els4, { index = 1 }, { x = 0, y = 0, w = 200, h = 150 }, true)
R.check("fermeture seule : quatre éléments", #els4, 4)
obj.showMinimizeButton = true
obj.mouseArmed = false

R.section("Réduire depuis le switcher")
nouvelleSession()
obj:step(1)
local cibleR = obj.entries[1]
R.check("la fenêtre n'est pas réduite", cibleR.minimized, false)
obj:minimizeEntry(1)
R.check("elle l'est maintenant", obj.entries[1].minimized, true)
R.check("la tuile reste, la fenêtre existe toujours", #obj.entries, 3)
R.check("sa vignette est invalidée", obj.snapshotCache[cibleR.id], nil)
R.check("la pastille apparaît",
    obj:stateBadges(obj.entries[1])[1].glyph, obj.badges.minimized.glyph)

R.section("Réduire deux fois ne fait rien de plus")
local avantR = #obj.entries
obj:minimizeEntry(1)
R.check("aucun effet", #obj.entries, avantR)

R.section("M réduit au clavier")
nouvelleSession()
obj:step(1)
local tapM
for _, t in ipairs(ctl.eventtaps) do
    if t.types and t.types[1] == "keyDown" then tapM = t end
end
local viseM = obj.selectedIndex
local mangeM = tapM.fn({ getKeyCode = function() return obj:minimizeKeyCode() end })
R.check("la touche est consommée", mangeM, true)
R.check("rien de réduit depuis le tap", obj.entries[viseM].minimized, false)
ctl.fireOnly(0)
R.check("la fenêtre visée est réduite au tour suivant",
    obj.entries[viseM].minimized, true)
R.check("la session continue", obj.entries ~= nil, true)
obj.enableMinimizeKey = false
R.check("désactivable : la touche passe",
    tapM.fn({ getKeyCode = function() return obj:minimizeKeyCode() end }), false)
obj.enableMinimizeKey = true
obj:commit()

R.section("Un clic sur le jaune réduit, sans activer")
nouvelleSession()
obj:step(1)
obj:handleMouseEvent("mouseUp", "minimize:1")
R.check("réduite", obj.entries[1].minimized, true)
R.check("sans activer la fenêtre", obj.entries ~= nil, true)
obj:commit()

R.section("Un clic sur la croix ferme, un clic ailleurs active")
nouvelleSession()
ferme = {}
for _, w in ipairs({ w1, w2, w3 }) do
    w.close = function() table.insert(ferme, w.id()) ; return true end
end
obj:step(1)
local visee = obj.entries[1].id
obj:handleMouseEvent("mouseUp", "close:1")
R.check("la croix ferme", ferme[1], visee)
R.check("sans activer la fenêtre", obj.entries ~= nil, true)
obj:commit()

R.section("Les canvas sont alloués au démarrage, pas au premier switch")
obj.isStarted = false
obj.switcherCanvas = nil
obj.previewCanvas = nil
obj.hotkeyMapping = { forward = { {"alt"}, "tab" } }
local canvasAvantStart = #ctl.canvases
obj:start()
R.check("les deux canvas sont créés", #ctl.canvases, canvasAvantStart + 2)
local canvasDuStart = obj.switcherCanvas
R.check("le panneau n'est pas affiché", canvasDuStart.shown, false)
R.check("l'aperçu non plus", obj.previewCanvas.shown, false)
R.check("l'aperçu est sous le panneau",
    obj.previewCanvas.level_ ~= canvasDuStart.level_, true)
nouvelleSession()
obj:step(1)
R.check("le premier switch réutilise le même panneau", obj.switcherCanvas, canvasDuStart)
R.check("et l'affiche", canvasDuStart.shown, true)
obj:commit()

------------------------------------------------------------
R.section("Aperçu : il attend avant de se montrer")
------------------------------------------------------------
nouvelleSession()
obj.enableWindowPreview = true
obj.previewOnKeyboard = true
obj:step(1)
R.check("rien n'est affiché dans l'instant", obj.previewVisible, false)
R.check("un délai est armé", obj.previewTimer ~= nil, true)
R.check("c'est le délai configuré", ctl.timers[#ctl.timers].delay, obj.previewDelay)
ctl.fireOnly(obj.previewDelay)
R.check("puis l'aperçu apparaît", obj.previewVisible, true)
R.check("il vise la tuile sélectionnée", obj.previewIndex, obj.selectedIndex)

R.section("Le Tab suivant le fait disparaître aussitôt")
ctl.now = ctl.now + 1
obj:step(1)
R.check("masqué sans attendre", obj.previewVisible, false)
R.check("le délai repart entier, pas raccourci",
    ctl.timers[#ctl.timers].delay, obj.previewDelay)
ctl.fireOnly(obj.previewDelay)
R.check("réaffiché seulement après le délai complet", obj.previewVisible, true)

R.section("Un parcours rapide n'en laisse aucun à l'écran")
nouvelleSession()
obj:step(1)
ctl.fireOnly(obj.previewDelay)
R.check("un premier aperçu est bien là", obj.previewVisible, true)
for _ = 1, 4 do
    ctl.now = ctl.now + 0.1        -- plus court que le délai
    obj:step(1)
end
R.check("il a disparu dès le premier saut, et rien ne revient",
    obj.previewVisible, false)
R.check("un délai reste armé pour l'arrêt", obj.previewTimer ~= nil, true)
ctl.fireOnly(obj.previewDelay)
R.check("il revient quand on s'arrête", obj.previewVisible, true)
obj:commit()

R.section("Une nouvelle session repart avec le même délai")
nouvelleSession()
obj:step(1)
R.check("délai identique", ctl.timers[#ctl.timers].delay, obj.previewDelay)
ctl.fireOnly(obj.previewDelay)

R.section("Une capture qui arrive ne relance pas le compte à rebours")
local avantIndex = obj.previewIndex
obj:redraw()
R.check("toujours visible", obj.previewVisible, true)
R.check("même tuile", obj.previewIndex, avantIndex)
R.check("aucun nouveau délai", obj.previewTimer, nil)

R.section("La validation le fait disparaître")
obj:commit()
R.check("aperçu masqué", obj.previewVisible, false)
R.check("délai annulé", obj.previewTimer, nil)

R.section("Le cadre suit la fenêtre réelle, borné par l'écran")
local geo = obj:previewGeometry({ id = 1, frame = { x = 100, y = 80, w = 600, h = 400 } })
R.check("largeur réelle conservée", geo.w, 600)
R.check("hauteur réelle conservée", geo.h, 400)
R.check("position réelle conservée", geo.x, 100)

local enorme = obj:previewGeometry({ id = 2, frame = { x = -500, y = -500, w = 9000, h = 6000 } })
R.check("réduit pour tenir à l'écran", enorme.w <= 1512, true)
R.check("ramené dans l'écran", enorme.x >= 0, true)
R.check("proportions préservées",
    math.abs((enorme.w / enorme.h) - (9000 / 6000)) < 0.02, true)

local sansCadre = obj:previewGeometry({ id = 3, frame = nil })
R.check("sans cadre exploitable, un aperçu est quand même proposé",
    sansCadre ~= nil and sansCadre.w > 0, true)

R.section("Aperçu clavier désactivable")
nouvelleSession()
obj.previewOnKeyboard = false
obj:step(1)
R.check("aucun délai armé au clavier", obj.previewTimer, nil)
R.check("rien d'affiché", obj.previewVisible, false)
obj.previewOnKeyboard = true
obj:commit()

R.section("Le survol de la souris le déclenche")
nouvelleSession()
obj:step(1)
ctl.fireOnly(obj.previewDelay)
ctl.mousePosition = { x = 470, y = 350 }
obj:handleMouseEvent("mouseMove", "tile:1")
R.check("masqué le temps de changer de cible", obj.previewVisible, false)
ctl.fireOnly(obj.previewDelay)
R.check("réaffiché sur la tuile survolée", obj.previewVisible, true)
R.check("sur la bonne tuile", obj.previewIndex, 1)
obj:commit()

R.section("Désactivé, il ne coûte rien")
nouvelleSession()
obj.enableWindowPreview = false
obj:step(1)
R.check("aucun délai", obj.previewTimer, nil)
R.check("rien d'affiché", obj.previewVisible, false)
obj.enableWindowPreview = true
obj:commit()

R.section("benchmark mesure sans laisser de trace")
nouvelleSession()
obj:step(1)
local avant = obj.entries
local selAvant = obj.selectedIndex
ctl.printed = {}
obj:benchmark()
local rapport = table.concat(ctl.printed, " | ")
R.check("un rapport est journalisé", rapport:find("benchmark", 1, true) ~= nil, true)
R.check("les phases sont détaillées", rapport:find("collecte", 1, true) ~= nil, true)
R.check("session intacte", obj.entries, avant)
R.check("sélection intacte", obj.selectedIndex, selAvant)
obj:commit()

R.section("Les feux apparaissent aussi sur la tuile déjà visée")
nouvelleSession()
obj:step(1)
local vise = obj.selectedIndex
R.check("souris pas encore armée", obj.mouseArmed, false)
local rendus = 0
local vraiRedraw2 = obj.redraw
obj.redraw = function(self) rendus = rendus + 1 return vraiRedraw2(self) end
ctl.mousePosition = { x = 480, y = 360 }        -- déplacement franc
obj:handleMouseEvent("mouseMove", "tile:" .. tostring(vise))
R.check("la souris a repris la main", obj.mouseArmed, true)
R.check("la sélection n'a pas bougé", obj.selectedIndex, vise)
R.check("un rendu a quand même eu lieu", rendus, 1)
obj.redraw = vraiRedraw2

R.section("Elle ne redessine pas à chaque frémissement ensuite")
rendus = 0
obj.redraw = function(self) rendus = rendus + 1 return vraiRedraw2(self) end
obj:handleMouseEvent("mouseMove", "tile:" .. tostring(vise))
obj:handleMouseEvent("mouseMove", "tile:" .. tostring(vise))
R.check("aucun rendu inutile", rendus, 0)
obj.redraw = vraiRedraw2

R.section("Les feux s'effacent quand la souris se tait")
R.check("une minuterie d'inactivité est armée", obj.mouseIdleTimer ~= nil, true)
R.check("au délai configuré",
    ctl.timers[#ctl.timers].delay, obj.mouseIdleSeconds)
ctl.fireOnly(obj.mouseIdleSeconds)
R.check("la souris est désarmée", obj.mouseArmed, false)
R.check("la session continue", obj.entries ~= nil, true)

R.section("Un nouveau mouvement les fait revenir")
ctl.mousePosition = { x = 600, y = 420 }
obj:handleMouseEvent("mouseMove", "tile:" .. tostring(vise))
R.check("réarmée", obj.mouseArmed, true)

R.section("Survoler un feu repousse son effacement")
obj:handleMouseEvent("mouseEnter", "close:" .. tostring(vise))
R.check("la minuterie est relancée", obj.mouseIdleTimer ~= nil, true)
R.check("les feux restent affichés", obj.mouseArmed, true)
obj:commit()
R.check("la minuterie est annulée en fin de session", obj.mouseIdleTimer, nil)

R.section("Effacement désactivable")
nouvelleSession()
obj.mouseIdleSeconds = 0
obj:step(1)
ctl.mousePosition = { x = 500, y = 380 }
obj:handleMouseEvent("mouseMove", "tile:1")
R.check("aucune minuterie", obj.mouseIdleTimer, nil)
R.check("les feux restent", obj.mouseArmed, true)
obj.mouseIdleSeconds = 1.6
obj:commit()

R.section("Après stop, un start repart proprement")
obj.isStarted = false
obj:releaseWindowFilter()
ctl.filtersCreated = 0
obj.hotkeyMapping = { forward = { {"alt"}, "tab" }, backward = { {"alt","shift"}, "tab" } }
obj:start()
R.check("marqué démarré", obj.isStarted, true)
R.check("filtre monté d'avance, pas au premier Alt+Tab", ctl.filtersCreated, 1)
R.check("raccourcis en place", obj.hotkeys.forward ~= nil, true)
R.check("raccourci arrière en place", obj.hotkeys.backward ~= nil, true)

R.finish()
