------------------------------------------------------------
-- Hammerspoon - Configuration principale
--
-- Tous les Spoons sont charges et configures ici, puis confies a
-- SpoonManager, qui les demarre et permet de les activer ou de les
-- eteindre depuis un menu unique.
--
-- Trois principes :
--
--   1. Ce fichier fait autorite. Les Spoons qui persistent des
--      reglages les realignent sur ces valeurs au demarrage.
--
--   2. Un Spoon absent ou casse ne doit pas emporter toute la
--      configuration : chaque chargement est protege, et seul le
--      Spoon fautif manque a l'appel.
--
--   3. Rien n'est demarre a la main. SpoonManager decide, a partir de
--      defaultEnabled et de ce que l'utilisateur a choisi ensuite.
------------------------------------------------------------


-- Les animations de fenetre ralentissent activation et deplacement.
-- Un switcher gagne a s'en passer.
hs.window.animationDuration = 0


-- Message de confirmation au chargement. Il enumere ce qui a repondu
-- present : une reconstruction incomplete se voit immediatement.
local afficherConfirmation = true


local charges = {}

local manquants = {}


-- Charge un Spoon sans laisser une erreur emporter le reste du
-- fichier. Renvoie vrai si le Spoon est utilisable.
local function chargerSpoon(nom)

    local ok = pcall(hs.loadSpoon, nom)

    if ok and spoon[nom] then
        table.insert(charges, nom)
        return true
    end

    table.insert(manquants, nom)
    print("Hammerspoon : Spoon indisponible - " .. nom)

    return false

end


-- Entrees remises a SpoonManager. Une entree n'est retenue que si son
-- Spoon a bien ete charge.
local entrees = {}

local function inscrire(entree)

    if spoon[entree.id] then
        table.insert(entrees, entree)
    end

end


-- Accesseur d'icone standard : le sous-menu de SpoonManager s'en sert
-- pour masquer ou reafficher l'icone sans desactiver le Spoon.
local function accesseurIcone(nom)

    return {

        get = function()

            return spoon[nom].showMenuBar

        end,

        set = function(visible)

            spoon[nom]:setMenuBarVisible(visible)

        end

    }

end


------------------------------------------------------------
-- ACTIVITY KEEPER
------------------------------------------------------------

if chargerSpoon("ActivityKeeper") then


    -- TEMPORISATIONS

    -- Temps d'inactivité réel avant passage en KEEPALIVE
    spoon.ActivityKeeper.idleThreshold = 120

    -- Fréquence de contrôle de l'idle
    spoon.ActivityKeeper.checkInterval = 10

    -- Fréquence des keepalive
    spoon.ActivityKeeper.keepAliveInterval = 50

    -- Ne pas écouter mouseMoved/drag : évite de ralentir les déplacements de fenêtres
    spoon.ActivityKeeper.trackHighFrequencyPointerEvents = false

    -- Reprise immédiate uniquement en mode vert, sans ralentir le mode jaune
    spoon.ActivityKeeper.fastReturnWatcherEnabled = true
    spoon.ActivityKeeper.fastReturnThrottle = 0.20

    -- Détection lente du retour utilisateur en mode vert via hs.host.idleTime()
    spoon.ActivityKeeper.realActivityReturnIdleThreshold = 6

    -- Ignore le reset d'idle provoqué par un keepalive synthétique
    spoon.ActivityKeeper.postKeepAliveIdleIgnorePeriod = 8

    -- Intervalle maximum entre deux clics pour le double clic
    spoon.ActivityKeeper.doubleClickInterval = 0.30

    ------------------------------------------------------------
    -- CLAVIER SYNTHÉTIQUE

    spoon.ActivityKeeper.activityKey = "shift"
    spoon.ActivityKeeper.keyPressDuration = 0.05
    spoon.ActivityKeeper.keyboardBacklightEnforceAfterKeepAlive = true
    spoon.ActivityKeeper.keyboardBacklightEnforceDelay = 0.20
    spoon.ActivityKeeper.keepAliveAfterEnergySavingDelay = 1.0
    spoon.ActivityKeeper.keyboardBrightnessRestoreFallback = 0.50
    spoon.ActivityKeeper.keyboardAutoRestoreConfirmDelay = 0.25

    -- SOURIS SYNTHÉTIQUE

    spoon.ActivityKeeper.mouseMovePixels = 1
    spoon.ActivityKeeper.mouseReturnDelay = 0.15

    -- PROTECTION ÉVÉNEMENTS SYNTHÉTIQUES

    spoon.ActivityKeeper.syntheticEventGracePeriod = 1.0

    -- PROBE RÉTROÉCLAIRAGE CLAVIER

    -- Séquence :
    --
    --   Maj
    --   attente
    --   lecture mac-brightnessctl
    --   extinction

    spoon.ActivityKeeper.keyboardBacklightProbeDelay = 0.75
    spoon.ActivityKeeper.keyboardBacklightProbeRetries = 4
    spoon.ActivityKeeper.keyboardBacklightProbeRetryInterval = 0.25
    spoon.ActivityKeeper.keyboardBrightnessSampleInterval = 300

    -- VALEURS PAR DÉFAUT
    -- Les valeurs sauvegardées dans hs.settings ont priorité.

    -- KEEPALIVE
    -- UserActivity reste actif et Maj ajoute une activité clavier silencieuse.

    spoon.ActivityKeeper.defaultUserActivityEnabled = false
    spoon.ActivityKeeper.defaultKeyboardEnabled = true
    spoon.ActivityKeeper.defaultMouseEnabled = false
    spoon.ActivityKeeper.forceConfiguredModesOnStart = true

    -- ÉCONOMIES D'ÉNERGIE

    -- Rétroéclairage clavier
    spoon.ActivityKeeper.defaultKeyboardBacklightEnabled = true

    -- Réduction luminosité écran
    spoon.ActivityKeeper.defaultScreenDimmingEnabled = false

    -- Cible écran : 15 %
    spoon.ActivityKeeper.screenBrightnessTarget = 0.15

    -- Mode économie d'énergie macOS
    spoon.ActivityKeeper.defaultLowPowerModeEnabled = false

    -- Éco automatique en vert lorsque le Mac est sur batterie.
    spoon.ActivityKeeper.defaultAutomaticLowPowerModeEnabled = true
    spoon.ActivityKeeper.lowPowerBatteryThreshold = 15

    -- INTERFACE

    -- Icone dans la barre des menus. Masquable a chaud depuis le
    -- sous-menu de SpoonManager.
    spoon.ActivityKeeper.showMenuBar = true

    -- Activation globale des raccourcis declares plus bas.
    spoon.ActivityKeeper.hotkeysEnabled = true

    spoon.ActivityKeeper.showStateNotifications = true
    spoon.ActivityKeeper.verboseLogging = false

    local function startActivityKeeper()

        spoon.ActivityKeeper:bindHotkeys({

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

        })


        spoon.ActivityKeeper:start()

    end


    local function stopActivityKeeper()

        spoon.ActivityKeeper:stop()

    end


    inscrire({
        id = "ActivityKeeper",
        label = "ActivityKeeper",
        defaultEnabled = true,
        start = startActivityKeeper,
        stop = stopActivityKeeper,
        icon = accesseurIcone("ActivityKeeper"),
    })

