------------------------------------------------------------
-- WireGuardVPN Spoon
--
-- Version : 1.2.0
--
-- États :
--
--   🔴 VPN  déconnecté
--   🟢 VPN  connecté
--   🔵 VPN  transition
--   🟠 VPN  erreur
--
-- Interactions :
--
--   Simple clic :
--       ouvre le menu
--
--   Double clic :
--       connexion / déconnexion
--
------------------------------------------------------------


local obj = {}

obj.__index = obj



------------------------------------------------------------
-- MÉTADONNÉES
------------------------------------------------------------

obj.name = "WireGuardVPN"

obj.version = "1.2.0"

obj.author = "Benjamin Cerede / OpenAI"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

obj.interfaceName = "wg0"


obj.configFile =
    "/opt/homebrew/etc/wireguard/wg0.conf"


obj.bashPath =
    "/opt/homebrew/bin/bash"


obj.wgQuickPath =
    "/opt/homebrew/bin/wg-quick"


obj.sudoPath =
    "/usr/bin/sudo"


obj.ifconfigPath =
    "/sbin/ifconfig"


obj.refreshInterval = 10

obj.doubleClickInterval = 0.25

-- Icône dans la barre des menus. Le menu reste joignable via le
-- sous-menu de SpoonManager, qui sait la réafficher.
obj.showMenuBar = true

obj.showNotifications = true

obj.verboseLogging = false



------------------------------------------------------------
-- ÉTATS
------------------------------------------------------------

obj.STATE = {

    DISCONNECTED = "DISCONNECTED",

    CONNECTED = "CONNECTED",

    CONNECTING = "CONNECTING",

    DISCONNECTING = "DISCONNECTING",

    ERROR = "ERROR"

}



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.currentState =
    obj.STATE.DISCONNECTED


obj.menuBar =
    nil


obj.refreshTimer =
    nil


obj.currentTask =
    nil


obj.wgIP =
    nil


obj.lastError =
    nil


obj.lastStateChange =
    nil


obj.clickCount =
    0


obj.clickTimer =
    nil



------------------------------------------------------------
-- LOG
------------------------------------------------------------

function obj:log(message)

    print(

        string.format(

            "%s - WireGuardVPN %s - %s",

            os.date("%Y-%m-%d %H:%M:%S"),

            self.version,

            tostring(message)

        )

    )

end



------------------------------------------------------------
-- TRIM
------------------------------------------------------------

function obj:trim(value)

    if not value then
        return nil
    end


    return (

        value
            :gsub("^%s+", "")
            :gsub("%s+$", "")

    )

end



------------------------------------------------------------
-- LECTURE IP WIREGUARD
------------------------------------------------------------

function obj:readWireGuardIP()

    local file,
          errorMessage =

        io.open(
            self.configFile,
            "r"
        )


    if not file then

        self.lastError =

            "Config illisible : "
            .. self.configFile
            .. " - "
            .. tostring(errorMessage)


        self:log(
            self.lastError
        )


        return nil

    end


    local address =
        nil


    for line in file:lines() do

        local value =

            line:match(
                "^%s*Address%s*=%s*(.-)%s*$"
            )


        if value then

            value =

                value:match(
                    "^%s*([^,%s]+)"
                )


            if value then

                address =

                    value:match(
                        "^([^/]+)"
                    )

            end


            break

        end

    end


    file:close()


    if not address
        or address == "" then


        self.lastError =

            "Directive Address introuvable dans "
            .. self.configFile


        self:log(
            self.lastError
        )


        return nil

    end


    self.wgIP =
        self:trim(address)


    self.lastError =
        nil


    return self.wgIP

end



------------------------------------------------------------
-- VALIDATION CONFIGURATION
------------------------------------------------------------

function obj:validateConfiguration()

    local requiredFiles = {

        self.bashPath,

        self.wgQuickPath,

        self.sudoPath,

        self.ifconfigPath,

        self.configFile

    }


    for _, path in ipairs(requiredFiles) do

        if not hs.fs.attributes(path) then

            return false,
                "Fichier introuvable : "
                .. path

        end

    end


    local ip =
        self:readWireGuardIP()


    if not ip then

        return false,
            self.lastError
            or "IP WireGuard introuvable"

    end


    return true, nil

end



------------------------------------------------------------
-- DÉTECTION CONNEXION
------------------------------------------------------------

function obj:isConnected()

    if not self.wgIP then

        if not self:readWireGuardIP() then

            return false

        end

    end


    local output,
          success,
          terminationType,
          returnCode =

        hs.execute(

            self.ifconfigPath
            .. " -a 2>/dev/null",

            true

        )


    if not success then

        self.lastError =

            "Erreur ifconfig : "
            .. tostring(terminationType)
            .. " / "
            .. tostring(returnCode)


        return false

    end


    local escapedIP =

        self.wgIP:gsub(
            "([^%w])",
            "%%%1"
        )


    local pattern =

        "inet%s+"
        .. escapedIP
        .. "%s"


    return

        output:match(pattern)
        ~= nil

