------------------------------------------------------------
--
-- ActivityKeeper Spoon
--
-- Version : 4.13.0
--
------------------------------------------------------------
--
-- OBJECTIF
--
-- Maintien de présence avec trois moteurs indépendants :
--
--   - UserActivity
--   - Clavier Maj
--   - Souris
--
-- Réduction optionnelle de consommation :
--
--   - extinction rétroéclairage clavier
--   - diminution luminosité écran
--   - activation temporaire Low Power Mode
--
------------------------------------------------------------
--
-- ÉTATS
--
--   ●AK gris
--       ActivityKeeper OFF
--
--   ●AK jaune
--       surveillance de l'activité utilisateur
--
--   ●AK vert
--       maintien actif
--
------------------------------------------------------------
--
-- OUTILS EXTERNES OPTIONNELS
--
------------------------------------------------------------
--
-- 1. mac-brightnessctl
--
-- Permet :
--
--   - lecture précise du rétroéclairage clavier
--   - extinction à 0
--   - restauration précise de la valeur capturée
--
-- Chemins recherchés automatiquement :
--
--   /opt/homebrew/bin/mac-brightnessctl
--   /usr/local/bin/mac-brightnessctl
--   /opt/local/bin/mac-brightnessctl
--
-- Test :
--
--   /opt/homebrew/bin/mac-brightnessctl
--
-- Exemple :
--
--   Current brightness: 0.18
--
-- Sans cet outil :
--
--   fallback sur ILLUMINATION_TOGGLE via Hammerspoon.
--
-- Le fallback ne peut pas garantir une restauration
-- numérique précise de la valeur initiale.
--
------------------------------------------------------------
--
-- COMMANDES SYSTÈME NATIVES UTILISÉES
--
------------------------------------------------------------
--
-- /usr/bin/pmset
--
-- Utilisé pour :
--
--   - lire lowpowermode
--   - activer temporairement le mode économie d'énergie
--   - restaurer uniquement les profils modifiés
--
-- Lecture :
--
--   /usr/bin/pmset -g custom
--
-- Vérification rapide :
--
--   /usr/bin/pmset -g | grep lowpowermode
--
------------------------------------------------------------
--
-- SUDOERS NÉCESSAIRE UNIQUEMENT POUR LOW POWER MODE
--
------------------------------------------------------------
--
-- Créer :
--
--   sudo visudo -f /etc/sudoers.d/hammerspoon-pmset
--
-- Ajouter pour l'utilisateur benjy :
--
-- benjy ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 0
-- benjy ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 1
-- benjy ALL=(root) NOPASSWD: /usr/bin/pmset -c lowpowermode 0
-- benjy ALL=(root) NOPASSWD: /usr/bin/pmset -c lowpowermode 1
--
-- Vérification :
--
--   sudo -n /usr/bin/pmset -b lowpowermode 1
--
-- Puis retour éventuel :
--
--   sudo -n /usr/bin/pmset -b lowpowermode 0
--
------------------------------------------------------------
--
-- AUCUN SUDO NÉCESSAIRE POUR :
--
--   - Maj
--   - UserActivity
--   - mouvement souris
--   - hs.screen:getBrightness()
--   - hs.screen:setBrightness()
--   - mac-brightnessctl
--
------------------------------------------------------------



------------------------------------------------------------
-- OBJET SPOON
------------------------------------------------------------

local obj = {}

obj.__index = obj



------------------------------------------------------------
-- MÉTADONNÉES
------------------------------------------------------------

obj.name = "ActivityKeeper"

obj.version = "4.19.0"

obj.author = "Benjamin Cerede / OpenAI"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------


------------------------------------------------------------
-- TEMPORISATIONS
------------------------------------------------------------

obj.idleThreshold = 120

obj.checkInterval = 5

obj.keepAliveInterval = 45

obj.doubleClickInterval = 0.30

obj.trackHighFrequencyPointerEvents = false

obj.fastReturnWatcherEnabled = true

obj.fastReturnThrottle = 0.20

-- Sortie du vert : deduire au lieu de seuiller.
--
-- Les deux reglages ci-dessous decrivaient l'ancienne regle : sortir si
-- l'activite datait de moins de realActivityReturnIdleThreshold ET si
-- notre dernier keep-alive remontait a plus de
-- postKeepAliveIdleIgnorePeriod. Deux fenetres etroites qui devaient se
-- recouvrir, et qui laissaient echapper le cas le plus courant :
--
--   T      keep-alive envoye, fenetre synthetique ouverte 1 s
--   T+0,3  l'utilisateur tape -- le tap ignore, c'est la fenetre
--   T+8    l'idle redevient consultable
--   T+10   idle vaut 10 s, plus que le seuil de 6 : rien
--   ...    l'utilisateur ne tape plus, donc plus aucun evenement
--
-- L'application restait verte indefiniment, jusqu'a la frappe suivante.
--
-- La nouvelle regle n'a besoin d'aucune fenetre. macOS remet l'horloge
-- d'inactivite a zero a chaque evenement, y compris les notres. Donc si
-- cette horloge est plus RECENTE que notre dernier evenement synthetique,
-- c'est que quelqu'un d'autre a agi : l'utilisateur. Vrai a tout instant,
-- sans zone morte.
obj.realActivityReturnIdleThreshold = 6

obj.postKeepAliveIdleIgnorePeriod = 8

-- Marge de l'inference, en secondes. os.time() a une resolution d'une
-- seconde et un keep-alive s'etale sur environ 0,2 s : deux secondes
-- absorbent l'un et l'autre sans jamais conclure a tort.
obj.keepaliveExitMargin = 2

-- Le tap reste la voie normale, immediate. Ce filet ne sert que
-- lorsqu'il a manque l'evenement. Il ne lit qu'une horloge, donc il
-- peut battre vite sans rien couter.
obj.keepaliveExitCheckInterval = 1

-- Instant d'entree en KEEPALIVE. Sert de reference tant qu'aucun
-- keep-alive n'a encore ete envoye.
obj.keepaliveEnteredAt = nil



------------------------------------------------------------
-- CLAVIER
------------------------------------------------------------

obj.activityKey = "shift"

obj.keyPressDuration = 0.05

obj.keyboardBacklightEnforceAfterKeepAlive = true

obj.keyboardBacklightEnforceDelay = 0.20

obj.keepAliveAfterEnergySavingDelay = 1.0

obj.keyboardBrightnessRestoreFallback = 0.50

obj.keyboardAutoRestoreConfirmDelay = 0.25



------------------------------------------------------------
-- SOURIS
------------------------------------------------------------

obj.mouseMovePixels = 1

obj.mouseReturnDelay = 0.15



------------------------------------------------------------
-- FILTRAGE ÉVÉNEMENTS SYNTHÉTIQUES
------------------------------------------------------------

-- Reconnaitre nos propres evenements a coup sur, plutot qu'a la montre.
--
-- La fenetre de grace ci-dessous est une approximation : elle suppose
-- que nos evenements arrivent au tap avant son echeance. Quand elle
-- durait une seconde, elle tenait mais aveuglait l'utilisateur pendant
-- tout ce temps. Raccourcie a la fin de la sequence, elle laissait
-- passer nos propres evenements en retard : ActivityKeeper reagissait a
-- lui-meme et sortait du vert sans que personne n'ait touche la
-- machine.
--
-- eventSourceUserData porte 64 bits que nous choisissons. Un evenement
-- qui porte cette marque est le notre, quel que soit son retard. Plus
-- aucune supposition de temps.
obj.syntheticMark = 0x414B0001

-- Passe a vrai des que le tap a vu la marque revenir : la preuve que le
-- mecanisme fonctionne sur cette machine. Tant qu'elle est fausse, la
-- fenetre de grace reste entiere, par prudence.
obj.syntheticMarkWorks = false

-- Instant du DERNIER evenement que nous avons emis, quel qu'il soit.
--
-- Le keep-alive n'est pas notre seul evenement. disableKeyboardBacklight
-- et restoreKeyboardBacklight postent des touches systeme, et
-- forceKeyboardBacklightOffAfterKeepAlive s'execute a des instants sans
-- rapport avec le dernier keep-alive. Toutes remettent a zero l'horloge
-- d'inactivite de macOS.
--
-- L'inference de sortie du vert comparait cette horloge au dernier
-- KEEP-ALIVE. Une touche de retroeclairage postee trente secondes plus
-- tard remettait donc l'horloge a zero alors que la reference datait de
-- trente secondes : l'inference concluait "quelqu'un d'autre a agi" et
-- sortait du vert. Puis l'inactivite remontait, on repassait au vert, et
-- ainsi de suite -- surveillance, actif, surveillance, actif, sans que
-- personne ne touche la machine.
--
-- markSynthetic est le passage oblige de tout ce que nous emettons :
-- c'est donc la que se note l'instant qui fait reference.
obj.lastSyntheticAt = nil

obj.syntheticEventGracePeriod = 1.0

-- Une fois la sequence synthetique terminee, la fenetre d'aveuglement
-- n'a plus besoin de durer une seconde entiere : il suffit de laisser
-- passer les evenements encore en vol. Sans cette fermeture, une frappe
-- arrivant 0,3 s apres notre keep-alive etait jetee, et rien ne la
-- rattrapait -- l'inference ne sait pas distinguer une activite si
-- proche de la notre.
obj.syntheticEventSettleDelay = 0.15



------------------------------------------------------------
-- PROBE BACKLIGHT
------------------------------------------------------------

obj.keyboardBacklightProbeDelay = 0.75

obj.keyboardBacklightProbeRetries = 4

obj.keyboardBacklightProbeRetryInterval = 0.25

obj.keyboardBrightnessSampleInterval = 300



------------------------------------------------------------
-- VALEURS PAR DÉFAUT
------------------------------------------------------------

obj.defaultUserActivityEnabled = false

obj.defaultKeyboardEnabled = true

obj.defaultMouseEnabled = false

obj.defaultKeyboardBacklightEnabled = true

obj.defaultScreenDimmingEnabled = false

obj.defaultLowPowerModeEnabled = false

obj.defaultAutomaticLowPowerModeEnabled = false

obj.lowPowerBatteryThreshold = 15

obj.forceConfiguredModesOnStart = false



------------------------------------------------------------
-- LUMINOSITÉ ÉCRAN CIBLE
--
-- 0.15 = 15 %
------------------------------------------------------------

obj.screenBrightnessTarget = 0.15



------------------------------------------------------------
-- INTERFACE
------------------------------------------------------------

-- Icône dans la barre des menus. Le menu reste joignable via le
-- sous-menu de SpoonManager, qui sait la réafficher.
obj.showMenuBar = true

-- Raccourcis clavier.
--
-- true par defaut, contrairement a LastWindowQuits : le raccourci de
-- bascule existe et sert depuis longtemps ici, le passer a false le
-- couperait sans prevenir.
obj.hotkeysEnabled = true

obj.showStateNotifications = true

-- BULLE DE NOTIFICATION
--
-- Petite bulle ancrée sous l'icône de la barre des menus, à la place
-- des pavés plein écran de hs.alert. Quand l'icône est masquée, elle
-- se place sous le coin haut droit de l'écran principal.

obj.toastDuration = 1.8

obj.toastFadeDuration = 0.12

obj.toastFontSize = 13

obj.toastMaxWidth = 320

obj.toastPaddingX = 12

obj.toastPaddingY = 7

obj.toastGap = 6

obj.toastCornerRadius = 8

obj.toastScreenMargin = 12

obj.verboseLogging = false



------------------------------------------------------------
-- OUTILS
------------------------------------------------------------

obj.keyboardBrightnessToolPaths = {

    "/opt/homebrew/bin/mac-brightnessctl",

    "/usr/local/bin/mac-brightnessctl",

    "/opt/local/bin/mac-brightnessctl"

}


-- Clé où sont consignés les états système modifiés, pour pouvoir
-- les restaurer après un arrêt brutal de Hammerspoon.
obj.pendingRestoreKey = "ActivityKeeper.pendingRestore"

obj.pmsetPath = "/usr/bin/pmset"

obj.sudoPath = "/usr/bin/sudo"



------------------------------------------------------------
-- SETTINGS PERSISTANTS
------------------------------------------------------------

obj.SETTING_KEYS = {

    USER_ACTIVITY =
        "ActivityKeeper.mode.userActivity",

    KEYBOARD =
        "ActivityKeeper.mode.keyboard",

    MOUSE =
        "ActivityKeeper.mode.mouse",

    KEYBOARD_BACKLIGHT =
        "ActivityKeeper.energy.keyboardBacklight",

    SCREEN_DIMMING =
        "ActivityKeeper.energy.screenDimming",

    LOW_POWER =
        "ActivityKeeper.energy.lowPowerMode",

    AUTOMATIC_LOW_POWER =
        "ActivityKeeper.energy.automaticLowPowerMode"

}



------------------------------------------------------------
-- ÉTATS
------------------------------------------------------------

obj.STATE = {

    OFF =
        "OFF",

    MONITORING =
        "MONITORING",

    KEEPALIVE =
        "KEEPALIVE"

}



------------------------------------------------------------
-- VARIABLES GÉNÉRALES
------------------------------------------------------------

obj.currentState =
    obj.STATE.OFF


obj.checkTimer =
    nil


obj.returnMouseTimer =
    nil


obj.activityKeyDown =
    false


obj.keyUpTimer =
    nil


obj.inputWatcher =
    nil


-- Un traitement d'activite reelle est deja programme : une rafale de
-- frappes ne doit pas en empiler autant.
obj.realActivityPending = false

obj.fastReturnWatcher =
    nil


obj.menuBar =
    nil


obj.hotkeyMapping =
    nil


obj.hotkeys =
    {}


obj.clickCount =
    0


obj.clickTimer =
    nil



------------------------------------------------------------
-- KEEPALIVE
------------------------------------------------------------

obj.lastKeepAliveTime =
    nil


obj.lastRealActivityTime =
    nil


obj.lastFastReturnEventAt =
    0


