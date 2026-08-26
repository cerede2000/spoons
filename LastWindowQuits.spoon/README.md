# LastWindowQuits.spoon

Spoon Hammerspoon qui quitte automatiquement une application quand sa derniere fenetre est fermee.

## Installation

Copier le dossier `LastWindowQuits.spoon` dans :

```text
~/.hammerspoon/Spoons/
```

Puis ajouter dans `~/.hammerspoon/init.lua` :

```lua
hs.loadSpoon("LastWindowQuits")

spoon.LastWindowQuits.quitDelay = 2
spoon.LastWindowQuits.showNotifications = true
spoon.LastWindowQuits.verboseLogging = false
spoon.LastWindowQuits.logToFile = true
spoon.LastWindowQuits.maxLogAgeSeconds = 24 * 60 * 60
spoon.LastWindowQuits.showMenuBar = false
spoon.LastWindowQuits.windowTransitionFallbackEnabled = true
spoon.LastWindowQuits.windowTransitionScanInterval = 1

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
})

spoon.LastWindowQuits:start()
```

Les bundle IDs ignores se configurent dans le fichier voisin :

```text
~/.hammerspoon/Spoons/LastWindowQuits.spoon/ignored-bundles.txt
```

Format :

```text
com.apple.finder
com.microsoft.Outlook
com.microsoft.teams2
com.objective-see.lulu.app
com.adobe.bridge
com.hnc.discord
pro.bettercmdtab.BetterCmdTab
com.microsoft.VSCode
com.google.Chrome
```

Une ligne par bundle ID. Les lignes vides et les commentaires commencant par `#` sont ignores.

## Trouver un bundle ID

Depuis la console Hammerspoon, `frontmostApplication()` renvoie souvent Hammerspoon lui-meme, car la console devient l'app active. Chercher donc l'application par nom :

```lua
app = hs.application.find("Microsoft Outlook")
print(app:name(), app:bundleID())
```

```lua
app = hs.application.find("Microsoft Teams")
print(app:name(), app:bundleID())
```

Pour lister les apps ouvertes contenant `Microsoft` :

```lua
for _, app in ipairs(hs.application.runningApplications()) do
    local name = app:name() or ""
    if name:lower():find("microsoft") then
        print(name, app:bundleID())
    end
end
```

Exemples courants :

```text
Microsoft Outlook  com.microsoft.Outlook
Microsoft Teams    com.microsoft.teams2
```

## Fonctionnalites

- Detection des fermetures de fenetres via `hs.window.filter`.
- Filtre Hammerspoon dedie au Spoon, pour eviter les effets de bord du filtre global.
- Ecoute des fenetres fermees et des fenetres retirees du filtre, utile avec des switchers comme BetterCmdTab.
- Surveillance de secours optionnelle : si l'evenement de fermeture n'est pas remonte par Hammerspoon, le Spoon detecte la transition d'une app de `1+` fenetre a `0` fenetre.
- Quit differe avec `quitDelay` pour eviter les faux positifs.
- Annulation du quit si une nouvelle fenetre apparait avant la fin du timer.
- Blacklist par bundle ID via `ignored-bundles.txt`, ou par nom d'application dans la config Lua.
- Exclusions dediees aux apps de fond, VPN, agents et apps systeme.
- Par defaut, seules les exclusions internes essentielles restent codees en dur : Hammerspoon, System Events et Security Agent.
- Pause temporaire depuis la barre de menus.
- Logs console et fichier `~/.hammerspoon/LastWindowQuits.log`, conserve 1 jour par defaut.
- Option "Hammerspoon au demarrage" depuis le menu.
- Option `showMenuBar = false` pour cacher `LWQ` dans la barre de menu.
- Option `windowTransitionFallbackEnabled = true` pour garder la detection fiable quand `hs.window.filter` rate un evenement.
- Simple clic sur `LWQ` pour le menu, double clic pour activer/desactiver.

Note : comme l'application d'origine, ce Spoon ecoute les notifications macOS de fermeture de fenetre. Le fallback `windowTransitionFallbackEnabled` sert de filet de securite quand macOS ou Hammerspoon ne remonte pas un evenement.

## BetterCmdTab

BetterCmdTab utilise aussi l'API Accessibilite pour lire et manipuler les fenetres. Si cette app est lancee, LWQ active plusieurs chemins de detection :

- `windowDestroyed` quand Hammerspoon voit une fermeture standard.
- `windowRejected` quand une fenetre sort du filtre Hammerspoon.
- un scan leger toutes les `windowTransitionScanInterval` secondes pour detecter la transition d'une app de `1+` fenetre a `0` fenetre.

Ajouter BetterCmdTab dans `ignored-bundles.txt` evite que LWQ tente de quitter BetterCmdTab lui-meme :

```text
pro.bettercmdtab.BetterCmdTab
```

## Applications a fenetres transitoires

Hammerspoon tient sa propre liste d'applications dont les fenetres sont
transitoires — Spotlight, le Centre de notifications, `loginwindow`, les
menulets — et s'en sert pour batir `hs.window.filter.default`.

Ce Spoon utilise `hs.window.filter.new(true)`, un filtre qui laisse tout
passer, et se privait donc de ce savoir. Le panneau de recherche de
Spotlight etait compte comme une fenetre ordinaire : chaque fois qu'on
le refermait, Spotlight etait vu comme ayant perdu sa derniere fenetre,
et quitte. `Commande + Espace` n'affichait alors plus rien.

Depuis la 1.8.0 cette liste est reprise. Ce n'est pas une exception de
plus : c'est cesser d'ignorer celle que la plateforme fournit deja.

```lua
spoon.LastWindowQuits.honourTransientWindowApps = false   -- revenir en arriere
```

Pour relancer Spotlight s'il a ete quitte :

```bash
launchctl kickstart -k gui/$(id -u)/com.apple.Spotlight
```
