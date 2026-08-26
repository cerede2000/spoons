#!/bin/sh
# Compile le service de capture, le signe, et depose l'empreinte de la
# source compilee.
#
# L'empreinte est ce qui permet au Spoon de dire si le binaire en
# service correspond a la source presente. Comparer les dates de
# modification ne le permettait pas : copier le Spoon suffisait a rendre
# le .swift plus recent que le binaire sans qu'une ligne ait change.
set -e
cd "$(dirname "$0")"

SRC=window-capture-helper.swift
BIN=window-capture-helper
APP=WindowSwitcherCapture.app

if [ ! -f "$SRC" ]; then
    echo "source introuvable : $SRC" >&2
    exit 1
fi

echo "compilation du binaire simple"
swiftc -O -parse-as-library "$SRC" -o "$BIN"

if [ -d "$APP" ]; then
    echo "compilation du bundle $APP"
    swiftc -O -parse-as-library "$SRC" -o "$APP/Contents/MacOS/$BIN"
    codesign --force --sign - \
        --identifier local.hammerspoon.WindowSwitcherCapture "$APP"
fi

shasum -a 256 "$SRC" | awk '{print $1}' > "$BIN.sha256"

echo "empreinte deposee : $(cat "$BIN.sha256")"
echo
echo "En mode helperLaunchMode = \"task\" (defaut), rien a reaccorder :"
echo "le service herite de l'autorisation de Hammerspoon."
echo "En mode \"open\", reaccorder Enregistrement de l'ecran."