obj.keepAliveCount =
    0


obj.keepAliveInProgress =
    false


obj.userActivityAssertionId =
    nil


obj.syntheticEventIgnoreUntil =
    0



------------------------------------------------------------
-- BACKLIGHT CLAVIER
------------------------------------------------------------

obj.keyboardBrightnessTool =
    nil


obj.keyboardBrightnessBackend =
    "fallback"


obj.lastKnownNonZeroKeyboardBrightness =
    nil


obj.savedKeyboardBrightness =
    nil


obj.keyboardBacklightModified =
    false


obj.savedKeyboardAutoBrightness =
    nil


obj.keyboardAutoBrightnessModified =
    false


obj.keyboardBacklightProbeTimer =
    nil


obj.keyboardBacklightProbeRetryTimer =
    nil


obj.keyboardBacklightEnforceTimer =
    nil


obj.initialKeepAliveTimer =
    nil


obj.keyboardAutoRestoreTimer =
    nil


obj.lastKeyboardBrightnessSampleAt =
    nil



------------------------------------------------------------
-- ÉCRAN
------------------------------------------------------------

obj.savedScreenBrightness =
    nil


obj.savedScreenId =
    nil


obj.screenBrightnessModified =
    false



------------------------------------------------------------
-- LOW POWER MODE
------------------------------------------------------------

obj.savedLowPowerBattery =
    nil


obj.savedLowPowerAC =
    nil


obj.lowPowerBatteryModified =
    false


obj.lowPowerACModified =
    false

obj.shutdownGuardInstalled =
    false


obj.lastPendingRestoreSignature =
    nil


obj.toastCanvas =
    nil


obj.toastTimer =
    nil


obj.automaticLowPowerHandled =
    false



------------------------------------------------------------
-- BULLE DE NOTIFICATION
------------------------------------------------------------

function obj:toastColors()

    local dark =
        false


    local ok,
          style =
        pcall(hs.host.interfaceStyle)


    if ok
        and style == "Dark" then

        dark = true

    end


    if dark then

        return {
            background = { red = 0.16, green = 0.16, blue = 0.18, alpha = 0.95 },
            border     = { white = 1, alpha = 0.14 },
            text       = { white = 1, alpha = 0.92 },
        }

    end


    return {
        background = { red = 0.99, green = 0.99, blue = 0.99, alpha = 0.96 },
        border     = { white = 0, alpha = 0.12 },
        text       = { white = 0, alpha = 0.85 },
    }

end


-- Renvoie le coin supérieur gauche de la bulle, en gardant l'ensemble
-- à l'intérieur de l'écran.

function obj:toastPosition(width)

    local anchorX,
          anchorY


    --------------------------------------------------------
    -- Sous l'icône quand elle est dans la barre des menus.
    -- frame() ne répond pas si l'objet en a été retiré.
    --------------------------------------------------------

    if self.menuBar then

        local ok,
              frame =
            pcall(
                function()

                    return self.menuBar:frame()

                end
            )


        if ok
            and frame
            and frame.w then

            anchorX =
                frame.x
                + (frame.w / 2)
                - (width / 2)


            anchorY =
                frame.y
                + frame.h
                + self.toastGap

        end

    end


    local screen =
        hs.screen.mainScreen()


    if not screen then

        return anchorX or 0,
            anchorY or 0

    end


    local usable =
        screen:frame()


    local full =
        screen:fullFrame()


    --------------------------------------------------------
    -- Sans icône : sous le coin haut droit.
    --------------------------------------------------------

    if not anchorX then

        anchorX =
            usable.x
            + usable.w
            - width
            - self.toastScreenMargin


        anchorY =
            usable.y
            + self.toastGap

    end


    --------------------------------------------------------
    -- Une icône proche du bord droit pousserait la bulle hors
    -- de l'écran.
    --------------------------------------------------------

    local minX =
        full.x
        + self.toastScreenMargin


    local maxX =
        full.x
        + full.w
        - width
        - self.toastScreenMargin


    if anchorX > maxX then

        anchorX = maxX

    end


    if anchorX < minX then

        anchorX = minX

    end


    return anchorX,
        anchorY

end


function obj:hideToast()

    if self.toastTimer then

        self.toastTimer:stop()


        self.toastTimer =
            nil

    end


    if self.toastCanvas then

        self.toastCanvas:delete(
            self.toastFadeDuration
        )


        self.toastCanvas =
            nil

    end


    return self

end


function obj:showToast(message)

    message =
        tostring(message or "")


    if message == "" then

        return self

    end


    local colors =
        self:toastColors()


    local styled =
        hs.styledtext.new(

            message,

            {
                font = {
                    name = ".AppleSystemUIFont",
                    size = self.toastFontSize,
                },

                color = colors.text,

                paragraphStyle = {
                    alignment = "center",
                },
            }

        )


    local measured =
        hs.drawing.getTextDrawingSize(styled)
        or { w = 140, h = 16 }


    local width =
        math.min(
            math.ceil(measured.w) + self.toastPaddingX * 2,
            self.toastMaxWidth
        )


    local height =
        math.ceil(measured.h) + self.toastPaddingY * 2


    local x,
          y =
        self:toastPosition(width)


    --------------------------------------------------------
    -- Une seule bulle à la fois : un nouveau message remplace
    -- le précédent au lieu d'empiler.
    --------------------------------------------------------

    self:hideToast()


    local canvas =
        hs.canvas.new({
            x = x,
            y = y,
            w = width,
            h = height,
        })


    if not canvas then

        return self

    end


    canvas:appendElements(

        {
            type = "rectangle",
            action = "strokeAndFill",
            fillColor = colors.background,
            strokeColor = colors.border,
            strokeWidth = 1,
            roundedRectRadii = {
                xRadius = self.toastCornerRadius,
                yRadius = self.toastCornerRadius,
            },
        },

        {
            type = "text",
            text = styled,
            frame = {
                x = self.toastPaddingX,
                y = self.toastPaddingY,
                w = width - self.toastPaddingX * 2,
                h = height - self.toastPaddingY * 2,
            },
        }

    )


    canvas:level(
        hs.canvas.windowLevels.overlay
    )


    -- Visible sur tous les Spaces, et ne suit pas les changements
    -- de bureau : la bulle doit se comporter comme la barre des
    -- menus au-dessus de laquelle elle s'affiche.

    canvas:behaviorAsLabels({
        "canJoinAllSpaces",
        "stationary",
    })


    -- Ne jamais voler le focus à l'application en cours.

    canvas:clickActivating(false)


    canvas:show(
        self.toastFadeDuration
    )


    self.toastCanvas =
        canvas


    self.toastTimer =
        hs.timer.doAfter(

            self.toastDuration,

            function()

                self.toastTimer =
                    nil


                self:hideToast()

            end

        )


    return self

end



------------------------------------------------------------
-- LOG
------------------------------------------------------------

function obj:log(message)

    print(

        string.format(

            "%s - ActivityKeeper %s - %s",

            os.date(
                "%Y-%m-%d %H:%M:%S"
            ),

            self.version,

            tostring(message)

        )

    )

end



------------------------------------------------------------
-- TEMPS HAUTE PRÉCISION
------------------------------------------------------------

function obj:now()

    return hs.timer.secondsSinceEpoch()

end



------------------------------------------------------------
-- FORMAT DURÉE
------------------------------------------------------------

function obj:formatDuration(seconds)

    seconds =
        math.floor(
            seconds or 0
        )


    if seconds < 60 then

        return string.format(
            "%d sec",
            seconds
        )

    end


    if seconds < 3600 then

        return string.format(

            "%d min %02d sec",

            math.floor(
                seconds / 60
            ),

            seconds % 60

        )

    end


    return string.format(

        "%d h %02d min",

        math.floor(
            seconds / 3600
        ),

        math.floor(

            (seconds % 3600)
            /
            60

        )

    )

end



------------------------------------------------------------
-- SETTINGS BOOLÉENS
------------------------------------------------------------

function obj:getBooleanSetting(
    key,
    defaultValue
)

    local value =
        hs.settings.get(key)


    if value == nil then

        return defaultValue == true

    end


    return value == true

end



function obj:setBooleanSetting(
    key,
    value,
    label
)

    hs.settings.set(

        key,

        value == true

    )


    self:log(

        string.format(

            "%s : %s",

            label,

            value
                and "ON"
                or "OFF"

        )

    )


    self:showToast(

        (
            value
            and "✓ "
            or "✕ "
        )
        ..
        label

    )


    return value

end


function obj:applyConfiguredModeDefaults()

    if not self.forceConfiguredModesOnStart then

        return self

    end


    hs.settings.set(
        self.SETTING_KEYS.USER_ACTIVITY,
        self.defaultUserActivityEnabled == true
    )


    hs.settings.set(
        self.SETTING_KEYS.KEYBOARD,
        self.defaultKeyboardEnabled == true
    )


    hs.settings.set(
        self.SETTING_KEYS.MOUSE,
        self.defaultMouseEnabled == true
    )


    return self

end



------------------------------------------------------------
-- LECTURE DES MODES
------------------------------------------------------------

function obj:isUserActivityEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.USER_ACTIVITY,

        self.defaultUserActivityEnabled

    )

end



function obj:isKeyboardEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.KEYBOARD,

        self.defaultKeyboardEnabled

    )

end



function obj:isMouseEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.MOUSE,

        self.defaultMouseEnabled

    )

end



function obj:isKeyboardBacklightEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.KEYBOARD_BACKLIGHT,

        self.defaultKeyboardBacklightEnabled

    )

end



function obj:isScreenDimmingEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.SCREEN_DIMMING,

        self.defaultScreenDimmingEnabled

    )

end



function obj:isLowPowerModeEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.LOW_POWER,

        self.defaultLowPowerModeEnabled

    )

end


function obj:isAutomaticLowPowerModeEnabled()

    return self:getBooleanSetting(

        self.SETTING_KEYS.AUTOMATIC_LOW_POWER,

        self.defaultAutomaticLowPowerModeEnabled

    )

end


function obj:getLowPowerBatteryThreshold()

    return math.max(
        0,
        math.min(
            100,
            tonumber(
                self.lowPowerBatteryThreshold
            )
            or 30
        )
    )

end



------------------------------------------------------------
-- IDLE MACOS
------------------------------------------------------------

function obj:getIdleTime()

    local success,
          result =

        pcall(
            hs.host.idleTime
        )


    -- Renvoyer 0 signifierait "l'utilisateur vient d'agir", ce qui
    -- ferait sortir du mode vert et restaurer les economies d'energie
    -- sur une simple erreur de lecture. nil laisse l'appelant decider.

    if not success then

        self:log(
            "ERREUR hs.host.idleTime()"
        )


        return nil

    end


    return result

end



------------------------------------------------------------
-- LABEL ÉTAT
------------------------------------------------------------

function obj:getStateLabel()

    if self.currentState == self.STATE.OFF then

        return "Désactivé"

    end


    if self.currentState == self.STATE.MONITORING then

        return "Surveillance active"

    end


    if self.currentState == self.STATE.KEEPALIVE then

        return "Maintien actif"

    end


    return "Inconnu"

end



------------------------------------------------------------
-- ICÔNE MENUBAR COMPACTE
--
-- ●AK gris
-- ●AK jaune
-- ●AK vert
------------------------------------------------------------

function obj:updateMenuBar()

    if not self.menuBar then

        return

    end


    local color

    local tooltip


    --------------------------------------------------------
    -- OFF
    --------------------------------------------------------

    if self.currentState == self.STATE.OFF then

        color = {

            red = 0.55,

            green = 0.55,

            blue = 0.55,

            alpha = 1.0

        }


        tooltip =
            "Activity Keeper désactivé"


    --------------------------------------------------------
    -- MONITORING
    --------------------------------------------------------

    elseif self.currentState == self.STATE.MONITORING then

        color = {

            red = 1.0,

            green = 0.75,

            blue = 0.0,

            alpha = 1.0

        }


        tooltip =
            "Activity Keeper actif - surveillance"


    --------------------------------------------------------
    -- KEEPALIVE
    --------------------------------------------------------

    elseif self.currentState == self.STATE.KEEPALIVE then

        color = {

            red = 0.15,

            green = 0.75,

            blue = 0.25,

            alpha = 1.0

        }


        tooltip =
            "Activity Keeper - maintien actif"


    --------------------------------------------------------
    -- INCONNU
    --------------------------------------------------------

    else

        color = {

            red = 0.55,

            green = 0.55,

            blue = 0.55,

            alpha = 1.0

        }


        tooltip =
            "Activity Keeper - état inconnu"

    end


    self.menuBar:setTitle(

        hs.styledtext.new(

            "●AK",

            {
                color = color
            }

        )

    )


    self.menuBar:setTooltip(
        tooltip
    )

end



------------------------------------------------------------
-- CHANGEMENT D'ÉTAT
------------------------------------------------------------

function obj:setState(newState)

    if self.currentState == newState then

        self:updateMenuBar()

        return

    end


    local oldState =
        self.currentState


    self.currentState =
        newState


    if newState == self.STATE.KEEPALIVE then

        self.keepaliveEnteredAt =
            os.time()


        self:startFastReturnWatcher()

        self:suspendInputWatcher()

        self:startKeepaliveExitWatch()

    else

        self.keepaliveEnteredAt =
            nil


        self:stopKeepaliveExitWatch()

        self:stopFastReturnWatcher()


        -- Uniquement MONITORING : en OFF c'est disable() qui a déjà
        -- arrêté le watcher, le relancer ici le ferait survivre.

        if newState == self.STATE.MONITORING then

            self:resumeInputWatcher()

        end

    end


    self:updateMenuBar()


    self:log(

        string.format(

            "État : %s -> %s",

            oldState,

            newState

        )

    )


    if not self.showStateNotifications then

        return

    end


    if newState == self.STATE.MONITORING then

        self:showToast(
            "Activity Keeper : surveillance"
        )


    elseif newState == self.STATE.KEEPALIVE then

        self:showToast(
            "Activity Keeper : maintien actif"
        )


    elseif newState == self.STATE.OFF then

        self:showToast(
            "Activity Keeper : OFF"
        )

    end

