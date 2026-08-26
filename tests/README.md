# Tests

Suites unitaires exécutables hors Hammerspoon : `lib_hs.lua` installe un
bouchon de l'API `hs`, chaque suite charge le Spoon avec `dofile` et
vérifie son comportement.

```bash
lua tests/ak_core.lua  ActivityKeeper.spoon/init.lua
lua tests/ak_filet.lua ActivityKeeper.spoon/init.lua
lua tests/ak_toast.lua ActivityKeeper.spoon/init.lua
```

| suite      | couvre |
|------------|--------|
| `ak_core`  | chemins d'événement, taps, commandes shell, rétroéclairage, luminosité écran |
| `ak_filet` | consignation et reprise de l'état système, hook d'arrêt |
| `ak_toast` | bulle de notification : ancrage, thème, cycle de vie |
