------------------------------------------------------------
-- WindowSwitcher Spoon
--
-- Switcher de fenetres facon Alt-Tab, avec grille de captures.
------------------------------------------------------------


local obj = {}

obj.__index = obj

local canvas =
    require("hs.canvas")

local eventtap =
    require("hs.eventtap")

local fs =
    require("hs.fs")

local hash =
    require("hs.hash")

local host =
    require("hs.host")

local image =
    require("hs.image")

local screen =
    require("hs.screen")

local styledtext =
    require("hs.styledtext")

local task =
    require("hs.task")

local timer =
    require("hs.timer")

local window =
    require("hs.window")

local windowFilter =
    require("hs.window.filter")

-- hs.spaces repose sur les API privees de SkyLight. Une mise a jour de
-- macOS peut le rendre indisponible du jour au lendemain : il est
-- charge a part, et son absence retire seulement ce que les bureaux
-- apportent. Le switcher continue de fonctionner sans.
local spacesLoaded,
      spaces =
    pcall(require, "hs.spaces")

if not spacesLoaded then

    spaces = nil

end

local unpackTable =
    table.unpack or unpack



------------------------------------------------------------
-- METADONNEES
------------------------------------------------------------

obj.name = "WindowSwitcher"

obj.version = "0.19.0"

obj.author = "Benjamin Cerede / OpenAI"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

obj.verboseLogging = false

obj.includeMinimized = true

obj.includeHidden = true

obj.includeOtherSpaces = true

obj.excludeEmptyTitles = false

obj.minWindowWidth = 80

obj.minWindowHeight = 60

-- false plutot que nil : pour SpoonManager, une cle absente de la
-- table d'un Spoon signale une faute de frappe dans les reglages.
obj.ignoredBundlesFile = false

obj.maxColumns = 4

obj.maxRows = 3

obj.maxPanelWidthRatio = 0.78

obj.maxPanelHeightRatio = 0.62

obj.screenMargin = 64

obj.minPanelWidth = 360

obj.minPanelHeight = 240

obj.panelPadding = 30

obj.columnGap = 28

obj.rowGap = 24

obj.labelHeight = 30

obj.labelToPreviewGap = 8

obj.iconSize = 22

obj.placeholderIconScale = 3.1

obj.textSize = 15

-- Pastilles d'etat dessinees dans le coin de la vignette. Rien ne
-- distinguait jusqu'ici une fenetre reduite d'une fenetre visible.
obj.showStateBadges = true

obj.badgeSize = 23

obj.badgeTextSize = 14

obj.badgeGap = 5

obj.badgeStrokeWidth = 1.5

-- Une pastille sombre translucide sur une vignette sombre ne se voyait
-- pas. Chaque nature a desormais sa couleur pleine, un glyphe blanc et
-- un lisere clair qui la detache du fond, quel que soit le contenu de
-- la vignette.
obj.badges = {
    minimized = {
        glyph = "▼",
        color = {
            red = 0.98,
            green = 0.62,
            blue = 0.09,
            alpha = 0.97,
        },
    },
    hidden = {
        glyph = "⦸",
        color = {
            red = 0.55,
            green = 0.44,
            blue = 0.87,
            alpha = 0.97,
        },
    },
    audio = {
        glyph = "♪",
        color = {
            red = 0.16,
            green = 0.55,
            blue = 0.96,
            alpha = 0.97,
        },
    },
    microphone = {
        glyph = "●",
        color = {
            red = 0.91,
            green = 0.26,
            blue = 0.24,
            alpha = 0.97,
        },
    },
    otherSpace = {
        glyph = "⧉",
        color = {
            red = 0.10,
            green = 0.68,
            blue = 0.62,
            alpha = 0.97,
        },
    },
}

-- Une vignette ne disait pas si sa fenetre se trouve sur le bureau
-- courant. En plein ecran, ou avec plusieurs bureaux, la moitie de la
-- grille pointait vers des fenetres invisibles ici sans que rien ne le
-- signale.
--
-- Contrairement au test d'existence qui a echoue dans LastWindowQuits,
-- l'appartenance d'une fenetre VIVANTE a un bureau est une reponse
-- fiable : la question posee au WindowServer est ici « ou est cette
-- fenetre », pas « existe-t-elle encore ». Le switcher ne liste que des
-- fenetres vivantes.
obj.showSpaceBadges = true

-- Il n'existe pas de mode "amener la fenetre a soi". Mesure faite sur
-- cette machine, meme binaire, memes permissions :
--
--                                    ma fenetre   fenetre d'une
--                                                 autre application
--   CGSMoveWindowsToManagedSpace     REUSSI       echec
--   SLSSetWindowListWorkspace        ECHEC 1006   echec
--
-- Deux raisons independantes, chacune suffisante :
--
-- 1. Un processus ne peut deplacer que SES PROPRES fenetres. Dock.app
--    detient la seule connexion au window server autorisee a le faire
--    pour les autres. C'est pour cela que yabai injecte une extension
--    dans Dock.app, ce qui exige de desactiver SIP.
--
-- 2. Depuis macOS 14.5, hs.spaces.moveWindowToSpace appelle
--    SLSSetWindowListWorkspace, qui renvoie 1006 et ne fait rien --
--    meme sur la fenetre du processus appelant. Hammerspoon renvoie
--    true sans verifier, d'ou "l'API a dit oui, la fenetre n'a pas
--    bouge" dans le journal.
--
-- Le service de capture n'y changerait rien : c'est un processus
-- ordinaire lui aussi, soumis a la premiere regle.
--
-- Reste donc la bascule native de macOS, qui fonctionne.

-- La bascule de bureau dure environ une demi-seconde. Verifier le focus
-- plus tot le trouve force sur la mauvaise fenetre et declenche une
-- reprise inutile en pleine animation.
obj.crossSpaceFocusDelay = 0.7

-- Grouper les fenetres du bureau courant avant les autres, en gardant
-- l'ordre d'usage a l'interieur de chaque groupe. Desactive par defaut :
-- l'ordre par usage recent reste le comportement attendu d'un Alt+Tab.
obj.currentSpaceFirst = false

-- Quelle application joue du son, laquelle capte le micro. L'inventaire
-- vient du service, par l'API publique CoreAudio des objets de
-- processus.
--
-- Il est demande au demarrage puis a chaque session, et le resultat est
-- conserve d'une session a l'autre. Quand le service est froid il met
-- environ une demi-seconde a repondre : un switch tres bref se termine
-- avant, et les pastilles paraissent alors a la session suivante. C'est
-- le prix de l'extinction du service entre deux switchs ; allonger
-- helperIdleGraceSeconds les rend immediates au prix de 31 Mo
-- residents.
obj.showAudioBadges = true

-- "task" lance le service comme enfant de Hammerspoon : macOS attribue
-- alors ses acces au processus responsable, c'est-a-dire Hammerspoon.
-- Un autre processus qui lancerait le binaire serait responsable de
-- lui-meme, donc sans autorisation de capture.
--
-- "open" est l'ancien comportement : le service est detache et porte sa
-- propre identite TCC, donc invocable par n'importe quel processus du
-- compte. A garder si l'attribution par parent ne fonctionne pas.
obj.helperLaunchMode = "task"

-- Le service coute 31 Mo residents et sonde son repertoire toutes les
-- 0,35 s. Il s'arrete tout seul, mais au bout de 30 s : avec les
-- pastilles audio demandees a chaque switch, il resterait en vie
-- pratiquement toute la journee.
--
-- On l'arrete donc nous-memes des qu'il n'y a plus rien a faire. Une
-- rafale de switchs rapproches reutilise le meme processus ; un switch
-- isole paie un relancement, mesure a 500 ms, qui n'est sur le chemin
-- critique de rien puisque captures et inventaire sont asynchrones.
obj.helperIdleGraceSeconds = 6

-- Echap ferme le switcher sans rien activer. Un eventtap plutot qu'un
-- hs.hotkey : pendant un Option+Tab les modificateurs sont enfonces, et
-- un raccourci sans modificateur ne se declencherait jamais.
obj.enableCancelKey = true

-- Croix de fermeture dans le coin de la vignette. Elle n'apparait que
-- sur la tuile visee et seulement quand la souris est en jeu : au
-- clavier elle n'aurait aucune cible, et affichee partout elle
-- encombrerait la grille.
obj.showCloseButton = true

obj.showMinimizeButton = true

obj.trafficLightSize = 19

-- Ecart entre les deux boutons, en fraction de leur taille. Releve sur
-- une vraie fenetre : boutons de 14 pt aux abscisses 9 et 32, soit 9 pt
-- d'ecart.
obj.trafficLightGapRatio = 0.64

-- Tout ce qui suit vient de mesures faites sur une vraie fenetre macOS,
-- capturee a 2x avec l'etat survole force. Le remplissage et le symbole
-- sont identiques en theme clair et sombre ; seul le lisere bouge un
-- peu, on prend la moyenne des deux.
obj.trafficLights = {
    close = {
        fill = {
            red = 0.925,
            green = 0.404,
            blue = 0.396,
            alpha = 1,
        },
        rim = {
            red = 0.878,
            green = 0.204,
            blue = 0.200,
            alpha = 1,
        },
    },
    minimize = {
        fill = {
            red = 0.949,
            green = 0.792,
            blue = 0.267,
            alpha = 1,
        },
        rim = {
            red = 0.918,
            green = 0.718,
            blue = 0.027,
            alpha = 1,
        },
    },
}

-- Le symbole n'a pas de couleur propre : c'est exactement le disque
-- assombri de moitie. Verifie sur les deux boutons et les deux themes,
-- au canal pres : #763433 = #EC6765 x 0,5 et #7A6522 = #F2CA44 x 0,5.
obj.trafficLightSymbolColor = {
    white = 0,
    alpha = 0.5,
}

-- Epaisseur du trait, en fraction du diametre : 4,24 px releves sur un
-- disque de 28 px pour la croix, 4 px pour la barre.
obj.trafficLightStrokeRatio = 0.147

-- Etendue visible du symbole, bouts arrondis compris, en fraction du
-- diametre : c'est ce que mesure une boite englobante sur la capture.
-- Les bouts depassant des extremites du trait de la moitie de son
-- epaisseur de chaque cote, le trait lui-meme est plus court d'une
-- epaisseur entiere.
obj.closeSymbolExtent = 0.50

obj.minimizeSymbolExtent = 0.571

-- W ferme la fenetre visee au clavier. Le code physique est lu sur la
-- disposition courante.
obj.enableCloseKey = true

obj.enableMinimizeKey = true

obj.panelCornerRadius = 24

obj.tileCornerRadius = 10

obj.canvasPadding = 22

obj.selectedStrokeWidth = 3

obj.previewMaxWidth = 300

obj.previewMaxHeight = 190

obj.previewMinWidth = 95

obj.previewMinHeight = 90

obj.labelMinWidth = 120

obj.labelMaxWidth = 330

obj.snapshotCacheSeconds = 20

obj.screenCaptureHelperEnabled = true

obj.instantVisibleSnapshots = true

obj.maxConcurrentScreenCaptures = 2

obj.enableMouseSelection = true

-- false plutot que nil : pour SpoonManager, une cle absente de la
-- table d'un Spoon signale une faute de frappe dans les reglages.
obj.screenCaptureHelperPath = false

-- false plutot que nil : pour SpoonManager, une cle absente de la
-- table d'un Spoon signale une faute de frappe dans les reglages.
obj.screenCaptureHelperAppPath = false

obj.screenCapturePixelHeight = 420

obj.screenCaptureFailureBackoffSeconds = 5

-- Certaines fenetres ne seront jamais capturables : macOS refuse par
-- conception le panneau Enregistrement de l'ecran, et renvoie une
-- erreur de diffusion a chaque tentative. Le delai de cinq secondes
-- faisait reessayer a chaque switch, en journalisant a chaque fois.
--
-- Apres ce nombre d'echecs consecutifs, la fenetre est mise de cote
-- pour une duree bien plus longue. Elle affiche l'icone de son
-- application, ce qui est le bon repli.
obj.screenCaptureGiveUpAfter = 3

obj.screenCaptureGiveUpBackoffSeconds = 600

-- Le helper s'accorde lui-meme 5 s par capture et sonde au repos
-- toutes les 0,35 s : il peut donc legitimement repondre a 5,35 s.
-- Abandonner a 5 s faisait echouer des captures qui allaient aboutir.
obj.screenCaptureRequestTimeoutSeconds = 6.5

obj.screenCapturePollIntervalSeconds = 0.08

-- /tmp est partage et inscriptible par tous (mode 1777) : un
-- repertoire cree a l'avance par un autre compte, laisse ouvert en
-- lecture, aurait accueilli nos captures. TMPDIR est le repertoire
-- temporaire propre a l'utilisateur, deja en 0700 et hors de portee des
-- autres comptes. On retombe sur /tmp seulement s'il est introuvable,
-- et la verification de propriete s'applique dans les deux cas.
obj.screenCaptureSessionBaseDirectory =
    (function()

        local temporary =
            os.getenv("TMPDIR")


        if temporary and temporary ~= "" then

            return (temporary:gsub("/+$", "")) .. "/WindowSwitcher"

        end


        return "/tmp/WindowSwitcher"

    end)()

obj.screenCaptureSessionPrefix = "session-"

obj.disableScreenCaptureHelperAfterCGSAssertion = true

obj.logScreenCaptureFailures = true

obj.stepThrottleSeconds = 0.06

-- Seconde passe d'inventaire via hs.window.allWindows() : un balayage
-- d'accessibilite de toutes les applications lancees. C'est l'operation
-- la plus couteuse d'une session, et elle n'est pas facultative.
--
-- La 0.9.0 l'avait desactivee en supposant qu'un filtre permanent
-- suffisait. C'est faux, pour deux raisons lues dans window_filter.lua :
--
-- 1. Une application n'entre dans le filtre que si app:focusedWindow()
--    repond, sinon elle part dans une echelle de reessais de 0,2 s a
--    1,2 s dont seul le dernier force l'inscription : 4,2 s au total.
--    Une application dont toutes les fenetres sont reduites n'a pas de
--    fenetre focalisee, donc elle est absente du filtre pendant les
--    quatre premieres secondes suivant le demarrage.
--
-- 2. A l'inscription, le filtre n'enumere que l'espace courant
--    (getCurrentSpaceAppWindows, avec un TODO explicite en commentaire
--    sur l'impossibilite de faire mieux).
--
-- Le filtre n'est donc pas une source de verite complete, et cette
-- passe est ce qui rattrape ses deux angles morts.
obj.completeWithAllWindows = true

-- Filet de securite derriere l'eventtap flagsChanged. L'ancien code
-- sondait le clavier toutes les 10 ms pendant toute la duree du switch.
obj.modifierSafetyInterval = 0.35

-- Intervalle utilise si l'eventtap n'a pas pu demarrer : la sans lui,
-- c'est ce timer qui doit rester reactif.
obj.modifierFallbackInterval = 0.05

-- Les captures qui arrivent en rafale ne doivent pas declencher un
-- rendu complet chacune.
obj.redrawCoalesceSeconds = 0.05

obj.snapshotCacheMaxEntries = 200

obj.snapshotCacheMaxAgeSeconds = 600

-- Distance en pixels que la souris doit parcourir avant de reprendre la
-- main sur la selection clavier.
obj.mouseActivationDistance = 6

-- Au bout de ce silence de la souris, les feux s'effacent. Ils
-- reapparaissent des qu'elle bouge a nouveau. Sans cela ils restaient a
-- l'ecran jusqu'a la fin de la session, alors qu'ils ne servent que
-- lorsqu'on vise avec la souris.
obj.mouseIdleSeconds = 1.6

obj.screenCaptureHelperBundleID = "local.hammerspoon.WindowSwitcherCapture"

-- Un raise ne prend pas toujours du premier coup : l'application cible
-- peut encore etre en train de se demasquer ou de restaurer sa fenetre.
-- On verifie une fois, peu apres, et on insiste si besoin.
obj.focusReassertDelay = 0.12

-- hs.window.snapshotForID est synchrone. Douze tuiles a capturer avant
-- le premier affichage, c'est le temps de fabrication que l'on ressent
-- a la premiere ouverture. On s'accorde ce budget, en commencant par la
-- tuile selectionnee ; le reste arrive au rendu suivant.
obj.snapshotBudgetSeconds = 0.045

-- Apercu : la fenetre selectionnee est redessinee a sa taille et a sa
-- place reelles, au-dessus des autres fenetres mais sous le panneau du
-- switcher. Le liseré la rend visible meme lorsqu'elle est deja au
-- premier plan et que l'apercu se confond avec elle.
obj.enableWindowPreview = true

-- Temps d'arret avant qu'un apercu apparaisse. Il est remis a zero a
-- chaque changement de tuile : tant qu'on parcourt la grille, rien ne
-- s'affiche, et l'apercu deja visible disparait aussitot. Il ne revient
-- que lorsqu'on s'arrete pour de bon.
obj.previewDelay = 0.65

obj.previewOnKeyboard = true

obj.previewMaxScreenRatio = 0.94

obj.previewCornerRadius = 10

obj.previewBorderWidth = 3

obj.theme = "auto"

obj.lightTheme = {
    badgeBackgroundColor = {
        red = 0.12,
        green = 0.13,
        blue = 0.15,
        alpha = 0.70,
    },
    badgeTextColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.97,
    },
    backgroundColor = {
        red = 0.91,
        green = 0.94,
        blue = 0.98,
        alpha = 0.72,
    },
    thumbnailBackgroundColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.28,
    },
    labelTextColor = {
        red = 0.14,
        green = 0.15,
        blue = 0.17,
        alpha = 0.96,
    },
    panelStrokeColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.62,
    },
    tileStrokeColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.52,
    },
    shadowColor = {
        red = 0,
        green = 0,
        blue = 0,
        alpha = 0.18,
    },
    hitTargetColor = {
        white = 1,
        alpha = 0.01,
    },
    selectedBorderColor = {
        red = 0.08,
        green = 0.48,
        blue = 0.95,
        alpha = 0.98,
    },
}