end



------------------------------------------------------------
-- FENÊTRE ANTI-DÉTECTION ÉVÉNEMENTS SYNTHÉTIQUES
------------------------------------------------------------

function obj:isSyntheticEventWindow()

    return

        self:now()
        <=
        self.syntheticEventIgnoreUntil

end



-- Referme la fenetre au plus tot : on ne garde que le temps de vol.
-- Ne l'allonge jamais.

-- Appose la marque et renvoie l'evenement, pour chainer avec :post().

function obj:markSynthetic(event)

    if not event then

        return event

    end


    self.lastSyntheticAt =
        os.time()


    pcall(function()

        event:setProperty(
            hs.eventtap.event.properties.eventSourceUserData,
            self.syntheticMark
        )

    end)


    return event

end


-- Vrai si cet evenement porte notre marque. Le constater vaut preuve
-- que le mecanisme fonctionne : on le retient.

function obj:isOurEvent(event)

    if not event then

        return false

    end


    local ok,
          valeur =
        pcall(function()

            return event:getProperty(
                hs.eventtap.event.properties.eventSourceUserData
            )

        end)


    if not ok or valeur ~= self.syntheticMark then

        return false

    end


    if not self.syntheticMarkWorks then

        self.syntheticMarkWorks =
            true


        self:log(
            "Marquage des evenements synthetiques confirme :"
            .. " ils sont reconnus a coup sur, sans fenetre de temps"
        )

    end


    return true

end


function obj:closeSyntheticEventWindow()

    -- Sans la preuve que la marque fonctionne, la fenetre reste
    -- entiere : la raccourcir laisserait passer nos propres evenements
    -- en retard, et ActivityKeeper sortirait du vert en se prenant
    -- lui-meme pour l'utilisateur.

    if not self.syntheticMarkWorks then

        return self

    end


    local cible =
        self:now()
        +
        (tonumber(self.syntheticEventSettleDelay) or 0.15)


    if cible < self.syntheticEventIgnoreUntil then

        self.syntheticEventIgnoreUntil =
            cible

    end


    return self

end


function obj:openSyntheticEventWindow()

    self.syntheticEventIgnoreUntil =

        self:now()
        +
        self.syntheticEventGracePeriod

end



------------------------------------------------------------
-- ACTIVITÉ UTILISATEUR RÉELLE
------------------------------------------------------------

-- dejaVerifie : l'appelant a deja ecarte la fenetre synthetique a
-- l'instant ou l'evenement est arrive. Refaire le test plus tard
-- risquerait de tomber dans une fenetre ouverte entre-temps par notre
-- propre keep-alive, et d'ignorer une vraie frappe.

-- origine : d'ou vient la conclusion. Cinq chemins peuvent faire
-- sortir du vert, et le journal ne disait pas lequel avait parle. Sans
-- cela, une sortie intempestive est indiagnosticable.

function obj:handleRealUserActivity(dejaVerifie, origine)

    if self.currentState == self.STATE.OFF then

        return

    end


    if not dejaVerifie
        and self:isSyntheticEventWindow() then

        return

    end


    self.lastRealActivityTime =
        os.time()


    --------------------------------------------------------
    -- Pas d'échantillonnage du rétroéclairage ici.
    --
    -- Cette fonction est appelée depuis le callback d'un eventtap,
    -- donc dans le chemin de livraison des événements clavier et
    -- souris. mac-brightnessctl passe par hs.execute, qui est
    -- bloquant (~10 ms mesurés) : une frappe serait retardée.
    --
    -- La lecture n'apporterait rien de toute façon :
    --   - en KEEPALIVE le rétroéclairage vient d'être mis à zéro par
    --     nos soins, et seules les valeurs > 0,01 sont mémorisées ;
    --   - en MONITORING, checkIdleState échantillonne déjà toutes les
    --     checkInterval secondes.
    --------------------------------------------------------


    --------------------------------------------------------
    -- VERT -> JAUNE
    --------------------------------------------------------

    if self.currentState == self.STATE.KEEPALIVE then

        self:log(
            "Activité utilisateur réelle détectée"
            .. " (origine : "
            .. tostring(origine or "inconnue")
            .. ", inactivité "
            .. string.format("%.1f", hs.host.idleTime() or -1)
            .. " s)"
        )


        ----------------------------------------------------
        -- Restaurer les états énergétiques
        ----------------------------------------------------

        self:restoreEnergySavingState()


        ----------------------------------------------------
        -- Retour monitoring
        ----------------------------------------------------

        self:setState(
            self.STATE.MONITORING
        )

    end

end



------------------------------------------------------------
-- SORTIR LE TRAVAIL DU CHEMIN DES ÉVÉNEMENTS
--
-- Un eventtap fait passer chaque frappe et chaque clic par le thread
-- principal de Hammerspoon, et macOS attend la réponse avant de livrer
-- l'événement. Au-delà du délai qu'il accorde, il désactive le tap.
--
-- Or handleRealUserActivity restaure les états énergétiques :
-- restoreKeyboardAutoBrightness et restoreKeyboardBacklight passent par
-- mac-brightnessctl, restoreLowPowerMode par « sudo pmset » -- tous par
-- hs.execute, qui est bloquant. Le commentaire de handleRealUserActivity
-- mesurait déjà 10 ms pour UN appel, et refusait pour cette raison d'y
-- échantillonner le rétroéclairage. La restauration, elle, en enchaîne
-- plusieurs, dont un sudo.
--
-- Pendant tout ce temps aucune frappe n'était transmise -- et c'est
-- précisément l'instant où l'utilisateur recommence à taper, donc
-- l'instant où il perd des touches.
--
-- Le tap rend désormais la main tout de suite ; le travail se fait au
-- tour de boucle suivant.
------------------------------------------------------------

-- Vrai si l'horloge d'inactivite de macOS est plus recente que notre
-- dernier evenement synthetique : quelqu'un d'autre que nous a agi.
--
-- Reference : le dernier keep-alive, ou a defaut l'entree en KEEPALIVE
-- tant qu'aucun n'a ete envoye. Sans cette seconde borne, une session
-- fraichement passee au vert verrait "aucun keep-alive, donc reference
-- a l'epoque" et conclurait aussitot a une activite.

function obj:realActivitySinceOurLastEvent()

    if self.currentState ~= self.STATE.KEEPALIVE then

        return false

    end


    -- Le plus recent de nos propres instants : entree dans le vert,
    -- dernier keep-alive, et dernier evenement emis quel qu'il soit.
    -- Omettre le troisieme faisait prendre nos touches de
    -- retroeclairage pour l'utilisateur.

    local reference =
        math.max(
            tonumber(self.lastKeepAliveTime) or 0,
            tonumber(self.keepaliveEnteredAt) or 0,
            tonumber(self.lastSyntheticAt) or 0
        )


    if reference <= 0 then

        return false

    end


    local marge =
        tonumber(self.keepaliveExitMargin) or 2


    local depuis =
        os.time() - reference


    if depuis <= marge then

        return false

    end


    local idle =
        hs.host.idleTime()


    if type(idle) ~= "number" then

        return false

    end


    return idle < (depuis - marge)

end


function obj:checkKeepaliveExit()

    if not self:realActivitySinceOurLastEvent() then

        return self

    end


    self:log(
        string.format(
            "Retour utilisateur deduit : inactivite %.1f s, notre"
            .. " dernier evenement remonte a %d s",
            hs.host.idleTime(),
            os.time() - math.max(
                tonumber(self.lastKeepAliveTime) or 0,
                tonumber(self.keepaliveEnteredAt) or 0
            )
        )
    )


    self:handleRealUserActivity(true, "inference")


    return self

end


function obj:startKeepaliveExitWatch()

    self:stopKeepaliveExitWatch()


    local intervalle =
        tonumber(self.keepaliveExitCheckInterval) or 1


    if intervalle <= 0 then

        return self

    end


    self.keepaliveExitTimer =
        hs.timer.doEvery(
            intervalle,
            function()

                self:checkKeepaliveExit()

            end
        )


    return self

end


function obj:stopKeepaliveExitWatch()

    if self.keepaliveExitTimer then

        self.keepaliveExitTimer:stop()


        self.keepaliveExitTimer =
            nil

    end


    return self

end


function obj:deferRealUserActivity(origine)

    if self.realActivityPending then

        return self

    end


    self.realActivityPending =
        true


    hs.timer.doAfter(
        0,
        function()

            self.realActivityPending =
                false


            self:handleRealUserActivity(true, origine)

        end
    )


    return self

end



------------------------------------------------------------
-- WATCHER D'ACTIVITÉ RÉELLE
------------------------------------------------------------

function obj:createInputWatcher()

    if self.inputWatcher then

        return

    end


    local eventTypes = {

        hs.eventtap.event.types.keyDown,

        hs.eventtap.event.types.flagsChanged,

        hs.eventtap.event.types.leftMouseDown,

        hs.eventtap.event.types.rightMouseDown,

        hs.eventtap.event.types.otherMouseDown,

        hs.eventtap.event.types.scrollWheel

    }


    if self.trackHighFrequencyPointerEvents then

        table.insert(
            eventTypes,
            hs.eventtap.event.types.mouseMoved
        )


        table.insert(
            eventTypes,
            hs.eventtap.event.types.leftMouseDragged
        )


        table.insert(
            eventTypes,
            hs.eventtap.event.types.rightMouseDragged
        )


        table.insert(
            eventTypes,
            hs.eventtap.event.types.otherMouseDragged
        )

    end


    self.inputWatcher =

        hs.eventtap.new(

            eventTypes,

            function(event)

                if self.currentState == self.STATE.OFF then

                    return false

                end


                if self.currentState == self.STATE.KEEPALIVE
                    and self.fastReturnWatcherEnabled then


                    return false

                end


                -- Notre propre evenement, reconnu a sa marque. Aucune
                -- supposition de temps : meme arrive en retard, il ne
                -- sera jamais pris pour l'utilisateur.

                if self:isOurEvent(event) then

                    return false

                end


                if self:isSyntheticEventWindow() then

                    return false

                end


                self:deferRealUserActivity("tap ordinaire")


                return false

            end

        )

end



------------------------------------------------------------
-- WATCHER RAPIDE DE RETOUR UTILISATEUR
--
-- Actif uniquement en KEEPALIVE pour retrouver une reprise
-- immédiate sans ralentir le mode MONITORING.
------------------------------------------------------------

function obj:createFastReturnWatcher()

    if self.fastReturnWatcher then

        return

    end


    local eventTypes = {

        hs.eventtap.event.types.keyDown,

        hs.eventtap.event.types.flagsChanged,

        hs.eventtap.event.types.leftMouseDown,

        hs.eventtap.event.types.rightMouseDown,

        hs.eventtap.event.types.otherMouseDown,

        hs.eventtap.event.types.mouseMoved,

        hs.eventtap.event.types.leftMouseDragged,

        hs.eventtap.event.types.rightMouseDragged,

        hs.eventtap.event.types.otherMouseDragged,

        hs.eventtap.event.types.scrollWheel

    }


    self.fastReturnWatcher =

        hs.eventtap.new(

            eventTypes,

            function(event)

                if self.currentState
                    ~= self.STATE.KEEPALIVE then


                    return false

                end


                -- Notre propre evenement, reconnu a sa marque. C'est ce
                -- qui manquait : la fenetre de temps laissait passer
                -- ceux qui arrivaient en retard, et ActivityKeeper
                -- sortait du vert en se prenant pour l'utilisateur.

                if self:isOurEvent(event) then

                    return false

                end


                if self:isSyntheticEventWindow() then

                    return false

                end


                local now =
                    self:now()


                if now - self.lastFastReturnEventAt
                    < self.fastReturnThrottle then


                    return false

                end


                self.lastFastReturnEventAt =
                    now


                self:deferRealUserActivity("tap rapide")


                return false

            end

        )

end


function obj:suspendInputWatcher()

    --------------------------------------------------------
    -- En KEEPALIVE, fastReturnWatcher écoute tous les types
    -- d'événements de inputWatcher, et davantage. Le callback de
    -- ce dernier commence d'ailleurs par ressortir sans rien faire.
    -- Laisser les deux actifs fait traverser deux taps système à
    -- chaque événement pour aucun gain.
    --
    -- Quand fastReturnWatcherEnabled est faux, inputWatcher reste au
    -- contraire le seul détecteur : on n'y touche pas.
    --------------------------------------------------------

    if not self.fastReturnWatcherEnabled then

        return self

    end


    if self.inputWatcher then

        self.inputWatcher:stop()

    end


    return self

end


function obj:resumeInputWatcher()

    if self.currentState == self.STATE.OFF then

        return self

    end


    self:createInputWatcher()


    if self.inputWatcher then

        self.inputWatcher:start()

    end


    return self

end


function obj:startFastReturnWatcher()

    if not self.fastReturnWatcherEnabled then

        return

    end


    self:createFastReturnWatcher()


    if self.fastReturnWatcher then

        self.fastReturnWatcher:start()

    end

end


function obj:stopFastReturnWatcher()

    if self.fastReturnWatcher then

        self.fastReturnWatcher:stop()

    end

end



------------------------------------------------------------
-- USER ACTIVITY
------------------------------------------------------------

function obj:sendUserActivity()

    if not self:isUserActivityEnabled() then

        return false

    end


    local success,
          errorMessage =

        pcall(

            function()

                self.userActivityAssertionId =

                    hs.caffeinate.declareUserActivity(

                        self.userActivityAssertionId

                    )

            end

        )


    if not success then

        self:log(

            "ERREUR UserActivity : "
            ..
            tostring(errorMessage)

        )


        return false

    end


    return true

end



------------------------------------------------------------
-- TOUCHE SYNTHÉTIQUE
------------------------------------------------------------

