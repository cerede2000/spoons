# WindowSwitcher.spoon

Spoon Hammerspoon pour remplacer un switcher de fenetres type Windows Alt+Tab, AltTab ou BetterCmdTab.

## Installation

Copier le dossier `WindowSwitcher.spoon` dans :

```text
~/.hammerspoon/Spoons/
```

Puis ajouter dans `~/.hammerspoon/init.lua` :

```lua
hs.loadSpoon("WindowSwitcher")

spoon.WindowSwitcher:bindHotkeys({
    forward = {
        {"alt"},
        "tab"
    },
    backward = {
        {"alt", "shift"},
        "tab"
    },
})

spoon.WindowSwitcher:start()
```

## Raccourcis

- `Option + Tab` : fenetre suivante.
- `Option + Maj + Tab` : fenetre precedente.
- Relacher les modificateurs : selectionne et active la fenetre.

## Fonctionnalites

- Switch par fenetre, pas seulement par application.
- Tri par derniere fenetre focussee.
- Vue en grille compacte, proche de BetterCmdTab/AltTab/Windows.
- Panneau clair, translucide, centre, avec marge de securite autour de l'ecran.
- Captures reelles via `hs.window.snapshotForID`, puis helper ScreenCaptureKit si necessaire.
- Filtre de fenetres permanent : `hs.window.filter` n'est monte qu'une fois, au demarrage.
- Une seule resolution d'application par fenetre et par session, portee par un descripteur.
- Fin de session detectee par un eventtap `flagsChanged`, sans sondage clavier.
- Ordre de profondeur lu au WindowServer via `hs.window._orderedwinids()`.
- Application masquee par Cmd+H demasquee avant l'activation.
- Fallback propre avec grande icone d'application centree si macOS refuse une capture.
- Affichage immediat : les captures ScreenCaptureKit sont chargees en arriere-plan.
- Selection souris : survol pour selectionner, clic pour activer directement la fenetre.
- Restauration des fenetres minimisees avant focus.
- Inclusion des fenetres minimisees et cachees par defaut.
- Inclusion des autres Spaces par defaut, dans les limites des API macOS exposees a Hammerspoon.
- Exclusion par bundle ID via `ignored-bundles.txt`.
- Activation/desactivation possible via `SpoonManager`.
- Rendu via un seul `hs.canvas`, pour eviter de creer/detruire beaucoup d'objets graphiques a chaque switch.
- Anti-rebond clavier via `stepThrottleSeconds`, pour eviter les sauts de selection.

## Options utiles

```lua
spoon.WindowSwitcher.maxColumns = 4
spoon.WindowSwitcher.maxRows = 3
spoon.WindowSwitcher.maxPanelWidthRatio = 0.78
spoon.WindowSwitcher.maxPanelHeightRatio = 0.62
spoon.WindowSwitcher.screenMargin = 64
spoon.WindowSwitcher.previewMaxWidth = 300
spoon.WindowSwitcher.previewMaxHeight = 190
spoon.WindowSwitcher.snapshotCacheSeconds = 20
spoon.WindowSwitcher.snapshotCacheMaxEntries = 200
spoon.WindowSwitcher.screenCaptureHelperEnabled = true
spoon.WindowSwitcher.instantVisibleSnapshots = true
spoon.WindowSwitcher.maxConcurrentScreenCaptures = 2
spoon.WindowSwitcher.screenCapturePixelHeight = 420
spoon.WindowSwitcher.screenCaptureFailureBackoffSeconds = 5
spoon.WindowSwitcher.screenCaptureRequestTimeoutSeconds = 6.5
spoon.WindowSwitcher.logScreenCaptureFailures = true
spoon.WindowSwitcher.stepThrottleSeconds = 0.06
spoon.WindowSwitcher.completeWithAllWindows = false
spoon.WindowSwitcher.modifierSafetyInterval = 0.35
spoon.WindowSwitcher.redrawCoalesceSeconds = 0.05
spoon.WindowSwitcher.mouseActivationDistance = 6
spoon.WindowSwitcher.focusReassertDelay = 0.12
spoon.WindowSwitcher.snapshotBudgetSeconds = 0.045
```

### Temps de la premiere ouverture

`hs.window.snapshotForID` est synchrone. Capturer douze tuiles avant le
premier affichage, c'est le temps de fabrication que l'on ressent a la
premiere ouverture, quand aucun cache n'est encore chaud.

`snapshotBudgetSeconds` borne ce que l'on s'autorise avant d'afficher.
Les tuiles sont rechauffees en partant de la selection, puis de proche
en proche : si le budget ne suffit pas, ce n'est jamais la tuile qu'on
regarde qui attend. Les autres arrivent au rendu suivant, sans bloquer.