end



------------------------------------------------------------
-- LABEL ÉTAT
------------------------------------------------------------

function obj:getStateLabel()

    if self.currentState == self.STATE.CONNECTED then

        return "Connecté"

    end


    if self.currentState == self.STATE.DISCONNECTED then

        return "Déconnecté"

    end


    if self.currentState == self.STATE.CONNECTING then

        return "Connexion en cours"

    end


    if self.currentState == self.STATE.DISCONNECTING then

        return "Déconnexion en cours"

    end


    if self.currentState == self.STATE.ERROR then

        return "Erreur"

    end


    return "Inconnu"

end



------------------------------------------------------------
-- MISE À JOUR ICÔNE
------------------------------------------------------------

function obj:updateMenuBar()

    if not self.menuBar then
        return
    end


    if self.currentState == self.STATE.CONNECTED then

        self.menuBar:setTitle(
            "🟢 VPN"
        )


        self.menuBar:setTooltip(

            "VPN Maison connecté"
            .. (
                self.wgIP
                and " - " .. self.wgIP
                or ""
            )

        )


        return

    end


    if self.currentState == self.STATE.DISCONNECTED then

        self.menuBar:setTitle(
            "🔴 VPN"
        )


        self.menuBar:setTooltip(
            "VPN Maison déconnecté"
        )


        return

    end


    if self.currentState == self.STATE.CONNECTING
        or self.currentState == self.STATE.DISCONNECTING then


        self.menuBar:setTitle(
            "🔵 VPN"
        )


        self.menuBar:setTooltip(
            self:getStateLabel()
        )


        return

    end


    self.menuBar:setTitle(
        "🟠 VPN"
    )


    self.menuBar:setTooltip(

        self.lastError
        or "Erreur WireGuard"

    )

end



------------------------------------------------------------
-- CHANGEMENT ÉTAT
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


    self.lastStateChange =
        os.time()


    self:updateMenuBar()


    self:log(

        string.format(

            "État : %s -> %s",

            oldState,

            newState

        )

    )

end



------------------------------------------------------------
-- NOTIFICATION
------------------------------------------------------------

function obj:notify(title, message)

    if not self.showNotifications then
        return
    end


    hs.notify.new({

        title = title,

        informativeText = message

    }):send()

end



------------------------------------------------------------
-- ACTUALISATION ÉTAT
------------------------------------------------------------

function obj:refreshState()

    if self.currentTask
        and self.currentTask:isRunning() then

        return self

    end


    local valid,
          errorMessage =

        self:validateConfiguration()


    if not valid then

        self.lastError =
            errorMessage


        self:setState(
            self.STATE.ERROR
        )


        return self

    end


    if self:isConnected() then

        self:setState(
            self.STATE.CONNECTED
        )

    else

        self:setState(
            self.STATE.DISCONNECTED
        )

    end


    return self

end



------------------------------------------------------------
-- EXÉCUTION WG-QUICK
------------------------------------------------------------

function obj:runWGQuick(action)

    if self.currentTask
        and self.currentTask:isRunning() then


        self:notify(

            "WireGuard VPN",

            "Une opération est déjà en cours."

        )


        return self

    end


    if action ~= "up"
        and action ~= "down" then


        self.lastError =
            "Action invalide : "
            .. tostring(action)


        self:setState(
            self.STATE.ERROR
        )


        return self

    end


    local valid,
          errorMessage =

        self:validateConfiguration()


    if not valid then

        self.lastError =
            errorMessage


        self:setState(
            self.STATE.ERROR
        )


        self:notify(
            "WireGuard VPN",
            errorMessage
        )


        return self

    end


    if action == "up" then

        self:setState(
            self.STATE.CONNECTING
        )

    else

        self:setState(
            self.STATE.DISCONNECTING
        )

    end


    self.lastError =
        nil


    self.currentTask =

        hs.task.new(

            self.sudoPath,

            function(
                exitCode,
                stdOut,
                stdErr
            )

                self.currentTask =
                    nil


                if exitCode == 0 then

                    self:log(
                        "wg-quick "
                        .. action
                        .. " terminé"
                    )


                    hs.timer.doAfter(

                        1,

                        function()

                            self:refreshState()


                            if action == "up"
                                and self.currentState
                                == self.STATE.CONNECTED then


                                self:notify(

                                    "VPN Maison",

                                    "Connecté"
                                    .. (
                                        self.wgIP
                                        and " - " .. self.wgIP
                                        or ""
                                    )

                                )

                            elseif action == "down"
                                and self.currentState
                                == self.STATE.DISCONNECTED then


                                self:notify(

                                    "VPN Maison",

                                    "Déconnecté"

                                )

                            end

                        end

                    )


                    return

                end


                local errorOutput =
                    self:trim(stdErr)


                if not errorOutput
                    or errorOutput == "" then

                    errorOutput =
                        self:trim(stdOut)

                end


                if not errorOutput
                    or errorOutput == "" then

                    errorOutput =

                        "wg-quick retourne le code "
                        .. tostring(exitCode)

                end


                self.lastError =
                    errorOutput


                self:setState(
                    self.STATE.ERROR
                )


                self:log(
                    "ERREUR : "
                    .. errorOutput
                )


                self:notify(

                    "Erreur WireGuard",

                    errorOutput

                )

            end,

            {

                "-n",

                self.bashPath,

                self.wgQuickPath,

                action,

                self.interfaceName

            }

        )


    if not self.currentTask then

        self.lastError =
            "Impossible de créer la tâche"


        self:setState(
            self.STATE.ERROR
        )


        return self

    end


    local started =
        self.currentTask:start()


    if not started then

        self.currentTask =
            nil


        self.lastError =
            "Impossible de démarrer wg-quick"


        self:setState(
            self.STATE.ERROR
        )

    end


    return self