-- Relache la touche d'activite si elle est encore enfoncee.
--
-- postActivityKey envoie un appui puis programme le relachement 50 ms
-- plus tard. Si ce minuteur est annule sans etre joue -- desactivation
-- du Spoon, arret, rechargement de Hammerspoon -- la touche reste
-- logiquement enfoncee pour tout le systeme. Avec Maj, tout ce que
-- l'utilisateur tape passe en majuscules jusqu'a ce qu'il appuie
-- lui-meme dessus.

function obj:releaseActivityKey()

    if self.keyUpTimer then

        self.keyUpTimer:stop()


        self.keyUpTimer =
            nil

    end


    if not self.activityKeyDown then

        return false

    end


    self.activityKeyDown =
        false


    local success,
          errorMessage =

        pcall(

            function()

                self:markSynthetic(

                    hs.eventtap.event.newKeyEvent(

                        {},

                        self.activityKey,

                        false

                    )

                ):post()

            end

        )


    if not success then

        self:log(

            "ERREUR relâchement "
            ..
            tostring(self.activityKey)
            ..
            " : "
            ..
            tostring(errorMessage)

        )


        return false

    end


    return true

end


function obj:postActivityKey()

    self:openSyntheticEventWindow()


    local success,
          errorMessage =

        pcall(

            function()

                ------------------------------------------------
                -- DOWN
                ------------------------------------------------

                self:markSynthetic(

                    hs.eventtap.event.newKeyEvent(

                        {},

                        self.activityKey,

                        true

                    )

                ):post()


                self.activityKeyDown =
                    true


                ------------------------------------------------
                -- UP différé
                ------------------------------------------------

                self.keyUpTimer =

                    hs.timer.doAfter(

                        self.keyPressDuration,

                        function()

                            self:releaseActivityKey()


                            -- La sequence clavier est finie : plus la
                            -- peine d'ignorer l'utilisateur.

                            self:closeSyntheticEventWindow()

                        end

                    )

            end

        )


    if not success then

        self:log(

            "ERREUR touche "
            ..
            tostring(self.activityKey)
            ..
            " : "
            ..
            tostring(errorMessage)

        )


        return false

    end


    return true

end



------------------------------------------------------------
-- ACTIVITÉ CLAVIER
------------------------------------------------------------

function obj:sendKeyboardActivity()

    if not self:isKeyboardEnabled() then

        return false

    end


    return self:postActivityKey()

end



------------------------------------------------------------
-- ACTIVITÉ SOURIS
------------------------------------------------------------

function obj:sendMouseActivity()

    if not self:isMouseEnabled() then

        return false

    end


    self:openSyntheticEventWindow()


    local originalPosition =
        hs.mouse.absolutePosition()


    if not originalPosition then

        self:log(
            "Position souris inaccessible"
        )


        return false

    end


    local temporaryPosition = {

        x =
            originalPosition.x
            +
            self.mouseMovePixels,

        y =
            originalPosition.y

    }


    local success,
          errorMessage =

        pcall(

            function()

                ------------------------------------------------
                -- Aller
                ------------------------------------------------

                self:markSynthetic(

                    hs.eventtap.event.newMouseEvent(

                        hs.eventtap.event.types.mouseMoved,

                        temporaryPosition

                    )

                ):post()


                hs.mouse.absolutePosition(
                    temporaryPosition
                )


                ------------------------------------------------
                -- Ou le curseur a-t-il REELLEMENT atterri.
                --
                -- On demande original.x + 1. Au bord droit de
                -- l'ecran, macOS ramene le curseur a sa place :
                -- il n'atteint jamais temporaryPosition. Comparer
                -- a la position DEMANDEE faisait alors conclure a
                -- chaque keep-alive que l'utilisateur avait bouge
                -- la souris.
                ------------------------------------------------

                local positionAtteinte =
                    hs.mouse.absolutePosition()
                    or temporaryPosition


                -- Le deplacement a-t-il eu lieu ? Sinon ce signal
                -- ne prouve plus rien et on s'interdit de s'en
                -- servir.

                local deplacementEffectif =
                    math.abs(
                        positionAtteinte.x - originalPosition.x
                    ) > 0.5
                    or math.abs(
                        positionAtteinte.y - originalPosition.y
                    ) > 0.5


                ------------------------------------------------
                -- Retour
                ------------------------------------------------

                if self.returnMouseTimer then

                    self.returnMouseTimer:stop()

                end


                self.returnMouseTimer =

                    hs.timer.doAfter(

                        self.mouseReturnDelay,

                        function()

                            self.returnMouseTimer =
                                nil


                            ------------------------------------
                            -- Si le curseur n'est plus la ou
                            -- nous l'avons laisse, l'utilisateur
                            -- l'a bouge entre-temps : le ramener
                            -- le teleporterait en arriere.
                            ------------------------------------

                            local currentPosition =
                                hs.mouse.absolutePosition()


                            if not currentPosition
                                or math.abs(
                                    currentPosition.x
                                    - positionAtteinte.x
                                ) > 1
                                or math.abs(
                                    currentPosition.y
                                    - positionAtteinte.y
                                ) > 1 then


                                self:closeSyntheticEventWindow()


                                -- Le curseur n'est plus ou nous l'avons
                                -- laisse : personne d'autre n'a pu le
                                -- bouger. Mais seulement si nous l'avons
                                -- vraiment deplace : un deplacement
                                -- refuse par macOS laisse le curseur ou
                                -- il etait, ce qui n'apprend rien.

                                if deplacementEffectif then

                                    self:deferRealUserActivity("souris deplacee")

                                end


                                return

                            end


                            self:markSynthetic(

                                hs.eventtap.event.newMouseEvent(

                                    hs.eventtap.event.types.mouseMoved,

                                    originalPosition

                                )

                            ):post()


                            hs.mouse.absolutePosition(
                                originalPosition
                            )


                            self:closeSyntheticEventWindow()

                        end

                    )

            end

        )


    if not success then

        self:log(

            "ERREUR souris : "
            ..
            tostring(errorMessage)

        )


        return false

    end


    return true

end



------------------------------------------------------------
-- DÉTECTION MAC-BRIGHTNESSCTL
------------------------------------------------------------

function obj:detectKeyboardBrightnessTool()

    self.keyboardBrightnessTool =
        nil


    self.keyboardBrightnessBackend =
        "fallback"


    for _, path
        in ipairs(self.keyboardBrightnessToolPaths) do


        local attributes =
            hs.fs.attributes(path)


        if attributes
            and attributes.mode == "file" then


            self.keyboardBrightnessTool =
                path


            self.keyboardBrightnessBackend =
                "mac-brightnessctl"


            self:log(

                "Backend backlight précis : "
                ..
                path

            )


            return path

        end

    end


    self:log(
        "Backend backlight : fallback Hammerspoon"
    )


    return nil

end



------------------------------------------------------------
-- LABEL BACKEND
------------------------------------------------------------

function obj:getKeyboardBacklightBackendLabel()

    if self.keyboardBrightnessBackend
        == "mac-brightnessctl" then


        return "mac-brightnessctl"

    end


    return "Hammerspoon fallback"

end



------------------------------------------------------------
-- EXÉCUTION MAC-BRIGHTNESSCTL
------------------------------------------------------------

function obj:runBrightnessTool(argument)

    if not self.keyboardBrightnessTool then

        return nil,
            false

    end


    local command =
        self:shellQuote(
            self.keyboardBrightnessTool
        )


    if argument ~= nil then

        command =
            command
            ..
            " "
            ..
            tostring(argument)

    end


    local output,
          success,
          terminationType,
          returnCode =

        hs.execute(

            command,

            false

        )


    if not success then

        self:log(

            "ERREUR mac-brightnessctl : "
            ..
            tostring(terminationType)
            ..
            " / "
            ..
            tostring(returnCode)
            ..
            " / "
            ..
            tostring(output)

        )

    end


    return output,
        success

end



------------------------------------------------------------
-- LECTURE BACKLIGHT CLAVIER
------------------------------------------------------------

function obj:getKeyboardBrightness()

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return nil

    end


    local output,
          success =

        self:runBrightnessTool(nil)


    if not success then

        return nil

    end


    --------------------------------------------------------
    -- Parse explicite :
    --
    -- Current brightness: 0.19
    --------------------------------------------------------

    local valueString =

        tostring(output):match(

            "Current%s+brightness:%s*([0-9]+%.?[0-9]*)"

        )


    if not valueString then

        self:log(

            "Sortie brightness non reconnue : "
            ..
            tostring(output)

        )


        return nil

    end


    return tonumber(
        valueString
    )

end



------------------------------------------------------------
-- MÉMORISER UNE VALEUR NON NULLE
------------------------------------------------------------

function obj:sampleKeyboardBrightness(force)

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return

    end


    local now =
        self:now()


    if force ~= true
        and self.lastKeyboardBrightnessSampleAt
        and now - self.lastKeyboardBrightnessSampleAt
            < self.keyboardBrightnessSampleInterval then


        return

    end


    self.lastKeyboardBrightnessSampleAt =
        now


    local value =
        self:getKeyboardBrightness()


    if value
        and value > 0.01 then


        self.lastKnownNonZeroKeyboardBrightness =
            value


        if self.verboseLogging then

            self:log(

                string.format(

                    "Référence clavier : %.4f",

                    value

                )

            )

        end

    end

end



------------------------------------------------------------
-- FIXER BACKLIGHT CLAVIER
------------------------------------------------------------

function obj:setKeyboardBrightness(value)

    value =
        tonumber(value)


    if value == nil then

        return false

    end


    value =

        math.max(

            0,

            math.min(
                1,
                value
            )

        )


    local _,
          success =

        self:runBrightnessTool(

            string.format(
                "%.4f",
                value
            )

        )


    return success

end


------------------------------------------------------------
-- AUTO-BRIGHTNESS CLAVIER
------------------------------------------------------------

function obj:getKeyboardAutoBrightness()

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return nil

    end


    local output,
          success =

        self:runBrightnessTool("-a")


    if not success then

        return nil

    end


    output =
        tostring(output or "")


    if output:match("Enabled") then

        return true

    end


    if output:match("Disabled") then

        return false

    end


    self:log(

        "Sortie auto-brightness non reconnue : "
        ..
        output

    )


    return nil

end


function obj:setKeyboardAutoBrightness(enabled)

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return false

    end


    local _,
          success =

        self:runBrightnessTool(

            enabled
                and "-a 1"
                or "-a 0"

        )


    return success

end


function obj:disableKeyboardAutoBrightness()

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return false

    end


    if self.keyboardAutoBrightnessModified then

        return true

    end


    local current =
        self:getKeyboardAutoBrightness()


    self.savedKeyboardAutoBrightness =
        current


    if current ~= true then

        self:log(
            "Auto-brightness clavier déjà désactivé ou inconnu"
        )


        return false

    end


    if self:setKeyboardAutoBrightness(false) then

        self.keyboardAutoBrightnessModified =
            true


        self:log(
            "Auto-brightness clavier désactivé temporairement"
        )


        return true

    end


    self:log(
        "Échec désactivation auto-brightness clavier"
    )


    return false

end


function obj:restoreKeyboardAutoBrightness()

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return false

    end


    if not self.keyboardAutoBrightnessModified then

        self.savedKeyboardAutoBrightness =
            nil


        return false

    end


    if self.savedKeyboardAutoBrightness == true then

        if self:setKeyboardAutoBrightness(true) then

            self:log(
                "Auto-brightness clavier restauré"
            )


            self.keyboardAutoBrightnessModified =
                false


            self.savedKeyboardAutoBrightness =
                nil


            return true

        end


        self:log(
            "Échec restauration auto-brightness clavier"
        )


        return false

    end


    self.keyboardAutoBrightnessModified =
        false


    self.savedKeyboardAutoBrightness =
        nil


    return false

end


function obj:scheduleKeyboardAutoBrightnessRestoreConfirm()

    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return self

    end


    if self.keyboardAutoRestoreTimer then

        self.keyboardAutoRestoreTimer:stop()


        self.keyboardAutoRestoreTimer =
            nil

    end


    self.keyboardAutoRestoreTimer =

        hs.timer.doAfter(

            self.keyboardAutoRestoreConfirmDelay,

            function()

                self.keyboardAutoRestoreTimer =
                    nil


                if self.currentState
                    == self.STATE.KEEPALIVE then


                    return

                end


                self:setKeyboardAutoBrightness(true)

            end

        )


    return self

end



------------------------------------------------------------
-- TOUCHE SYSTÈME
------------------------------------------------------------

function obj:sendSystemKey(keyName)

    local success,
          errorMessage =

        pcall(

            function()

                self:markSynthetic(

                    hs.eventtap.event.newSystemKeyEvent(

                        keyName,

                        true

                    )

                ):post()


                self:markSynthetic(

                    hs.eventtap.event.newSystemKeyEvent(

                        keyName,

                        false

                    )

                ):post()

            end

        )


    if not success then

        self:log(

            "ERREUR touche système "
            ..
            tostring(keyName)
            ..
            " : "
            ..
            tostring(errorMessage)

        )

    end


    return success

end



------------------------------------------------------------
-- RÉVEIL DU CLAVIER AVANT CAPTURE
------------------------------------------------------------

------------------------------------------------------------
-- CAPTURE APRÈS RÉVEIL ET EXTINCTION
------------------------------------------------------------

