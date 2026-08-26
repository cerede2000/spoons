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

[`init.lua`](init.lua) ne fait que **déclarer**. SpoonManager charge les
Spoons, leur applique les réglages, branche les raccourcis et démarre
ceux qui doivent l'être :

```lua
spoon.SpoonManager:setup({
    {
        id = "LastWindowQuits",
        label = "Last Window Quits",
        settings = { quitDelay = 5, logToFile = true },
        hotkeys = { toggle = { {"ctrl", "alt", "cmd"}, "Q" } },
    },
    { id = "FinderCutPaste", label = "Finder Couper/Coller" },
})
```

`start`, `stop` et l'accès à l'icône sont **déduits du Spoon** : il n'y
a rien à écrire pour eux. Ils restent surchargeables si un Spoon demande
autre chose.

Quatre garanties :

1. **Ce fichier fait autorité.** Les Spoons qui persistent des réglages
   les réalignent sur ces valeurs au démarrage.
2. **Un Spoon absent n'emporte pas le reste.** Seul le Spoon fautif
   manque à l'appel, et le message de fin le nomme. Sans cette
   précaution, un seul dossier manquant laissait la configuration
   entière sans rien démarrer.
3. **Une clé de réglage inconnue est signalée en console.** Une faute de
   frappe ne passe plus inaperçue — avec des affectations libres, elle
   ne faisait rien et ne disait rien.
4. **Les tables imbriquées se surchargent partiellement**, sans avoir à
   les redéclarer en entier.

Deux chemins y sont propres à la machine, à adapter : ceux de WireGuard
(`/opt/homebrew/etc/wireguard/wg0.conf`) et de Homebrew.

Chaque Spoon expose sa configuration en tête de fichier, sous
`CONFIGURATION PUBLIQUE`.

## Tests

674 cas, exécutables sans Hammerspoon — voir [tests/](tests/).

```bash
sh tests/run-all.sh
```
