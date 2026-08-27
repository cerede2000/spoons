------------------------------------------------------------
-- FinderPermanentDelete Spoon
--
-- Suppression definitive facon Windows dans le Finder.
--
--   Shift + Suppr (Maj + Delete) sur la selection
--     => declenche "Supprimer immediatement" natif de macOS
--        (equivalent du raccourci Cmd+Option+Suppr).
--
-- On NE contourne PAS la confirmation : le dialogue Finder
-- "... sera supprime immediatement" s'affiche toujours.
--
-- Ne s'active QUE lorsque le Finder est l'application active,
-- et laisse passer le raccourci natif quand on edite du texte
-- (renommage, champ de recherche...).
------------------------------------------------------------


local obj = {}

obj.__index = obj



------------------------------------------------------------
-- METADONNEES
------------------------------------------------------------

obj.name = "FinderPermanentDelete"

obj.version = "1.1.0"

obj.author = "Benjamin Cerede"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

-- Petite alerte visuelle au moment du declenchement.
obj.showNotifications = false

obj.verboseLogging = false



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.tap = nil



------------------------------------------------------------
-- LOG
------------------------------------------------------------

function obj:log(message)

    if not self.verboseLogging then

        return

    end


    print(
        string.format(
            "%s - FinderPermanentDelete %s - %s",
            os.date("%Y-%m-%d %H:%M:%S"),
            self.version,
            tostring(message)
        )
    )

end



------------------------------------------------------------
-- DETECTION : sommes-nous en train d'editer un champ texte ?
-- (renommage inline, champ de recherche, barre d'adresse...)
------------------------------------------------------------

function obj:isEditingText()

    local app =
        hs.application.frontmostApplication()


    if not app then

        return false

    end


    local axApp =
        hs.axuielement.applicationElement(app)


    if not axApp then

        return false

    end


    local focused =
        axApp:attributeValue("AXFocusedUIElement")


    if not focused then

        return false

    end


    local role =
        focused:attributeValue("AXRole")

    local subrole =
        focused:attributeValue("AXSubrole")


    -- Un champ editable a le focus => on laisse le comportement natif.
    if role == "AXTextField"
        or role == "AXTextArea"
        or role == "AXComboBox"
        or subrole == "AXSearchField"
        or subrole == "AXTextInput" then

        return true

    end


    return false

end




------------------------------------------------------------
-- LE TAP NE VIT QUE DANS LE FINDER
--
-- Il etait enregistre en permanence, alors que son callback commence
-- par verifier que le Finder est au premier plan. Un eventtap fait
-- passer chaque frappe du systeme par le thread principal de
-- Hammerspoon : tant que ce tap existe, le moindre blocage de ce
-- thread -- un balayage d'accessibilite, un appel bloquant, un autre
-- Spoon -- retarde la saisie PARTOUT, pas seulement dans le Finder.
--
-- Le test lui-meme est gratuit (0,0002 ms, mesure). Ce n'est donc pas
-- son cout qui pose probleme, c'est l'exposition. Hors du Finder, le
-- tap n'existe plus du tout et le clavier ne traverse plus Hammerspoon.
------------------------------------------------------------

obj.followFrontmostApp = true


function obj:finderIsFrontmost()

    local app =
        hs.application.frontmostApplication()


    return app ~= nil
        and app:bundleID() == "com.apple.finder"

end


function obj:syncTapToFrontmost()

    if not self.tap then

        return self

    end


    if not self.followFrontmostApp
        or self:finderIsFrontmost() then

        if not self.tapRunning then

            self.tap:start()

            self.tapRunning = true

        end

    elseif self.tapRunning then

        self.tap:stop()

        self.tapRunning = false

    end


    return self

end


function obj:startFrontmostWatcher()

    self:stopFrontmostWatcher()


    if not self.followFrontmostApp then

        return self

    end


    -- Tous les evenements, pas seulement activated : une application
    -- qui se termine ou se demasque change aussi le premier plan, et
    -- un evenement manque laisserait le tap dans le mauvais etat. Le
    -- test coute 0,0002 ms, on peut se permettre de le refaire.

    self.frontmostWatcher =
        hs.application.watcher.new(function()

            self:syncTapToFrontmost()

        end)


    self.frontmostWatcher:start()


    return self

end


function obj:stopFrontmostWatcher()

    if self.frontmostWatcher then

        self.frontmostWatcher:stop()

        self.frontmostWatcher = nil

    end


    return self

end


------------------------------------------------------------
-- START / STOP
------------------------------------------------------------

function obj:start()

    if self.tap then

        self.tap:stop()

        self.tap = nil

    end


    -- Touche "Suppr" principale (Backspace) = keycode 51.
    local kDelete =
        hs.keycodes.map["delete"] or 51


    self.tap =
        hs.eventtap.new(
            { hs.eventtap.event.types.keyDown },
            function(event)

                -- On n'agit que dans le Finder.
                local app =
                    hs.application.frontmostApplication()


                if not app
                    or app:bundleID() ~= "com.apple.finder" then

                    return false

                end


                local flags =
                    event:getFlags()


                -- Uniquement Shift seul (pas Cmd, Alt, etc.).
                if not flags:containExactly({ "shift" }) then

                    return false

                end


                -- Uniquement la touche Suppr principale.
                if event:getKeyCode() ~= kDelete then

                    return false

                end


                -- En pleine edition de texte => Shift+Suppr natif (texte).
                if self:isEditingText() then

                    return false

                end


                -- Suppression definitive native = Cmd+Option+Suppr.
                -- (Le Finder affiche son propre dialogue de confirmation.)
                hs.eventtap.keyStroke({ "cmd", "alt" }, "delete", 0)


                if self.showNotifications then

                    hs.alert.show("Suppression définitive")

                end


                return true    -- on consomme le Shift+Suppr d'origine

            end
        )


    self.tapRunning = false

    self:startFrontmostWatcher()

    self:syncTapToFrontmost()

    self:log("demarre")


    return self

end


function obj:stop()

    self:stopFrontmostWatcher()


    if self.tap then

        self.tap:stop()

        self.tap = nil

    end


    self.tapRunning = false


    self:log("arrete")


    return self

end



return obj