L'augmenter donne plus de vignettes reelles des la premiere image, au
prix d'une ouverture plus lente ; le reduire fait apparaitre l'icone de
l'application le temps d'un rendu.

### Mesurer

```lua
spoon.WindowSwitcher:benchmark()
```

Construit une session complete sans l'afficher et detaille dans la
console le temps de chaque etape : collecte, geometrie, captures, rendu.
Le cache est vide d'office, pour reproduire la premiere ouverture ;
`benchmark(false)` le conserve.

### Le levier principal

`completeWithAllWindows` commande la seconde passe d'inventaire, faite
avec `hs.window.allWindows()`. C'est un balayage d'accessibilite de
toutes les applications lancees, et de loin l'operation la plus couteuse
d'une session. Elle rattrape les fenetres que le filtre n'a pas encore
vues, typiquement juste apres le demarrage d'une application.

Elle existait parce que le filtre etait reconstruit a froid a chaque
`Option+Tab` et pouvait donc etre incomplet. Le filtre est desormais
permanent et tenu a jour par evenements : il est la source de verite, et
cette seconde passe ne rattrape plus rien. Elle est donc **desactivee
par defaut** depuis la 0.9.0, ce qui divise environ par deux le cout
d'un `Option+Tab`.

C'est le seul changement de la 0.9.0 qui porte un risque de
comportement. Si une fenetre venait a manquer dans la grille :

```lua
spoon.WindowSwitcher.completeWithAllWindows = true
```

Le panneau est toujours calcule depuis le contenu puis limite par `maxPanelWidthRatio`, `maxPanelHeightRatio` et `screenMargin`, donc il ne doit jamais prendre tout l'ecran.

Les fenetres reduites utilisent le helper `window-capture-helper` fourni avec le Spoon pour obtenir une capture ScreenCaptureKit, comme les switchers natifs modernes. Si macOS ne fournit pas de capture exploitable, le Spoon affiche l'icone de l'app au centre de l'apercu au lieu d'une vignette noire.

Si macOS demande une permission "Enregistrement de l'ecran", l'accorder pour Hammerspoon ou pour le helper affiche. Sans cette permission, le switcher continue de fonctionner avec le fallback icone.

## Exclusions

Les bundle IDs ignores se configurent dans le fichier voisin :

```text
~/.hammerspoon/Spoons/WindowSwitcher.spoon/ignored-bundles.txt
```

Format :

```text
com.apple.controlcenter
com.apple.notificationcenterui
pro.bettercmdtab.BetterCmdTab
```

Une ligne par bundle ID. Les lignes vides et les commentaires commencant par `#` sont ignores.

Ne pas ajouter `com.hammerspoon.Hammerspoon` ici si tu veux voir la console Hammerspoon dans le switcher.

## Trouver un bundle ID

Depuis la console Hammerspoon, la console devient souvent l'app active. Chercher donc l'application par nom :

```lua
app = hs.application.find("Microsoft Outlook")
print(app:name(), app:bundleID())
```

```lua
app = hs.application.find("Microsoft Teams")
print(app:name(), app:bundleID())
```

## Notes BetterCmdTab

BetterCmdTab va plus loin qu'un script Hammerspoon : il combine WindowServer, Accessibility, ScreenCaptureKit et quelques API privees pour retrouver les fenetres, les onglets natifs, l'ordre exact, puis lever la fenetre cible.

Cette version Hammerspoon vise le coeur du besoin : un switcher Option+Tab par fenetre avec grille d'apercus reels et restauration des fenetres minimisees, sans processus externe permanent.

Pour tester proprement, quitter BetterCmdTab ou changer son raccourci, sinon il peut intercepter `Option + Tab` avant Hammerspoon.


## Le helper de capture

`WindowSwitcherCapture.app` est un service ScreenCaptureKit lance a la
demande. Le Spoon lui parle par fichiers, dans un repertoire de session
sous `/tmp/WindowSwitcher`, protege par un secret tire de `/dev/urandom`
et regenere a chaque demarrage. Le helper verifie la version du
protocole, le jeton, le secret, et refuse d'ecrire ailleurs que dans le
sous-repertoire `captures/` de la session.

Le service se termine seul apres 30 secondes sans requete. Le Spoon le
detecte par son identifiant de bundle et le relance a la demande.

### Reconstruire le binaire

```bash
swiftc -O window-capture-helper.swift -o window-capture-helper
```

Le binaire livre est signe ad hoc. **Le recompiler change son `cdhash`
et revoque l'autorisation Enregistrement de l'ecran** accordee dans les
Reglages Systeme : il faut la reaccorder ensuite. Ne le reconstruire que
si le fichier `.swift` a reellement change.

Le binaire compile et le bundle `.app` ne sont pas versionnes ici : la
signature ad hoc est propre a la machine qui l'a produite.
