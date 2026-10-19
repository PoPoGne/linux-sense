#!/bin/bash
# Installa (o aggiorna) Linux Sense. Il driver linuwu_sense è gestito a parte da DKMS.
set -euo pipefail
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/linux-sense

# rimuove DAMX se presente
if [ -f /etc/systemd/system/damx-daemon.service ]; then
    systemctl disable --now damx-daemon.service 2>/dev/null || true
    rm -f /etc/systemd/system/damx-daemon.service
fi
rm -rf /opt/damx /etc/DAMX_Daemon /run/DAMX.sock /var/log/DAMX_Daemon_Log.log*
rm -f /usr/local/bin/DAMX /usr/share/applications/damx.desktop /usr/share/icons/hicolor/256x256/apps/damx.png

# driver linuwu_sense tramite DKMS (patch per kernel 7.x e Nitro AN14-41)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$SRC/driver/dkms.conf")
if ! dkms status "linuwu_sense/$VER" 2>/dev/null | grep -q installed; then
    command -v dkms >/dev/null || dnf install -y dkms
    rm -rf "/usr/src/linuwu_sense-$VER"
    cp -r "$SRC/driver" "/usr/src/linuwu_sense-$VER"
    dkms add "linuwu_sense/$VER" 2>/dev/null || true
    dkms install "linuwu_sense/$VER"
fi
echo "blacklist acer_wmi" > /etc/modprobe.d/blacklist-acer_wmi.conf
echo "linuwu_sense" > /etc/modules-load.d/linuwu_sense.conf
# LED kbd_backlight creato dal demone, per la luminosità della tastiera in Plasma
echo "uleds" > /etc/modules-load.d/linux-sense-uleds.conf
modprobe uleds
install -m 644 "$SRC/system/linuwu_sense.service" /etc/systemd/system/linuwu_sense.service
if ! lsmod | grep -q '^linuwu_sense'; then
    modprobe -r acer_wmi 2>/dev/null || true
    modprobe linuwu_sense
fi

# tasto N: scancode 0xf5 -> prog1 (XF86Launch1)
install -m 644 "$SRC/system/90-linux-sense-nitro-key.hwdb" /etc/udev/hwdb.d/
systemd-hwdb update
udevadm trigger --action=change --subsystem-match=input

# file dell'applicazione
install -d "$DEST"
rm -rf "$DEST/app" "$DEST/daemon"
cp -r "$SRC/app" "$DEST/app"
install -D -m 755 "$SRC/daemon/linux-sense-daemon.py" "$DEST/daemon/linux-sense-daemon.py"
find "$DEST" -name __pycache__ -prune -exec rm -rf {} +
chmod 755 "$DEST/app/linux_sense.py"

cat > /etc/systemd/system/linux-sense.service <<UNIT
[Unit]
Description=Linux Sense (profili, ventole, tastiera e batteria Acer)
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DEST/daemon/linux-sense-daemon.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

cat > /usr/local/bin/linux-sense <<LAUNCH
#!/bin/sh
exec /usr/bin/python3 $DEST/app/linux_sense.py "\$@"
LAUNCH
chmod 755 /usr/local/bin/linux-sense

# icone e voce di menu
install -D -m 644 "$SRC/logo/out/linux-sense.svg" /usr/share/icons/hicolor/scalable/apps/linux-sense.svg
for s in 16 24 32 48 64 128 256 512; do
    install -D -m 644 "$SRC/logo/out/linux-sense-$s.png" "/usr/share/icons/hicolor/${s}x${s}/apps/linux-sense.png"
done
cat > /usr/share/applications/linux-sense.desktop <<DESK
[Desktop Entry]
Type=Application
Name=Linux Sense
GenericName=Controllo del portatile
Comment=Profili, ventole, illuminazione della tastiera e batteria
Exec=linux-sense
Icon=linux-sense
Terminal=false
Categories=Settings;HardwareSettings;
Keywords=acer;nitro;predator;nitrosense;ventole;rgb;tastiera;profili;batteria;
StartupWMClass=linux-sense
DESK
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
update-desktop-database -q /usr/share/applications 2>/dev/null || true

systemctl daemon-reload
systemctl enable linuwu_sense.service linux-sense.service >/dev/null 2>&1
systemctl restart linux-sense.service

# scorciatoia KDE nella sessione dell'utente che ha lanciato l'installazione
if [ -n "${SUDO_USER:-}" ]; then
    BUS="/run/user/$(id -u "$SUDO_USER")/bus"
    [ -S "$BUS" ] && sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=$BUS" \
        "$SRC/scripts/register-shortcut.sh" || true
fi
echo "Linux Sense installato."
