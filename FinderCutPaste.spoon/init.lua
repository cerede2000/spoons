------------------------------------------------------------
-- FinderCutPaste Spoon
--
-- Couper / coller de fichiers et dossiers dans le Finder,
-- facon Windows.
--
--   Cmd+X  = Copier la selection + marquer "a deplacer"
--   Cmd+V  = Deplacer ici (Cmd+Option+V) si un Cmd+X precedait,
--            sinon coller normal (copie)
--   Cmd+C  = Copier normal, annule un couper en attente
--
-- Ne s'active QUE lorsque le Finder est l'application active,
-- et laisse passer le raccourci natif quand on edite du texte :
-- renommage d'un fichier/dossier, champ de recherche,
-- barre "Aller au dossier"...
------------------------------------------------------------


local obj = {}

obj.__index = obj



------------------------------------------------------------
-- METADONNEES
------------------------------------------------------------

obj.name = "FinderCutPaste"

obj.version = "1.2.0"

obj.author = "Benjamin Cerede"

obj.homepage = "Local Spoon"

obj.license = "MIT"



------------------------------------------------------------
-- CONFIGURATION PUBLIQUE
------------------------------------------------------------

-- Petite alerte visuelle au moment du couper.
obj.showNotifications = false

obj.verboseLogging = false

-- Duree pendant laquelle le Cmd+C que nous emettons nous-memes reste
-- reconnaissable. Passe ce delai, tout Cmd+C est considere comme
-- venant de l'utilisateur.
obj.syntheticCopyGracePeriod = 0.5



------------------------------------------------------------
-- VARIABLES INTERNES
------------------------------------------------------------

obj.tap = nil

-- Indicateur "ciseaux" dans la barre de menus (couper en attente).
obj.menuBar = nil

-- true = le dernier geste etait un "couper", le prochain Cmd+V deplace.
obj.cutPending = false

-- true = le prochain Cmd+C vu est celui qu'on emet nous-memes (synthetique)
-- lors du couper : il ne doit PAS annuler le couper en attente.
obj.ignoreSyntheticCopy = false

-- Minuteur qui rearme ignoreSyntheticCopy a false.
obj.syntheticCopyTimer = nil



------------------------------------------------------------
-- LOG
------------------------------------------------------------

