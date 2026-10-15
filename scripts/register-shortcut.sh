#!/bin/bash
# Assegna in KDE Plasma il tasto N (rimappato su XF86Launch1) all'avvio di Linux Sense.
# Va eseguito nella sessione dell'utente, non come root.
set -e
KEY=16777379  # Qt::Key_Launch1
ID=(4 linux-sense.desktop _launch "Linux Sense" "Avvia Linux Sense")
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel doRegister as "${ID[@]}"
# flag 6 = SetPresent | NoAutoloading: senza SetPresent la scorciatoia resta inattiva
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setShortcut asaiu "${ID[@]}" 1 "$KEY" 6 >/dev/null
echo "Tasto N assegnato a Linux Sense."
