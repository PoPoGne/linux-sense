#!/bin/bash
# Assigns the N key (remapped to XF86Launch1) to launching Linux Sense.
# KDE Plasma: kglobalaccel shortcut, and Fn+F11/Fn+F12 freed from powerdevil
#   (the daemon performs the brightness step).
# GNOME (Zorin, Ubuntu...): custom keybinding; gnome-settings-daemon keeps
#   handling Fn+F11/Fn+F12 through the daemon's kbd_backlight LED.
# Must be run in the user session, not as root.
set -e

if busctl --user status org.kde.kglobalaccel >/dev/null 2>&1; then
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
    exit 0
fi

if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.settings-daemon.plugins.media-keys; then
    S=org.gnome.settings-daemon.plugins.media-keys
    P=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/linux-sense/
    cur=$(gsettings get $S custom-keybindings)
    case "$cur" in
        *"'$P'"*) ;;
        "@as []"|"[]") gsettings set $S custom-keybindings "['$P']" ;;
        *) gsettings set $S custom-keybindings "${cur%]}, '$P']" ;;
    esac
    K="$S.custom-keybinding:$P"
    gsettings set "$K" name 'Linux Sense'
    gsettings set "$K" command 'linux-sense'
    gsettings set "$K" binding 'XF86Launch1'
    echo "N key assigned to Linux Sense (GNOME)."
    exit 0
fi

echo "Desktop not recognized: assign XF86Launch1 to 'linux-sense' by hand." >&2
