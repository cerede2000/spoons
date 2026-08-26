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

obj.version = "1.0.0"

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


    self.tap:start()

    self:log("demarre")


    return self

end


function obj:stop()

    if self.tap then

        self.tap:stop()

        self.tap = nil

    end


    self:log("arrete")


    return self

end



return obj
