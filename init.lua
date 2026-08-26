------------------------------------------------------------
-- Hammerspoon - Configuration
--
-- Ce fichier ne fait que declarer. SpoonManager charge les Spoons,
-- leur applique ces reglages, branche les raccourcis, puis demarre
-- ceux qui doivent l'etre selon ce qui a ete choisi au menu.
--
-- Ce qu'il faut savoir :
--
--   * Ce fichier fait autorite au demarrage. Les bascules faites en
--     cours de session tiennent jusqu'au prochain rechargement.
--
--   * Un Spoon absent ne coute que lui-meme : les autres demarrent, et
--     le message de fin le nomme.
--
--   * Une cle de reglage qui n'existe pas dans un Spoon est signalee
--     en console. Une faute de frappe ne passe plus inapercue.
--
--   * start, stop et l'acces a l'icone sont deduits du Spoon. Ne les
--     declarer que si un Spoon demande autre chose.
------------------------------------------------------------


-- Les animations de fenetre ralentissent activation et deplacement.
hs.window.animationDuration = 0


-- Message de confirmation au chargement, qui nomme les manquants.
local afficherConfirmation = true


hs.loadSpoon("SpoonManager")


spoon.SpoonManager.menuTitle = "⚙️"

spoon.SpoonManager.showNotifications = true

spoon.SpoonManager.warnUnknownSettings = true


