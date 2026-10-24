#!/bin/bash
# Assigns the N key (remapped to XF86Launch1) to launching Linux Sense in KDE Plasma
# and frees Fn+F11/Fn+F12 from powerdevil: the daemon performs the brightness step.
# Must be run in the user session, not as root.
set -e
KEY=16777379  # Qt::Key_Launch1
ID=(4 linux-sense.desktop _launch "Linux Sense" "Launch Linux Sense")
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel doRegister as "${ID[@]}"
# flag 6 = SetPresent | NoAutoloading: without SetPresent the shortcut stays inactive
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setShortcut asaiu "${ID[@]}" 1 "$KEY" 6 >/dev/null
echo "N key assigned to Linux Sense."

# powerdevil steps by 20% at best (see KB_LED_MAX in the daemon)
for action in "Increase Keyboard Brightness" "Decrease Keyboard Brightness"; do
    busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcutKeys \
        "asa(ai)" 4 org_kde_powerdevil "$action" "" "" 0
done
echo "Keyboard brightness keys handled by Linux Sense."
