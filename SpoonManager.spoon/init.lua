------------------------------------------------------------
-- SpoonManager Spoon
--
-- Menu central pour activer/desactiver les Spoons locaux.
--
-- Un Spoon peut declarer un accesseur "icon" : son entree devient
-- alors un sous-menu permettant de masquer ou reafficher son icone
-- dans la barre des menus, sans le desactiver.
------------------------------------------------------------


local obj = {}

obj.__index = obj



------------------------------------------------------------
-- METADONNEES
------------------------------------------------------------

obj.name = "SpoonManager"

obj.version = "1.3.0"

obj.author = "Benjamin Cerede / OpenAI"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

obj.menuTitle = "⚙️"

obj.settingsKey = "SpoonManager.enabledSpoons"

obj.showNotifications = true

obj.spoons = {}



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.menuBar = nil

obj.enabledSpoons = nil

-- Echecs de demarrage de la session en cours. Volontairement non
-- persiste : un echec transitoire ne doit pas se transformer en
-- preference enregistree et empecher le Spoon de redemarrer.
obj.failedSpoons = {}



------------------------------------------------------------
-- LOG / NOTIFICATIONS
------------------------------------------------------------

function obj:log(message)

    print(
        string.format(
            "%s - SpoonManager %s - %s",
            os.date("%Y-%m-%d %H:%M:%S"),
            self.version,
            tostring(message)
        )
    )

end


function obj:notify(title, message)

    if not self.showNotifications then

        return

    end


    hs.notify.new({
        title = title,
        informativeText = message,
    }):send()

end



------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------

-- Verifie une entree avant de l'accepter. Le role de ce Spoon est
-- d'isoler les pannes : une erreur de configuration ne doit pas plus
-- faire tomber le gestionnaire qu'un Spoon defaillant.
--
-- Renvoie ok, motif.

function obj:validateSpoonEntry(item, index, seen)

    if type(item) ~= "table" then

        return false,
            "entree #" .. tostring(index) .. " : ce n'est pas une table"

    end


    if type(item.id) ~= "string"
        or item.id == "" then

        return false,
            "entree #" .. tostring(index) .. " : identifiant manquant"

    end


    if seen[item.id] then

        return false,
            item.id .. " : identifiant deja enregistre"

    end


    -- Un start absent est presque toujours une faute de frappe sur le
    -- nom de la fonction : sans ce controle, l'entree serait acceptee
    -- et le demarrage compte comme reussi sans rien demarrer.

    if type(item.start) ~= "function" then

        return false,
            item.id .. " : 'start' absent ou n'est pas une fonction"

    end


    if item.stop ~= nil
        and type(item.stop) ~= "function" then

        return false,
            item.id .. " : 'stop' n'est pas une fonction"

    end


    return true

end


function obj:registerSpoons(spoons)

    self.spoons =
        {}


    self.failedSpoons =
        {}


    local seen =
        {}


    local rejected =
        0


    for index, item in ipairs(spoons or {}) do

        local ok,
              reason =
            self:validateSpoonEntry(item, index, seen)


        if not ok then

            rejected =
                rejected + 1


            self:log(
                "Entree ignoree - " .. tostring(reason)
            )

        else

            -- Un accesseur d'icone incomplet ne coute que le sous-menu,
            -- pas le Spoon : on le retire et on garde l'entree.

            if item.icon ~= nil
                and not self:hasIconControl(item) then

                self:log(
                    item.id
                    .. " : accesseur 'icon' incomplet, sous-menu ignore"
                )


                item.icon =
                    nil

            end


            seen[item.id] =
                true


            table.insert(
                self.spoons,
                item
            )

        end

    end


    if rejected > 0 then

        self:notify(
            "SpoonManager",
            tostring(rejected) .. " entree(s) ignoree(s), voir la console"
        )

    end


    -- Les etats charges se rapportaient peut-etre a une autre liste.

    self.enabledSpoons =
        nil


    return self

end


