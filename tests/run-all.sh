#!/bin/sh
# Lance toutes les suites. À exécuter depuis la racine du dépôt.
set -e
cd "$(dirname "$0")/.."
total=0; failed=0
for pair in \
    "ak_core:ActivityKeeper.spoon/init.lua" \
    "ak_filet:ActivityKeeper.spoon/init.lua" \
    "ak_toast:ActivityKeeper.spoon/init.lua" \
    "ak_robustesse:ActivityKeeper.spoon/init.lua" \
    "lwq_windows:LastWindowQuits.spoon/init.lua" \
    "lwq_securite:LastWindowQuits.spoon/init.lua" \
    "lwq_config:LastWindowQuits.spoon/init.lua" \
    "finder_cutpaste:FinderCutPaste.spoon/init.lua" \
    "sm_menu:SpoonManager.spoon/init.lua" \
    "sm_robustesse:SpoonManager.spoon/init.lua" \
    "ws_fenetres:WindowSwitcher.spoon/init.lua" \
    "ws_capture:WindowSwitcher.spoon/init.lua" \
    "ws_session:WindowSwitcher.spoon/init.lua" \
    "ws_bureaux:WindowSwitcher.spoon/init.lua" \
    "config:init.lua" ; do
    suite=${pair%%:*}; target=${pair#*:}
    line=$(lua "tests/$suite.lua" "$target" 2>&1 | grep -oE '^=> [0-9]+/[0-9]+' || echo "=> ERREUR")
    n=$(echo "$line" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f1)
    d=$(echo "$line" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f2)
    printf "  %-16s %s\n" "$suite" "${n:-?}/${d:-?}"
    total=$((total + ${d:-0})); failed=$((failed + ${d:-0} - ${n:-0}))
done
echo "  ─────────────────────────"
printf "  %-16s %s\n" "TOTAL" "$((total-failed))/$total"
[ "$failed" -eq 0 ] || exit 1