obj.darkTheme = {
    badgeBackgroundColor = {
        red = 0,
        green = 0,
        blue = 0,
        alpha = 0.62,
    },
    badgeTextColor = {
        red = 0.96,
        green = 0.97,
        blue = 0.99,
        alpha = 0.97,
    },
    backgroundColor = {
        red = 0.09,
        green = 0.105,
        blue = 0.125,
        alpha = 0.78,
    },
    thumbnailBackgroundColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.10,
    },
    labelTextColor = {
        red = 0.91,
        green = 0.93,
        blue = 0.96,
        alpha = 0.98,
    },
    panelStrokeColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.16,
    },
    tileStrokeColor = {
        red = 1,
        green = 1,
        blue = 1,
        alpha = 0.18,
    },
    shadowColor = {
        red = 0,
        green = 0,
        blue = 0,
        alpha = 0.34,
    },
    hitTargetColor = {
        white = 1,
        alpha = 0.01,
    },
    selectedBorderColor = {
        red = 0.23,
        green = 0.58,
        blue = 1,
        alpha = 1,
    },
}

obj.badgeBackgroundColor = {
    red = 0.12,
    green = 0.13,
    blue = 0.15,
    alpha = 0.70,
}

obj.badgeTextColor = {
    red = 1,
    green = 1,
    blue = 1,
    alpha = 0.97,
}

obj.backgroundColor = {
    red = 0.92,
    green = 0.95,
    blue = 0.98,
    alpha = 0.72,
}

obj.thumbnailBackgroundColor = {
    red = 1,
    green = 1,
    blue = 1,
    alpha = 0.26,
}

obj.labelTextColor = {
    red = 0.16,
    green = 0.16,
    blue = 0.16,
    alpha = 0.96,
}

obj.selectedBorderColor = {
    red = 0.08,
    green = 0.48,
    blue = 0.95,
    alpha = 0.98,
}

obj.unselectedAlpha = 0.90

obj.selectedAlpha = 1.0

obj.excludedBundleIDs = {
    ["com.apple.controlcenter"] = true,
    ["com.apple.notificationcenterui"] = true,
    ["pro.bettercmdtab.BetterCmdTab"] = true,
}

obj.excludedAppNames = {
}

obj.allowedWindowRoles = {
    ["AXStandardWindow"] = true,
    ["AXDialog"] = true,
    ["AXSystemDialog"] = true,
}



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.hotkeys = {}

obj.hotkeyMapping = nil

obj.isStarted = false

obj.loadedExcludedBundleIDs = nil


obj.selectedIndex = nil

obj.switcherCanvas = nil

obj.modifierTimer = nil

obj.snapshotCache = {}

obj.screenCaptureFailureCache = {}

obj.screenCaptureFailureCounts = {}

obj.screenCaptureReportedFailures = {}

obj.screenCaptureQueue = {}

obj.queuedScreenCaptures = {}

obj.runningScreenCaptures = {}

obj.screenCaptureDisabledReason = nil

obj.screenCapturePollTimer = nil

obj.screenCaptureHelperAppStarted = false

obj.screenCaptureSessionID = nil

obj.screenCaptureSessionSecret = nil

obj.screenCaptureSessionDirectory = nil

obj.iconCache = {}

obj.lastStepAt = nil

obj.entries = nil

obj.descriptorPass = nil

-- Bureaux visibles au moment ou la session s'ouvre. Rafraichi une fois
-- par session : pendant qu'on tient Alt, l'utilisateur ne change pas de
-- bureau.
obj.activeSpaceIDs = nil

-- Faux des qu'un appel a hs.spaces a echoue : on cesse d'insister pour
-- la session en cours.
obj.spacesUsable = true

obj.windowFilterInstance = nil

obj.windowFilterSpaceMode = nil

obj.layoutCache = nil

obj.titleCache = {}

obj.redrawTimer = nil

obj.modifierTap = nil

obj.ignoredBundlesSignature = nil

obj.captureFiles = {}

obj.mouseArmed = false

obj.mouseOrigin = nil

obj.mouseIdleTimer = nil

obj.previewCanvas = nil

obj.previewTimer = nil

obj.previewIndex = nil

obj.previewVisible = false

obj.cachedUserID = nil

obj.sessionKeyTap = nil

obj.helperTask = nil

obj.helperIdleTimer = nil

obj.audioPIDs = {}

obj.microphonePIDs = {}

obj.selectionFromMouse = false



------------------------------------------------------------
-- LOG / NOTIFICATIONS
------------------------------------------------------------

function obj:log(message)

    print(
        string.format(
            "%s - WindowSwitcher %s - %s",
            os.date("%Y-%m-%d %H:%M:%S"),
            self.version,
            tostring(message)
        )
    )

end


function obj:debug(message)

    if self.verboseLogging then

        self:log(message)

    end

end


------------------------------------------------------------
-- OUTILS
------------------------------------------------------------

-- Renvoie valeur, erreur. L'ancienne version ne renvoyait qu'une
-- valeur : les deux sites qui ecrivaient "Erreur layout canvas : " ..
-- tostring(err) affichaient donc toujours "nil", et le seul diagnostic
-- du rendu ne diagnostiquait rien.
local function safeCall(fn)

    local ok,
          value =
        pcall(fn)


    if ok then

        return value, nil

    end


    return nil, value

end


local function trim(value)

    return tostring(value or ""):match("^%s*(.-)%s*$")

end


local function rounded(radius)

    return {
        xRadius = radius,
        yRadius = radius,
    }

end


function obj:isDarkThemeActive()

    local theme =
        tostring(self.theme or "auto"):lower()


    if theme == "dark" then

        return true

    end


    if theme == "light" or theme == "custom" then

        return false

    end


    return safeCall(function()

        return host.interfaceStyle() == "Dark"

    end) == true

end


function obj:themeColor(name)

    local theme =
        tostring(self.theme or "auto"):lower()


    if theme == "custom" then

        return self[name]

    end


    local palette =
        self:isDarkThemeActive() and self.darkTheme or self.lightTheme


    return (palette and palette[name]) or self[name]

end


local function shellQuote(value)

    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"

end


local function bytesToHex(value)

    return (tostring(value or ""):gsub(
        ".",
        function(char)

            return string.format("%02x", string.byte(char))

        end
    ))

end


local function readRandomHex(byteCount)

    local file =
        io.open("/dev/urandom", "rb")


    if not file then

        return hash.SHA256(
            tostring(timer.secondsSinceEpoch())
                .. tostring(math.random())
                .. tostring({})
        )

    end


    local value =
        file:read(byteCount)


    file:close()


    return bytesToHex(value)

end