spoon.SpoonManager:setup({

    ------------------------------------------------------------
    -- ACTIVITY KEEPER
    ------------------------------------------------------------

    {
        id = "ActivityKeeper",
        label = "ActivityKeeper",

        settings = {

            -- TEMPORISATIONS
            -- Temps d'inactivité réel avant passage en KEEPALIVE
            idleThreshold = 120,

            -- Fréquence de contrôle de l'idle
            checkInterval = 10,

            -- Fréquence des keepalive
            keepAliveInterval = 50,

            -- Ne pas écouter mouseMoved/drag : évite de ralentir les déplacements de fenêtres
            trackHighFrequencyPointerEvents = false,

            -- Reprise immédiate uniquement en mode vert, sans ralentir le mode jaune
            fastReturnWatcherEnabled = true,

            fastReturnThrottle = 0.20,

            -- Détection lente du retour utilisateur en mode vert via hs.host.idleTime()
            realActivityReturnIdleThreshold = 6,

            -- Ignore le reset d'idle provoqué par un keepalive synthétique
            postKeepAliveIdleIgnorePeriod = 8,

            -- Intervalle maximum entre deux clics pour le double clic
            doubleClickInterval = 0.30,

            ------------------------------------------------------------
            -- CLAVIER SYNTHÉTIQUE
            activityKey = "shift",

            keyPressDuration = 0.05,

            keyboardBacklightEnforceAfterKeepAlive = true,

            keyboardBacklightEnforceDelay = 0.20,

            keepAliveAfterEnergySavingDelay = 1.0,

            keyboardBrightnessRestoreFallback = 0.50,

            keyboardAutoRestoreConfirmDelay = 0.25,

            -- SOURIS SYNTHÉTIQUE
            mouseMovePixels = 1,

            mouseReturnDelay = 0.15,

            -- PROTECTION ÉVÉNEMENTS SYNTHÉTIQUES
            syntheticEventGracePeriod = 1.0,

            -- PROBE RÉTROÉCLAIRAGE CLAVIER
            -- Séquence :
            --
            --   Maj
            --   attente
            --   lecture mac-brightnessctl
            --   extinction
            keyboardBacklightProbeDelay = 0.75,

            keyboardBacklightProbeRetries = 4,

            keyboardBacklightProbeRetryInterval = 0.25,

            keyboardBrightnessSampleInterval = 300,

            -- VALEURS PAR DÉFAUT
            -- Les valeurs sauvegardées dans hs.settings ont priorité.
            -- KEEPALIVE
            -- UserActivity reste actif et Maj ajoute une activité clavier silencieuse.
            defaultUserActivityEnabled = false,

            defaultKeyboardEnabled = true,

            defaultMouseEnabled = false,

            forceConfiguredModesOnStart = true,

            -- ÉCONOMIES D'ÉNERGIE
            -- Rétroéclairage clavier
            defaultKeyboardBacklightEnabled = true,

            -- Réduction luminosité écran
            defaultScreenDimmingEnabled = false,

            -- Cible écran : 15 %
            screenBrightnessTarget = 0.15,

            -- Mode économie d'énergie macOS
            defaultLowPowerModeEnabled = false,

            -- Éco automatique en vert lorsque le Mac est sur batterie.
            defaultAutomaticLowPowerModeEnabled = true,

            lowPowerBatteryThreshold = 15,

            -- INTERFACE
            -- Icone dans la barre des menus. Masquable a chaud depuis le
            -- sous-menu de SpoonManager.
            showMenuBar = true,

            -- Activation globale des raccourcis declares plus bas.
            hotkeysEnabled = true,

            showStateNotifications = true,

            verboseLogging = false,

        },

        hotkeys = {
                toggle = {
                    {"ctrl", "alt", "cmd"},
                    "J"
                },

                -- Ouvre le menu sous le pointeur, sans icone
                menu = {
                    {"ctrl", "alt", "cmd"},
                    "M"
                },

                -- Bulle indiquant l'etat courant
                status = {
                    {"ctrl", "alt", "cmd"},
                    "U"
                },

                -- Test manuel d'un keepalive
                test = {
                    {"ctrl", "alt", "cmd"},
                    "T"
                }
        },
    },


    ------------------------------------------------------------
    -- WIREGUARD VPN
    ------------------------------------------------------------

    {
        id = "WireGuardVPN",
        label = "WireGuard VPN maison",

        settings = {

            interfaceName = "wg0",

            configFile = "/opt/homebrew/etc/wireguard/wg0.conf",

            bashPath = "/opt/homebrew/bin/bash",

            wgQuickPath = "/opt/homebrew/bin/wg-quick",

            refreshInterval = 10,

            doubleClickInterval = 0.30,

            -- Icone dans la barre des menus. Masquable a chaud depuis le
            -- sous-menu de SpoonManager.
            showMenuBar = true,

            showNotifications = true,

            verboseLogging = false,

        },
    },


    ------------------------------------------------------------
    -- LAST WINDOW QUITS
    ------------------------------------------------------------

    {
        id = "LastWindowQuits",
        label = "Last Window Quits",

        settings = {

            -- Ce fichier fait autorite : au demarrage le Spoon realigne
            -- hs.settings sur les valeurs ci-dessous. Les bascules faites en
            -- cours de session restent actives jusqu'au prochain rechargement.
            forceConfiguredSettingsOnStart = true,

            quitDelay = 5,

            showNotifications = false,

            verboseLogging = false,

            logToFile = false,

            maxLogAgeSeconds = 24 * 60 * 60,

            -- Pas d'icone dans la barre des menus. Le menu complet reste
            -- accessible sous le pointeur via le raccourci "menu" ci-dessous.
            showMenuBar = false,

            -- TEMPORISATIONS
            -- Periode du scan de secours. Le filtre de fenetres couvre deja les
            -- creations et fermetures : ce scan ne rattrape que les manques.
            windowTransitionScanInterval = 5,

            -- SECURITES
            -- Nombre maximum d'applications qu'un seul scan peut condamner.
            -- Au-dela, la cause est systeme et non l'utilisateur : on renonce.
            maxSimultaneousScanQuits = 2,

            -- Suspend la surveillance pendant veille, verrouillage et
            -- economiseur d'ecran : l'API d'accessibilite y rend des listes de
            -- fenetres vides pour toutes les applications.
            suspendOnPowerEvents = true,

            -- Delai laisse a macOS pour se stabiliser au reveil.
            wakeGracePeriod = 15,

            -- Delai avant de recompter les fenetres apres un retrait.
            windowRemovalRecheckDelay = 0.15,

            -- RACCOURCIS
            -- Activation globale des raccourcis declares plus bas.
            -- A false, aucun n'est lie : le mapping reste memorise et se
            -- reapplique des la reactivation. Pour n'en desactiver qu'un seul,
            -- commenter son entree dans bindHotkeys().
            hotkeysEnabled = false,

            -- Duree de la pause declenchee par le raccourci "pause".
            hotkeyPauseDuration = 15 * 60,

            -- Duree d'affichage du resume d'etat.
            statusAlertDuration = 4,

        },

        hotkeys = {
                toggle = {
                    {"ctrl", "alt", "cmd"},
                    "Q"
                },

                pause = {
                    {"ctrl", "alt", "cmd"},
                    "P"
                },

                resume = {
                    {"ctrl", "alt", "cmd", "shift"},
                    "P"
                },

                -- Ouvre le menu complet sous le pointeur, sans icone
                menu = {
                    {"ctrl", "alt", "cmd"},
                    "L"
                },

                -- Resume d'etat : actif/pause, delai, quits en attente
                status = {
                    {"ctrl", "alt", "cmd"},
                    "I"
                },

                -- Blackliste l'application au premier plan
                blacklist = {
                    {"ctrl", "alt", "cmd"},
                    "B"
                },

                -- Annule tous les quits en attente
                cancel = {
                    {"ctrl", "alt", "cmd"},
                    "K"
                }
        },
    },


    ------------------------------------------------------------
    -- WINDOW SWITCHER
    ------------------------------------------------------------

    {
        id = "WindowSwitcher",
        label = "Window Switcher",

        settings = {

            verboseLogging = false,

            includeMinimized = true,

            includeHidden = true,

            includeOtherSpaces = true,

        },

        hotkeys = {
                forward = {
                    {"alt"},
                    "tab"
                },

                backward = {
                    {"alt", "shift"},
                    "tab"
                }
        },
    },


    ------------------------------------------------------------
    -- FINDER CUT PASTE
    ------------------------------------------------------------

    {
        id = "FinderCutPaste",
        label = "Finder Couper/Coller",

        settings = {

            showNotifications = false,

            verboseLogging = false,

        },
    },


    ------------------------------------------------------------
    -- FINDER PERMANENT DELETE
    ------------------------------------------------------------

    {
        id = "FinderPermanentDelete",
        label = "Finder Suppression definitive (Maj+Suppr)",

        settings = {

            showNotifications = false,

            verboseLogging = false,

        },
    },


})



------------------------------------------------------------
-- CHARGEMENT TERMINE
------------------------------------------------------------

if afficherConfirmation then

    local manquants = {}

    for id in pairs(spoon.SpoonManager.missingSpoons or {}) do

        table.insert(manquants, id)

    end


    table.sort(manquants)


    local message =
        "Hammerspoon : "
        .. #spoon.SpoonManager.spoons
        .. " Spoon(s) charge(s)"


    if #manquants > 0 then

        message =
            message .. "\nManquant(s) : " .. table.concat(manquants, ", ")

    end


    hs.alert.show(message)

end
