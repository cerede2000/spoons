# Spoons

Modules [Hammerspoon](https://www.hammerspoon.org), chargés et pilotés par
**SpoonManager**, qui les active ou les désactive depuis un menu unique.

| Spoon | rôle |
|---|---|
| [SpoonManager](SpoonManager.spoon/) | menu central : active/désactive les autres Spoons, masque leur icône |
| [ActivityKeeper](ActivityKeeper.spoon/) | maintien de présence, avec réduction de consommation en veille |
| [LastWindowQuits](LastWindowQuits.spoon/) | ferme une application quand sa dernière fenêtre est fermée |
| [WireGuardVPN](WireGuardVPN.spoon/) | connexion WireGuard depuis la barre des menus |

## Installation

```bash
git clone https://github.com/cerede2000/spoons.git
cp -R spoons/*.spoon ~/.hammerspoon/Spoons/
```

Puis dans `~/.hammerspoon/init.lua` :

```lua
hs.loadSpoon("ActivityKeeper")
spoon.ActivityKeeper:start()
```

Chaque Spoon expose sa configuration en tête de fichier, sous
`CONFIGURATION PUBLIQUE`.

## Tests

209 cas, exécutables sans Hammerspoon — voir [tests/](tests/).

```bash
sh tests/run-all.sh
```