function obj:captureAndDisableKeyboardBacklight(
    attempt
)

    attempt =
        attempt or 1


    --------------------------------------------------------
    -- L'utilisateur est revenu entre-temps
    --------------------------------------------------------

    if self.currentState
        ~= self.STATE.KEEPALIVE then


        self:log(
            "Probe backlight annulé : sortie KEEPALIVE"
        )


        return false

    end


    --------------------------------------------------------
    -- Lecture
    --------------------------------------------------------

    local current =
        self:getKeyboardBrightness()


    self:log(

        string.format(

            "Probe clavier %d/%d : %s",

            attempt,

            self.keyboardBacklightProbeRetries,

            current
                and string.format(
                    "%.4f",
                    current
                )
                or "lecture impossible"

        )

    )


    --------------------------------------------------------
    -- VALEUR VALIDE
    --------------------------------------------------------

    if current
        and current > 0.01 then


        self.savedKeyboardBrightness =
            current


        self.lastKnownNonZeroKeyboardBrightness =
            current


        self:log(

            string.format(

                "Valeur backlight capturée : %.4f",

                current

            )

        )


        if self:setKeyboardBrightness(0) then

            self.keyboardBacklightModified =
                true


            self:log(

                string.format(

                    "Clavier éteint ; restauration prévue : %.4f",

                    current

                )

            )


            return true

        end


        self:log(
            "Échec extinction backlight clavier"
        )


        return false

    end


    --------------------------------------------------------
    -- RETRY
    --------------------------------------------------------

    if attempt
        < self.keyboardBacklightProbeRetries then


        self.keyboardBacklightProbeRetryTimer =

            hs.timer.doAfter(

                self.keyboardBacklightProbeRetryInterval,

                function()

                    self.keyboardBacklightProbeRetryTimer =
                        nil


                    self:captureAndDisableKeyboardBacklight(

                        attempt + 1

                    )

                end

            )


        return true

    end


    --------------------------------------------------------
    -- FALLBACK DERNIÈRE BONNE VALEUR
    --------------------------------------------------------

    if self.lastKnownNonZeroKeyboardBrightness then

        self.savedKeyboardBrightness =
            self.lastKnownNonZeroKeyboardBrightness


        self:log(

            string.format(

                "Fallback référence précédente : %.4f",

                self.savedKeyboardBrightness

            )

        )


        if self:setKeyboardBrightness(0) then

            self.keyboardBacklightModified =
                true


            return true

        end

    end


    --------------------------------------------------------
    -- AUCUNE VALEUR FIABLE
    --
    -- On ne coupe pas le clavier pour éviter de ne pas
    -- savoir le restaurer correctement.
    --------------------------------------------------------

    self:log(

        "Aucune valeur backlight fiable ; "
        ..
        "extinction annulée"

    )


    return false

end



------------------------------------------------------------
-- DÉSACTIVER BACKLIGHT CLAVIER
------------------------------------------------------------

function obj:disableKeyboardBacklight()

    if not self:isKeyboardBacklightEnabled() then

        return false

    end


    if self.keyboardBacklightModified then

        return true

    end


    --------------------------------------------------------
    -- BACKEND PRÉCIS
    --------------------------------------------------------

    if self.keyboardBrightnessBackend
        == "mac-brightnessctl" then


        ----------------------------------------------------
        -- Nettoyage ancien probe
        ----------------------------------------------------

        if self.keyboardBacklightProbeTimer then

            self.keyboardBacklightProbeTimer:stop()


            self.keyboardBacklightProbeTimer =
                nil

        end


        if self.keyboardBacklightProbeRetryTimer then

            self.keyboardBacklightProbeRetryTimer:stop()


            self.keyboardBacklightProbeRetryTimer =
                nil

        end


        ----------------------------------------------------
        -- Capture directe sans réveiller le clavier.
        --
        -- Réveiller par une touche allume le rétroéclairage alors
        -- qu'on vient justement d'entrer en KEEPALIVE.
        ----------------------------------------------------

        return self:captureAndDisableKeyboardBacklight(
            1
        )

    end


    --------------------------------------------------------
    -- FALLBACK HAMMERSPOON
    --------------------------------------------------------

    local success =

        self:sendSystemKey(
            "ILLUMINATION_TOGGLE"
        )


    if success then

        self.keyboardBacklightModified =
            true


        self:log(
            "Backlight coupé via fallback toggle"
        )

    end


    return success

end


------------------------------------------------------------
-- FORCER BACKLIGHT À 0 APRÈS KEEPALIVE
------------------------------------------------------------

function obj:forceKeyboardBacklightOffAfterKeepAlive()

    if not self.keyboardBacklightEnforceAfterKeepAlive then

        return false

    end


    if not self:isKeyboardBacklightEnabled() then

        return false

    end


    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return false

    end


    if self.currentState
        ~= self.STATE.KEEPALIVE then


        return false

    end


    local current =
        self:getKeyboardBrightness()


    if current
        and current > 0.01
        and self.savedKeyboardBrightness == nil then


        self.savedKeyboardBrightness =
            current


        self.lastKnownNonZeroKeyboardBrightness =
            current

    end


    --------------------------------------------------------
    -- Rétroéclairage déjà éteint : rien à faire.
    --
    -- Écrire 0 par-dessus coûtait un appel shell bloquant de plus par
    -- keepalive, et surtout posait keyboardBacklightModified sans
    -- aucune valeur de référence. La restauration retombait alors sur
    -- keyboardBrightnessRestoreFallback et rallumait le clavier à
    -- 50 % alors qu'il était éteint avant le passage en vert.
    --
    -- C'est exactement ce que captureAndDisableKeyboardBacklight
    -- refuse de faire quand il ne trouve aucune valeur fiable.
    --------------------------------------------------------

    if current ~= nil
        and current <= 0.01 then


        return false

    end


    if self:setKeyboardBrightness(0) then

        --------------------------------------------------------
        -- Ne revendiquer la modification que si on sait la défaire.
        --------------------------------------------------------

        if self.savedKeyboardBrightness ~= nil
            or self.lastKnownNonZeroKeyboardBrightness ~= nil then


            self.keyboardBacklightModified =
                true

        end


        if self.verboseLogging then

            self:log(
                "Backlight clavier forcé à 0 après keepalive"
            )

        end


        return true

    end


    self:log(
        "Échec forçage backlight clavier après keepalive"
    )


    return false

end


function obj:scheduleKeyboardBacklightEnforce()

    if not self.keyboardBacklightEnforceAfterKeepAlive then

        return self

    end


    if self.keyboardBrightnessBackend
        ~= "mac-brightnessctl" then


        return self

    end


    if self.keyboardBacklightEnforceTimer then

        self.keyboardBacklightEnforceTimer:stop()


        self.keyboardBacklightEnforceTimer =
            nil

    end


    self.keyboardBacklightEnforceTimer =

        hs.timer.doAfter(

            self.keyPressDuration
            +
            self.keyboardBacklightEnforceDelay,

            function()

                self.keyboardBacklightEnforceTimer =
                    nil


                self:forceKeyboardBacklightOffAfterKeepAlive()

            end

        )


    return self

end



------------------------------------------------------------
-- RESTAURER BACKLIGHT CLAVIER
------------------------------------------------------------

function obj:restoreKeyboardBacklight(force)

    --------------------------------------------------------
    -- Annuler probe en attente
    --------------------------------------------------------

    if self.keyboardBacklightProbeTimer then

        self.keyboardBacklightProbeTimer:stop()


        self.keyboardBacklightProbeTimer =
            nil

    end


    if self.keyboardBacklightProbeRetryTimer then

        self.keyboardBacklightProbeRetryTimer:stop()


        self.keyboardBacklightProbeRetryTimer =
            nil

    end


    --------------------------------------------------------
    -- Rien à restaurer
    --------------------------------------------------------

    if not self.keyboardBacklightModified
        and force ~= true then

        return false

    end


    --------------------------------------------------------
    -- RESTAURATION PRÉCISE
    --------------------------------------------------------

    if self.keyboardBrightnessBackend
        == "mac-brightnessctl" then


        local value =
            self.savedKeyboardBrightness
            or self.lastKnownNonZeroKeyboardBrightness
            or self.keyboardBrightnessRestoreFallback


        if self:setKeyboardBrightness(value) then

            self:log(

                string.format(

                    "Clavier restauré : %.4f",

                    value

                )

            )


            self.lastKnownNonZeroKeyboardBrightness =
                value


            self.savedKeyboardBrightness =
                nil


            self.keyboardBacklightModified =
                false


            return true

        end


        self:log(
            "Échec restauration précise clavier"
        )


        return false

    end


    --------------------------------------------------------
    -- FALLBACK TOGGLE
    --------------------------------------------------------

    local success =

        self:sendSystemKey(
            "ILLUMINATION_TOGGLE"
        )


    if success then

        self.savedKeyboardBrightness =
            nil


        self.keyboardBacklightModified =
            false


        self:log(
            "Clavier restauré via fallback toggle"
        )

    end


    return success

end



------------------------------------------------------------
-- RÉDUCTION LUMINOSITÉ ÉCRAN
------------------------------------------------------------

function obj:dimScreen()

    if not self:isScreenDimmingEnabled() then

        return false

    end


    if self.screenBrightnessModified then

        return true

    end


    local screen =
        hs.screen.mainScreen()


    if not screen then

        self:log(
            "Écran principal introuvable"
        )


        return false

    end


    local current =
        screen:getBrightness()


    if current == nil then

        self:log(
            "Lecture luminosité écran non supportée"
        )


        return false

    end


    --------------------------------------------------------
    -- L'écran est déjà plus sombre que la cible.
    --
    -- Ne pas l'augmenter.
    --------------------------------------------------------

    if current <= self.screenBrightnessTarget then

        self:log(

            string.format(

                "Écran déjà <= cible : %.4f",

                current

            )

        )


        return false

    end


    self.savedScreenBrightness =
        current


    self.savedScreenId =
        screen:id()


    screen:setBrightness(
        self.screenBrightnessTarget
    )


    self.screenBrightnessModified =
        true


    self:log(

        string.format(

            "Écran %.4f -> %.4f",

            current,

            self.screenBrightnessTarget

        )

    )


    return true

end



------------------------------------------------------------
-- RESTAURER LUMINOSITÉ ÉCRAN
------------------------------------------------------------

function obj:restoreScreen()

    if not self.screenBrightnessModified then

        return false

    end


    local screen =
        nil


    --------------------------------------------------------
    -- Retrouver l'écran sauvegardé
    --------------------------------------------------------

    if self.savedScreenId then

        for _, candidate
            in ipairs(
                hs.screen.allScreens()
            ) do


            if candidate:id()
                == self.savedScreenId then


                screen =
                    candidate


                break

            end

        end

    end


    --------------------------------------------------------
    -- L'écran sauvegardé a disparu : moniteur débranché, session
    -- changée. Appliquer sa luminosité à l'écran principal actuel
    -- écraserait un réglage qui ne nous appartient pas.
    --------------------------------------------------------

    if self.savedScreenId
        and not screen then


        self:log(
            "Écran d'origine absent : restauration abandonnée"
        )


        self.savedScreenBrightness =
            nil


        self.savedScreenId =
            nil


        self.screenBrightnessModified =
            false


        return false

    end


    --------------------------------------------------------
    -- Aucun identifiant mémorisé : l'écran principal reste le
    -- meilleur candidat disponible.
    --------------------------------------------------------

    if not screen then

        screen =
            hs.screen.mainScreen()

    end


    if not screen
        or self.savedScreenBrightness == nil then


        self:log(
            "Impossible de restaurer l'écran"
        )


        -- Sans remise à zéro, dimScreen ressortirait indéfiniment sur
        -- screenBrightnessModified et la réduction ne fonctionnerait
        -- plus de toute la session.

        self.savedScreenBrightness =
            nil


        self.savedScreenId =
            nil


        self.screenBrightnessModified =
            false


        return false

    end


    screen:setBrightness(
        self.savedScreenBrightness
    )


    self:log(

        string.format(

            "Écran restauré : %.4f",

            self.savedScreenBrightness

        )

    )


    self.savedScreenBrightness =
        nil


    self.savedScreenId =
        nil


    self.screenBrightnessModified =
        false


    return true

end



------------------------------------------------------------
-- LIRE LES PROFILS LOW POWER MODE
--
-- Retour :
--
--   battery
--   ac
------------------------------------------------------------

function obj:getLowPowerStates()

    local output,
          success,
          terminationType,
          returnCode =

        hs.execute(

            string.format(

                "%s -g custom",

                self:shellQuote(self.pmsetPath)

            ),

            false

        )


    if not success then

        self:log(

            "ERREUR lecture pmset : "
            ..
            tostring(terminationType)
            ..
            " / "
            ..
            tostring(returnCode)

        )


        return nil,
            nil

    end


    local section =
        nil


    local battery =
        nil


    local ac =
        nil


    for line
        in tostring(output):gmatch(
            "[^\r\n]+"
        ) do


        ----------------------------------------------------
        -- Sections
        ----------------------------------------------------

        if line:match(
            "^Battery Power:"
        ) then


            section =
                "battery"


        elseif line:match(
            "^AC Power:"
        ) then


            section =
                "ac"


        else

            ------------------------------------------------
            -- lowpowermode N
            ------------------------------------------------

            local value =

                line:match(

                    "^%s*lowpowermode%s+(%d+)"

                )


            if value then

                value =
                    tonumber(value)


                if section == "battery" then

                    battery =
                        value


                elseif section == "ac" then

                    ac =
                        value

                end

            end

        end

    end


    return battery,
        ac

end



------------------------------------------------------------
-- PMSET PRIVILÉGIÉ
------------------------------------------------------------

-- %q de Lua produit un littéral Lua, pas un argument shell échappé.
-- Les chemins sont fixes aujourd'hui, mais la confusion est le genre
-- de détail qui casse le jour où l'un d'eux change.

function obj:shellQuote(value)

    return "'"
        .. tostring(value or ""):gsub("'", "'\\''")
        .. "'"

end


function obj:runPrivilegedPMSet(
    scope,
    value
)

    value =
        tonumber(value)


    if value ~= 0
        and value ~= 1 then


        self:log(
            "Valeur pmset invalide"
        )


        return false

    end


    if scope ~= "-b"
        and scope ~= "-c" then


        self:log(
            "Scope pmset invalide"
        )


        return false

    end


    local command =

        string.format(

            "%s -n %s %s lowpowermode %d",

            self:shellQuote(self.sudoPath),

            self:shellQuote(self.pmsetPath),

            scope,

            value

        )


    local output,
          success,
          terminationType,
          returnCode =

        hs.execute(

            command,

            false

        )


    if not success then

        self:log(

            "ERREUR pmset "
            ..
            scope
            ..
            " : "
            ..
            tostring(terminationType)
            ..
            " / "
            ..
            tostring(returnCode)
            ..
            " / "
            ..
            tostring(output)

        )

    end


    return success