local function splitLines(value, limit)

    local lines =
        {}


    local text =
        tostring(value or "")


    local start =
        1


    while start <= #text + 1
        and (not limit or #lines < limit) do

        local stop =
            text:find("\n", start, true)


        if stop then

            table.insert(lines, text:sub(start, stop - 1))

            start =
                stop + 1

        else

            table.insert(lines, text:sub(start))

            break

        end

    end


    return lines

end


function obj:getSpoonDirectory()

    local info =
        debug.getinfo(1, "S")


    local source =
        tostring(info and info.source or "")


    if source:sub(1, 1) == "@" then

        source =
            source:sub(2)

    end


    return source:match("^(.*)/init%.lua$")

end


function obj:defaultIgnoredBundlesFile()

    local path =
        self:getSpoonDirectory()


    if path then

        return path .. "/ignored-bundles.txt"

    end


    return nil

end


function obj:defaultScreenCaptureHelperPath()

    local path =
        self:getSpoonDirectory()


    if path then

        local bundledHelper =
            path .. "/WindowSwitcherCapture.app/Contents/MacOS/window-capture-helper"


        if fs.attributes(bundledHelper) then

            return bundledHelper

        end


        return path .. "/window-capture-helper"

    end


    return nil

end


-- Le binaire livre est signe ad hoc : le recompiler change son cdhash
-- et revoque l'autorisation Enregistrement de l'ecran. On ne compile
-- donc jamais tout seul, mais on signale quand la source a evolue sans
-- que le binaire ait suivi : sinon un durcissement ecrit dans le .swift
-- donnerait l'illusion d'etre en place.

function obj:helperSourcePath()

    local path =
        self:getSpoonDirectory()


    if path then

        return path .. "/window-capture-helper.swift"

    end


    return nil

end


-- Empreinte de la source telle qu'elle etait au moment de la
-- compilation, deposee par build-helper.sh a cote du binaire.

function obj:helperStampPath()

    local path =
        self:getSpoonDirectory()


    if path then

        return path .. "/window-capture-helper.sha256"

    end


    return nil

end


function obj:readTextFile(path)

    if not path then

        return nil

    end


    local file =
        io.open(path, "r")


    if not file then

        return nil

    end


    local contents =
        file:read("*a")


    file:close()


    return contents

end


-- La comparaison des dates de modification etait un mauvais juge.
-- Copier le Spoon suffisait a rendre le .swift plus recent que le
-- binaire, sans qu'une seule ligne ait change : l'avertissement
-- reclamait alors une recompilation -- et, en mode "open", une
-- reautorisation d'Enregistrement de l'ecran -- pour rien.
--
-- Ce qui compte n'est pas la date mais le contenu. build-helper.sh
-- depose l'empreinte de la source compilee ; une copie l'emporte avec
-- elle, une vraie modification la contredit.

function obj:checkHelperFreshness()

    local sourcePath =
        self:helperSourcePath()


    local binaryPath =
        self.screenCaptureHelperPath or self:defaultScreenCaptureHelperPath()


    if not sourcePath or not binaryPath then

        return true

    end


    local source =
        self:readTextFile(sourcePath)


    if not source then

        return true

    end


    local empreinte =
        safeCall(function()

            return hash.SHA256(source)

        end)


    local depose =
        self:readTextFile(self:helperStampPath())


    if depose then

        depose =
            depose:match("^%s*(%x+)")

    end


    if depose and empreinte then

        if depose:lower() == empreinte:lower() then

            return true

        end


        self:log(
            "ATTENTION : window-capture-helper.swift a change depuis la "
            .. "compilation du binaire en service. Les corrections de la "
            .. "source ne sont pas actives. Relancer build-helper.sh."
            .. (self.helperLaunchMode == "open"
                and " En mode \"open\", reaccorder ensuite Enregistrement"
                    .. " de l'ecran : la signature change."
                or "")
        )


        return false

    end


    -- Pas d'empreinte deposee : installation anterieure a
    -- build-helper.sh. On retombe sur les dates, en le disant.

    local sourceTime =
        fs.attributes(sourcePath, "modification")


    local binaryTime =
        fs.attributes(binaryPath, "modification")


    if not sourceTime or not binaryTime or sourceTime <= binaryTime then

        return true

    end


    self:log(
        "window-capture-helper.swift porte une date plus recente que le "
        .. "binaire. Aucune empreinte n'ayant ete deposee, ce constat "
        .. "peut venir d'une simple copie. Relancer build-helper.sh "
        .. "leve le doute."
    )


    return false

end


function obj:defaultScreenCaptureHelperAppPath()

    local path =
        self:getSpoonDirectory()


    if path then

        return path .. "/WindowSwitcherCapture.app"

    end


    return nil

end


function obj:screenCaptureCacheDirectory()

    return self.screenCaptureSessionDirectory
        or self.screenCaptureSessionBaseDirectory

end


function obj:screenCaptureRequestDirectory()

    return self:screenCaptureCacheDirectory() .. "/requests"

end


function obj:screenCaptureCaptureDirectory()

    return self:screenCaptureCacheDirectory() .. "/captures"

end


function obj:screenCaptureSecretPath()

    return self:screenCaptureCacheDirectory() .. "/secret"

end


function obj:screenCaptureRequestPath(jobOrToken)

    local token =
        type(jobOrToken) == "table" and jobOrToken.token or jobOrToken

    return string.format(
        "%s/%s.request",
        self:screenCaptureRequestDirectory(),
        tostring(token)
    )

end


function obj:screenCaptureStatusPath(jobOrToken)

    local token =
        type(jobOrToken) == "table" and jobOrToken.token or jobOrToken

    return string.format(
        "%s/%s.status",
        self:screenCaptureRequestDirectory(),
        tostring(token)
    )

end


function obj:readIgnoredBundlesFile()

    local path =
        self.ignoredBundlesFile or self:defaultIgnoredBundlesFile()


    local ignored =
        {}


    for bundleID, enabled in pairs(self.excludedBundleIDs or {}) do

        if enabled then

            ignored[bundleID] =
                true

        end

    end


    if not path then

        return ignored

    end


    local file =
        io.open(path, "r")


    if not file then

        self:debug("Fichier ignore absent : " .. tostring(path))

        return ignored

    end


    for line in file:lines() do

        local bundleID =
            trim(line:gsub("#.*$", ""))


        if bundleID ~= "" then

            ignored[bundleID] =
                true

        end

    end


    file:close()


    return ignored

end


------------------------------------------------------------
-- DESCRIPTEURS DE FENETRE
--
-- Interroger une fenetre coute cher : chaque win:application() est un
-- aller-retour NSRunningApplication. L'ancienne version en faisait
-- trois par fenetre rien que pour la filtrer (nom, bundle, masquage),
-- puis trois de plus au moment de mettre une capture en file. On
-- resout tout une seule fois et on transporte le resultat.
------------------------------------------------------------

function obj:beginDescriptorPass()

    self.descriptorPass =
        {}


    return self

end


function obj:endDescriptorPass()

    self.descriptorPass =
        nil


    return self

end


function obj:describeWindow(win)

    if not win then

        return nil

    end


    local id =
        self:windowID(win)


    if not id then

        return nil

    end


    local pass =
        self.descriptorPass


    if pass then

        local cached =
            pass[id]


        if cached and cached.window == win then

            return cached

        end

    end


    local application =
        safeCall(function()

            return win:application()

        end)


    local descriptor =
        {
            window = win,
            id = id,
            application = application,
            appResolved = application ~= nil,
        }


    if application then

        descriptor.pid =
            safeCall(function()

                return application:pid()

            end)


        descriptor.bundleID =
            safeCall(function()

                return application:bundleID()

            end)


        descriptor.appName =
            safeCall(function()

                return application:name()

            end)


        descriptor.hidden =
            safeCall(function()

                return application:isHidden()

            end) == true

    end


    descriptor.title =
        safeCall(function()

            return win:title()

        end) or ""


    descriptor.role =
        safeCall(function()

            return win:subrole()

        end)


    descriptor.frame =
        safeCall(function()

            return win:frame()

        end)


    descriptor.minimized =
        safeCall(function()

            return win:isMinimized()

        end) == true


    descriptor.displayTitle =
        (descriptor.appName or "Application")


    if descriptor.title ~= "" then

        descriptor.displayTitle =
            descriptor.displayTitle .. " - " .. descriptor.title

    end


    if pass then

        pass[id] =
            descriptor

    end


    return descriptor

end



------------------------------------------------------------
-- BUREAUX
--
-- Le WindowServer sait sur quels bureaux se trouve une fenetre. Mesure
-- sur macOS 26, cette reponse est fiable pour une fenetre vivante, et
-- elle ne l'est pas pour savoir si une fenetre existe encore : une
-- fenetre fermee garde sa ligne tant que son application tourne. Le
-- switcher ne pose que la premiere question.
------------------------------------------------------------

-- L'inventaire est lu directement, et non par hs.spaces.activeSpaces().
--
-- Cette derniere passe par activeSpaceOnScreen(), qui contient ceci :
-- quand NSScreen.screensHaveSeparateSpaces vaut faux, elle remplace
-- l'UUID de l'ecran par la chaine "Main", puis cherche un ecran nomme
-- "Main" dans la liste des ecrans geres. Mesure sur cette machine :
--
--   NSScreen.screensHaveSeparateSpaces = false
--   hs.screen:getUUID()                = 37D8832A-2D66-...
--   Display Identifier                 = 37D8832A-2D66-...
--
-- La liste ne contient que des UUID. La comparaison echoue toujours et
-- activeSpaces() renvoie nil : tout ce qui concerne les bureaux
-- s'eteignait sans un mot des que l'option "Les moniteurs ont des
-- espaces separes" etait decochee.
--
-- data_managedDisplaySpaces() donne la meme information sans passer par
-- cette identification d'ecran. C'est aussi l'appel unique dont
-- activeSpaces() se sert une fois PAR ECRAN.

function obj:refreshActiveSpaces()

    self.activeSpaceIDs =
        nil


    self.spacesUsable =
        spaces ~= nil


    if not self.spacesUsable
        or not (self.showSpaceBadges
            or self.currentSpaceFirst) then

        return self

    end


    local visibles =
        {}


    local compte =
        0


    local ecrans =
        safeCall(function()

            return spaces.data_managedDisplaySpaces()

        end)


    if type(ecrans) == "table" then

        for _, ecran in ipairs(ecrans) do

            local courant =
                type(ecran) == "table" and ecran["Current Space"]


            local spaceID =
                type(courant) == "table" and courant.ManagedSpaceID


            if type(spaceID) == "number" then

                visibles[spaceID] =
                    true


                compte =
                    compte + 1

            end

        end

    end


    -- Repli sur l'API documentee si la lecture directe disparait un
    -- jour. Elle souffre du defaut decrit plus haut, mais mieux vaut
    -- une reponse parfois absente que pas de reponse du tout.

    if compte == 0 then

        local par_ecran =
            safeCall(function()

                return spaces.activeSpaces()

            end)


        if type(par_ecran) == "table" then

            for _, spaceID in pairs(par_ecran) do

                if type(spaceID) == "number" then

                    visibles[spaceID] =
                        true


                    compte =
                        compte + 1

                end

            end

        end

    end


    if compte == 0 then

        self.spacesUsable =
            false


        return self

    end


    self.activeSpaceIDs =
        visibles


    return self

end


-- Renvoie true, false, ou nil quand la question n'a pas de reponse.
-- Le resultat est memorise dans le descripteur : une session ne paie
-- qu'une seule interrogation par fenetre.

function obj:isOnOtherSpace(descriptor)

    if not descriptor then

        return nil

    end


    if descriptor.onOtherSpace ~= nil then

        return descriptor.onOtherSpace

    end


    if not spaces
        or not self.spacesUsable
        or not self.activeSpaceIDs then

        return nil

    end


    -- Une version precedente ecartait ici les fenetres reduites et
    -- masquees, en supposant qu'elles n'appartenaient plus a aucun
    -- bureau. Mesure faite sur une vraie NSWindow :
    --
    --   ouverte, visible   spaces=[1]
    --   REDUITE (Dock)     spaces=[1]
    --   restauree          spaces=[1]
    --
    -- Une fenetre reduite garde son bureau, et unminimize l'y rend :
    -- l'utilisateur qui tabule dessus se retrouve sur l'autre bureau.
    -- C'est exactement ce que la pastille doit annoncer, et exactement
    -- ce que le mode "bring" doit pouvoir eviter.

    local liste =
        safeCall(function()

            return spaces.windowSpaces(descriptor.id)

        end)


    if type(liste) ~= "table" or #liste == 0 then

        -- Pas de reponse, et ce cas est majoritaire. Sonde sur cette
        -- machine, 40 fenetres relevees par CGWindowList :
        --
        --   Notes           wid=2035  spaces=204  -> autre bureau
        --   Claude          wid=1441  spaces=1    -> bureau courant
        --   Firefox, Edge, 1Password, panneaux... spaces=[] (vide)
        --
        -- Le WindowServer ne situe que les fenetres qui ont une
        -- presence : les panneaux, les fenetres reduites et celles des
        -- applications masquees repondent une liste vide. Les traiter
        -- comme "ailleurs" aurait pastille presque toute la grille.
        --
        -- On tranche donc du cote qui n'invente rien : ni pastille, ni
        -- deplacement, ni regroupement. Et on ne redemande pas pour
        -- cette fenetre.

        descriptor.onOtherSpace =
            false


        return false

    end


    for _, spaceID in ipairs(liste) do

        if self.activeSpaceIDs[spaceID] then

            descriptor.onOtherSpace =
                false


            return false

        end

    end


    descriptor.onOtherSpace =
        true


    return true

end


-- Groupe les fenetres du bureau courant devant les autres, sans
-- deranger l'ordre d'usage a l'interieur de chaque groupe.

function obj:groupByCurrentSpace(collected)

    if not self.currentSpaceFirst
        or not self.activeSpaceIDs
        or #collected < 2 then

        return collected

    end


    local ici,
          ailleurs =
        {},
        {}


    for _, descriptor in ipairs(collected) do

        if self:isOnOtherSpace(descriptor) == true then

            ailleurs[#ailleurs + 1] =
                descriptor

        else

            ici[#ici + 1] =
                descriptor

        end

    end


    for _, descriptor in ipairs(ailleurs) do

        ici[#ici + 1] =
            descriptor

    end


    return ici

end



------------------------------------------------------------
-- ACCESSEURS FENETRE
--
-- Conserves pour compatibilite ; ils passent tous par le descripteur
-- afin qu'un meme appel ne soit jamais paye deux fois dans une passe.
------------------------------------------------------------

function obj:windowApplication(win)

    local descriptor =
        self:describeWindow(win)


    return descriptor and descriptor.application

end


function obj:windowBundleID(win)

    local descriptor =
        self:describeWindow(win)


    return descriptor and descriptor.bundleID

end


function obj:windowAppName(win)

    local descriptor =
        self:describeWindow(win)


    return descriptor and descriptor.appName

end


function obj:windowTitle(win)

    local descriptor =
        self:describeWindow(win)


    return (descriptor and descriptor.title) or ""

end


function obj:windowRole(win)

    local descriptor =
        self:describeWindow(win)


    return descriptor and descriptor.role

end


function obj:windowFrame(win)

    local descriptor =
        self:describeWindow(win)


    return descriptor and descriptor.frame

end


function obj:isWindowMinimized(win)

    local descriptor =
        self:describeWindow(win)


    return (descriptor and descriptor.minimized) == true

end


function obj:isWindowHidden(win)

    local descriptor =
        self:describeWindow(win)


    return (descriptor and descriptor.hidden) == true

end


function obj:isDescriptorAllowed(descriptor)

    if not descriptor then

        return false

    end


    -- Une lecture qui echoue est un incident passager, pas une preuve
    -- que la fenetre n'a pas sa place ici. L'ancienne version excluait
    -- toute fenetre dont le nom d'application etait illisible : un
    -- timeout AX suffisait a la rendre inatteignable au clavier pour
    -- toute la session. Afficher une tuile en trop coute infiniment
    -- moins cher que perdre une fenetre.

    if descriptor.appResolved then

        if descriptor.appName
            and self.excludedAppNames[descriptor.appName] then

            return false

        end


        if descriptor.bundleID
            and self.loadedExcludedBundleIDs
            and self.loadedExcludedBundleIDs[descriptor.bundleID] then

            return false

        end

    end


    if self.excludeEmptyTitles and descriptor.title == "" then

        return false

    end


    if descriptor.role
        and not self.allowedWindowRoles[descriptor.role] then

        return false

    end


    local frame =
        descriptor.frame


    if frame then

        if frame.w and frame.w < self.minWindowWidth then

            return false

        end


        if frame.h and frame.h < self.minWindowHeight then

            return false

        end

    end


    if not self.includeMinimized and descriptor.minimized then

        return false

    end


    if not self.includeHidden and descriptor.hidden then

        return false

    end


    return true

end


function obj:isWindowAllowed(win)

    return self:isDescriptorAllowed(
        self:describeWindow(win)
    )

end



------------------------------------------------------------
-- FILTRE DE FENETRES
--
-- Le filtre est cree une fois et maintenu actif. L'ancienne version en
-- construisait un neuf a chaque Alt+Tab : hs.window.filter monte alors
-- un observateur AX sur chaque application et chaque fenetre de la
-- machine (startGlobalWatcher), puis demonte tout au :pause() qui suit
-- getWindows(). Ce cycle laissait derriere lui les timers de reessai
-- de pendingApps, qui rappelaient app:focusedWindow() sur des
-- applications entre-temps fermees : c'est la source des messages
-- "LuaSkin: Unable to fetch NSRunningApplication for pid", repetes
-- autant de fois qu'il y avait de reessais.
------------------------------------------------------------

function obj:ensureWindowFilter()

    local spaceMode =
        self.includeOtherSpaces and "all" or "current"


    if self.windowFilterInstance
        and self.windowFilterSpaceMode == spaceMode then

        return self.windowFilterInstance

    end


    self:releaseWindowFilter()


    local filter =
        windowFilter.new(function(win)

            return self:isWindowAllowed(win)

        end)


    if not filter then

        return nil

    end


    if not self.includeOtherSpaces then

        filter:setCurrentSpace(true)

    end


    -- Sans keepActive, getWindows() met le filtre en pause juste apres
    -- l'avoir demarre, ce qui declenche le demontage complet decrit
    -- plus haut.

    if filter.keepActive then

        safeCall(function()

            filter:keepActive()

        end)

    end


    self.windowFilterInstance =
        filter


    self.windowFilterSpaceMode =
        spaceMode


    return filter

end


function obj:releaseWindowFilter()

    if self.windowFilterInstance then

        safeCall(function()

            self.windowFilterInstance:delete()

        end)


        self.windowFilterInstance =
            nil


        self.windowFilterSpaceMode =
            nil

    end


    return self

end


-- window._orderedwinids() est un appel unique au WindowServer, sans
-- accessibilite : c'est la meme primitive que celle qu'utilisent les
-- switchers natifs pour connaitre l'ordre de profondeur. Les fenetres
-- que seule la seconde passe trouve etaient jusqu'ici ajoutees dans
-- l'ordre d'enumeration des applications, c'est-a-dire au hasard.

function obj:orderedWindowRanks()

    local ids =
        safeCall(function()

            return window._orderedwinids()

        end)


    if type(ids) ~= "table" then

        return nil

    end


    local ranks =
        {}


    for rank, id in ipairs(ids) do

        if ranks[id] == nil then

            ranks[id] =
                rank

        end

    end


    return ranks

end


function obj:collectWindows()

    self:refreshIgnoredBundles()
    self:beginDescriptorPass()


    local collected =
        {}


    local seen =
        {}


    local function addWindows(windows)

        for _, win in ipairs(windows or {}) do

            local descriptor =
                self:describeWindow(win)


            if descriptor
                and not seen[descriptor.id]
                and self:isDescriptorAllowed(descriptor) then

                seen[descriptor.id] =
                    true


                table.insert(collected, descriptor)

            end

        end

    end


    local filter =
        self:ensureWindowFilter()


    if filter then

        addWindows(
            safeCall(function()

                return filter:getWindows(
                    windowFilter.sortByFocusedLast
                )

            end)
        )

    end


    -- Les fenetres trouvees seulement ici arrivent apres celles du
    -- filtre, donc hors ordre MRU : c'est le prix de l'exhaustivite.

    if self.completeWithAllWindows then

        local firstPassCount =
            #collected


        addWindows(
            safeCall(function()

                return window.allWindows()

            end)
        )


        self:sortTail(collected, firstPassCount)

    end


    self:endDescriptorPass()


    return collected

end



-- Range les elements ajoutes apres firstPassCount par ordre de
-- profondeur, en preservant l'ordre MRU des precedents.

function obj:sortTail(collected, firstPassCount)

    if #collected <= firstPassCount + 1 then

        return collected

    end


    local ranks =
        self:orderedWindowRanks()


    if not ranks then

        return collected

    end


    local tail =
        {}


    for index = firstPassCount + 1, #collected do

        table.insert(
            tail,
            {
                descriptor = collected[index],
                rank = ranks[collected[index].id] or math.huge,
                order = index,
            }
        )

    end


    table.sort(
        tail,
        function(left, right)

            if left.rank ~= right.rank then

                return left.rank < right.rank

            end


            return left.order < right.order

        end
    )


    for offset, item in ipairs(tail) do

        collected[firstPassCount + offset] =
            item.descriptor

    end


    return collected

end


function obj:windowID(win)

    return safeCall(function()

        return win:id()

    end)

end


function obj:trimSnapshotCache()

    local now =
        timer.secondsSinceEpoch()


    local kept =
        {}


    local count =
        0


    for id, entry in pairs(self.snapshotCache) do

        if entry.time
            and now - entry.time <= self.snapshotCacheMaxAgeSeconds then

            kept[#kept + 1] =
                {
                    id = id,
                    time = entry.time,
                }


            count =
                count + 1

        else

            self.snapshotCache[id] =
                nil


            self:discardCaptureFile(id)

        end

    end


    if count <= self.snapshotCacheMaxEntries then

        return self

    end


    table.sort(
        kept,
        function(left, right)

            return left.time < right.time

        end
    )


    for index = 1, count - self.snapshotCacheMaxEntries do

        self.snapshotCache[kept[index].id] =
            nil


        self:discardCaptureFile(kept[index].id)

    end


    return self

end


function obj:clearSnapshotCache()

    for id in pairs(self.snapshotCache) do

        self:discardCaptureFile(id)

    end


    self.snapshotCache =
        {}


    self.screenCaptureFailureCache =
        {}


    self.screenCaptureFailureCounts =
        {}


    self.screenCaptureReportedFailures =
        {}


    return self

end


-- Le cache ne connaissait aucune eviction : une fenetre fermee laissait
-- sa capture en memoire jusqu'au rechargement de Hammerspoon, et le PNG
-- correspondant restait dans /tmp jusqu'au lendemain.

-- Le fichier etait relu integralement a chaque Alt+Tab. On ne le relit
-- que si sa date de modification a change.

function obj:refreshIgnoredBundles(force)

    local path =
        self.ignoredBundlesFile or self:defaultIgnoredBundlesFile()


    local signature =
        "absent"


    if path then

        local modified =
            fs.attributes(path, "modification")


        signature =
            tostring(path) .. ":" .. tostring(modified or "absent")

    end


    if not force
        and self.loadedExcludedBundleIDs
        and self.ignoredBundlesSignature == signature then

        return self.loadedExcludedBundleIDs

    end


    self.loadedExcludedBundleIDs =
        self:readIgnoredBundlesFile()


    self.ignoredBundlesSignature =
        signature


    return self.loadedExcludedBundleIDs

end


-- Renvoie l'image en cache et si elle est encore fraiche.

function obj:cachedSnapshot(descriptor, now)

    local cached =
        descriptor and self.snapshotCache[descriptor.id]


    if not cached then

        return nil, false

    end


    local fresh =
        cached.time + self.snapshotCacheSeconds
            > (now or timer.secondsSinceEpoch())


    return cached.image, fresh

end


function obj:captureVisibleSnapshot(descriptor, now)

    descriptor.snapshotAttempted =
        true


    local snapshot =
        safeCall(function()

            return window.snapshotForID(descriptor.id)

        end)


    if snapshot then

        self.snapshotCache[descriptor.id] =
            {
                image = snapshot,
                time = now,
            }


        return snapshot

    end


    -- Le WindowServer n'a rien a offrir : le service prend le relais.

    self:queueScreenCapture(descriptor)


    return nil

end


-- Ordre de rechauffage : la tuile selectionnee d'abord, puis ses
-- voisines. C'est celle qu'on regarde ; si le budget ne suffit pas
-- pour toutes, ce n'est pas elle qui doit attendre.

function obj:warmOrder(startIndex, endIndex, selected)

    if not selected
        or selected < startIndex
        or selected > endIndex then

        selected =
            startIndex

    end


    local order =
        { selected }


    local offset =
        1


    while true do

        local added =
            false


        if selected + offset <= endIndex then

            order[#order + 1] =
                selected + offset


            added =
                true

        end


        if selected - offset >= startIndex then

            order[#order + 1] =
                selected - offset


            added =
                true

        end


        if not added then

            break

        end


        offset =
            offset + 1

    end


    return order

end


function obj:warmSnapshots(startIndex, endIndex)

    if not self.entries then

        return self

    end


    local now =
        timer.secondsSinceEpoch()


    local deadline =
        now + self.snapshotBudgetSeconds


    local remaining =
        false


    for _, index in ipairs(self:warmOrder(startIndex, endIndex, self.selectedIndex)) do

        local descriptor =
            self.entries[index]


        local _,
              fresh =
            self:cachedSnapshot(descriptor, now)


        if descriptor and not fresh then

            if descriptor.minimized or descriptor.hidden then

                -- Deja asynchrone : ne coute rien au budget.

                self:queueScreenCapture(descriptor)

            elseif not self.instantVisibleSnapshots then

                self:queueScreenCapture(descriptor)

            elseif descriptor.snapshotAttempted then

                -- Une seule tentative synchrone par fenetre et par
                -- session : sans cela une fenetre incapturable serait
                -- reessayee a chaque rendu.

            elseif timer.secondsSinceEpoch() < deadline then

                self:captureVisibleSnapshot(descriptor, now)

            else

                remaining =
                    true

            end

        end

    end


    if remaining then

        self:scheduleRedraw()

    end


    return self

end


-- N'interroge plus le WindowServer : warmSnapshots s'en charge, sous
-- budget, avant le rendu. Une tuile sans capture affiche l'icone de
-- son application, et la vraie vignette arrive au rendu suivant.

function obj:windowSnapshot(descriptor)

    if not descriptor then

        return nil

    end


    return (self:cachedSnapshot(descriptor))

end



function obj:screenCaptureOutputPath(jobOrID, token)

    local id =
        type(jobOrID) == "table" and jobOrID.id or jobOrID


    local captureToken =
        type(jobOrID) == "table" and jobOrID.token or token

    return string.format(
        "%s/%s-%s.png",
        self:screenCaptureCaptureDirectory(),
        tostring(id),
        tostring(captureToken or "capture")
    )

end


function obj:readSmallFile(path)

    local file =
        io.open(path, "r")


    if not file then

        return nil

    end


    local content =
        file:read("*a")


    file:close()


    return content

end


function obj:removeFile(path)

    if path and fs.attributes(path) then

        safeCall(function()

            os.remove(path)

        end)

    end

end


function obj:chmod(path, mode)

    if not path or not mode then

        return false

    end


    local ok =
        os.execute(
            string.format(
                "/bin/chmod %s %s",
                shellQuote(mode),
                shellQuote(path)
            )
        )


    return ok == true or ok == 0

end


-- L'identifiant de l'utilisateur courant, lu sur son propre dossier
-- personnel : Hammerspoon n'expose pas getuid().

function obj:currentUserID()

    if self.cachedUserID ~= nil then

        return self.cachedUserID

    end


    local home =
        os.getenv("HOME")


    local attributes =
        home and fs.attributes(home)


    self.cachedUserID =
        (attributes and attributes.uid) or false


    return self.cachedUserID

end


-- Un repertoire n'est acceptable que s'il nous appartient, qu'il n'est
-- ouvert ni au groupe ni aux autres, et qu'il n'est pas un lien
-- symbolique pointant ailleurs.
--
-- Renvoie ok, motif.

function obj:isPrivateDirectory(path)

    local link =
        fs.symlinkAttributes and fs.symlinkAttributes(path)


    if link and link.mode == "link" then

        return false, "lien symbolique"

    end


    local attributes =
        fs.attributes(path)


    if not attributes then

        return false, "absent"

    end


    if attributes.mode ~= "directory" then

        return false, "n'est pas un repertoire"

    end


    local uid =
        self:currentUserID()


    if uid and attributes.uid and attributes.uid ~= uid then

        return false,
            "appartient a l'uid " .. tostring(attributes.uid)

    end


    local permissions =
        tostring(attributes.permissions or "")


    if #permissions == 9
        and permissions:sub(4) ~= "------" then

        return false,
            "ouvert au groupe ou aux autres (" .. permissions .. ")"

    end


    return true

end


function obj:ensureDirectory(path, mode)

    if not fs.attributes(path) then

        safeCall(function()

            fs.mkdir(path)

        end)

    end


    if mode then

        self:chmod(path, mode)

    end


    -- Un repertoire preexistant n'est pas forcement le notre. Sans ce
    -- controle, il suffisait de creer le repertoire de base avant nous
    -- pour lire toutes les captures qui y passeraient ensuite.

    local ok,
          reason =
        self:isPrivateDirectory(path)


    if not ok then

        self:log(
            "Repertoire de capture refuse : "
            .. tostring(path)
            .. " (" .. tostring(reason) .. ")"
        )


        return false

    end


    return true

end


function obj:writePrivateFile(path, content)

    local tmpPath =
        path .. ".tmp." .. readRandomHex(8)


    local file =
        io.open(tmpPath, "w")


    if not file then

        return false

    end


    file:write(tostring(content or ""))
    file:close()
    self:chmod(tmpPath, "600")


    local ok =
        os.rename(tmpPath, path)


    if not ok then

        self:removeFile(tmpPath)

        return false

    end


    self:chmod(path, "600")


    return true

end


function obj:createScreenCaptureSession()

    if self.screenCaptureSessionDirectory
        and self.screenCaptureSessionSecret then

        return true

    end


    self.screenCaptureSessionID =
        self.screenCaptureSessionPrefix .. readRandomHex(16)


    self.screenCaptureSessionSecret =
        readRandomHex(32)


    self.screenCaptureSessionDirectory =
        self.screenCaptureSessionBaseDirectory
            .. "/"
            .. self.screenCaptureSessionID


    if not self:ensureDirectory(self.screenCaptureSessionBaseDirectory, "700")
        or not self:ensureDirectory(self.screenCaptureSessionDirectory, "700")
        or not self:ensureDirectory(self:screenCaptureRequestDirectory(), "700")
        or not self:ensureDirectory(self:screenCaptureCaptureDirectory(), "700") then

        -- On ne reessaie pas en boucle : tant que l'emplacement n'est
        -- pas sur, aucune capture ne doit partir. Le switcher continue
        -- de fonctionner avec les icones d'application.

        self.screenCaptureDisabledReason =
            "emplacement de capture non sur"


        self.screenCaptureSessionDirectory =
            nil


        self.screenCaptureSessionSecret =
            nil


        return false

    end


    return self:writePrivateFile(
        self:screenCaptureSecretPath(),
        self.screenCaptureSessionSecret
    )

end


function obj:removeSessionDirectory(path)

    if not path or not fs.attributes(path) then

        return self

    end


    -- hs.task plutot que hs.execute : pas de shell, donc pas de
    -- .zshrc a interpreter, et rien qui bloque le thread principal.

    local removal =
        task.new(
            "/bin/rm",
            nil,
            {
                "-rf",
                path,
            }
        )


    if removal then

        removal:start()

    end


    return self

end


function obj:removeScreenCaptureSession()

    self:removeSessionDirectory(self.screenCaptureSessionDirectory)


    self.screenCaptureSessionID =
        nil


    self.screenCaptureSessionSecret =
        nil


    self.screenCaptureSessionDirectory =
        nil


    return self

end


-- Emplacements utilises par les versions precedentes. On les efface au
-- demarrage pour ne pas laisser d'anciennes captures dans /tmp, mais
-- seulement apres avoir verifie qu'ils nous appartiennent : on ne
-- supprime pas recursivement un repertoire dont on n'est pas sur.

obj.legacySessionBaseDirectories = {
    "/tmp/WindowSwitcher",
}


function obj:cleanupLegacySessionDirectories()

    for _, path in ipairs(self.legacySessionBaseDirectories or {}) do

        if path ~= self.screenCaptureSessionBaseDirectory
            and fs.attributes(path) then

            local ok,
                  reason =
                self:isPrivateDirectory(path)


            if ok then

                self:removeSessionDirectory(path)

            else

                self:log(
                    "Ancien repertoire de capture laisse en place : "
                    .. tostring(path)
                    .. " (" .. tostring(reason) .. ")"
                )

            end

        end

    end


    return self

end


function obj:cleanupScreenCaptureSessions()

    local baseDir =
        self.screenCaptureSessionBaseDirectory


    if not fs.attributes(baseDir) then

        return self

    end


    local iterator,
          directory =
        fs.dir(baseDir)


    if not iterator or not directory then

        return self

    end


    -- Toute session qui n'est pas la notre appartient a une instance
    -- de Hammerspoon qui n'existe plus, et les helpers survivants ont
    -- deja ete arretes juste avant. L'ancien delai de 24 h laissait
    -- s'empiler un repertoire par rechargement.

    for entry in iterator, directory do

        if entry
            and entry:sub(1, #self.screenCaptureSessionPrefix) == self.screenCaptureSessionPrefix
            and entry ~= self.screenCaptureSessionID then

            self:removeSessionDirectory(
                baseDir .. "/" .. entry
            )

        end

    end


    return self

end


function obj:writeScreenCaptureRequest(job)

    if not self:createScreenCaptureSession() then

        return false

    end


    if job.outputPath then

        self:removeFile(job.outputPath)

    end

    self:removeFile(self:screenCaptureStatusPath(job))


    local payload =
        table.concat(
            {
                "4",
                tostring(job.token),
                tostring(job.kind or "capture"),
                tostring(job.windowID or 0),
                tostring(job.outputPath or ""),
                tostring(job.pixelHeight or 0),
                tostring(job.appName or ""):gsub("[\r\n]", " "),
                tostring(job.title or ""):gsub("[\r\n]", " "),
                tostring(self.screenCaptureSessionSecret),
            },
            "\n"
        ) .. "\n"


    return self:writePrivateFile(
        self:screenCaptureRequestPath(job),
        payload
    )

end


function obj:readScreenCaptureStatus(job)

    local status =
        self:readSmallFile(self:screenCaptureStatusPath(job))


    if not status then

        return nil

    end


    local lines =
        splitLines(status, 5)


    if lines[1] ~= "4"
        or lines[2] ~= tostring(job.token)
        or not lines[3]
        or not lines[5] then

        return "error", "statut capture invalide"

    end


    if lines[5] ~= tostring(self.screenCaptureSessionSecret) then

        return "error", "jeton statut capture invalide"

    end


    return lines[3], lines[4] or ""

end


function obj:screenCaptureHelperIsRunning()

    if self.helperTask then

        local running =
            safeCall(function()

                return self.helperTask:isRunning()

            end)


        if running == true then

            return true

        end


        self.helperTask =
            nil

    end


    local applications =
        safeCall(function()

            return hs.application.applicationsForBundleID(
                self.screenCaptureHelperBundleID
            )

        end)


    return type(applications) == "table"
        and #applications > 0

end


function obj:stopScreenCaptureHelperApp()

    local applications =
        safeCall(function()

            return hs.application.applicationsForBundleID(
                self.screenCaptureHelperBundleID
            )

        end)


    for _, application in ipairs(applications or {}) do

        safeCall(function()

            application:kill()

        end)

    end


    if self.helperTask then

        safeCall(function()

            self.helperTask:terminate()

        end)


        self.helperTask =
            nil

    end


    self:cancelHelperIdleTimer()


    self.screenCaptureHelperAppStarted =
        false


    return self

end


-- Le helper se termine de lui-meme apres 30 s sans requete
-- (idleQuitDelay, cote Swift). L'ancienne version laissait
-- screenCaptureHelperAppStarted a true indefiniment : passe ce delai,
-- chaque requete etait ecrite pour un processus mort, et les vignettes
-- des fenetres reduites ne revenaient plus jamais jusqu'au rechargement.

function obj:startScreenCaptureHelperApp()

    if self.screenCaptureHelperAppStarted
        and self:screenCaptureHelperIsRunning() then

        return true

    end


    self.screenCaptureHelperAppStarted =
        false


    local appPath =
        self.screenCaptureHelperAppPath or self:defaultScreenCaptureHelperAppPath()


    if not self:createScreenCaptureSession() then

        return false

    end


    if not appPath or not fs.attributes(appPath) then

        return false

    end


    -- Lance en enfant de Hammerspoon. macOS attribue les acces TCC au
    -- processus responsable : le service herite alors de l'autorisation
    -- de Hammerspoon au lieu d'en porter une propre, et le binaire
    -- lance par un autre processus ne capture rien.

    if tostring(self.helperLaunchMode) == "task" then

        local helper =
            self.screenCaptureHelperPath or self:defaultScreenCaptureHelperPath()


        if not helper or not fs.attributes(helper) then

            return false

        end


        local launched =
            task.new(
                helper,
                nil,
                {
                    "--service",
                    self.screenCaptureSessionDirectory,
                }
            )


        if not launched or not launched:start() then

            return false

        end


        self.helperTask =
            launched


        self.screenCaptureHelperAppStarted =
            true


        return true

    end


    local launchTask =
        task.new(
            "/usr/bin/open",
            nil,
            {
                "-gj",
                "-n",
                appPath,
                "--args",
                "--service",
                self.screenCaptureSessionDirectory,
            }
        )


    if not launchTask or not launchTask:start() then

        return false

    end


    self.screenCaptureHelperAppStarted =
        true


    return true

end


function obj:startScreenCapturePollTimer()

    if self.screenCapturePollTimer then

        return self

    end


    self.screenCapturePollTimer =
        timer.doEvery(
            self.screenCapturePollIntervalSeconds,
            function()

                self:pollScreenCaptureRequests()

            end
        )


    return self

end


function obj:cancelHelperIdleTimer()

    if self.helperIdleTimer then

        self.helperIdleTimer:stop()


        self.helperIdleTimer =
            nil

    end


    return self

end


function obj:scheduleHelperShutdown()

    self:cancelHelperIdleTimer()


    if not self.helperIdleGraceSeconds
        or self.helperIdleGraceSeconds <= 0 then

        return self

    end


    if not self.screenCaptureHelperAppStarted then

        return self

    end


    self.helperIdleTimer =
        timer.doAfter(
            self.helperIdleGraceSeconds,
            function()

                self.helperIdleTimer =
                    nil


                if #self.screenCaptureQueue > 0
                    or self:countRunningScreenCaptures() > 0 then

                    return

                end


                self:stopScreenCaptureHelperApp()

            end
        )


    return self

end


function obj:stopScreenCapturePollTimerIfIdle()

    if self.screenCapturePollTimer
        and self:countRunningScreenCaptures() == 0 then

        self.screenCapturePollTimer:stop()

        self.screenCapturePollTimer =
            nil

    end


    if #self.screenCaptureQueue == 0
        and self:countRunningScreenCaptures() == 0 then

        self:scheduleHelperShutdown()

    end


    return self

end


function obj:countRunningScreenCaptures()

    local count =
        0


    for _, _task in pairs(self.runningScreenCaptures or {}) do

        count =
            count + 1

    end


    return count

end


function obj:discardCaptureFile(id)

    local path =
        self.captureFiles[id]


    if path then

        self.captureFiles[id] =
            nil


        self:removeFile(path)

    end


    return self

end


function obj:finishScreenCaptureJob(job, capturedImage, errorMessage)

    self.runningScreenCaptures[job.id] =
        nil


    if capturedImage then

        -- Chaque capture recoit un jeton neuf, donc un fichier neuf :
        -- sans cette ligne, un PNG s'accumulait dans /tmp a chaque
        -- rafraichissement de vignette, pour toute la session.

        self:discardCaptureFile(job.id)


        self.captureFiles[job.id] =
            job.outputPath


        self.snapshotCache[job.id] =
            {
                image = capturedImage,
                time = timer.secondsSinceEpoch(),
            }


        self.screenCaptureFailureCache[job.id] =
            nil


        self.screenCaptureFailureCounts[job.id] =
            nil


        self.screenCaptureReportedFailures[job.id] =
            nil


        self:trimSnapshotCache()


        if self.entries then

            self:scheduleRedraw()

        end


        return self

    end


    self:removeFile(job.outputPath)


    self.screenCaptureFailureCache[job.id] =
        timer.secondsSinceEpoch()


    self.screenCaptureFailureCounts[job.id] =
        (self.screenCaptureFailureCounts[job.id] or 0) + 1


    local messageText =
        tostring(errorMessage or "")


    if self.disableScreenCaptureHelperAfterCGSAssertion
        and messageText:find("CGS_REQUIRE_INIT", 1, true) then

        self.screenCaptureDisabledReason =
            "CGS_REQUIRE_INIT"


        self.screenCaptureQueue =
            {}


        self.queuedScreenCaptures =
            {}

    end

    if messageText:find("TCC", 1, true)
        or messageText:lower():find("refus", 1, true)
        or messageText:lower():find("denied", 1, true) then

        self.screenCaptureDisabledReason =
            "autorisation capture ecran manquante pour WindowSwitcherCapture"


        self.screenCaptureQueue =
            {}


        self.queuedScreenCaptures =
            {}

    end


    local message =
        string.format(
            "Capture impossible pour %s - %s [%s%s] : %s%s",
            tostring(job.appName),
            tostring(job.title or ""),
            job.isMinimized and "reduite" or "visible",
            job.isHidden and ", cachee" or "",
            messageText,
            self.screenCaptureDisabledReason and " (helper desactive jusqu'au reload)" or ""
        )


    -- Une meme fenetre ne doit pas remplir la console a chaque switch :
    -- on journalise le premier echec, puis on se tait jusqu'a ce qu'elle
    -- soit mise de cote.

    local echecs =
        self.screenCaptureFailureCounts[job.id] or 1


    local premierEchec =
        not self.screenCaptureReportedFailures[job.id]


    self.screenCaptureReportedFailures[job.id] =
        true


    if echecs >= self.screenCaptureGiveUpAfter then

        self:log(
            string.format(
                "Capture abandonnee pour %s - %s apres %d echecs, "
                .. "l'icone de l'application sera affichee : %s",
                tostring(job.appName),
                tostring(job.title or ""),
                echecs,
                messageText
            )
        )

    elseif premierEchec
        and (self.logScreenCaptureFailures or job.isMinimized or job.isHidden) then

        self:log(message)

    else

        self:debug(message)

    end


    return self

end


function obj:pollScreenCaptureRequests()

    local now =
        timer.secondsSinceEpoch()


    for id, running in pairs(self.runningScreenCaptures or {}) do

        local job =
            running.job or running


        local statusPath =
            self:screenCaptureStatusPath(job)


        if fs.attributes(statusPath) then

            local state,
                  statusMessage =
                self:readScreenCaptureStatus(job)


            self:removeFile(statusPath)


            if job.kind == "audio" then

                self:finishAudioJob(job, state, statusMessage)

            elseif state == "ok" and fs.attributes(job.outputPath) then

                local capturedImage =
                    image.imageFromPath(job.outputPath)


                self:finishScreenCaptureJob(
                    job,
                    capturedImage,
                    capturedImage and nil or "image illisible"
                )

            else

                self:finishScreenCaptureJob(job, nil, statusMessage or "capture failed")

            end

        else

            if running.startedAt
                and running.startedAt + self.screenCaptureRequestTimeoutSeconds < now then

                self:removeFile(self:screenCaptureRequestPath(job))
                self:removeFile(statusPath)


                if job.kind == "audio" then

                    self.screenCaptureHelperAppStarted =
                        false


                    self:finishAudioJob(job, "error", "delai depasse")


                    self:stopScreenCapturePollTimerIfIdle()
                    self:drainScreenCaptureQueue()


                    return self

                end


                -- Un depassement signifie presque toujours que le
                -- service s'est arrete. On le note pour que la
                -- prochaine capture le relance au lieu d'ecrire dans
                -- le vide indefiniment.

                self.screenCaptureHelperAppStarted =
                    false


                self:finishScreenCaptureJob(job, nil, "capture timed out")

            end

        end

    end


    self:stopScreenCapturePollTimerIfIdle()
    self:drainScreenCaptureQueue()


    return self

end


-- Inventaire du son : quelles applications jouent, lesquelles captent.
-- Une seule demande par session, elle ne touche ni le disque ni
-- ScreenCaptureKit cote service.

function obj:queueAudioSnapshot()

    if not self.showAudioBadges
        or not self.screenCaptureHelperEnabled
        or self.screenCaptureDisabledReason then

        return self

    end


    if self.queuedScreenCaptures["audio"]
        or self.runningScreenCaptures["audio"] then

        return self

    end


    local helper =
        self.screenCaptureHelperPath or self:defaultScreenCaptureHelperPath()


    if not helper or not fs.attributes(helper) then

        return self

    end


    if not self:createScreenCaptureSession() then

        return self

    end


    self.queuedScreenCaptures["audio"] =
        true


    table.insert(
        self.screenCaptureQueue,
        {
            id = "audio",
            kind = "audio",
            token = readRandomHex(16),
        }
    )


    self:drainScreenCaptureQueue()


    return self

end


-- Charge utile : "out=123,456;in=789".

function obj:applyAudioSnapshot(payload)

    local playing =
        {}


    local recording =
        {}


    local text =
        tostring(payload or "")


    for pid in tostring(text:match("out=([^;]*)") or ""):gmatch("%d+") do

        playing[tonumber(pid)] =
            true

    end


    for pid in tostring(text:match("in=([^;]*)") or ""):gmatch("%d+") do

        recording[tonumber(pid)] =
            true

    end


    self.audioPIDs =
        playing


    self.microphonePIDs =
        recording


    if self.entries then

        self:scheduleRedraw()

    end


    return self

end


function obj:finishAudioJob(job, state, message)

    self.runningScreenCaptures[job.id] =
        nil


    if state == "ok" then

        self:applyAudioSnapshot(message)

    else

        self:debug("Inventaire audio indisponible : " .. tostring(message))

    end


    return self

end


function obj:queueScreenCapture(descriptor)

    if not self.screenCaptureHelperEnabled then

        return self

    end

    if self.screenCaptureDisabledReason then

        return self

    end


    if not descriptor then

        return self

    end


    local id =
        descriptor.id


    if self.queuedScreenCaptures[id]
        or self.runningScreenCaptures[id] then

        return self

    end


    local now =
        timer.secondsSinceEpoch()


    local failedAt =
        self.screenCaptureFailureCache[id]


    local echecs =
        self.screenCaptureFailureCounts[id] or 0


    local attente =
        self.screenCaptureFailureBackoffSeconds


    if echecs >= self.screenCaptureGiveUpAfter then

        attente =
            self.screenCaptureGiveUpBackoffSeconds

    end


    if failedAt and failedAt + attente > now then

        return self

    end


    local helper =
        self.screenCaptureHelperPath or self:defaultScreenCaptureHelperPath()


    if not helper or not fs.attributes(helper) then

        self:debug("Helper ScreenCaptureKit absent")

        return self

    end


    if not self:createScreenCaptureSession() then

        return self

    end


    self.queuedScreenCaptures[id] =
        true


    -- Tout vient du descripteur : l'ancienne version relisait ici le
    -- nom de l'application, le titre, l'etat reduit et l'etat masque,
    -- soit trois resolutions NSRunningApplication de plus par capture.

    local job =
        {
            id = id,
            windowID = id,
            kind = "capture",
            token = readRandomHex(16),
            pixelHeight = tostring(math.floor(self.screenCapturePixelHeight)),
            appName = descriptor.appName or "Application",
            title = descriptor.title or "",
            isMinimized = descriptor.minimized,
            isHidden = descriptor.hidden,
        }


    job.outputPath =
        self:screenCaptureOutputPath(job)


    table.insert(
        self.screenCaptureQueue,
        job
    )


    self:drainScreenCaptureQueue()


    return self

end


function obj:drainScreenCaptureQueue()

    while #self.screenCaptureQueue > 0
        and self:countRunningScreenCaptures() < self.maxConcurrentScreenCaptures do

        local job =
            table.remove(self.screenCaptureQueue, 1)


        self.queuedScreenCaptures[job.id] =
            nil


        self:cancelHelperIdleTimer()


        if self:startScreenCaptureHelperApp()
            and self:writeScreenCaptureRequest(job) then

            self.runningScreenCaptures[job.id] =
                {
                    job = job,
                    startedAt = timer.secondsSinceEpoch(),
                }


            self:startScreenCapturePollTimer()

        else

            self:finishScreenCaptureJob(job, nil, "service capture indisponible")

        end

    end


    return self

end



function obj:previewImage(descriptor)

    local snapshot =
        self:windowSnapshot(descriptor)


    if snapshot then

        return snapshot, false

    end


    return self:appIcon(descriptor), true

end


function obj:appIcon(descriptor)

    local bundleID =
        descriptor and descriptor.bundleID


    if not bundleID then

        return image.imageFromName("NSApplicationIcon")

    end


    if not self.iconCache[bundleID] then

        self.iconCache[bundleID] =
            image.imageFromAppBundle(bundleID)
            or image.imageFromName("NSApplicationIcon")

    end


    return self.iconCache[bundleID]

end


function obj:displayTitle(descriptor)

    return (descriptor and descriptor.displayTitle) or "Application"

end


-- styledtext.new construit une NSAttributedString a chaque appel. Sans
-- ce cache, une grille de douze tuiles en refaisait douze a chaque
-- rendu, et un rendu a lieu a chaque appui sur Tab comme a chaque
-- capture qui arrive.

function obj:styledTitle(descriptor, isSelected)

    local title =
        self:displayTitle(descriptor)


    local cacheKey =
        tostring(descriptor and descriptor.id)
        .. (isSelected and ":1" or ":0")


    local cached =
        self.titleCache[cacheKey]


    if cached then

        return cached

    end


    local styled =
        safeCall(function()

            return styledtext.new(
                title,
                {
                    font = {
                        name = ".AppleSystemUIFont",
                        size = isSelected and self.textSize + 1 or self.textSize,
                    },
                    color = self:themeColor("labelTextColor"),
                    paragraphStyle = {
                        lineBreak = "truncateTail",
                    },
                }
            )

        end) or title


    self.titleCache[cacheKey] =
        styled


    return styled

end



function obj:modifiersPressed()

    local modifiers =
        eventtap.checkKeyboardModifiers(true)


    return modifiers and modifiers._raw and modifiers._raw > 0 and modifiers._raw ~= 65536

end



------------------------------------------------------------
-- LAYOUT
------------------------------------------------------------

function obj:visibleRange(total, pageSize)

    if total <= pageSize then

        return 1, total

    end


    local page =
        math.floor((self.selectedIndex - 1) / pageSize)


    local startIndex =
        page * pageSize + 1


    local endIndex =
        math.min(total, startIndex + pageSize - 1)


    return startIndex, endIndex

end


function obj:estimatedLabelWidth(descriptor)

    if descriptor and descriptor.labelWidth then

        return descriptor.labelWidth

    end


    local title =
        self:displayTitle(descriptor)


    -- #title compte les octets : "Preferences Systeme" accentue etait
    -- surevalue de deux caracteres a chaque accent.

    local length =
        (utf8 and utf8.len and utf8.len(title)) or #title


    local estimated =
        self.iconSize + 10 + (length * self.textSize * 0.52)


    if estimated < self.labelMinWidth then

        estimated =
            self.labelMinWidth

    elseif estimated > self.labelMaxWidth then

        estimated =
            self.labelMaxWidth

    end


    estimated =
        math.floor(estimated)


    if descriptor then

        descriptor.labelWidth =
            estimated

    end


    return estimated

end


function obj:previewSize(descriptor, maxWidth, maxHeight)

    local frame =
        descriptor and descriptor.frame


    local aspect =
        16 / 10


    if frame and frame.w and frame.h and frame.w > 1 and frame.h > 1 then

        aspect =
            frame.w / frame.h

    end


    local width =
        maxWidth


    local height =
        width / aspect


    if height > maxHeight then

        height =
            maxHeight

        width =
            height * aspect

    end


    if width < self.previewMinWidth then

        width =
            self.previewMinWidth

    end


    if height < self.previewMinHeight then

        height =
            self.previewMinHeight

    end


    return math.floor(width), math.floor(height)

end


function obj:layout(startIndex, endIndex)

    local screenFrame =
        screen.mainScreen():frame()


    local totalVisible =
        endIndex - startIndex + 1


    local availablePanelWidth =
        math.max(
            260,
            screenFrame.w - (self.screenMargin * 2)
        )


    local availablePanelHeight =
        math.max(
            180,
            screenFrame.h - (self.screenMargin * 2)
        )


    local maxPanelWidth =
        math.min(
            math.floor(screenFrame.w * self.maxPanelWidthRatio),
            math.floor(availablePanelWidth)
        )


    local maxPanelHeight =
        math.min(
            math.floor(screenFrame.h * self.maxPanelHeightRatio),
            math.floor(availablePanelHeight)
        )


    local maxContentWidth =
        maxPanelWidth - (self.panelPadding * 2)


    local maxContentHeight =
        maxPanelHeight - (self.panelPadding * 2)


    local columns =
        math.min(
            math.max(1, self.maxColumns),
            math.max(1, totalVisible)
        )


    while columns > 1
        and (columns * math.max(self.previewMinWidth, self.labelMinWidth))
            + ((columns - 1) * self.columnGap) > maxContentWidth do

        columns =
            columns - 1

    end


    local rows =
        math.ceil(totalVisible / columns)


    local maxPreviewWidth =
        math.min(
            self.previewMaxWidth,
            math.floor((maxContentWidth - (columns - 1) * self.columnGap) / columns)
        )


    if maxPreviewWidth < self.previewMinWidth then

        maxPreviewWidth =
            self.previewMinWidth

    end


    local maxPreviewHeight =
        math.min(
            self.previewMaxHeight,
            math.floor((maxContentHeight - (rows - 1) * self.rowGap) / rows) - self.labelHeight - self.labelToPreviewGap
        )


    if maxPreviewHeight < self.previewMinHeight then

        maxPreviewHeight =
            self.previewMinHeight

    end


    local items =
        {}


    local rowWidths =
        {}


    local rowHeights =
        {}


    local slot =
        1


    for index = startIndex, endIndex do

        local row =
            math.floor((slot - 1) / columns) + 1


        local previewWidth,
              previewHeight =
            self:previewSize(
                self.entries[index],
                maxPreviewWidth,
                maxPreviewHeight
            )


        local labelWidth =
            math.min(
                self:estimatedLabelWidth(self.entries[index]),
                maxPreviewWidth
            )


        local itemWidth =
            math.max(previewWidth, labelWidth)


        local itemHeight =
            self.labelHeight + self.labelToPreviewGap + previewHeight


        table.insert(
            items,
            {
                index = index,
                entry = self.entries[index],
                row = row,
                width = itemWidth,
                height = itemHeight,
                previewWidth = previewWidth,
                previewHeight = previewHeight,
                labelWidth = labelWidth,
            }
        )


        rowWidths[row] =
            (rowWidths[row] or 0) + itemWidth


        if slot % columns ~= 1 then

            rowWidths[row] =
                rowWidths[row] + self.columnGap

        end


        rowHeights[row] =
            math.max(rowHeights[row] or 0, itemHeight)


        slot =
            slot + 1

    end


    local contentWidth =
        0


    local contentHeight =
        0


    for row = 1, rows do

        contentWidth =
            math.max(contentWidth, rowWidths[row] or 0)


        contentHeight =
            contentHeight + (rowHeights[row] or 0)


        if row > 1 then

            contentHeight =
                contentHeight + self.rowGap

        end

    end


    local panelWidth =
        math.min(
            maxPanelWidth,
            math.max(self.minPanelWidth, contentWidth + self.panelPadding * 2)
        )


    local panelHeight =
        math.min(
            maxPanelHeight,
            math.max(self.minPanelHeight, contentHeight + self.panelPadding * 2)
        )


    local centeredX =
        math.floor(screenFrame.x + (screenFrame.w - panelWidth) / 2)


    local centeredY =
        math.floor(screenFrame.y + (screenFrame.h - panelHeight) / 2)


    local panelX =
        math.max(
            screenFrame.x + self.screenMargin,
            math.min(
                centeredX,
                screenFrame.x + screenFrame.w - self.screenMargin - panelWidth
            )
        )


    local panelY =
        math.max(
            screenFrame.y + self.screenMargin,
            math.min(
                centeredY,
                screenFrame.y + screenFrame.h - self.screenMargin - panelHeight
            )
        )


    local y =
        math.floor((panelHeight - contentHeight) / 2)


    for row = 1, rows do

        local x =
            math.floor((panelWidth - (rowWidths[row] or 0)) / 2)


        for _, item in ipairs(items) do

            if item.row == row then

                item.x =
                    x


                item.y =
                    y


                x =
                    x + item.width + self.columnGap

            end

        end


        y =
            y + (rowHeights[row] or 0) + self.rowGap

    end


    return {
        canvas = {
            x = panelX - self.canvasPadding,
            y = panelY - self.canvasPadding,
            w = panelWidth + (self.canvasPadding * 2),
            h = panelHeight + (self.canvasPadding * 2),
        },
        panel = {
            x = self.canvasPadding,
            y = self.canvasPadding,
            w = panelWidth,
            h = panelHeight,
        },
        items = items,
    }

end



------------------------------------------------------------
-- RENDU CANVAS
------------------------------------------------------------

function obj:panelElement(layout)

    return {
        type = "rectangle",
        action = "strokeAndFill",
        frame = {
            x = layout.panel.x,
            y = layout.panel.y,
            w = layout.panel.w,
            h = layout.panel.h,
        },
        roundedRectRadii = rounded(self.panelCornerRadius),
        fillColor = self:themeColor("backgroundColor"),
        strokeColor = self:themeColor("panelStrokeColor"),
        strokeWidth = 1,
        withShadow = true,
        shadow = {
            blurRadius = 18,
            color = self:themeColor("shadowColor"),
            offset = {
                h = -10,
                w = 0,
            },
        },
    }

end


-- Les etats sont deja dans le descripteur : la pastille ne coute qu'un
-- element de dessin, aucune interrogation supplementaire.

function obj:stateBadges(descriptor)

    local badges =
        {}


    if not self.showStateBadges or not descriptor then

        return badges

    end


    if descriptor.minimized then

        badges[#badges + 1] =
            self.badges.minimized

    end


    if descriptor.hidden then

        badges[#badges + 1] =
            self.badges.hidden

    end


    if self.showSpaceBadges
        and self:isOnOtherSpace(descriptor) == true then

        badges[#badges + 1] =
            self.badges.otherSpace

    end


    if self.showAudioBadges and descriptor.pid then

        if self.audioPIDs[descriptor.pid] then

            badges[#badges + 1] =
                self.badges.audio

        end


        if self.microphonePIDs[descriptor.pid] then

            badges[#badges + 1] =
                self.badges.microphone

        end

    end


    return badges

end


function obj:badgeElements(elements, descriptor, thumbFrame)

    local badges =
        self:stateBadges(descriptor)


    -- Le coin superieur gauche revient au bouton de fermeture, comme
    -- sur une fenetre macOS : les pastilles passent a droite et se
    -- posent de droite a gauche.

    local x =
        thumbFrame.x + thumbFrame.w - self.badgeSize - 6


    local y =
        thumbFrame.y + 6


    for _, badge in ipairs(badges) do

        table.insert(
            elements,
            {
                type = "rectangle",
                action = "strokeAndFill",
                frame = {
                    x = x,
                    y = y,
                    w = self.badgeSize,
                    h = self.badgeSize,
                },
                roundedRectRadii = rounded(math.floor(self.badgeSize / 2)),
                fillColor = badge.color,
                strokeColor = self:themeColor("badgeTextColor"),
                strokeWidth = self.badgeStrokeWidth,
            }
        )


        table.insert(
            elements,
            {
                type = "text",
                frame = {
                    x = x,
                    y = y + math.floor((self.badgeSize - self.badgeTextSize) / 2) - 2,
                    w = self.badgeSize,
                    h = self.badgeSize,
                },
                text = safeCall(function()

                    return styledtext.new(
                        badge.glyph,
                        {
                            font = {
                                name = ".AppleSystemUIFont",
                                size = self.badgeTextSize,
                            },
                            color = self:themeColor("badgeTextColor"),
                            paragraphStyle = {
                                alignment = "center",
                            },
                        }
                    )

                end) or badge.glyph,
            }
        )


        x =
            x - self.badgeSize - self.badgeGap

    end


    return elements

end


function obj:tileElements(elements, item, offsetX, offsetY)

    offsetX =
        offsetX or 0


    offsetY =
        offsetY or 0

    local isSelected =
        item.index == self.selectedIndex


    local alpha =
        isSelected and self.selectedAlpha or self.unselectedAlpha


    local entry =
        item.entry


    local preview,
          isPlaceholder =
        self:previewImage(entry)

    local placeholderSize =
        math.floor(self.iconSize * self.placeholderIconScale)


    local labelX =
        offsetX + item.x + math.floor((item.width - item.labelWidth) / 2)


    local labelY =
        offsetY + item.y


    local thumbFrame =
        {
            x = offsetX + item.x + math.floor((item.width - item.previewWidth) / 2),
            y = offsetY + item.y + self.labelHeight + self.labelToPreviewGap,
            w = item.previewWidth,
            h = item.previewHeight,
        }


    if isPlaceholder then

        table.insert(
            elements,
            {
                type = "rectangle",
                action = "fill",
                frame = thumbFrame,
                roundedRectRadii = rounded(self.tileCornerRadius),
                fillColor = self:themeColor("thumbnailBackgroundColor"),
            }
        )

    end


    if not isPlaceholder then

        table.insert(
            elements,
            {
                type = "rectangle",
                action = "clip",
                frame = thumbFrame,
                roundedRectRadii = rounded(self.tileCornerRadius),
            }
        )

    end


    table.insert(
        elements,
        {
            type = "image",
            frame = isPlaceholder and {
                x = thumbFrame.x + math.floor((thumbFrame.w - placeholderSize) / 2),
                y = thumbFrame.y + math.floor((thumbFrame.h - placeholderSize) / 2),
                w = placeholderSize,
                h = placeholderSize,
            } or thumbFrame,
            image = preview,
            imageScaling = "scaleProportionally",
            imageAlpha = alpha,
        }
    )


    if not isPlaceholder then

        table.insert(
            elements,
            {
                type = "resetClip",
            }
        )

    end


    table.insert(
        elements,
        {
            type = "rectangle",
            action = "stroke",
            frame = thumbFrame,
            roundedRectRadii = rounded(self.tileCornerRadius),
            strokeColor = self:themeColor("tileStrokeColor"),
            strokeWidth = 1,
        }
    )


    self:badgeElements(elements, entry, thumbFrame)


    if isSelected then

        table.insert(
            elements,
            {
                type = "rectangle",
                action = "stroke",
                frame = {
                    x = thumbFrame.x - 5,
                    y = thumbFrame.y - 5,
                    w = thumbFrame.w + 10,
                    h = thumbFrame.h + 10,
                },
                roundedRectRadii = rounded(self.tileCornerRadius + 4),
                strokeColor = self:themeColor("selectedBorderColor"),
                strokeWidth = self.selectedStrokeWidth,
            }
        )

    end


    table.insert(
        elements,
        {
            type = "image",
            frame = {
                x = labelX,
                y = labelY,
                w = self.iconSize,
                h = self.iconSize,
            },
            image = self:appIcon(entry),
            imageScaling = "scaleProportionally",
            imageAlpha = alpha,
        }
    )


    table.insert(
        elements,
        {
            type = "text",
            frame = {
                x = labelX + self.iconSize + 10,
                y = labelY - 1,
                w = item.labelWidth - self.iconSize - 10,
                h = self.labelHeight,
            },
            text = self:styledTitle(entry, isSelected),
        }
    )


    if self.enableMouseSelection then

        table.insert(
            elements,
            {
                id = "tile:" .. tostring(item.index),
                type = "rectangle",
                action = "fill",
                frame = {
                    x = offsetX + item.x - 8,
                    y = offsetY + item.y - 6,
                    w = item.width + 16,
                    h = item.height + 14,
                },
                roundedRectRadii = rounded(self.tileCornerRadius + 8),
                fillColor = self:themeColor("hitTargetColor"),
                trackMouseDown = true,
                trackMouseUp = true,
                trackMouseEnterExit = true,
                trackMouseMove = true,
            }
        )

    end


    -- Apres la cible de la tuile : les elements plus tardifs recoivent
    -- le clic en premier, sinon la croix activerait la fenetre au lieu
    -- de la fermer.

    self:closeButtonElements(elements, item, thumbFrame, isSelected)

end


-- Dessine un feu de fenetre macOS : disque plein, lisere, et le symbole
-- obtenu en assombrissant le disque de moitie. Les proportions viennent
-- de mesures faites sur une vraie fenetre.

function obj:trafficLightElements(elements, kind, frame, identifier)

    local palette =
        self.trafficLights[kind]


    if not palette then

        return elements

    end


    local size =
        frame.w


    local centerX =
        frame.x + (size / 2)


    local centerY =
        frame.y + (size / 2)


    table.insert(
        elements,
        {
            type = "circle",
            action = "strokeAndFill",
            center = {
                x = centerX,
                y = centerY,
            },
            radius = (size / 2) - 0.5,
            fillColor = palette.fill,
            strokeColor = palette.rim,
            strokeWidth = 1,
        }
    )


    local thickness =
        math.max(1, size * self.trafficLightStrokeRatio)


    local strokes =
        {}


    if kind == "close" then

        local reach =
            (size * self.closeSymbolExtent - thickness) / 2


        strokes = {
            {
                { x = centerX - reach, y = centerY - reach },
                { x = centerX + reach, y = centerY + reach },
            },
            {
                { x = centerX + reach, y = centerY - reach },
                { x = centerX - reach, y = centerY + reach },
            },
        }

    else

        local reach =
            (size * self.minimizeSymbolExtent - thickness) / 2


        strokes = {
            {
                { x = centerX - reach, y = centerY },
                { x = centerX + reach, y = centerY },
            },
        }

    end


    for _, stroke in ipairs(strokes) do

        table.insert(
            elements,
            {
                type = "segments",
                action = "stroke",
                coordinates = stroke,
                strokeColor = self.trafficLightSymbolColor,
                strokeWidth = thickness,
                strokeCapStyle = "round",
            }
        )

    end


    table.insert(
        elements,
        {
            id = identifier,
            type = "rectangle",
            action = "fill",
            frame = {
                x = frame.x - 3,
                y = frame.y - 3,
                w = size + 6,
                h = size + 6,
            },
            roundedRectRadii = rounded(math.floor(size / 2) + 3),
            fillColor = self:themeColor("hitTargetColor"),
            trackMouseDown = true,
            trackMouseUp = true,
            trackMouseEnterExit = true,
            trackMouseMove = true,
        }
    )


    return elements

end


function obj:closeButtonElements(elements, item, thumbFrame, isSelected)

    if not self.enableMouseSelection
        or not isSelected
        or not self.mouseArmed then

        return elements

    end


    local size =
        self.trafficLightSize


    local gap =
        math.floor(size * self.trafficLightGapRatio)


    -- En haut a gauche, dans l'ordre du systeme : fermer puis reduire.

    local x =
        thumbFrame.x + 6


    local y =
        thumbFrame.y + 6


    if self.showCloseButton then

        self:trafficLightElements(
            elements,
            "close",
            { x = x, y = y, w = size, h = size },
            "close:" .. tostring(item.index)
        )


        x =
            x + size + gap

    end


    if self.showMinimizeButton then

        self:trafficLightElements(
            elements,
            "minimize",
            { x = x, y = y, w = size, h = size },
            "minimize:" .. tostring(item.index)
        )

    end


    return elements

end


-- Le panneau s'ouvre souvent sous le pointeur. Comme les tuiles
-- suivent aussi mouseMove, le moindre fremissement du trackpad
-- ecrasait la selection au clavier pendant que l'utilisateur tabulait.
-- La souris ne reprend la main qu'apres un deplacement reel.

function obj:armMouseSelection()

    self.mouseArmed =
        false


    self.mouseOrigin =
        safeCall(function()

            return hs.mouse.absolutePosition()

        end)


    return self

end


function obj:cancelMouseIdleTimer()

    if self.mouseIdleTimer then

        self.mouseIdleTimer:stop()


        self.mouseIdleTimer =
            nil

    end


    return self

end


-- Repousse l'effacement des feux. Appele a chaque signe de vie de la
-- souris, y compris quand elle survole les feux eux-memes : sinon ils
-- disparaitraient sous le pointeur au moment de cliquer.

function obj:noteMouseActivity()

    self:cancelMouseIdleTimer()


    if not self.mouseIdleSeconds
        or self.mouseIdleSeconds <= 0 then

        return self

    end


    self.mouseIdleTimer =
        timer.doAfter(
            self.mouseIdleSeconds,
            function()

                self.mouseIdleTimer =
                    nil


                if not self.entries or not self.mouseArmed then

                    return

                end


                self.mouseArmed =
                    false


                -- On repart de la position courante : il faudra un
                -- nouveau deplacement franc pour les faire revenir.

                self.mouseOrigin =
                    safeCall(function()

                        return hs.mouse.absolutePosition()

                    end)


                self:redraw()

            end
        )


    return self

end


function obj:mouseHasMoved()

    if self.mouseArmed then

        return true

    end


    local origin =
        self.mouseOrigin


    if not origin then

        self.mouseArmed =
            true


        return true

    end


    local position =
        safeCall(function()

            return hs.mouse.absolutePosition()

        end)


    if not position then

        return false

    end


    local distance =
        math.max(
            math.abs(position.x - origin.x),
            math.abs(position.y - origin.y)
        )


    if distance >= self.mouseActivationDistance then

        self.mouseArmed =
            true

    end


    return self.mouseArmed

end


function obj:closeEntry(index)

    local descriptor =
        self.entries and self.entries[index]


    if not descriptor then

        return self

    end


    self:hidePreview()


    local closed,
          err =
        safeCall(function()

            return descriptor.window:close()

        end)


    if closed == false or err then

        self:log(
            "Fermeture refusee pour "
            .. tostring(descriptor.displayTitle)
            .. (err and (" : " .. tostring(err)) or "")
        )


        return self

    end


    table.remove(self.entries, index)


    self.snapshotCache[descriptor.id] =
        nil


    self:discardCaptureFile(descriptor.id)


    self.layoutCache =
        nil


    self.titleCache =
        {}


    self.previewIndex =
        nil


    if #self.entries == 0 then

        self:endSession()


        return self

    end


    if (self.selectedIndex or 1) > #self.entries then

        self.selectedIndex =
            #self.entries

    end


    self:redraw()


    return self

end


function obj:closeSelected()

    return self:closeEntry(self.selectedIndex)

end


-- Reduire ne retire pas la tuile : la fenetre existe toujours, elle
-- change seulement d'etat. Sa vignette n'est plus valable et sa
-- pastille doit apparaitre.

function obj:minimizeEntry(index)

    local descriptor =
        self.entries and self.entries[index]


    if not descriptor or descriptor.minimized then

        return self

    end


    local ok,
          err =
        safeCall(function()

            return descriptor.window:minimize()

        end)


    if err then

        self:log(
            "Reduction refusee pour "
            .. tostring(descriptor.displayTitle)
            .. " : " .. tostring(err)
        )


        return self

    end


    descriptor.minimized =
        true


    descriptor.snapshotAttempted =
        nil


    self.snapshotCache[descriptor.id] =
        nil


    self:discardCaptureFile(descriptor.id)


    self.titleCache =
        {}


    self:hidePreview()
    self:redraw()


    return self

end


function obj:minimizeSelected()

    return self:minimizeEntry(self.selectedIndex)

end


function obj:handleMouseEvent(message, elementID)

    local closeIndex =
        tostring(elementID or ""):match("^close:(%d+)$")


    if closeIndex then

        self:noteMouseActivity()


        if message == "mouseUp" then

            self:closeEntry(tonumber(closeIndex))

        end


        return

    end


    local minimizeIndex =
        tostring(elementID or ""):match("^minimize:(%d+)$")


    if minimizeIndex then

        self:noteMouseActivity()


        if message == "mouseUp" then

            self:minimizeEntry(tonumber(minimizeIndex))

        end


        return

    end


    local index =
        tostring(elementID or ""):match("^tile:(%d+)$")


    if not index then

        return

    end


    index =
        tonumber(index)


    if not index or not self.entries or not self.entries[index] then

        return

    end


    -- Un clic est toujours une intention explicite ; un survol, non.

    local etaitArmee =
        self.mouseArmed


    if message ~= "mouseUp" and not self:mouseHasMoved() then

        return

    end


    if message == "mouseEnter" or message == "mouseMove" then

        self:noteMouseActivity()


        if self.selectedIndex ~= index then

            self.selectionFromMouse =
                true


            self.selectedIndex =
                index


            self:redraw()

        elseif not etaitArmee then

            -- La souris vient de reprendre la main sur la tuile deja
            -- visee. Rien ne change dans la selection, donc rien ne
            -- serait redessine, et les feux n'apparaitraient jamais
            -- sur celle-la.

            self:redraw()

        end

    elseif message == "mouseUp" then

        self.selectedIndex =
            index


        self:commit()

    end

end


function obj:renderElements(layout)

    local elements =
        {
            self:panelElement(layout),
        }


    for _, item in ipairs(layout.items or {}) do

        self:tileElements(
            elements,
            item,
            layout.panel.x,
            layout.panel.y
        )

    end


    return elements

end


-- Construire la fenetre graphique coute une allocation systeme. La
-- faire au demarrage plutot qu'au premier Option+Tab retire ce cout du
-- chemin critique ; elle reste invisible tant qu'on ne l'affiche pas.

function obj:createCanvas(frame)

    if self.switcherCanvas then

        return self.switcherCanvas

    end


    self.switcherCanvas =
        canvas.new(frame or { x = 0, y = 0, w = 1, h = 1 })


    if not self.switcherCanvas then

        return nil

    end


    self.switcherCanvas:level(canvas.windowLevels.overlay)


    if self.enableMouseSelection then

        local mouseOk =
            safeCall(function()

                self.switcherCanvas:clickActivating(false)
                self.switcherCanvas:mouseCallback(function(_canvas, message, elementID)

                    self:handleMouseEvent(message, elementID)

                end)


                if self.switcherCanvas.canvasMouseEvents then

                    self.switcherCanvas:canvasMouseEvents(true, true, false, false)

                end


                return true

            end)


        if not mouseOk then

            self.enableMouseSelection =
                false


            self:log("Selection souris desactivee : API canvas indisponible")

        end

    end


    return self.switcherCanvas

end


function obj:showCanvas(layout, elements)

    self:createCanvas(layout.canvas or layout.panel)


    if not self.switcherCanvas then

        return

    end


    self.switcherCanvas:frame(layout.canvas or layout.panel)


    local ok,
          err =
        pcall(function()

            self.switcherCanvas:replaceElements(
                unpackTable(elements)
            )


            self.switcherCanvas:show(0)

        end)


    if not ok then

        self:log("Erreur rendu canvas : " .. tostring(err))


        if self.enableMouseSelection then

            self.enableMouseSelection =
                false


            self.switcherCanvas:replaceElements(
                unpackTable(self:renderElements(layout))
            )


            self.switcherCanvas:show(0)

        end

    end

end


function obj:hideCanvas()

    if self.switcherCanvas then

        self.switcherCanvas:hide(0)

    end


    return self

end


function obj:deleteCanvas()

    if self.switcherCanvas then

        self.switcherCanvas:delete(0)

        self.switcherCanvas =
            nil

    end


    return self

end


function obj:stopScreenCaptureTasks()

    for _, running in pairs(self.runningScreenCaptures or {}) do

        local job =
            running.job or running


        if type(job) == "table" and job.token then

            self:removeFile(self:screenCaptureRequestPath(job))
            self:removeFile(self:screenCaptureStatusPath(job))
            self:removeFile(job.outputPath)

        end

    end


    self.screenCaptureQueue =
        {}


    self.queuedScreenCaptures =
        {}


    self.runningScreenCaptures =
        {}


    if self.screenCapturePollTimer then

        self.screenCapturePollTimer:stop()

        self.screenCapturePollTimer =
            nil

    end


    return self

end


function obj:cancelPendingRedraw()

    if self.redrawTimer then

        self.redrawTimer:stop()

        self.redrawTimer =
            nil

    end


    return self

end


-- Une capture qui arrive declenche un rendu. Quand plusieurs
-- reviennent dans la meme fraction de seconde, un seul suffit.

function obj:scheduleRedraw()

    if not self.entries then

        return self

    end


    if self.redrawTimer then

        return self

    end


    self.redrawTimer =
        timer.doAfter(
            self.redrawCoalesceSeconds,
            function()

                self.redrawTimer =
                    nil


                self:redraw()

            end
        )


    return self

end


function obj:redraw()

    if not self.entries or #self.entries == 0 then

        return self

    end


    local pageSize =
        self.maxColumns * self.maxRows


    local startIndex,
          endIndex =
        self:visibleRange(#self.entries, pageSize)


    -- La geometrie ne depend pas de la selection : seuls le liseré et
    -- la taille du libelle changent. Inutile de tout recalculer a
    -- chaque appui sur Tab.

    local cache =
        self.layoutCache


    local layout,
          layoutErr


    if cache
        and cache.startIndex == startIndex
        and cache.endIndex == endIndex then

        layout =
            cache.layout

    else

        layout,
        layoutErr =
            safeCall(function()

                return self:layout(startIndex, endIndex)

            end)


        if layout then

            self.layoutCache =
                {
                    startIndex = startIndex,
                    endIndex = endIndex,
                    layout = layout,
                }

        end

    end


    if not layout then

        self:log("Erreur layout canvas : " .. tostring(layoutErr))


        return self

    end


    self:warmSnapshots(startIndex, endIndex)


    local elements,
          renderErr =
        safeCall(function()

            return self:renderElements(layout)

        end)


    if not elements then

        self:log("Erreur elements canvas : " .. tostring(renderErr))


        return self

    end


    self:showCanvas(layout, elements)
    self:notePreviewTarget()


    return self

end


-- L'ancienne version interrogeait le clavier toutes les 10 ms pendant
-- toute la duree du switch, soit cent sondages par seconde sur le
-- thread principal. Un eventtap sur flagsChanged reagit a l'instant
-- exact ou la touche retombe et ne coute rien entre deux evenements.
-- Le timer qui reste n'est qu'un filet : si le tap manque un
-- evenement, le panneau ne doit pas rester ouvert indefiniment.

function obj:ensureModifierTap()

    if self.modifierTap then

        return self.modifierTap

    end


    local tap =
        eventtap.new(
            { eventtap.event.types.flagsChanged },
            function()

                if not self:modifiersPressed() then

                    self:commit()

                end


                return false

            end
        )


    self.modifierTap =
        tap


    return tap

end


function obj:cancelKeyCode()

    if self.cachedCancelKeyCode then

        return self.cachedCancelKeyCode

    end


    local code =
        safeCall(function()

            return hs.keycodes.map.escape

        end)


    self.cachedCancelKeyCode =
        code or 53


    return self.cachedCancelKeyCode

end


function obj:closeKeyCode()

    if self.cachedCloseKeyCode then

        return self.cachedCloseKeyCode

    end


    local code =
        safeCall(function()

            return hs.keycodes.map.w

        end)


    self.cachedCloseKeyCode =
        code or 13


    return self.cachedCloseKeyCode

end


function obj:minimizeKeyCode()

    if self.cachedMinimizeKeyCode then

        return self.cachedMinimizeKeyCode

    end


    local code =
        safeCall(function()

            return hs.keycodes.map.m

        end)


    self.cachedMinimizeKeyCode =
        code or 46


    return self.cachedMinimizeKeyCode

end


function obj:ensureSessionKeyTap()

    if self.sessionKeyTap then

        return self.sessionKeyTap

    end


    self.sessionKeyTap =
        eventtap.new(
            { eventtap.event.types.keyDown },
            function(event)

                local code =
                    safeCall(function()

                        return event:getKeyCode()

                    end)


                if code == self:cancelKeyCode() then

                    self:cancel()


                    -- Consomme : l'application dessous ne doit pas
                    -- recevoir l'Echap qui a ferme le switcher.

                    return true

                end


                if self.enableCloseKey
                    and code == self:closeKeyCode() then

                    self:closeSelected()


                    return true

                end


                if self.enableMinimizeKey
                    and code == self:minimizeKeyCode() then

                    self:minimizeSelected()


                    return true

                end


                return false

            end
        )


    return self.sessionKeyTap

end


function obj:startSessionKeyTap()

    if not self.enableCancelKey then

        return self

    end


    local tap =
        self:ensureSessionKeyTap()


    if tap then

        safeCall(function()

            tap:start()

        end)

    end


    return self

end


function obj:stopSessionKeyTap()

    if self.sessionKeyTap then

        safeCall(function()

            self.sessionKeyTap:stop()

        end)

    end


    return self

end


function obj:releaseSessionKeyTap()

    self:stopSessionKeyTap()


    self.sessionKeyTap =
        nil


    return self

end


function obj:startModifierWatcher()

    self:stopModifierWatcher()


    local tap =
        self:ensureModifierTap()


    local tapStarted =
        false


    if tap then

        tapStarted =
            safeCall(function()

                tap:start()


                return true

            end) == true

    end


    local interval =
        tapStarted and self.modifierSafetyInterval
            or self.modifierFallbackInterval


    self.modifierTimer =
        timer.doEvery(
            interval,
            function()

                if not self:modifiersPressed() then

                    self:commit()

                end

            end
        )


    return self

end


function obj:stopModifierWatcher()

    if self.modifierTap then

        safeCall(function()

            self.modifierTap:stop()

        end)

    end


    if self.modifierTimer then

        self.modifierTimer:stop()

        self.modifierTimer =
            nil

    end


    return self

end


function obj:releaseModifierTap()

    self:stopModifierWatcher()


    self.modifierTap =
        nil


    return self

end



------------------------------------------------------------
-- HOTKEYS
------------------------------------------------------------

function obj:deleteHotkeys()

    for _, hotkey in pairs(self.hotkeys or {}) do

        if hotkey then

            hotkey:delete()

        end

    end


    self.hotkeys =
        {}


    return self

end


function obj:bindHotkeys(mapping)

    self.hotkeyMapping =
        mapping or {}


    -- Rien n'est lie tant que le Spoon ne tourne pas : createHotkeys()
    -- est rappele par start().

    if self.isStarted then

        self:createHotkeys()

    end


    return self

end


function obj:createHotkeys()

    self:deleteHotkeys()


    local mapping =
        self.hotkeyMapping or {}


    if mapping.forward then

        self.hotkeys.forward =
            hs.hotkey.bind(
                mapping.forward[1],
                mapping.forward[2],
                function()

                    self:next()

                end,
                nil,
                function()

                    self:next()

                end
            )

    end


    if mapping.backward then

        self.hotkeys.backward =
            hs.hotkey.bind(
                mapping.backward[1],
                mapping.backward[2],
                function()

                    self:previous()

                end,
                nil,
                function()

                    self:previous()

                end
            )

    end


    return self

end



------------------------------------------------------------
-- ACTIONS
------------------------------------------------------------

function obj:selectRelative(direction)

    if not self.entries or #self.entries == 0 then

        return

    end


    self.selectedIndex =
        (self.selectedIndex or 1) + direction


    if self.selectedIndex < 1 then

        self.selectedIndex =
            #self.entries

    elseif self.selectedIndex > #self.entries then

        self.selectedIndex =
            1

    end

end


function obj:beginSession(direction)

    self.layoutCache =
        nil


    self.titleCache =
        {}


    self:trimSnapshotCache()


    -- Avant de collecter : le regroupement par bureau et les pastilles
    -- ont besoin de savoir ce qui est visible maintenant.

    self:refreshActiveSpaces()


    self.entries =
        self:groupByCurrentSpace(
            self:collectWindows()
        )


    if not self.entries or #self.entries == 0 then

        self.entries =
            nil

        return false

    end


    self.selectedIndex =
        1


    if #self.entries > 1 then

        self:selectRelative(direction)

    end


    self.previewIndex =
        nil


    self.selectionFromMouse =
        false


    self:queueAudioSnapshot()
    self:armMouseSelection()
    self:startModifierWatcher()
    self:startSessionKeyTap()


    return true

end


function obj:step(direction)

    local now =
        timer.secondsSinceEpoch()


    if self.entries and self.lastStepAt and now - self.lastStepAt < self.stepThrottleSeconds then

        return

    end


    self.lastStepAt =
        now


    self.selectionFromMouse =
        false


    if not self.entries then

        if not self:beginSession(direction) then

            return

        end

    else

        self:selectRelative(direction)

    end


    self:redraw()

end


function obj:next()

    self:step(1)

end


function obj:previous()

    self:step(-1)

end


-- Ferme la session et rend tout ce qu'elle tenait. Ne decide rien :
-- commit active la fenetre choisie, cancel ne fait que fermer.

function obj:endSession()

    local selected =
        self.entries and self.entries[self.selectedIndex]


    self:stopModifierWatcher()
    self:stopSessionKeyTap()
    self:cancelMouseIdleTimer()
    self:cancelPendingRedraw()
    self:hidePreview()
    self:hideCanvas()

    self.entries =
        nil

    self.selectedIndex =
        nil

    self.lastStepAt =
        nil

    self.layoutCache =
        nil

    self.titleCache =
        {}

    self.mouseArmed =
        false

    self.mouseOrigin =
        nil

    self.previewIndex =
        nil


    return selected

end


-- Echap : on ferme sans rien activer. Le focus reste ou il etait.

function obj:cancel()

    if not self.entries then

        return self

    end


    self:endSession()


    return self

end


function obj:commit()

    local selected =
        self:endSession()


    if not selected then

        return

    end


    -- Une application masquee par Cmd+H ne se reaffiche pas d'elle
    -- meme : hs.window:focus() ne fait que becomeMain puis
    -- bringtofront. Comme includeHidden vaut true par defaut, ses
    -- fenetres etaient listees dans la grille sans qu'on puisse les
    -- atteindre.

    local ailleurs =
        self:isOnOtherSpace(selected) == true


    if selected.hidden and selected.application then

        safeCall(function()

            selected.application:unhide()

        end)

    end


    safeCall(function()

        selected.window:unminimize()

    end)


    safeCall(function()

        selected.window:focus()

    end)


    -- Une bascule de bureau prend le temps de son animation. Verifier
    -- le focus avant la fin le trouve sur la fenetre precedente et
    -- declenche une reprise qui se bat contre l'animation en cours.

    self:reassertFocus(
        selected,
        ailleurs and self.crossSpaceFocusDelay or nil
    )

end


function obj:reassertFocus(selected, delay)

    delay =
        delay or self.focusReassertDelay


    if not delay
        or delay <= 0 then

        return self

    end


    timer.doAfter(
        delay,
        function()

            local focused =
                safeCall(function()

                    return window.focusedWindow()

                end)


            local focusedID =
                focused and safeCall(function()

                    return focused:id()

                end)


            if focusedID == selected.id then

                return

            end


            safeCall(function()

                selected.window:focus()

            end)

        end
    )


    return self

end



------------------------------------------------------------
-- APERCU DE LA FENETRE SELECTIONNEE
------------------------------------------------------------

-- Cadre de l'apercu : la taille et la position reelles de la fenetre,
-- reduites seulement si elles depassent l'ecran. Une fenetre sans cadre
-- exploitable (reduite depuis longtemps, cadre illisible) est centree.

function obj:previewGeometry(descriptor)

    local screenFrame =
        safeCall(function()

            return screen.mainScreen():fullFrame()

        end)
        or safeCall(function()

            return screen.mainScreen():frame()

        end)


    if not screenFrame then

        return nil

    end


    local maxWidth =
        screenFrame.w * self.previewMaxScreenRatio


    local maxHeight =
        screenFrame.h * self.previewMaxScreenRatio


    local frame =
        descriptor and descriptor.frame


    local width,
          height


    if frame
        and frame.w and frame.h
        and frame.w > 1 and frame.h > 1 then

        width =
            frame.w


        height =
            frame.h

    else

        frame =
            nil


        width =
            maxWidth


        height =
            maxHeight

    end


    local scale =
        math.min(
            1,
            maxWidth / width,
            maxHeight / height
        )


    width =
        math.floor(width * scale)


    height =
        math.floor(height * scale)


    local x,
          y


    if frame then

        -- On garde le centre de la fenetre reelle : si elle tenait
        -- deja a l'ecran, l'apercu se superpose exactement a elle.

        x =
            math.floor(frame.x + (frame.w - width) / 2)


        y =
            math.floor(frame.y + (frame.h - height) / 2)

    else

        x =
            math.floor(screenFrame.x + (screenFrame.w - width) / 2)


        y =
            math.floor(screenFrame.y + (screenFrame.h - height) / 2)

    end


    x =
        math.max(
            screenFrame.x,
            math.min(x, screenFrame.x + screenFrame.w - width)
        )


    y =
        math.max(
            screenFrame.y,
            math.min(y, screenFrame.y + screenFrame.h - height)
        )


    return {
        x = x,
        y = y,
        w = width,
        h = height,
    }

end


function obj:previewElements(geometry, snapshot)

    local margin =
        self.canvasPadding


    local frame =
        {
            x = margin,
            y = margin,
            w = geometry.w,
            h = geometry.h,
        }


    local elements =
        {
            {
                type = "rectangle",
                action = "fill",
                frame = frame,
                roundedRectRadii = rounded(self.previewCornerRadius),
                fillColor = self:themeColor("backgroundColor"),
                withShadow = true,
                shadow = {
                    blurRadius = 26,
                    color = self:themeColor("shadowColor"),
                    offset = {
                        h = -12,
                        w = 0,
                    },
                },
            },
        }


    if snapshot then

        table.insert(
            elements,
            {
                type = "rectangle",
                action = "clip",
                frame = frame,
                roundedRectRadii = rounded(self.previewCornerRadius),
            }
        )


        table.insert(
            elements,
            {
                type = "image",
                frame = frame,
                image = snapshot,
                imageScaling = "scaleProportionally",
                imageAlpha = 1,
            }
        )


        table.insert(
            elements,
            {
                type = "resetClip",
            }
        )

    end


    -- Le liseré est ce qui rend l'apercu lisible quand il recouvre
    -- exactement la fenetre reelle.

    table.insert(
        elements,
        {
            type = "rectangle",
            action = "stroke",
            frame = frame,
            roundedRectRadii = rounded(self.previewCornerRadius),
            strokeColor = self:themeColor("selectedBorderColor"),
            strokeWidth = self.previewBorderWidth,
        }
    )


    return elements

end


function obj:createPreviewCanvas(rect)

    if self.previewCanvas then

        return self.previewCanvas

    end


    self.previewCanvas =
        canvas.new(rect or { x = 0, y = 0, w = 1, h = 1 })


    if not self.previewCanvas then

        return nil

    end


    -- Au-dessus des fenetres ordinaires, sous le panneau du switcher :
    -- l'apercu ne doit jamais masquer la grille ni intercepter ses
    -- clics.

    self.previewCanvas:level(canvas.windowLevels.floating)


    safeCall(function()

        self.previewCanvas:clickActivating(false)

    end)


    return self.previewCanvas

end


function obj:renderPreview()

    local descriptor =
        self.entries and self.entries[self.selectedIndex]


    if not descriptor then

        return self:hidePreview()

    end


    local geometry =
        self:previewGeometry(descriptor)


    if not geometry then

        return self:hidePreview()

    end


    local margin =
        self.canvasPadding


    local rect =
        {
            x = geometry.x - margin,
            y = geometry.y - margin,
            w = geometry.w + (margin * 2),
            h = geometry.h + (margin * 2),
        }


    if not self:createPreviewCanvas(rect) then

        return self

    end


    local snapshot =
        self:cachedSnapshot(descriptor)


    local ok,
          err =
        pcall(function()

            self.previewCanvas:frame(rect)


            self.previewCanvas:replaceElements(
                unpackTable(self:previewElements(geometry, snapshot))
            )

        end)


    if not ok then

        self:log("Erreur apercu : " .. tostring(err))


        return self:hidePreview()

    end


    return self

end


function obj:showPreview()

    if not self.enableWindowPreview then

        return self

    end


    if not self.entries then

        return self

    end


    self:renderPreview()


    if not self.previewCanvas then

        return self

    end


    safeCall(function()

        self.previewCanvas:show(0)

    end)


    self.previewVisible =
        true


    return self

end


function obj:hidePreview()

    self:cancelPreviewTimer()


    if self.previewCanvas and self.previewVisible then

        safeCall(function()

            self.previewCanvas:hide(0)

        end)

    end


    self.previewVisible =
        false


    return self

end


function obj:cancelPreviewTimer()

    if self.previewTimer then

        self.previewTimer:stop()


        self.previewTimer =
            nil

    end


    return self

end


function obj:deletePreviewCanvas()

    self:hidePreview()


    if self.previewCanvas then

        safeCall(function()

            self.previewCanvas:delete(0)

        end)


        self.previewCanvas =
            nil

    end


    self.previewIndex =
        nil


    return self

end


-- Appele apres chaque rendu. Une capture qui arrive ne doit pas relancer
-- le compte a rebours : sur la meme tuile, on se contente de rafraichir
-- l'image de l'apercu deja visible.

function obj:notePreviewTarget()

    if not self.enableWindowPreview
        or not self.entries then

        return self

    end


    if self.selectionFromMouse == false
        and not self.previewOnKeyboard then

        self:hidePreview()

        return self

    end


    if self.previewIndex == self.selectedIndex then

        if self.previewVisible then

            self:renderPreview()

        end


        return self

    end


    self.previewIndex =
        self.selectedIndex


    self:hidePreview()


    self.previewTimer =
        timer.doAfter(
            self.previewDelay,
            function()

                self.previewTimer =
                    nil


                self:showPreview()

            end
        )


    return self

end



------------------------------------------------------------
-- MESURE
------------------------------------------------------------

-- A lancer depuis la console Hammerspoon :
--     spoon.WindowSwitcher:benchmark()
--
-- Construit une session complete sans l'afficher et detaille le temps
-- de chaque etape. Utile pour savoir ou passe reellement le temps de la
-- premiere ouverture plutot que de le supposer.

function obj:benchmark(coldCache)

    local mark =
        timer.secondsSinceEpoch


    local sauvegarde =
        {
            entries = self.entries,
            selectedIndex = self.selectedIndex,
            layoutCache = self.layoutCache,
            titleCache = self.titleCache,
        }


    if coldCache ~= false then

        self.snapshotCache =
            {}


        self.iconCache =
            {}

    end


    self.layoutCache =
        nil


    self.titleCache =
        {}


    local t0 =
        mark()


    self.entries =
        self:collectWindows()


    local t1 =
        mark()


    local total =
        #(self.entries or {})


    if total == 0 then

        self.entries =
            sauvegarde.entries


        self:log("benchmark : aucune fenetre")


        return self

    end


    self.selectedIndex =
        math.min(2, total)


    local pageSize =
        self.maxColumns * self.maxRows


    local startIndex,
          endIndex =
        self:visibleRange(total, pageSize)


    local layout =
        self:layout(startIndex, endIndex)


    local t2 =
        mark()


    self:warmSnapshots(startIndex, endIndex)


    local t3 =
        mark()


    local elements =
        self:renderElements(layout)


    local t4 =
        mark()


    local captures =
        0


    for index = startIndex, endIndex do

        local _,
              fresh =
            self:cachedSnapshot(self.entries[index])


        if fresh then

            captures =
                captures + 1

        end

    end


    self:log(
        string.format(
            "benchmark : %d fenetres, %d tuiles, %d elements | "
            .. "collecte %.0f ms | geometrie %.0f ms | "
            .. "captures %.0f ms (%d/%d prêtes) | rendu %.0f ms | total %.0f ms",
            total,
            endIndex - startIndex + 1,
            #elements,
            (t1 - t0) * 1000,
            (t2 - t1) * 1000,
            (t3 - t2) * 1000,
            captures,
            endIndex - startIndex + 1,
            (t4 - t3) * 1000,
            (t4 - t0) * 1000
        )
    )


    self.entries =
        sauvegarde.entries


    self.selectedIndex =
        sauvegarde.selectedIndex


    self.layoutCache =
        sauvegarde.layoutCache


    self.titleCache =
        sauvegarde.titleCache


    return self

end



-- A lancer depuis la console Hammerspoon :
--     spoon.WindowSwitcher:audioStatus()
--
-- Dit ou en est l'inventaire du son, sans rien changer. Utile pour
-- savoir si une pastille absente vient du service, du releve ou de
-- l'application elle-meme.

function obj:audioStatus()

    local joue =
        {}


    local capte =
        {}


    for pid in pairs(self.audioPIDs) do

        joue[#joue + 1] =
            tostring(pid)

    end


    for pid in pairs(self.microphonePIDs) do

        capte[#capte + 1] =
            tostring(pid)

    end


    table.sort(joue)
    table.sort(capte)


    self:log(
        string.format(
            "audio : pastilles %s | service %s | demande en vol %s | "
            .. "jouent [%s] | captent [%s]",
            self.showAudioBadges and "actives" or "desactivees",
            self:screenCaptureHelperIsRunning() and "en marche" or "arrete",
            (self.runningScreenCaptures["audio"] or self.queuedScreenCaptures["audio"])
                and "oui" or "non",
            table.concat(joue, ","),
            table.concat(capte, ",")
        )
    )


    return self

end



------------------------------------------------------------
-- START / STOP
------------------------------------------------------------

function obj:start()

    if self.isStarted then

        return self

    end


    self.isStarted =
        true


    self.screenCaptureDisabledReason =
        nil

    self.screenCaptureHelperAppStarted =
        false


    self.screenCaptureSessionID =
        nil


    self.screenCaptureSessionSecret =
        nil


    self.screenCaptureSessionDirectory =
        nil


    self.captureFiles =
        {}


    -- Un helper survivant d'une session precedente pointe vers un
    -- repertoire qui n'existe plus : il ne repondrait a aucune de nos
    -- requetes tout en nous faisant croire qu'un service tourne.

    self:stopScreenCaptureHelperApp()

    self:createScreenCaptureSession()
    self:cleanupScreenCaptureSessions()
    self:cleanupLegacySessionDirectories()
    self:checkHelperFreshness()


    self:refreshIgnoredBundles(true)


    -- Monter le filtre des maintenant plutot qu'au premier Alt+Tab :
    -- hs.window.filter a besoin d'un instant pour enregistrer toutes
    -- les applications, et c'est ce delai qui rendait le premier
    -- switch lent.

    self:ensureWindowFilter()


    -- Demande des maintenant, pour que le premier switch ait deja ses
    -- pastilles au lieu de les decouvrir une demi-seconde trop tard.

    self:queueAudioSnapshot()


    -- Allouees des maintenant, affichees seulement au premier switch.

    self:createCanvas()


    if self.enableWindowPreview then

        self:createPreviewCanvas()

    end

    self:createHotkeys()

    self:log("Spoon initialise")


    return self

end


function obj:stop()

    if not self.isStarted then

        return self

    end


    self.isStarted =
        false


    self:deleteHotkeys()
    self:releaseModifierTap()
    self:releaseSessionKeyTap()
    self:cancelMouseIdleTimer()
    self:cancelPendingRedraw()
    self:stopScreenCaptureTasks()
    self:stopScreenCaptureHelperApp()


    -- L'ancienne version se contentait de masquer le canvas : un Spoon
    -- desactive gardait en memoire son canvas et toutes ses vignettes.

    self:deleteCanvas()
    self:deletePreviewCanvas()
    self:releaseWindowFilter()
    self:clearSnapshotCache()
    self:removeScreenCaptureSession()


    self.entries =
        nil

    self.selectedIndex =
        nil

    self.lastStepAt =
        nil

    self.layoutCache =
        nil

    self.titleCache =
        {}

    self.iconCache =
        {}

    self.captureFiles =
        {}

    self.audioPIDs =
        {}

    self.microphonePIDs =
        {}

    self.mouseArmed =
        false

    self.mouseOrigin =
        nil

    self.screenCaptureDisabledReason =
        nil

    self:log("Spoon arrete")


    return self

end


return obj