end


------------------------------------------------------------
-- WIREGUARD VPN
------------------------------------------------------------

if chargerSpoon("WireGuardVPN") then



    spoon.WireGuardVPN.interfaceName = "wg0"

    spoon.WireGuardVPN.configFile =
        "/opt/homebrew/etc/wireguard/wg0.conf"

    spoon.WireGuardVPN.bashPath =
        "/opt/homebrew/bin/bash"

    spoon.WireGuardVPN.wgQuickPath =
        "/opt/homebrew/bin/wg-quick"

    spoon.WireGuardVPN.refreshInterval = 10

    spoon.WireGuardVPN.doubleClickInterval = 0.30

    -- Icone dans la barre des menus. Masquable a chaud depuis le
    -- sous-menu de SpoonManager.
    spoon.WireGuardVPN.showMenuBar = true

    spoon.WireGuardVPN.showNotifications = true

    spoon.WireGuardVPN.verboseLogging = false


    local function startWireGuardVPN()

        spoon.WireGuardVPN:start()

    end


    local function stopWireGuardVPN()

        spoon.WireGuardVPN:stop()

    end


    inscrire({
        id = "WireGuardVPN",
        label = "WireGuard VPN maison",
        defaultEnabled = true,
        start = startWireGuardVPN,
        stop = stopWireGuardVPN,
        icon = accesseurIcone("WireGuardVPN"),
    })

end


------------------------------------------------------------
-- LAST WINDOW QUITS
------------------------------------------------------------