end



------------------------------------------------------------
-- ACTIVER LOW POWER MODE
--
-- IMPORTANT :
--
-- Batterie et secteur sont traités séparément.
--
-- Un profil déjà à 1 :
--
--   - n'est pas modifié
--   - n'est pas remis à 0 à la sortie
------------------------------------------------------------

function obj:enableLowPowerMode(
    force,
    batteryOnly
)

    if not force
        and not self:isLowPowerModeEnabled() then

        return false

    end


    --------------------------------------------------------
    -- Déjà géré pour cette session KEEPALIVE
    --------------------------------------------------------

    if self.lowPowerBatteryModified
        or self.lowPowerACModified then


        return true

    end


    local battery,
          ac =

        self:getLowPowerStates()


    if battery == nil
        and ac == nil then


        self:log(
            "Impossible de lire lowpowermode"
        )


        return false

    end


    self.savedLowPowerBattery =
        battery


    self.savedLowPowerAC =
        ac


    --------------------------------------------------------
    -- BATTERIE
    --------------------------------------------------------

    if battery ~= nil then

        if battery == 0 then

            if self:runPrivilegedPMSet(

                "-b",

                1

            ) then


                self.lowPowerBatteryModified =
                    true


                self:log(
                    "Low Power batterie activé temporairement"
                )

            end


        else

            self:log(
                "Low Power batterie déjà actif : inchangé"
            )

        end

    end


    --------------------------------------------------------
    -- SECTEUR
    --------------------------------------------------------

    if not batteryOnly
        and ac ~= nil then

        if ac == 0 then

            if self:runPrivilegedPMSet(

                "-c",

                1

            ) then


                self.lowPowerACModified =
                    true


                self:log(
                    "Low Power secteur activé temporairement"
                )

            end


        else

            self:log(
                "Low Power secteur déjà actif : inchangé"
            )

        end

    end


    return

        self.lowPowerBatteryModified

        or

        self.lowPowerACModified

        or

        battery == 1

        or

        (
            not batteryOnly
            and ac == 1
        )

end



------------------------------------------------------------
-- LOW POWER AUTOMATIQUE SELON LA BATTERIE
------------------------------------------------------------

function obj:getBatteryStatus()

    local percentageSuccess,
          percentage =

        pcall(
            hs.battery.percentage
        )


    local sourceSuccess,
          powerSource =

        pcall(
            hs.battery.powerSource
        )


    if not percentageSuccess
        or not sourceSuccess then

        return nil,
            nil

    end


    return tonumber(percentage),
        powerSource

end


function obj:checkAutomaticLowPowerMode()

    if self.currentState
        ~= self.STATE.KEEPALIVE
        or not self:isAutomaticLowPowerModeEnabled()
        or self.automaticLowPowerHandled then

        return false

    end


    local percentage,
          powerSource =

        self:getBatteryStatus()


    if percentage == nil
        or powerSource ~= "Battery Power" then

        return false

    end


    local threshold =
        self:getLowPowerBatteryThreshold()


    if percentage > threshold then

        return false

    end


    self.automaticLowPowerHandled =
        true


    self:log(

        string.format(

            "Low Power automatique : batterie %.0f %% <= seuil %.0f %%",

            percentage,

            threshold

        )

    )


    local result =
        self:enableLowPowerMode(
            true,
            true
        )


    self:persistPendingRestore()


    return result

end


------------------------------------------------------------
-- RESTAURER LOW POWER MODE
------------------------------------------------------------

function obj:restoreLowPowerMode()

    self.automaticLowPowerHandled =
        false


    local allSuccess =
        true


    local hadModification =

        self.lowPowerBatteryModified

        or

        self.lowPowerACModified


    --------------------------------------------------------
    -- BATTERIE
    --
    -- Restaurer uniquement si ActivityKeeper l'a modifiée.
    --------------------------------------------------------

    if self.lowPowerBatteryModified then

        if not self:runPrivilegedPMSet(

            "-b",

            self.savedLowPowerBattery or 0

        ) then


            allSuccess =
                false

        else

            self:log(

                "Low Power batterie restauré : "
                ..
                tostring(
                    self.savedLowPowerBattery
                )

            )

        end

    end


    --------------------------------------------------------
    -- SECTEUR
    --------------------------------------------------------

    if self.lowPowerACModified then

        if not self:runPrivilegedPMSet(

            "-c",

            self.savedLowPowerAC or 0

        ) then


            allSuccess =
                false

        else

            self:log(

                "Low Power secteur restauré : "
                ..
                tostring(
                    self.savedLowPowerAC
                )

            )

        end

    end


    --------------------------------------------------------
    -- Reset uniquement en cas de restauration complète
    --------------------------------------------------------

    if allSuccess then

        self.savedLowPowerBattery =
            nil


        self.savedLowPowerAC =
            nil


        self.lowPowerBatteryModified =
            false


        self.lowPowerACModified =
            false

    end


    return

        hadModification
        and allSuccess

end



------------------------------------------------------------
-- FILET DE SÉCURITÉ
--
-- Les états modifiés ici sont des réglages système, pas de la
-- mémoire de processus : rétroéclairage, auto-luminosité, luminosité
-- écran, Low Power Mode. Si Hammerspoon disparaît entre l'application
-- et la restauration, ils restent tels quels et les valeurs d'origine
-- meurent avec l'état Lua.
--
-- Deux parades :
--   - hs.shutdownCallback couvre le rechargement et la sortie propre
--   - la consignation dans hs.settings couvre le crash et le kill
------------------------------------------------------------

function obj:hasModifiedSystemState()

    return self.keyboardBacklightModified
        or self.keyboardAutoBrightnessModified
        or self.screenBrightnessModified
        or self.lowPowerBatteryModified
        or self.lowPowerACModified

end


-- Empreinte de l'état à consigner. Permet d'appeler la consignation
-- aussi souvent qu'on veut sans écrire dans hs.settings à chaque fois.

function obj:pendingRestoreSignature()

    return table.concat(
        {
            tostring(self.keyboardBacklightModified == true),
            tostring(self.savedKeyboardBrightness),
            tostring(self.keyboardAutoBrightnessModified == true),
            tostring(self.savedKeyboardAutoBrightness),
            tostring(self.screenBrightnessModified == true),
            tostring(self.savedScreenBrightness),
            tostring(self.savedScreenId),
            tostring(self.lowPowerBatteryModified == true),
            tostring(self.savedLowPowerBattery),
            tostring(self.lowPowerACModified == true),
            tostring(self.savedLowPowerAC),
        },
        "|"
    )

end


function obj:persistPendingRestore()

    local signature =
        self:pendingRestoreSignature()


    if signature == self.lastPendingRestoreSignature then

        return self

    end


    self.lastPendingRestoreSignature =
        signature


    if not self:hasModifiedSystemState() then

        hs.settings.set(
            self.pendingRestoreKey,
            nil
        )


        return self

    end


    hs.settings.set(

        self.pendingRestoreKey,

        {
            keyboardBacklightModified =
                self.keyboardBacklightModified == true,

            savedKeyboardBrightness =
                self.savedKeyboardBrightness,

            keyboardAutoBrightnessModified =
                self.keyboardAutoBrightnessModified == true,

            savedKeyboardAutoBrightness =
                self.savedKeyboardAutoBrightness,

            screenBrightnessModified =
                self.screenBrightnessModified == true,

            savedScreenBrightness =
                self.savedScreenBrightness,

            savedScreenId =
                self.savedScreenId,

            lowPowerBatteryModified =
                self.lowPowerBatteryModified == true,

            savedLowPowerBattery =
                self.savedLowPowerBattery,

            lowPowerACModified =
                self.lowPowerACModified == true,

            savedLowPowerAC =
                self.savedLowPowerAC,
        }

    )


    return self

end


function obj:clearPendingRestore()

    hs.settings.set(
        self.pendingRestoreKey,
        nil
    )


    return self

end


function obj:recoverPendingRestore()

    local pending =
        hs.settings.get(self.pendingRestoreKey)


    if type(pending) ~= "table" then

        return false

    end


    self:log(
        "État système laissé modifié par un arrêt precedent :"
        .. " restauration"
    )


    -- Réinjection des valeurs capturées avant la disparition, pour
    -- que restoreEnergySavingState retrouve de quoi travailler.

    -- L'enregistrement vient d'une session précédente, possiblement
    -- d'une autre version : on ne lui fait pas confiance sur les
    -- types. Une chaîne arrivant jusqu'à setBrightness lèverait.

    local function number(value)

        return tonumber(value)

    end


    self.keyboardBacklightModified =
        pending.keyboardBacklightModified == true

    self.savedKeyboardBrightness =
        number(pending.savedKeyboardBrightness)

    self.keyboardAutoBrightnessModified =
        pending.keyboardAutoBrightnessModified == true

    self.savedKeyboardAutoBrightness =
        pending.savedKeyboardAutoBrightness == true

    self.screenBrightnessModified =
        pending.screenBrightnessModified == true

    self.savedScreenBrightness =
        number(pending.savedScreenBrightness)

    self.savedScreenId =
        number(pending.savedScreenId)

    self.lowPowerBatteryModified =
        pending.lowPowerBatteryModified == true

    self.savedLowPowerBattery =
        number(pending.savedLowPowerBattery)

    self.lowPowerACModified =
        pending.lowPowerACModified == true

    self.savedLowPowerAC =
        number(pending.savedLowPowerAC)


    self:restoreEnergySavingState()


    self:clearPendingRestore()


    return true

end


function obj:installShutdownGuard()

    if self.shutdownGuardInstalled then

        return self

    end


    self.shutdownGuardInstalled =
        true


    -- Un autre module pourrait déjà en avoir posé un : on le chaîne
    -- plutôt que de l'écraser.

    local previous =
        hs.shutdownCallback


    hs.shutdownCallback =

        function()

            pcall(
                function()

                    obj:releaseActivityKey()


                    obj:restoreEnergySavingState()


                    obj:clearPendingRestore()

                end
            )


            if type(previous) == "function" then

                pcall(previous)

            end

        end


    return self

end



------------------------------------------------------------
-- APPLIQUER LES ÉCONOMIES
------------------------------------------------------------

function obj:applyEnergySavingState()

    --------------------------------------------------------
    -- Clavier
    --------------------------------------------------------

    self:disableKeyboardAutoBrightness()


    self:disableKeyboardBacklight()


    --------------------------------------------------------
    -- Écran
    --------------------------------------------------------

    self:dimScreen()


    --------------------------------------------------------
    -- Low Power
    --------------------------------------------------------

    self:enableLowPowerMode()

    self:checkAutomaticLowPowerMode()


    self:persistPendingRestore()

end



------------------------------------------------------------
-- RESTAURER LES ÉCONOMIES
------------------------------------------------------------

function obj:restoreEnergySavingState()

    --------------------------------------------------------
    -- Clavier
    --------------------------------------------------------

    local shouldConfirmKeyboardAuto =
        self.keyboardAutoBrightnessModified
        and self.savedKeyboardAutoBrightness == true


    self:restoreKeyboardAutoBrightness()


    self:restoreKeyboardBacklight(
        shouldConfirmKeyboardAuto
    )


    if shouldConfirmKeyboardAuto then

        self:scheduleKeyboardAutoBrightnessRestoreConfirm()

    end


    --------------------------------------------------------
    -- Écran
    --------------------------------------------------------

    self:restoreScreen()


    --------------------------------------------------------
    -- Low Power
    --------------------------------------------------------

    self:restoreLowPowerMode()


    -- Consigne ce qui reste éventuellement modifié : une restauration
    -- partiellement en échec doit rester rattrapable au prochain
    -- démarrage.

    self:persistPendingRestore()

end



------------------------------------------------------------
-- KEEPALIVE
------------------------------------------------------------

function obj:sendKeepAlive()

    if self.currentState
        ~= self.STATE.KEEPALIVE then


        return

    end


    if self.keepAliveInProgress then

        return

    end


    self.keepAliveInProgress =
        true


    --------------------------------------------------------
    -- Le verrou doit etre relache quoi qu'il arrive.
    --
    -- Sans cette protection, une seule erreur dans un des moteurs ou
    -- dans la journalisation laissait keepAliveInProgress a true pour
    -- toujours : tous les keepalives suivants ressortaient aussitot,
    -- et le Spoon cessait silencieusement de faire son travail.
    --------------------------------------------------------

    local userSuccess,
          keyboardSuccess,
          mouseSuccess


    local ok,
          errorMessage =

        pcall(

            function()

                userSuccess =
                    self:sendUserActivity()


                keyboardSuccess =
                    self:sendKeyboardActivity()


                mouseSuccess =
                    self:sendMouseActivity()


                if keyboardSuccess then

                    self:scheduleKeyboardBacklightEnforce()

                end

            end

        )


    if not ok then

        self:log(

            "ERREUR keepalive : "
            ..
            tostring(errorMessage)

        )

    end


    --------------------------------------------------------
    -- Timestamp
    --------------------------------------------------------

    self.lastKeepAliveTime =
        os.time()


    --------------------------------------------------------
    -- Statistiques
    --------------------------------------------------------

    if userSuccess
        or keyboardSuccess
        or mouseSuccess then


        self.keepAliveCount =
            self.keepAliveCount
            +
            1


        --------------------------------------------------------
        -- Seul message réellement périodique du Spoon : une ligne
        -- toutes les keepAliveInterval secondes tant que le mode vert
        -- dure. Le garde évite aussi de construire la chaîne et de
        -- relire trois réglages pour rien.
        --------------------------------------------------------

        if self.verboseLogging then

            self:log(

                string.format(

                    "Keepalive #%d | UA=%s Clavier=%s Mouse=%s",

                    self.keepAliveCount,

                    tostring(
                        self:isUserActivityEnabled()
                    ),

                    tostring(
                        self:isKeyboardEnabled()
                    ),

                    tostring(
                        self:isMouseEnabled()
                    )

                )

            )

        end


    else

        self:log(
            "ATTENTION : aucun moteur keepalive actif"
        )

    end


    self.keepAliveInProgress =
        false

