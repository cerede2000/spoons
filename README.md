# Spoons

Modules [Hammerspoon](https://www.hammerspoon.org), chargés et pilotés par
**SpoonManager**, qui les active ou les désactive depuis un menu unique.

| Spoon | rôle |
|---|---|
| [SpoonManager](SpoonManager.spoon/) | menu central : active/désactive les autres Spoons, masque leur icône |
| [ActivityKeeper](ActivityKeeper.spoon/) | maintien de présence, avec réduction de consommation en veille |
| [LastWindowQuits](LastWindowQuits.spoon/) | ferme une application quand sa dernière fenêtre est fermée |
| [WireGuardVPN](WireGuardVPN.spoon/) | connexion WireGuard depuis la barre des menus |
| [FinderCutPaste](FinderCutPaste.spoon/) | couper/coller de fichiers dans le Finder, façon Windows |
| [FinderPermanentDelete](FinderPermanentDelete.spoon/) | Maj+Suppr = suppression définitive dans le Finder |
| [WindowSwitcher](WindowSwitcher.spoon/) | Option+Tab par fenêtre, grille d'aperçus réels |

## Installation

```bash
git clone https://github.com/cerede2000/spoons.git
cp -R spoons/*.spoon ~/.hammerspoon/Spoons/
cp spoons/init.lua ~/.hammerspoon/init.lua
```

[`init.lua`](init.lua) est la configuration complète : il charge les six
Spoons pilotables, les règle, et les confie à **SpoonManager** qui les
démarre. Rien n'est démarré à la main.

Trois principes y sont tenus :

1. **Ce fichier fait autorité.** Les Spoons qui persistent des réglages
   les réalignent sur ces valeurs au démarrage.
2. **Un Spoon absent n'emporte pas le reste.** Chaque chargement est
   protégé : seul le Spoon fautif manque à l'appel, et le message de
   confirmation le nomme. Sans cette précaution, un seul dossier
   manquant laissait la configuration entière sans rien démarrer.
3. **L'inscription est locale.** Chaque bloc déclare sa propre entrée
   auprès du gestionnaire, au lieu d'une liste centrale à tenir à jour.

Deux chemins y sont propres à la machine, à adapter : ceux de WireGuard
(`/opt/homebrew/etc/wireguard/wg0.conf`) et de Homebrew.

Chaque Spoon expose sa configuration en tête de fichier, sous
`CONFIGURATION PUBLIQUE`.

## Tests

650 cas, exécutables sans Hammerspoon — voir [tests/](tests/).

```bash
sh tests/run-all.sh
```
