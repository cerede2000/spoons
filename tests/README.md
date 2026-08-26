# Tests

Suites unitaires exécutables **sans Hammerspoon** : `lib_hs.lua` installe un
bouchon de l'API `hs`, chaque suite charge le Spoon avec `dofile` et vérifie
son comportement.

```bash
sh tests/run-all.sh          # tout
lua tests/lwq_config.lua LastWindowQuits.spoon/init.lua   # une seule suite
```

| suite            | Spoon           | couvre |
|------------------|-----------------|--------|
| `ak_core`        | ActivityKeeper  | chemins d'événement, taps système, commandes shell, rétroéclairage, luminosité écran |
| `ak_filet`       | ActivityKeeper  | consignation et reprise de l'état système, hook d'arrêt |
| `ak_toast`       | ActivityKeeper  | bulle de notification : ancrage, thème, cycle de vie |
| `ak_robustesse`  | ActivityKeeper  | touche Maj relâchée, verrou de keepalive, test manuel, idle illisible |
| `lwq_windows`    | LastWindowQuits | comptage des fenêtres, réduction, `windowRejected`, coût du scan |
| `lwq_securite`   | LastWindowQuits | veille et verrouillage, arrêt du Spoon, application terminée |
| `lwq_config`     | LastWindowQuits | autorité de `init.lua`, menu sans icône, raccourcis |
| `finder_cutpaste`| FinderCutPaste  | marqueur de copie synthétique, indicateur ciseaux |
| `sm_menu`        | SpoonManager    | sous-menu d'icône, accesseurs |
| `sm_robustesse`  | SpoonManager    | entrées mal formées, échecs de démarrage, `stop()` |
| `ws_fenetres`    | WindowSwitcher  | descripteurs, filtre permanent, collecte, ordre de profondeur, exclusions |
| `ws_capture`     | WindowSwitcher  | cycle de vie du service ScreenCaptureKit, protocole, caches, fichiers /tmp |
| `ws_session`     | WindowSwitcher  | modificateurs, souris, cache de géométrie, aperçu, activation, arrêt |

## Écrire une suite

`lib_hs.install()` renvoie une table de contrôle : `store` (hs.settings),
`shell` (commandes émises), `canvases`, `timers`, `killed`, `runningApps`,
`axMode` (`ok` / `vide` / `erreur`), plus `fireTimers()`, `power(event)` et
`shutdown()` pour déclencher les callbacks.

Les fabriques `lib.app(ctl, opts)` et `lib.window(opts)` reproduisent le
comportement réel de macOS — notamment qu'une fenêtre réduite perd son
subrole standard, et qu'une application terminée ne répond plus qu'à `pid()`.

### Bouchon en mode fichiers virtuels

Les suites WindowSwitcher appellent `lib.install({ virtualFS = true })` :
`io.open`, `os.remove` et `os.rename` sont alors redirigés vers `ctl.files`,
et `hs.fs` vers `ctl.files` / `ctl.dirs`. Aucune suite ne touche au disque.

`require("hs.window.filter")` est également intercepté, WindowSwitcher
important ses modules plutôt que d'utiliser la table `hs` globale.
