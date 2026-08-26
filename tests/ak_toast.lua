package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end

obj.showStateNotifications = true
obj.verboseLogging = false

R.section("Plus aucun pavé plein écran")
ctl.printed = {}
obj.currentState = obj.STATE.OFF
obj:setState(obj.STATE.MONITORING)
local alerts = 0
for _,l in ipairs(ctl.printed) do if l:match("^ALERT:") then alerts = alerts + 1 end end
R.check("hs.alert n'est plus appelé", alerts, 0)
R.check("une bulle a été créée", #ctl.canvases, 1)

local c = ctl.canvases[1]
R.section("Forme et comportement de la bulle")
R.check("affichée", c.shown, true)
R.check("fondu à l'apparition", c.fadeIn, obj.toastFadeDuration)
R.check("deux éléments : fond + texte", #c.elements, 2)
R.check("fond arrondi", c.elements[1].roundedRectRadii.xRadius, obj.toastCornerRadius)
R.check("contour dessiné", c.elements[1].action, "strokeAndFill")
R.check("ne vole pas le focus", c.clickAct, false)
R.check("visible sur tous les Spaces", c.behaviors[1], "canJoinAllSpaces")
R.check("ne suit pas les bureaux", c.behaviors[2], "stationary")
R.check("au-dessus des fenêtres", c.level_, "overlay")

R.section("Ancrage sous l'icône")
ctl.canvases = {}
obj.menuBar = hs.menubar.new(true)
obj:showToast("Test")
local t = ctl.canvases[#ctl.canvases]
local icon = ctl.menuBarFrame
R.check("centrée sur l'icône", math.floor(t.rect.x + t.rect.w/2), math.floor(icon.x + icon.w/2))
R.check("juste sous l'icône", t.rect.y, icon.y + icon.h + obj.toastGap)

R.section("Icône masquée : repli en haut à droite")
ctl.canvases = {}
obj.menuBar = hs.menubar.new(false)
obj:showToast("Test")
t = ctl.canvases[#ctl.canvases]
local usable = hs.screen.mainScreen():frame()
R.check("collée au bord droit", t.rect.x + t.rect.w, usable.x + usable.w - obj.toastScreenMargin)
R.check("sous la barre des menus", t.rect.y, usable.y + obj.toastGap)

R.section("Icône près du bord : la bulle reste dans l'écran")
ctl.canvases = {}
ctl.menuBarFrame = { x = 1500, y = 0, w = 12, h = 24 }
obj.menuBar = hs.menubar.new(true)
obj:showToast("Un message plutôt long pour déborder")
t = ctl.canvases[#ctl.canvases]
local full = hs.screen.mainScreen():fullFrame()
R.check("ne dépasse pas à droite", t.rect.x + t.rect.w <= full.x + full.w - obj.toastScreenMargin + 0.01, true)

R.section("Largeur bornée")
ctl.canvases = {}
obj:showToast(string.rep("x", 300))
R.check("plafonnée à toastMaxWidth", ctl.canvases[#ctl.canvases].rect.w, obj.toastMaxWidth)

R.section("Une seule bulle à la fois")
ctl.canvases = {}
obj:showToast("premier")
local first = ctl.canvases[1]
obj:showToast("second")
R.check("la précédente est détruite", first.deleted, true)
R.check("deux bulles créées, une seule vivante", #ctl.canvases, 2)
R.check("celle retenue est la dernière", obj.toastCanvas, ctl.canvases[2])

R.section("Disparition automatique")
R.check("un minuteur est armé", obj.toastTimer ~= nil, true)
ctl.fireTimers()
R.check("bulle retirée après le délai", ctl.canvases[2].deleted, true)
R.check("plus de référence conservée", obj.toastCanvas, nil)

R.section("Thème sombre")
ctl.interfaceStyle = "Dark"
ctl.canvases = {}
obj:showToast("sombre")
local dark = ctl.canvases[1].elements[1].fillColor
ctl.interfaceStyle = nil
ctl.canvases = {}
obj:showToast("clair")
local light = ctl.canvases[1].elements[1].fillColor
R.check("fond sombre distinct du fond clair", dark.red ~= light.red, true)
R.check("fond sombre bien sombre", dark.red < 0.5, true)
R.check("fond clair bien clair", light.red > 0.5, true)

R.section("Message vide et nettoyage")
ctl.canvases = {}
obj:showToast("")
R.check("message vide : aucune bulle", #ctl.canvases, 0)
obj:showToast("quelque chose")
obj:hideToast()
R.check("hideToast détruit la bulle", ctl.canvases[1].deleted, true)
R.check("hideToast arrête le minuteur", obj.toastTimer, nil)

R.section("Les états respectent showStateNotifications")
obj.showStateNotifications = false
ctl.canvases = {}
obj.currentState = obj.STATE.MONITORING
obj:setState(obj.STATE.KEEPALIVE)
R.check("aucune bulle quand l'option est coupée", #ctl.canvases, 0)

R.finish()