if chargerSpoon("LastWindowQuits") then



    -- Ce fichier fait autorite : au demarrage le Spoon realigne
    -- hs.settings sur les valeurs ci-dessous. Les bascules faites en
    -- cours de session restent actives jusqu'au prochain rechargement.
    spoon.LastWindowQuits.forceConfiguredSettingsOnStart = true

    spoon.LastWindowQuits.quitDelay = 5

    spoon.LastWindowQuits.showNotifications = false

    spoon.LastWindowQuits.verboseLogging = false

    spoon.LastWindowQuits.logToFile = false

    spoon.LastWindowQuits.maxLogAgeSeconds = 24 * 60 * 60

    -- Pas d'icone dans la barre des menus. Le menu complet reste
    -- accessible sous le pointeur via le raccourci "menu" ci-dessous.
    spoon.LastWindowQuits.showMenuBar = false

    -- TEMPORISATIONS

    -- Periode du scan de secours. Le filtre de fenetres couvre deja les
    -- creations et fermetures : ce scan ne rattrape que les manques.
    spoon.LastWindowQuits.windowTransitionScanInterval = 5

    -- SECURITES

    -- Nombre maximum d'applications qu'un seul scan peut condamner.
    -- Au-dela, la cause est systeme et non l'utilisateur : on renonce.
    spoon.LastWindowQuits.maxSimultaneousScanQuits = 2

    -- Suspend la surveillance pendant veille, verrouillage et
    -- economiseur d'ecran : l'API d'accessibilite y rend des listes de
    -- fenetres vides pour toutes les applications.
    spoon.LastWindowQuits.suspendOnPowerEvents = true

    -- Delai laisse a macOS pour se stabiliser au reveil.
    spoon.LastWindowQuits.wakeGracePeriod = 15

    -- Delai avant de recompter les fenetres apres un retrait.
    spoon.LastWindowQuits.windowRemovalRecheckDelay = 0.15

    -- RACCOURCIS

    -- Activation globale des raccourcis declares plus bas.
    -- A false, aucun n'est lie : le mapping reste memorise et se
    -- reapplique des la reactivation. Pour n'en desactiver qu'un seul,
    -- commenter son entree dans bindHotkeys().
    spoon.LastWindowQuits.hotkeysEnabled = false

    -- Duree de la pause declenchee par le raccourci "pause".
    spoon.LastWindowQuits.hotkeyPauseDuration = 15 * 60

    -- Duree d'affichage du resume d'etat.
    spoon.LastWindowQuits.statusAlertDuration = 4

    local function startLastWindowQuits()

        spoon.LastWindowQuits:bindHotkeys({

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

        })


        spoon.LastWindowQuits:start()

    end


    local function stopLastWindowQuits()

        spoon.LastWindowQuits:stop()

    end


    inscrire({
        id = "LastWindowQuits",
        label = "Last Window Quits",
        defaultEnabled = true,
        start = startLastWindowQuits,
        stop = stopLastWindowQuits,
        icon = accesseurIcone("LastWindowQuits"),
    })

end


------------------------------------------------------------
-- WINDOW SWITCHER
------------------------------------------------------------

if chargerSpoon("WindowSwitcher") then




    spoon.WindowSwitcher.verboseLogging = false

    spoon.WindowSwitcher.includeMinimized = true

    spoon.WindowSwitcher.includeHidden = true

    spoon.WindowSwitcher.includeOtherSpaces = true

    local function startWindowSwitcher()

        spoon.WindowSwitcher:bindHotkeys({

            forward = {
                {"alt"},
                "tab"
            },

            backward = {
                {"alt", "shift"},
                "tab"
            }

        })


        spoon.WindowSwitcher:start()

    end


    local function stopWindowSwitcher()

        spoon.WindowSwitcher:stop()

    end


    inscrire({
        id = "WindowSwitcher",
        label = "Window Switcher",
        defaultEnabled = true,
        start = startWindowSwitcher,
        stop = stopWindowSwitcher,
    })

end


------------------------------------------------------------
-- FINDER CUT PASTE
------------------------------------------------------------

if chargerSpoon("FinderCutPaste") then



    spoon.FinderCutPaste.showNotifications = false

    spoon.FinderCutPaste.verboseLogging = false


    local function startFinderCutPaste()

        spoon.FinderCutPaste:start()

    end


    local function stopFinderCutPaste()

        spoon.FinderCutPaste:stop()

    end


    inscrire({
        id = "FinderCutPaste",
        label = "Finder Couper/Coller",
        defaultEnabled = true,
        start = startFinderCutPaste,
        stop = stopFinderCutPaste,
    })

end


------------------------------------------------------------
-- FINDER PERMANENT DELETE
------------------------------------------------------------

if chargerSpoon("FinderPermanentDelete") then



    spoon.FinderPermanentDelete.showNotifications = false

    spoon.FinderPermanentDelete.verboseLogging = false


    local function startFinderPermanentDelete()

        spoon.FinderPermanentDelete:start()

    end


    local function stopFinderPermanentDelete()

        spoon.FinderPermanentDelete:stop()

    end


    inscrire({
        id = "FinderPermanentDelete",
        label = "Finder Suppression definitive (Maj+Suppr)",
        defaultEnabled = true,
        start = startFinderPermanentDelete,
        stop = stopFinderPermanentDelete,
    })

end


------------------------------------------------------------
-- SPOON MANAGER
------------------------------------------------------------

if chargerSpoon("SpoonManager") then

    spoon.SpoonManager.menuTitle = "⚙️"

    spoon.SpoonManager.showNotifications = true


    spoon.SpoonManager:registerSpoons(entrees)

    spoon.SpoonManager:start()

else

    -- Sans gestionnaire, plus rien ne demarrerait : on demarre nous
    -- memes ce qui a pu etre charge, pour ne pas rester sans rien.

    for _, entree in ipairs(entrees) do

        pcall(entree.start)

    end

end



------------------------------------------------------------
-- CHARGEMENT TERMINE
------------------------------------------------------------

if afficherConfirmation then

    local message =
        "Hammerspoon : " .. #charges .. " Spoon(s) charge(s)"


    if #manquants > 0 then

        message =
            message .. "\nManquant(s) : " .. table.concat(manquants, ", ")

    end


    hs.alert.show(message)

end
