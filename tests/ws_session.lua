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
    obj.modifierTimer = nil
    obj.redrawTimer = nil
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
R.check("un eventtap est en place", #ctl.eventtaps, 1)
R.check("il écoute flagsChanged", ctl.eventtaps[1].types[1], "flagsChanged")
R.check("il tourne", ctl.eventtaps[1].running, true)
R.check("un seul timer de secours", #ctl.everyTimers, 1)
R.check("timer de secours espacé, pas 0,01 s",
    ctl.everyTimers[1].delay, obj.modifierSafetyInterval)

R.section("Relâcher la touche valide immédiatement")
ctl.modifierRaw = 0
ctl.eventtaps[1].fn()
R.check("session fermée", obj.entries, nil)
R.check("eventtap arrêté", ctl.eventtaps[1].running, false)
R.check("timer de secours arrêté", ctl.everyTimers[1].stopped, true)

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

R.section("Le canvas est alloué au démarrage, pas au premier switch")
obj.isStarted = false
obj.switcherCanvas = nil
obj.hotkeyMapping = { forward = { {"alt"}, "tab" } }
local canvasAvantStart = #ctl.canvases
obj:start()
R.check("canvas créé par start()", #ctl.canvases, canvasAvantStart + 1)
R.check("mais pas affiché", ctl.canvases[#ctl.canvases].shown, false)
local canvasDuStart = ctl.canvases[#ctl.canvases]
nouvelleSession()
obj:step(1)
R.check("le premier switch réutilise le même", ctl.canvases[#ctl.canvases], canvasDuStart)
R.check("et l'affiche", canvasDuStart.shown, true)
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