function obj:loadEnabledSpoons()

    local stored =
        hs.settings.get(self.settingsKey)


    if type(stored) ~= "table" then

        stored =
            {}

    end


    self.enabledSpoons =
        {}


    for _, item in ipairs(self.spoons) do

        -- registerSpoons garantit deja un identifiant, mais une table
        -- partiellement construite ici serait definitive : isEnabled
        -- ne relance le chargement que si enabledSpoons est nil.

        if type(item.id) == "string" then

            if stored[item.id] ~= nil then

                self.enabledSpoons[item.id] =
                    stored[item.id] == true

            else

                self.enabledSpoons[item.id] =
                    item.defaultEnabled ~= false

            end

        end

    end


    return self

end


function obj:saveEnabledSpoons()

    hs.settings.set(
        self.settingsKey,
        self.enabledSpoons or {}
    )


    return self

end


function obj:isEnabled(item)

    if not self.enabledSpoons then

        self:loadEnabledSpoons()

    end


    if type(item.id) ~= "string" then

        return false

    end


    return self.enabledSpoons[item.id] == true

end



------------------------------------------------------------
-- ICONE BARRE DES MENUS
------------------------------------------------------------

function obj:hasIconControl(item)

    return type(item.icon) == "table"
        and type(item.icon.get) == "function"
        and type(item.icon.set) == "function"

end


function obj:isIconVisible(item)

    if not self:hasIconControl(item) then

        return false

    end


    local ok,
          visible =
        pcall(item.icon.get)


    if not ok then

        self:log(
            "Erreur lecture icone "
            .. tostring(item.id)
            .. " : "
            .. tostring(visible)
        )


        return false

    end


    return visible == true

end


function obj:setIconVisible(item, visible)

    if not self:hasIconControl(item) then

        return self

    end


    local ok,
          err =
        pcall(
            item.icon.set,
            visible == true
        )


    if not ok then

        self:log(
            "Erreur icone "
            .. tostring(item.id)
            .. " : "
            .. tostring(err)
        )


        self:notify(
            "SpoonManager",
            "Erreur icone " .. tostring(item.label or item.id)
        )

    end


    self:updateMenuBar()


    return self

end


function obj:toggleIcon(item)

    return self:setIconVisible(
        item,
        not self:isIconVisible(item)
    )

end



------------------------------------------------------------
-- ACTIONS SPOONS
------------------------------------------------------------

function obj:runAction(item, actionName)

    local action =
        item[actionName]


    if type(action) ~= "function" then

        return true

    end


    local ok,
          err =
        pcall(action)


    if not ok then

        self:log(
            "Erreur "
            .. tostring(actionName)
            .. " "
            .. tostring(item.id)
            .. " : "
            .. tostring(err)
        )


        self:notify(
            "SpoonManager",
            "Erreur " .. tostring(item.label or item.id)
        )


        return false

    end


    return true

end


function obj:startManagedSpoon(item)

    if self:runAction(item, "start") then

        self.failedSpoons[item.id] =
            nil


        self:log(
            "Spoon active : "
            .. tostring(item.id)
        )


        return true

    end


    self.failedSpoons[item.id] =
        true


    return false

end


function obj:stopManagedSpoon(item)

    self.failedSpoons[item.id] =
        nil


    if self:runAction(item, "stop") then

        self:log(
            "Spoon desactive : "
            .. tostring(item.id)
        )


        return true

    end


    return false

end


function obj:setSpoonEnabled(item, enabled)

    if not self.enabledSpoons then

        self:loadEnabledSpoons()

    end


    local ok =
        false


    if enabled then

        ok =
            self:startManagedSpoon(item)

    else

        ok =
            self:stopManagedSpoon(item)

    end


    if ok then

        self.enabledSpoons[item.id] =
            enabled == true


        self:saveEnabledSpoons()

    end


    self:updateMenuBar()


    return self

end


function obj:toggleSpoon(item)

    return self:setSpoonEnabled(
        item,
        not self:isEnabled(item)
    )

end


