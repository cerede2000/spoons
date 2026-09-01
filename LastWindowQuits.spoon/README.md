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

## Bureaux et plein ecran

Quand une application passe en plein ecran, elle prend son propre
bureau. Toutes les autres se retrouvent sur d'autres bureaux, et
`app:allWindows()` renvoie alors une liste **vide** pour elles.
`hs.window.filter` le dit dans son propre code :

> *windows on a different space aren't picked up by `:allWindows()` at
> first refresh*

Ce zero etait lu comme « derniere fenetre fermee », et l'application
etait quittee sans que personne n'ait rien ferme.

### Ce que le WindowServer ne peut pas nous dire

La tentation est d'aller demander au WindowServer, qui lui voit tous les
bureaux. Mesure faite sur macOS 26 avec de vraies `NSWindow`, en
separant une fenetre **detruite** d'une fenetre seulement retiree de
l'ecran :

| etat | `CGSCopySpacesForWindows` | `onScreen` |
|---|---|---|
| ouverte, visible | `[1]` | oui |
| sur un autre bureau | `[204]` | non |
| `orderOut` (retiree de l'ecran) | `[1]` | non |
| **fermee (detruite)** | `[]` | non |
| identifiant bidon | `[]` | absente de `CGWindowList` |

Une fenetre reellement detruite perd donc bien son bureau — contrairement
a ce qu'une premiere mesure, faite sur une fenetre seulement `orderOut`,
avait laisse croire.

Cela ne sauve pas le recoupement pour autant. AppKit garde tres souvent
la `NSWindow` apres que l'utilisateur a ferme la fenetre : elle est
alors seulement `orderOut`, donc **encore posee sur un bureau**. Or une
fenetre situee sur un autre bureau repond exactement la meme chose.

**« Fermee mais retenue par l'application » et « ouverte sur un autre
bureau » sont indiscernables.** C'est ce qui rendait IINA definitivement
infermable. Le meme constat figure dans le code d'AltTab. Le recoupement
a ete retire.

Le switcher, lui, se sert de cette meme API sans risque : il ne pose que
la question de la **position** d'une fenetre dont il sait deja qu'elle
est vivante, et une reponse vide y vaut « ici ».

### Le balayage complet est etale, jamais abandonne

Un balayage complet -- celui du demarrage, et celui qui revient toutes
les trente secondes -- etablit la reference : combien de fenetres chaque
application possede. L'interrompre laisse cette reference incomplete,
et une application qui n'y figure pas n'est plus interrogee par les
balayages partiels, qui ne s'occupent que de celles dont on sait
qu'elles ont des fenetres. Elle devient invisible.

Une version bornait le temps de TOUS les balayages. Au demarrage les
caches d'accessibilite sont froids -- 2626 ms mesurees pour 57
applications, contre 36 ms une fois chauds -- donc le budget sautait des
les premieres applications, et le Spoon demarrait sans savoir quelles
fenetres existaient. Il ne fermait plus rien.

Mais il ne peut pas non plus monopoliser le thread principal -- celui-la
meme qui livre les frappes. Mesure sur la machine : **570 ms toutes les
trente secondes**, pendant lesquelles aucune touche n'etait transmise.
Assez, aussi, pour retarder la livraison des evenements synthetiques
d'ActivityKeeper au-dela de sa fenetre de grace, et lui faire prendre
ses propres keep-alives pour l'utilisateur.

Le balayage complet **reprend donc la ou il s'est arrete** au tick
suivant, jusqu'a couvrir tout le monde : meme reference etablie, en
morceaux de `scanTimeBudget`. Ce qui a ete vu avant la reprise est
conserve, ce qui reste a voir garde son comptage precedent.

Un balayage partiel, lui, s'interrompt sans reprise : il n'interroge que
les applications ayant deja des fenetres connues, et le tick suivant les
reverra de toute facon.

Le demarrage ne balaie qu'une fois. `primeSeenApps` et le balayage
initial interrogeaient tous deux l'ensemble des applications, et
appelaient `markSeen` dans exactement les memes cas : cinq secondes de
thread principal prises juste apres un rechargement, pour rien.

### Ce qui reste sur

Deux choses, et elles n'ont besoin d'aucune API privee :

1. **`mainWindow()`** — une fenetre retournee est une vraie fenetre.
   Tant que cette voie repond, un zero ne prouve rien. Un filet de
   `undecidableGraceSeconds` evite qu'une fenetre principale perimee ne
   bloque une application pour toujours.

2. **Ne jamais conclure sur une seule observation.** Un aveuglement de
   l'accessibilite dure quelques secondes ; une fermeture est
   definitive. Il faut `quitConfirmations` zeros de suite pour conclure.
   Une seule fenetre revue remet la serie a zero.

```lua
spoon.LastWindowQuits.quitConfirmations = 3
spoon.LastWindowQuits.quitConfirmationSpacing = 2
spoon.LastWindowQuits.undecidableGraceSeconds = 60
```

### Une confirmation est un instant, pas un appel

Six chemins distincts interrogent le comptage, et la fermeture d'une
fenetre en declenche plusieurs d'affilee. Mesure sur une vraie session :

```
00:14:49  Fenetre fermee : IINA
00:14:49  aucune fenetre vue, 1 confirmation(s) sur 3
00:14:49  aucune fenetre vue, 2 confirmation(s) sur 3
00:14:50  Quit programme pour IINA
```

Trois confirmations en une seconde. Compter les appels revenait donc a
ne rien confirmer du tout : la garde tombait exactement dans le cas
qu'elle devait couvrir, une salve pendant un aveuglement passager.

`quitConfirmationSpacing` impose un ecart minimal entre deux
confirmations retenues. Il reste sous la periode du scan de secours
(5 s) pour que deux scans consecutifs comptent toujours pour deux
confirmations : une fermeture reelle est conclue en une dizaine de
secondes, une salve ne vaut qu'une seule voix.

### Les etats indexes par pid sont effaces

macOS reattribue les pid. Serie de zeros, horodatage et etat indecidable
sont effaces a la fin de chaque application : sans cela une application
fraichement lancee heritait de la serie d'une autre et pouvait etre
fermee sur sa toute premiere observation.

### Le journal reste lisible

Le passage a l'etat indecidable n'est journalise qu'une fois, pas a
chaque scan : une application posee sur un autre bureau ecrivait sinon
une ligne toutes les cinq secondes, indefiniment.

Les services auxiliaires — `IINA Networking`, `Contenu web IINA` — se
taisent completement : un processus qui n'a jamais eu de fenetre ne peut
pas en perdre une derniere, donc son decompte n'interesse personne.