function obj:log(message)

    if not self.verboseLogging then

        return

    end


    print(
        string.format(
            "%s - FinderCutPaste %s - %s",
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
-- INDICATEUR BARRE DE MENUS (couper en attente)
------------------------------------------------------------

-- Affiche l'icone ciseaux (avec le nombre d'elements si connu).
-- Marque le prochain Cmd+C comme etant le notre.
--
-- Sans expiration, ce drapeau restait arme si le Cmd+C synthetique
-- n'etait jamais observe par le tap : changement d'application, perte
-- de focus du Finder, tap desactive. Le prochain vrai Cmd+C de
-- l'utilisateur etait alors avale sans annuler le couper en attente,
-- et son Cmd+V suivant deplacait les fichiers coupes au lieu de coller
-- sa copie.

function obj:armSyntheticCopy()

    self.ignoreSyntheticCopy = true

    if self.syntheticCopyTimer then
        self.syntheticCopyTimer:stop()
    end

    self.syntheticCopyTimer =
        hs.timer.doAfter(
            self.syntheticCopyGracePeriod,
            function()
                self.syntheticCopyTimer = nil
                self.ignoreSyntheticCopy = false
            end
        )

end


function obj:disarmSyntheticCopy()

    self.ignoreSyntheticCopy = false

    if self.syntheticCopyTimer then
        self.syntheticCopyTimer:stop()
        self.syntheticCopyTimer = nil
    end

end


function obj:cancelCut()

    self.cutPending = false

    self:disarmSyntheticCopy()

    self:hideIndicator()

end


-- Recree l'indicateur plutot que de le sortir et le rentrer.
--
-- Un objet hs.menubar remis dans la barre apres removeFromMenuBar()
-- ne retrouve pas forcement son cablage : c'est le defaut qui rendait
-- les icones inertes dans les autres Spoons. Ici le menu "Annuler le
-- couper" en dependait.

function obj:showIndicator(count)

    local title = "✂️"

    if count and count > 1 then

        title = "✂️ " .. tostring(count)

    end


    if not self.menuBar then

        self.menuBar = hs.menubar.new(true)

        if not self.menuBar then

            return

        end


        self.menuBar:setMenu({
            {
                title = "Annuler le couper",
                fn = function()

                    self:cancelCut()

                end,
            },
        })

    end


    self.menuBar:setTitle(title)

end


function obj:hideIndicator()

    if self.menuBar then

        self.menuBar:delete()

        self.menuBar = nil

    end

end


-- Compte les elements selectionnes dans le Finder (AppleScript, non bloquant)
-- et met a jour le titre. Degradation silencieuse si l'automation est refusee.
function obj:updateCountAsync()

    hs.timer.doAfter(0, function()

        if not self.cutPending then

            return

        end


        local ok, result =
            hs.osascript.applescript(
                'tell application "Finder" to return (count of (get selection))'
            )


        if ok
            and type(result) == "number"
            and self.cutPending then

            self:showIndicator(result)

        end

    end)

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


    self.cutPending = false

    self.ignoreSyntheticCopy = false


    -- L'indicateur est cree a la demande, lors d'un couper.

    local kX =
        hs.keycodes.map["x"]

    local kC =
        hs.keycodes.map["c"]

    local kV =
        hs.keycodes.map["v"]


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


                -- Uniquement Cmd+touche pur (pas Cmd+Shift, Cmd+Alt...).
                if not flags:containExactly({ "cmd" }) then

                    return false

                end


                local keyCode =
                    event:getKeyCode()


                ----------------------------------------------------
                -- Cmd+X : couper des fichiers / dossiers
                ----------------------------------------------------
                if keyCode == kX then

                    if self:isEditingText() then

                        return false   -- edition texte => couper normal

                    end


                    self.cutPending = true

                    -- Le Cmd+C qu'on va emettre est le notre : il ne doit
                    -- pas annuler le couper en attente quand on le reverra.
                    self:armSyntheticCopy()

                    -- On copie ; le deplacement se fera au collage.
                    hs.eventtap.keyStroke({ "cmd" }, "c", 0)


                    -- Indicateur ciseaux dans la barre de menus + comptage.
                    self:showIndicator()

                    self:updateCountAsync()


                    if self.showNotifications then

                        hs.alert.show("Coupe")

                    end


                    return true        -- on consomme le Cmd+X d'origine

                end


                ----------------------------------------------------
                -- Cmd+C : une copie annule un couper en attente
                ----------------------------------------------------
                if keyCode == kC then

                    -- Cmd+C synthetique emis par notre couper : on l'ignore
                    -- pour ne pas annuler le couper en attente.
                    if self.ignoreSyntheticCopy then

                        self:disarmSyntheticCopy()

                        return false

                    end


                    -- Vrai Cmd+C utilisateur : une copie annule le couper.
                    if not self:isEditingText() then

                        self:cancelCut()

                    end


                    return false       -- copie normale

                end


                ----------------------------------------------------
                -- Cmd+V : coller (deplacer si couper en attente)
                ----------------------------------------------------
                if keyCode == kV then

                    if self:isEditingText() then

                        return false   -- edition texte => coller normal

                    end


                    if self.cutPending then

                        self.cutPending = false

                        self:disarmSyntheticCopy()

                        self:hideIndicator()

                        -- "Deplacer l'element ici" = Cmd+Option+V
                        hs.eventtap.keyStroke({ "cmd", "alt" }, "v", 0)

                        return true    -- on consomme le Cmd+V d'origine

                    end


                    return false       -- coller normal (copie)

                end


                return false

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


    if self.menuBar then

        self.menuBar:delete()

        self.menuBar = nil

    end


    self.cutPending = false

    self:disarmSyntheticCopy()

    self:log("arrete")


    return self

end



return obj