function obj:startEnabledSpoons()

    self:loadEnabledSpoons()


    for _, item in ipairs(self.spoons) do

        if self:isEnabled(item) then

            -- L'echec est retenu pour l'affichage seulement. L'ecrire
            -- dans enabledSpoons transformerait une panne passagere en
            -- desactivation definitive.

            self:startManagedSpoon(item)

        end

    end


    return self

end



------------------------------------------------------------
-- HAMMERSPOON
------------------------------------------------------------

function obj:quitHammerspoon()

    local application =
        hs.application.get("Hammerspoon")


    if application then

        application:kill()

        return

    end


    hs.execute(
        "/usr/bin/osascript -e 'quit app \"Hammerspoon\"'"
    )

end



------------------------------------------------------------
-- MENU
------------------------------------------------------------

function obj:buildMenu()

    local menu =
        {}


    table.insert(
        menu,
        {
            title = "Spoons",
            disabled = true,
        }
    )


    for _, item in ipairs(self.spoons) do

        local enabled =
            self:isEnabled(item)


        -- L'entree reste cliquable et cochee comme avant : le
        -- sous-menu ne fait que s'ajouter, il ne remplace rien.

        local entry =
            {
                title = item.label or item.id,
                fn = function()

                    self:toggleSpoon(item)

                end,
            }


        -- Demarrage en echec : ni coche ni decoche. Le tiret distingue
        -- "je ne l'ai pas active" de "je l'ai active et il n'a pas
        -- demarre". La condition ne regarde pas enabled : lors d'une
        -- activation manuelle qui echoue, l'etat n'est pas enregistre,
        -- et l'echec resterait invisible.

        if self.failedSpoons[item.id] then

            entry.state =
                "mixed"


            entry.title =
                (item.label or item.id)
                .. " (echec au demarrage)"

        else

            entry.checked =
                enabled

        end


        if self:hasIconControl(item) then

            entry.menu =
                {
                    {
                        title = "Icone barre des menus",
                        checked = self:isIconVisible(item),

                        -- Un Spoon arrete n'a pas d'icone a piloter.
                        disabled = not enabled,

                        fn = function()

                            self:toggleIcon(item)

                        end,
                    },
                }

        end


        table.insert(
            menu,
            entry
        )

    end


    table.insert(
        menu,
        {
            title = "-",
        }
    )


    table.insert(
        menu,
        {
            title = "Ouvrir la console",
            fn = function()

                hs.openConsole()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Recharger Hammerspoon",
            fn = function()

                hs.reload()

            end,
        }
    )


    table.insert(
        menu,
        {
            title = "Quitter Hammerspoon",
            fn = function()

                self:quitHammerspoon()

            end,
        }
    )


    return menu

end


function obj:updateMenuBar()

    if not self.menuBar then

        return self

    end


    self.menuBar:setTitle(
        self.menuTitle
    )


    self.menuBar:setMenu(
        function()

            return self:buildMenu()

        end
    )


    return self

end


function obj:createMenuBar()

    if self.menuBar then

        return self:updateMenuBar()

    end


    self.menuBar =
        hs.menubar.new()


    if not self.menuBar then

        self:log(
            "ERREUR creation menubar"
        )


        return self

    end


    return self:updateMenuBar()

end



------------------------------------------------------------
-- START / STOP
------------------------------------------------------------

function obj:start()

    self:createMenuBar()

    self:startEnabledSpoons()

    self:updateMenuBar()

    self:log(
        "Spoon initialise"
    )


    return self

end


function obj:stop()

    -- Sans cela les Spoons geres continuaient de tourner apres l'arret
    -- du gestionnaire, sans plus aucune interface pour les eteindre.
    -- enabledSpoons n'est pas touche : c'est la preference de
    -- l'utilisateur, et un start() ulterieur doit les relancer.

    for _, item in ipairs(self.spoons) do

        if self:isEnabled(item) then

            self:stopManagedSpoon(item)

        end

    end


    if self.menuBar then

        self.menuBar:delete()

        self.menuBar =
            nil

    end


    return self

end


return obj