end



------------------------------------------------------------
-- CONNEXION
------------------------------------------------------------

function obj:connect()

    if self:isConnected() then

        self:setState(
            self.STATE.CONNECTED
        )


        return self

    end


    return self:runWGQuick(
        "up"
    )

end



------------------------------------------------------------
-- DÉCONNEXION
------------------------------------------------------------

function obj:disconnect()

    if not self:isConnected() then

        self:setState(
            self.STATE.DISCONNECTED
        )


        return self

    end


    return self:runWGQuick(
        "down"
    )

end



------------------------------------------------------------
-- TOGGLE
------------------------------------------------------------

function obj:toggle()

    if self.currentState == self.STATE.CONNECTED then

        return self:disconnect()

    end


    if self.currentState == self.STATE.DISCONNECTED then

        return self:connect()

    end


    if self.currentState == self.STATE.ERROR then

        if self:isConnected() then

            return self:disconnect()

        end


        return self:connect()

    end


    return self

end



------------------------------------------------------------
-- CONSTRUCTION MENU
------------------------------------------------------------

function obj:buildMenu()

    local menu = {}


    table.insert(
        menu,
        {
            title =
                "VPN Maison : "
                .. self:getStateLabel(),

            disabled = true
        }
    )


    if self.wgIP then

        table.insert(
            menu,
            {
                title =
                    "IP tunnel : "
                    .. self.wgIP,

                disabled = true
            }
        )

    end


    if self.currentState == self.STATE.ERROR
        and self.lastError then


        table.insert(
            menu,
            {
                title =
                    "Erreur : "
                    .. self.lastError,

                disabled = true
            }
        )

    end


    table.insert(
        menu,
        {
            title = "-"
        }
    )


    if self.currentState == self.STATE.CONNECTED then

        table.insert(
            menu,
            {
                title =
                    "Désactiver le VPN",

                fn = function()

                    self:disconnect()

                end
            }
        )

    elseif self.currentState == self.STATE.DISCONNECTED
        or self.currentState == self.STATE.ERROR then


        table.insert(
            menu,
            {
                title =
                    "Activer le VPN",

                fn = function()

                    self:connect()

                end
            }
        )

    else

        table.insert(
            menu,
            {
                title =
                    self:getStateLabel()
                    .. "…",

                disabled = true
            }
        )

    end


    table.insert(
        menu,
        {
            title =
                "Actualiser l'état",

            fn = function()

                self:refreshState()

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
                "Double-clic : activer / désactiver",

            disabled = true
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
                "Ouvrir la console Hammerspoon",

            fn = function()

                hs.openConsole()

            end
        }
    )


    table.insert(
        menu,
        {
            title =
                "Recharger Hammerspoon",

            fn = function()

                hs.reload()

            end
        }
    )


    return menu

end



------------------------------------------------------------
-- OUVERTURE MENU MANUELLE
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

            x = frame.x,

            y = frame.y + frame.h

        }

    else

        point =
            hs.mouse.absolutePosition()

    end


    self.menuBar:popupMenu(
        point
    )


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
        self.clickCount + 1


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


        self:log(
            "Double clic : toggle VPN"
        )


        self:toggle()

    end

end



------------------------------------------------------------
-- MENUBAR
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
-- START
------------------------------------------------------------

function obj:start()

    self:createMenuBar()


    self:refreshState()


    if self.refreshTimer then

        self.refreshTimer:stop()

    end


    self.refreshTimer =

        hs.timer.doEvery(

            self.refreshInterval,

            function()

                self:refreshState()

            end

        )


    self:log(

        string.format(

            "Démarré - interface=%s - refresh=%ds",

            self.interfaceName,

            self.refreshInterval

        )

    )


    return self

end



------------------------------------------------------------
-- STOP
------------------------------------------------------------

function obj:stop()

    if self.refreshTimer then

        self.refreshTimer:stop()

        self.refreshTimer =
            nil

    end


    if self.clickTimer then

        self.clickTimer:stop()

        self.clickTimer =
            nil

    end


    if self.currentTask
        and self.currentTask:isRunning() then


        self.currentTask:terminate()

    end


    self.currentTask =
        nil


    if self.menuBar then

        self.menuBar:delete()

        self.menuBar =
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