end


function obj:scheduleInitialKeepAlive()

    if self.initialKeepAliveTimer then

        self.initialKeepAliveTimer:stop()


        self.initialKeepAliveTimer =
            nil

    end


    self.initialKeepAliveTimer =

        hs.timer.doAfter(

            self.keepAliveAfterEnergySavingDelay,

            function()

                self.initialKeepAliveTimer =
                    nil


                if self.currentState
                    ~= self.STATE.KEEPALIVE then


                    return

                end


                self:forceKeyboardBacklightOffAfterKeepAlive()


                self:sendKeepAlive()

            end

        )


    return self

end



------------------------------------------------------------
-- CONTRÔLE IDLE
------------------------------------------------------------

function obj:checkIdleState()

    if self.currentState == self.STATE.OFF then

        return

    end


    --------------------------------------------------------
    -- Consignation de rattrapage.
    --
    -- La capture du rétroéclairage est asynchrone : elle peut
    -- réussir jusqu'à une seconde après applyEnergySavingState, et
    -- forceKeyboardBacklightOffAfterKeepAlive peut modifier l'état à
    -- n'importe quel keepalive. Sans ce passage, ces modifications
    -- tardives ne seraient jamais consignées et un arrêt brutal les
    -- rendrait irrécupérables.
    --
    -- L'empreinte rend l'appel gratuit quand rien n'a changé.
    --------------------------------------------------------

    self:persistPendingRestore()


    local idle =
        self:getIdleTime()


    if idle == nil then

        self:log(
            "Idle indisponible : tick ignoré"
        )


        return

    end


    --------------------------------------------------------
    -- En mode jaune :
    -- mémoriser les valeurs clavier non nulles disponibles.
    --------------------------------------------------------

    if self.currentState == self.STATE.MONITORING then

        self:sampleKeyboardBrightness(false)

    end


    if self.verboseLogging then

        self:log(

            string.format(

                "state=%s idle=%.1f",

                self.currentState,

                idle

            )

        )

    end


    --------------------------------------------------------
    -- JAUNE -> VERT
    --------------------------------------------------------

    if self.currentState == self.STATE.MONITORING then

        if idle >= self.idleThreshold then

            ------------------------------------------------
            -- Passage vert
            ------------------------------------------------

            self:setState(
                self.STATE.KEEPALIVE
            )


            ------------------------------------------------
            -- Économies énergie
            ------------------------------------------------

            self:applyEnergySavingState()


            ------------------------------------------------
            -- Premier keepalive après stabilisation clavier.
            ------------------------------------------------

            self:scheduleInitialKeepAlive()

        end


        return

    end


    --------------------------------------------------------
    -- MODE KEEPALIVE
    --------------------------------------------------------

    if self.currentState == self.STATE.KEEPALIVE then

        self:checkAutomaticLowPowerMode()


        local secondsSinceKeepAlive =
            nil


        if self.lastKeepAliveTime then

            secondsSinceKeepAlive =
                os.time()
                -
                self.lastKeepAliveTime

        end


        -- Meme regle que le filet rapide : l'horloge d'inactivite est-elle
        -- plus recente que notre dernier evenement ? Les deux anciens
        -- seuils sont conserves comme second recours, pour le cas ou
        -- l'inference ne conclut pas alors que l'activite est manifeste.

        if self:realActivitySinceOurLastEvent()
            or (
                idle <= self.realActivityReturnIdleThreshold
                and (
                    not secondsSinceKeepAlive
                    or secondsSinceKeepAlive
                        > self.postKeepAliveIdleIgnorePeriod
                )
            ) then


            self:log(
                "Activité utilisateur détectée par idle macOS"
                .. " (origine : "
                .. (self:realActivitySinceOurLastEvent()
                    and "inference" or "anciens seuils")
                .. ", inactivité "
                .. string.format("%.1f", idle)
                .. " s, notre dernier événement remonte à "
                .. tostring(secondsSinceKeepAlive or "?")
                .. " s)"
            )


            self:restoreEnergySavingState()


            self:setState(
                self.STATE.MONITORING
            )


            return

        end


        if not self.lastKeepAliveTime then

            self:sendKeepAlive()


            return

        end


        local elapsed =

            os.time()
            -
            self.lastKeepAliveTime


        if elapsed
            >= self.keepAliveInterval then


            self:sendKeepAlive()

        end

    end

end



------------------------------------------------------------
-- ACTIVATION
------------------------------------------------------------

function obj:enable()

    if self.currentState ~= self.STATE.OFF then

        return self

    end


    self.lastRealActivityTime =
        os.time()


    self.lastKeepAliveTime =
        nil


    --------------------------------------------------------
    -- Tentative de référence clavier immédiate
    --------------------------------------------------------

    self:sampleKeyboardBrightness(true)


    --------------------------------------------------------
    -- Passage jaune
    --------------------------------------------------------

    self:setState(
        self.STATE.MONITORING
    )


    --------------------------------------------------------
    -- Watcher
    --------------------------------------------------------

    self:createInputWatcher()


    if self.inputWatcher then

        self.inputWatcher:start()

    end


    --------------------------------------------------------
    -- Timer précédent éventuel
    --------------------------------------------------------

    if self.checkTimer then

        self.checkTimer:stop()


        self.checkTimer =
            nil

    end


    --------------------------------------------------------
    -- Timer principal
    --------------------------------------------------------

    self.checkTimer =

        hs.timer.doEvery(

            self.checkInterval,

            function()

                self:checkIdleState()

            end

        )


    --------------------------------------------------------
    -- Contrôle immédiat
    --------------------------------------------------------

    self:checkIdleState()


    self:log(

        string.format(

            "Activé | UA=%s Clavier=%s Mouse=%s KBLight=%s Screen=%s LowPower=%s",

            tostring(
                self:isUserActivityEnabled()
            ),

            tostring(
                self:isKeyboardEnabled()
            ),

            tostring(
                self:isMouseEnabled()
            ),

            tostring(
                self:isKeyboardBacklightEnabled()
            ),

            tostring(
                self:isScreenDimmingEnabled()
            ),

            tostring(
                self:isLowPowerModeEnabled()
            )

        )

    )


    return self

end



------------------------------------------------------------
-- DÉSACTIVATION
------------------------------------------------------------

function obj:disable()

    if self.currentState == self.STATE.OFF then

        return self

    end


    --------------------------------------------------------
    -- Restaurer avant arrêt
    --------------------------------------------------------

    self:restoreEnergySavingState()


    --------------------------------------------------------
    -- Timer principal
    --------------------------------------------------------

    if self.checkTimer then

        self.checkTimer:stop()


        self.checkTimer =
            nil

    end


    --------------------------------------------------------
    -- Souris
    --------------------------------------------------------

    if self.returnMouseTimer then

        self.returnMouseTimer:stop()


        self.returnMouseTimer =
            nil

    end


    --------------------------------------------------------
    -- Key Up
    --------------------------------------------------------

    self:releaseActivityKey()


    --------------------------------------------------------
    -- Probe clavier
    --------------------------------------------------------

    if self.keyboardBacklightProbeTimer then

        self.keyboardBacklightProbeTimer:stop()


        self.keyboardBacklightProbeTimer =
            nil

    end


    if self.keyboardBacklightProbeRetryTimer then

        self.keyboardBacklightProbeRetryTimer:stop()


        self.keyboardBacklightProbeRetryTimer =
            nil

    end


    if self.keyboardBacklightEnforceTimer then

        self.keyboardBacklightEnforceTimer:stop()


        self.keyboardBacklightEnforceTimer =
            nil

    end


    if self.initialKeepAliveTimer then

        self.initialKeepAliveTimer:stop()


        self.initialKeepAliveTimer =
            nil

    end


    if self.keyboardAutoRestoreTimer then

        self.keyboardAutoRestoreTimer:stop()


        self.keyboardAutoRestoreTimer =
            nil

    end


    --------------------------------------------------------
    -- Watcher
    --------------------------------------------------------

    if self.inputWatcher then

        self.inputWatcher:stop()

    end


    self:stopKeepaliveExitWatch()

    self:stopFastReturnWatcher()


    --------------------------------------------------------
    -- Reset
    --------------------------------------------------------

    self.keepAliveInProgress =
        false


    self.syntheticEventIgnoreUntil =
        0


    self.lastKeepAliveTime =
        nil


    --------------------------------------------------------
    -- OFF
    --------------------------------------------------------

    self:setState(
        self.STATE.OFF
    )


    self:log(
        "ActivityKeeper désactivé"
    )


    return self

end



------------------------------------------------------------
-- TOGGLE GLOBAL
------------------------------------------------------------

function obj:toggle()

    if self.currentState == self.STATE.OFF then

        return self:enable()

    end


    return self:disable()

end



------------------------------------------------------------
-- TOGGLE USER ACTIVITY
------------------------------------------------------------

function obj:toggleUserActivityMode()

    self:setBooleanSetting(

        self.SETTING_KEYS.USER_ACTIVITY,

        not self:isUserActivityEnabled(),

        "UserActivity"

    )


    return self

end



------------------------------------------------------------
-- TOGGLE CLAVIER
------------------------------------------------------------

function obj:toggleKeyboardMode()

    self:setBooleanSetting(

        self.SETTING_KEYS.KEYBOARD,

        not self:isKeyboardEnabled(),

        "Clavier Maj"

    )


    return self

end



------------------------------------------------------------
-- TOGGLE SOURIS
------------------------------------------------------------

function obj:toggleMouseMode()

    self:setBooleanSetting(

        self.SETTING_KEYS.MOUSE,

        not self:isMouseEnabled(),

        "Souris"

    )


    return self

end



------------------------------------------------------------
-- TOGGLE BACKLIGHT CLAVIER
------------------------------------------------------------

function obj:toggleKeyboardBacklightMode()

    local enabled =
        not self:isKeyboardBacklightEnabled()


    self:setBooleanSetting(

        self.SETTING_KEYS.KEYBOARD_BACKLIGHT,

        enabled,

        "Rétroéclairage clavier"

    )


    --------------------------------------------------------
    -- Application immédiate en KEEPALIVE
    --------------------------------------------------------

    if self.currentState == self.STATE.KEEPALIVE then

        if enabled then

            self:disableKeyboardBacklight()

        else

            self:restoreKeyboardBacklight()

        end

    end


    return self

end



------------------------------------------------------------
-- TOGGLE SCREEN DIMMING
------------------------------------------------------------

function obj:toggleScreenDimmingMode()

    local enabled =
        not self:isScreenDimmingEnabled()


    self:setBooleanSetting(

        self.SETTING_KEYS.SCREEN_DIMMING,

        enabled,

        "Réduction luminosité écran"

    )


    --------------------------------------------------------
    -- Application immédiate en KEEPALIVE
    --------------------------------------------------------

    if self.currentState == self.STATE.KEEPALIVE then

        if enabled then

            self:dimScreen()

        else

            self:restoreScreen()

        end

    end


    return self

end



------------------------------------------------------------
-- TOGGLE LOW POWER
------------------------------------------------------------

function obj:toggleLowPowerMode()

    local enabled =
        not self:isLowPowerModeEnabled()


    self:setBooleanSetting(

        self.SETTING_KEYS.LOW_POWER,

        enabled,

        "Mode économie d'énergie"

    )


    --------------------------------------------------------
    -- Application immédiate en KEEPALIVE
    --------------------------------------------------------

    if self.currentState == self.STATE.KEEPALIVE then

        if enabled then

            self:enableLowPowerMode()

        else

            self:restoreLowPowerMode()

        end

    end


    return self

end


function obj:toggleAutomaticLowPowerMode()

    local enabled =
        not self:isAutomaticLowPowerModeEnabled()


    self:setBooleanSetting(

        self.SETTING_KEYS.AUTOMATIC_LOW_POWER,

        enabled,

        string.format(
            "Éco auto sous %.0f %%",
            self:getLowPowerBatteryThreshold()
        )

    )


    if self.currentState == self.STATE.KEEPALIVE then

        if enabled then

            self.automaticLowPowerHandled =
                false


            self:checkAutomaticLowPowerMode()


        elseif not self:isLowPowerModeEnabled() then

            self:restoreLowPowerMode()

        end

    end


    return self

end


------------------------------------------------------------
-- TEST KEEPALIVE
--
-- Test uniquement :
--
--   UserActivity
--   Maj
--   Souris
--
-- Ne modifie pas les économies d'énergie.
------------------------------------------------------------

function obj:testKeepAlive()

    self:log(
        "Test manuel keepalive"
    )


    local previousState =
        self.currentState


    local previousKeepAliveTime =
        self.lastKeepAliveTime


    self.currentState =
        self.STATE.KEEPALIVE


    -- Sans protection, une erreur laisserait currentState sur
    -- KEEPALIVE alors que rien n'a ete mis en place : ni watchers, ni
    -- economies d'energie, et setState n'ayant pas ete appele, le menu
    -- et le watcher de retour resteraient desynchronises.

    pcall(
        function()

            self:sendKeepAlive()

        end
    )


    self.currentState =
        previousState


    -- Un test manuel ne doit pas decaler le rythme reel des keepalives.

    self.lastKeepAliveTime =
        previousKeepAliveTime


    self:updateMenuBar()


    self:showToast(
        "Test keepalive envoyé"
    )


    return self

end



------------------------------------------------------------
-- CHECKBOX MENU
------------------------------------------------------------

function obj:menuCheck(value)

    if value then

        return "✓ "

    end


    return "    "

end



------------------------------------------------------------
-- CONSTRUCTION MENU
------------------------------------------------------------

function obj:buildMenu()

    local menu =
        {}


    --------------------------------------------------------
    -- INFORMATIONS
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "État : "
                ..
                self:getStateLabel(),

            disabled =
                true
        }

    )


    table.insert(

        menu,

        {
            title =
                "Idle macOS : "
                ..
                self:formatDuration(
                    self:getIdleTime()
                ),

            disabled =
                true
        }

    )


    table.insert(

        menu,

        {
            title =
                "Seuil : "
                ..
                self:formatDuration(
                    self.idleThreshold
                ),

            disabled =
                true
        }

    )


    table.insert(

        menu,

        {
            title =
                "Intervalle : "
                ..
                self:formatDuration(
                    self.keepAliveInterval
                ),

            disabled =
                true
        }

    )


    if self.lastKeepAliveTime then

        table.insert(

            menu,

            {
                title =
                    "Dernier keepalive : "
                    ..
                    os.date(

                        "%H:%M:%S",

                        self.lastKeepAliveTime

                    ),

                disabled =
                    true
            }

        )

    end


    table.insert(

        menu,

        {
            title =
                "Keepalive générés : "
                ..
                tostring(
                    self.keepAliveCount
                ),

            disabled =
                true
        }

    )


    --------------------------------------------------------
    -- Valeur clavier mémorisée
    --------------------------------------------------------

    if self.lastKnownNonZeroKeyboardBrightness then

        table.insert(

            menu,

            {
                title =
                    string.format(

                        "Référence clavier : %.2f",

                        self.lastKnownNonZeroKeyboardBrightness

                    ),

                disabled =
                    true
            }

        )

    end


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    --------------------------------------------------------
    -- MODES DE MAINTIEN
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Maintien de présence",

            disabled =
                true
        }

    )


    --------------------------------------------------------
    -- USER ACTIVITY
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isUserActivityEnabled()
                )
                ..
                "UserActivity",

            fn =
                function()

                    self:toggleUserActivityMode()

                end
        }

    )


    --------------------------------------------------------
    -- Clavier
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isKeyboardEnabled()
                )
                ..
                "Clavier Maj",

            fn =
                function()

                    self:toggleKeyboardMode()

                end
        }

    )


    --------------------------------------------------------
    -- SOURIS
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isMouseEnabled()
                )
                ..
                "Souris",

            fn =
                function()

                    self:toggleMouseMode()

                end
        }

    )


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    --------------------------------------------------------
    -- RÉDUCTION CONSOMMATION
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Réduction consommation",

            disabled =
                true
        }

    )


    --------------------------------------------------------
    -- CLAVIER
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isKeyboardBacklightEnabled()
                )
                ..
                "Éteindre rétroéclairage clavier",

            fn =
                function()

                    self:toggleKeyboardBacklightMode()

                end
        }

    )


    --------------------------------------------------------
    -- ÉCRAN
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isScreenDimmingEnabled()
                )
                ..
                string.format(

                    "Réduire écran à %d %%",

                    math.floor(

                        self.screenBrightnessTarget
                        *
                        100

                    )

                ),

            fn =
                function()

                    self:toggleScreenDimmingMode()

                end
        }

    )


    --------------------------------------------------------
    -- LOW POWER
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isLowPowerModeEnabled()
                )
                ..
                "Mode économie d'énergie",

            fn =
                function()

                    self:toggleLowPowerMode()

                end
        }

    )


    table.insert(

        menu,

        {
            title =
                self:menuCheck(
                    self:isAutomaticLowPowerModeEnabled()
                )
                ..
                string.format(
                    "Éco auto sous %.0f %%",
                    self:getLowPowerBatteryThreshold()
                ),

            fn =
                function()

                    self:toggleAutomaticLowPowerMode()

                end
        }

    )


    --------------------------------------------------------
    -- BACKEND
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Clavier : "
                ..
                self:getKeyboardBacklightBackendLabel(),

            disabled =
                true
        }

    )


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    --------------------------------------------------------
    -- GLOBAL
    --------------------------------------------------------

    if self.currentState == self.STATE.OFF then

        table.insert(

            menu,

            {
                title =
                    "Activer Activity Keeper",

                fn =
                    function()

                        self:enable()

                    end
            }

        )


    else

        table.insert(

            menu,

            {
                title =
                    "Désactiver Activity Keeper",

                fn =
                    function()

                        self:disable()

                    end
            }

        )

    end


    --------------------------------------------------------
    -- TEST
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Tester les modes actifs",

            fn =
                function()

                    self:testKeepAlive()

                end
        }

    )


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    table.insert(

        menu,

        {
            title =
                "Double-clic : ON / OFF",

            disabled =
                true
        }

    )


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    --------------------------------------------------------
    -- CONSOLE
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Ouvrir la console",

            fn =
                function()

                    hs.openConsole()

                end
        }

    )


    --------------------------------------------------------
    -- RELOAD
    --------------------------------------------------------

    table.insert(

        menu,

        {
            title =
                "Recharger Hammerspoon",

            fn =
                function()

                    hs.reload()

                end
        }

    )


    return menu

end



------------------------------------------------------------
-- AFFICHER MENU
------------------------------------------------------------

function obj:showMenu()

    if not self.menuBar then

        return

    end


    self.menuBar:setMenu(
        self:buildMenu()
    )


    -- frame() ne répond que si l'objet est dans la barre des menus.
    -- Sans icône, le menu s'ouvre sous le pointeur.

    local frame =
        self.menuBar:frame()


    local point


    if frame then

        point = {

            x =
                frame.x,

            y =
                frame.y
                +
                frame.h

        }

    else

        point =
            hs.mouse.absolutePosition()

    end


    self.menuBar:popupMenu(point)


    --------------------------------------------------------
    -- Détachement pour conserver le clickCallback
    --------------------------------------------------------

    hs.timer.doAfter(

        0.1,

        function()

            if self.menuBar then

                self.menuBar:setMenu(nil)

            end

        end

    )

end



------------------------------------------------------------
-- SIMPLE / DOUBLE CLIC
------------------------------------------------------------

function obj:handleMenuBarClick()

    self.clickCount =
        self.clickCount
        +
        1


    --------------------------------------------------------
    -- PREMIER CLIC
    --------------------------------------------------------

    if self.clickCount == 1 then

        self.clickTimer =

            hs.timer.doAfter(

                self.doubleClickInterval,

                function()

                    if self.clickCount == 1 then

                        self:showMenu()

                    end


                    self.clickCount =
                        0


                    self.clickTimer =
                        nil

                end

            )


        return

    end


    --------------------------------------------------------
    -- DOUBLE CLIC
    --------------------------------------------------------

    if self.clickCount >= 2 then

        if self.clickTimer then

            self.clickTimer:stop()


            self.clickTimer =
                nil

        end


        self.clickCount =
            0


        self:toggle()

    end

end



------------------------------------------------------------
-- CRÉATION MENUBAR
------------------------------------------------------------

function obj:setMenuBarVisible(visible)

    self.showMenuBar =
        visible == true


    -- Recreation complete plutot que returnToMenuBar() : un objet
    -- cree masque, ou remis dans la barre apres retrait, revient sans
    -- son cablage de clic et l'icone est inerte. hs.menubar.new()
    -- suivi de setClickCallback() est le seul etat verifiable.

    if self.menuBar then

        self.menuBar:setMenu(nil)

        self.menuBar:delete()

        self.menuBar =
            nil

    end


    self:createMenuBar()


    self:updateMenuBar()


    self:log(
        "Icône barre des menus : "
        .. tostring(self.showMenuBar)
    )


    return self

end


function obj:createMenuBar()

    if self.menuBar then

        self:updateMenuBar()


        return self

    end


    -- new(false) crée un objet masqué, absent de la barre des menus
    -- mais utilisable en menu contextuel via popupMenu().

    self.menuBar =
        hs.menubar.new(
            self.showMenuBar ~= false
        )


    if not self.menuBar then

        self:log(
            "ERREUR création menubar"
        )


        return self

    end


    self:updateMenuBar()


    self.menuBar:setClickCallback(

        function()

            self:handleMenuBarClick()

        end

    )


    return self

end



------------------------------------------------------------
-- HOTKEYS
------------------------------------------------------------

function obj:hotkeyActions()

    return {

        toggle = function()

            self:toggle()

        end,

        menu = function()

            self:showMenu()

        end,

        status = function()

            self:showToast(
                "Activity Keeper : "
                .. self:getStateLabel()
            )

        end,

        test = function()

            self:testKeepAlive()

        end,

    }

end


function obj:deleteHotkeys()

    for _, hotkey
        in pairs(self.hotkeys) do

        if hotkey then

            hotkey:delete()

        end

    end


    self.hotkeys =
        {}


    return self

end


function obj:applyHotkeys()

    self:deleteHotkeys()


    if not self.hotkeysEnabled then

        self:log(
            "Raccourcis clavier désactivés"
        )


        return self

    end


    if not self.hotkeyMapping then

        return self

    end


    local bound =
        0


    for name, action
        in pairs(self:hotkeyActions()) do

        local binding =
            self.hotkeyMapping[name]


        if binding
            and binding[1]
            and binding[2] then

            self.hotkeys[name] =
                hs.hotkey.bind(
                    binding[1],
                    binding[2],
                    action
                )


            bound =
                bound + 1

        end

    end


    self:log(
        "Raccourcis clavier liés : "
        .. tostring(bound)
    )


    return self

end


function obj:bindHotkeys(mapping)

    -- Le mapping est memorise et non consomme : desactiver puis
    -- reactiver les raccourcis les relie sans repasser par init.lua.

    self.hotkeyMapping =
        mapping


    -- Rien n'est lie tant que le Spoon ne tourne pas. Sans cette
    -- garde, declarer les raccourcis depuis SpoonManager les rendrait
    -- actifs alors meme que le Spoon est desactive : ses touches
    -- piloteraient un Spoon eteint.

    if not self.running then

        return self

    end


    return self:applyHotkeys()

end


function obj:setHotkeysEnabled(enabled)

    self.hotkeysEnabled =
        enabled == true


    self:applyHotkeys()


    self:updateMenuBar()


    return self

end


function obj:toggleHotkeys()

    return self:setHotkeysEnabled(
        not self.hotkeysEnabled
    )

end



------------------------------------------------------------
-- START
------------------------------------------------------------

function obj:start(enableImmediately)

    self.running =
        true


    self:applyConfiguredModeDefaults()


    --------------------------------------------------------
    -- Détection outil clavier
    --------------------------------------------------------

    self:detectKeyboardBrightnessTool()


    --------------------------------------------------------
    -- Filet de sécurité
    --
    -- La reprise vient après la détection de l'outil : sans lui, la
    -- restauration du rétroéclairage n'aurait aucun moyen d'agir.
    --------------------------------------------------------

    self:installShutdownGuard()


    self:recoverPendingRestore()


    --------------------------------------------------------
    -- Watcher
    --------------------------------------------------------

    self:createInputWatcher()


    --------------------------------------------------------
    -- Raccourcis
    --
    -- bindHotkeys() ne lie rien tant que le Spoon ne tourne pas : ils
    -- sont appliques ici, une fois les reglages connus.
    --------------------------------------------------------

    self:applyHotkeys()


    --------------------------------------------------------
    -- Menubar
    --------------------------------------------------------

    self:createMenuBar()


    --------------------------------------------------------
    -- État initial
    --------------------------------------------------------

    self.currentState =
        self.STATE.OFF


    self:updateMenuBar()


    --------------------------------------------------------
    -- Activation automatique facultative
    --------------------------------------------------------

    if enableImmediately == true then

        self:enable()

    end


    self:log(

        string.format(

            "Initialisé | Clavier=%s Screen=%s LowPower=%s Backend=%s",

            tostring(
                self:isKeyboardEnabled()
            ),

            tostring(
                self:isScreenDimmingEnabled()
            ),

            tostring(
                self:isLowPowerModeEnabled()
            ),

            self:getKeyboardBacklightBackendLabel()

        )

    )


    return self

end



------------------------------------------------------------
-- STOP COMPLET
------------------------------------------------------------

function obj:stop()

    self.running =
        false


    --------------------------------------------------------
    -- Bulle éventuellement affichée
    --------------------------------------------------------

    self:hideToast()


    --------------------------------------------------------
    -- Désactivation et restauration
    --------------------------------------------------------

    self:disable()


    --------------------------------------------------------
    -- Sécurité supplémentaire
    --------------------------------------------------------

    self:restoreEnergySavingState()


    --------------------------------------------------------
    -- Timers
    --------------------------------------------------------

    self:stopKeepaliveExitWatch()


    if self.clickTimer then

        self.clickTimer:stop()


        self.clickTimer =
            nil

    end


    if self.returnMouseTimer then

        self.returnMouseTimer:stop()


        self.returnMouseTimer =
            nil

    end


    self:releaseActivityKey()


    if self.keyboardBacklightProbeTimer then

        self.keyboardBacklightProbeTimer:stop()


        self.keyboardBacklightProbeTimer =
            nil

    end


    if self.keyboardBacklightProbeRetryTimer then

        self.keyboardBacklightProbeRetryTimer:stop()


        self.keyboardBacklightProbeRetryTimer =
            nil

    end


    --------------------------------------------------------
    -- Hotkeys
    --------------------------------------------------------

    self:deleteHotkeys()


    --------------------------------------------------------
    -- Menubar
    --------------------------------------------------------

    if self.menuBar then

        self.menuBar:delete()


        self.menuBar =
            nil

    end


    --------------------------------------------------------
    -- Watcher
    --------------------------------------------------------

    if self.inputWatcher then

        self.inputWatcher:stop()


        self.inputWatcher =
            nil

    end


    self:log(
        "Spoon arrêté"
    )


    return self

end



------------------------------------------------------------
-- RETOUR SPOON
------------------------------------------------------------

return obj
