#!/usr/bin/python3
"""Linux Sense daemon.

Root service that exposes the linuwu_sense driver controls (thermal profiles,
fans, RGB keyboard, battery) over a Unix socket using line-based JSON.

Compared to the original DAMX daemon:
- the profile is read/written through the "acer-wmi" platform-profile handler
  and not through the legacy /sys/firmware/acpi/platform_profile interface,
  which returns "custom" when multiple handlers (acer-wmi + amd-pmf) disagree;
- a thread watches the profile: changes made with the physical key are
  detected, propagated to the other handlers (amd-pmf) and remembered;
- the profile is remembered separately for battery and power adapter.
"""

import json
import logging
import os
import pwd
import select
import signal
import socket
import struct
import subprocess
import threading
import time
from pathlib import Path

VERSION = "1.0.1"
SOCKET_PATH = "/run/linux-sense.sock"
CONFIG_PATH = Path("/etc/linux-sense/config.json")

DRV = Path("/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi")
KB = DRV / "four_zoned_kb"
PROFILE_CLASS = Path("/sys/class/platform-profile")
POWER_SUPPLY = Path("/sys/class/power_supply")

# Acer profile -> preferences for the other handlers (e.g. amd-pmf), in order
SECONDARY_MAP = {
    "low-power": ["low-power", "quiet", "cool", "balanced"],
    "quiet": ["quiet", "low-power", "cool", "balanced"],
    "balanced": ["balanced"],
    "balanced-performance": ["balanced-performance", "performance", "balanced"],
    "performance": ["performance", "balanced-performance", "balanced"],
}

# The firmware (and driver) only accepts these profiles with the power adapter connected
AC_ONLY = {"quiet", "balanced-performance", "performance"}
# In Eco/Quiet the driver forces automatic fan control
FAN_LOCKED = {"low-power", "quiet"}
# On power changes tuned-ppd applies its own profile (e.g. "balanced" on AC)
# and rewrites platform_profile right after us: for a few seconds external changes
# are discarded instead of being remembered as the user's choice.
POWER_SETTLE = 5

# Fn+F11/Fn+F12 keys (remapped by hwdb to KEY_KBDILLUMDOWN/UP).
# The firmware changes brightness by ±25 with no clamping: below 0 or above 100 the
# value wraps around (e.g. 8 - 25 = 239) and the keyboard goes haywire. On Windows
# NitroSense intercepts the keys; here the daemon does it, in steps of 5 with off at 0.
KEY_KBDILLUMDOWN = 229
KEY_KBDILLUMUP = 230
KB_STEP = 5
INPUT_EVENT = struct.Struct("llHHi")

# The driver does not register a "kbd_backlight" LED, so UPower and Plasma do not see
# the keyboard (popup always at 0%). The daemon creates one from userspace (uleds module)
# with one level per step, so the Plasma slider and the daemon stay in sync.
# Plasma cannot handle the keys itself: with more than 7 levels powerdevil steps by 20%.
# Its shortcuts are disabled (scripts/register-shortcut.sh): the daemon performs the
# step and shows the Plasma popup in the active session (OSD_CALL).
ULEDS = "/dev/uleds"
ULEDS_DEV = struct.Struct("64si")
KB_LED_NAME = "acer::kbd_backlight"
KB_LED_MAX = 100 // KB_STEP
OSD_CALL = ["busctl", "--user", "--timeout=1", "call", "org.kde.plasmashell", "/org/kde/osdService",
            "org.kde.osdService", "keyboardBrightnessChanged", "i"]
UPOWER_KBD = ["busctl", "--system", "--timeout=2", "call", "org.freedesktop.UPower",
              "/org/freedesktop/UPower/KbdBacklight", "org.freedesktop.UPower.KbdBacklight"]

KB_EFFECTS = ["static", "breathing", "neon", "wave", "shifting", "zoom", "meteor", "twinkling"]
USB_LEVELS = [0, 10, 20, 30]

DEFAULT_CONFIG = {
    "auto_profile": True,
    "profile_ac": "balanced",
    "profile_battery": "balanced",
    "fan": {"mode": "auto", "cpu": 50, "gpu": 50},
    "keyboard": None,  # inizializzato dallo stato del driver
}

log = logging.getLogger("linux-sense")


def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def write(path, value):
    try:
        Path(path).write_text(str(value))
        return True
    except OSError as e:
        log.error("write %s = %r failed: %s", path, value, e)
        return False


def dmi(field):
    return read(f"/sys/class/dmi/id/{field}")


class Hardware:
    def __init__(self):
        self.base = None
        for name in ("nitro_sense", "predator_sense"):
            if (DRV / name).is_dir():
                self.base = DRV / name
                self.laptop_type = name.split("_")[0].upper()
                break
        else:
            self.laptop_type = "UNKNOWN"
        # every read of these features is a WMI call to the firmware: we cache
        # them and refresh only when we change them ourselves
        self._cache = {}

    # --- profili -----------------------------------------------------------
    def _handlers(self):
        acer, others = None, []
        if PROFILE_CLASS.is_dir():
            for d in sorted(PROFILE_CLASS.iterdir()):
                if read(d / "name") == "acer-wmi":
                    acer = d
                else:
                    others.append(d)
        return acer, others

    def profile(self):
        acer, _ = self._handlers()
        return read(acer / "profile") if acer else read("/sys/firmware/acpi/platform_profile")

    def profile_choices(self):
        if "choices" not in self._cache:
            acer, _ = self._handlers()
            f = acer / "choices" if acer else Path("/sys/firmware/acpi/platform_profile_choices")
            self._cache["choices"] = read(f).split()
        return self._cache["choices"]

    def profile_files(self):
        """Files to watch: the kernel notifies them when the profile changes."""
        acer, _ = self._handlers()
        files = [acer / "profile"] if acer else []
        return files + [Path("/sys/firmware/acpi/platform_profile")]

    def set_profile(self, profile):
        if profile not in self.profile_choices():
            raise ValueError(f"invalid profile: {profile}")
        acer, _ = self._handlers()
        ok = write(acer / "profile" if acer else "/sys/firmware/acpi/platform_profile", profile)
        self.sync_secondary(profile)
        return ok

    def sync_secondary(self, profile):
        _, others = self._handlers()
        for h in others:
            choices = read(h / "choices").split()
            target = next((p for p in SECONDARY_MAP.get(profile, [profile]) if p in choices), None)
            if target and read(h / "profile") != target:
                write(h / "profile", target)
                log.info("%s -> %s", read(h / "name"), target)

    # --- feature generiche -------------------------------------------------
    def feature(self, name):
        if not self.base:
            return None
        if name not in self._cache:
            v = read(self.base / name, None)
            # None/-1: missing or not supported by the firmware
            self._cache[name] = None if v is None or v == "-1" else v
        return self._cache[name]

    def set_feature(self, name, value):
        if self.feature(name) is None:
            raise ValueError(f"unsupported feature: {name}")
        ok = write(self.base / name, value)
        self._cache.pop(name, None)
        return ok

    # --- fans --------------------------------------------------------------
    def apply_fan(self, fan):
        if self.feature("fan_speed") is None:
            return False
        mode = fan.get("mode", "auto")
        if mode == "auto":
            value = "0,0"
        elif mode == "max":
            value = "100,100"
        else:
            cpu = max(1, min(100, int(fan.get("cpu", 50))))
            gpu = max(1, min(100, int(fan.get("gpu", 50))))
            value = f"{cpu},{gpu}"
        return write(self.base / "fan_speed", value)

    def keyboard_brightness_hw(self):
        """Current brightness according to the firmware (WMI read)."""
        try:
            return int(read(KB / "four_zone_mode").split(",")[2])
        except (IndexError, ValueError):
            return None

    # --- keyboard ----------------------------------------------------------
    def has_keyboard(self):
        return (KB / "per_zone_mode").exists() and (KB / "four_zone_mode").exists()

    def keyboard_from_driver(self):
        kb = {"effect": "static", "zones": ["ff2e4d"] * 4, "brightness": 75,
              "speed": 3, "direction": 1, "color": "ff2e4d"}
        pz = read(KB / "per_zone_mode").split(",")
        if len(pz) == 5:
            kb["zones"] = [z.lower() for z in pz[:4]]
            kb["brightness"] = int(pz[4])
        return kb

    def apply_keyboard(self, kb):
        if not self.has_keyboard():
            return False
        bright = max(0, min(100, int(kb.get("brightness", 75))))
        effect = kb.get("effect", "static")
        if effect == "static":
            zones = [z.lower().lstrip("#") for z in kb["zones"]]
            for z in zones:
                if len(z) != 6:
                    raise ValueError(f"invalid color: {z}")
                int(z, 16)
            return write(KB / "per_zone_mode", ",".join(zones) + f",{bright}\n")
        mode = KB_EFFECTS.index(effect)
        speed = max(0, min(9, int(kb.get("speed", 3))))
        direction = 2 if int(kb.get("direction", 1)) == 2 else 1
        c = kb.get("color", "ffffff").lstrip("#")
        r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
        return write(KB / "four_zone_mode", f"{mode},{speed},{bright},{direction},{r},{g},{b}\n")


class Daemon:
    def __init__(self):
        self.hw = Hardware()
        self.lock = threading.RLock()
        self.config = self._load_config()
        self.ac = self._ac_online()
        self.last_profile = self.hw.profile()
        self.running = True
        self._power_settle = None  # (scadenza, profilo voluto), vedi POWER_SETTLE
        self._kb_settle = None
        self._kb_led = False
        self._kb_published = None  # last level written to the LED by the daemon
        self._kb_notify = threading.Event()

    # --- config ------------------------------------------------------------
    def _load_config(self):
        cfg = json.loads(json.dumps(DEFAULT_CONFIG))
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text()))
        except (OSError, ValueError):
            pass
        if cfg.get("keyboard") is None and self.hw.has_keyboard():
            cfg["keyboard"] = self.hw.keyboard_from_driver()
        return cfg

    def _save_config(self):
        try:
            CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            tmp = CONFIG_PATH.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.config, indent=2))
            tmp.replace(CONFIG_PATH)
        except OSError as e:
            log.error("salvataggio config fallito: %s", e)

    # --- alimentazione -----------------------------------------------------
    @staticmethod
    def _ac_online():
        if POWER_SUPPLY.is_dir():
            for d in POWER_SUPPLY.iterdir():
                if read(d / "type") == "Mains":
                    return read(d / "online") == "1"
        return True

    def _source_key(self):
        return "profile_ac" if self.ac else "profile_battery"

    # --- startup and watching ----------------------------------------------
    def restore(self):
        with self.lock:
            if self.config.get("auto_profile"):
                wanted = self.config.get(self._source_key())
                if wanted in self._available():
                    try:
                        self.hw.set_profile(wanted)
                    except (ValueError, OSError) as e:
                        log.warning("profile restore failed: %s", e)
            self.hw.sync_secondary(self.hw.profile())
            self.last_profile = self.hw.profile()
            self._apply_fan()
            if self.config.get("keyboard") and self.hw.has_keyboard():
                try:
                    self.hw.apply_keyboard(self.config["keyboard"])
                except (ValueError, KeyError) as e:
                    log.warning("invalid keyboard state: %s", e)

    def watch(self):
        """Watches the physical key, external changes and power adapter plug events.

        Reading the Acer profile is a ~9 ms WMI call: instead of polling it
        continuously we wait for the kernel sysfs notification, with a safety
        check every 10 seconds.
        """
        poller = select.poll()
        files = {}
        for path in self.hw.profile_files():
            try:
                fh = open(path)
                fh.read()
            except OSError:
                continue
            files[fh.fileno()] = fh
            poller.register(fh, select.POLLPRI | select.POLLERR)
        ticks = 0
        while self.running:
            events = poller.poll(1000)
            for fd, _ in events:
                files[fd].seek(0)
                files[fd].read()  # re-arm the notification
            ticks += 1
            with self.lock:
                ac = self._ac_online()
                if ac != self.ac:
                    self.ac = ac
                    log.info("power source: %s", "AC" if ac else "battery")
                    if self.config.get("auto_profile"):
                        wanted = self.config.get(self._source_key())
                        if wanted in self._available() and wanted != self.last_profile:
                            try:
                                self.hw.set_profile(wanted)
                            except (ValueError, OSError) as e:
                                log.warning("automatic profile switch failed: %s", e)
                            self.last_profile = self.hw.profile()
                            self._apply_fan()
                        if wanted in self._available():
                            self._power_settle = (time.monotonic() + POWER_SETTLE, wanted)
                settling = self._power_settle and time.monotonic() < self._power_settle[0]
                if not events and ticks % 10 and not settling:
                    continue
                cur = self.hw.profile()
                if settling and cur and cur != self._power_settle[1]:
                    log.info("profile changed externally after power change: "
                             "%s -> %s, restoring %s", self.last_profile, cur, self._power_settle[1])
                    try:
                        self.hw.set_profile(self._power_settle[1])
                    except (ValueError, OSError) as e:
                        log.warning("profile restore failed: %s", e)
                    self.last_profile = self.hw.profile()
                    self._apply_fan()
                elif cur and cur != self.last_profile:
                    log.info("profile changed externally: %s -> %s", self.last_profile, cur)
                    self.last_profile = cur
                    self.hw.sync_secondary(cur)
                    self._apply_fan()
                    if cur in self.hw.profile_choices():
                        self.config[self._source_key()] = cur
                        self._save_config()

    def _apply_fan(self):
        """Fans according to config, except in profiles where the driver locks them."""
        if self.last_profile in FAN_LOCKED:
            return self.hw.apply_fan({"mode": "auto"})
        return self.hw.apply_fan(self.config["fan"])

    def _available(self):
        choices = self.hw.profile_choices()
        return choices if self.ac else [p for p in choices if p not in AC_ONLY]

    @staticmethod
    def _keyboard_device():
        name = None
        for line in read("/proc/bus/input/devices", "").splitlines():
            if line.startswith("N: Name="):
                name = line.split("=", 1)[1].strip('"')
            elif line.startswith("H: Handlers=") and name == "AT Translated Set 2 keyboard":
                for h in line.split("=", 1)[1].split():
                    if h.startswith("event"):
                        return f"/dev/input/{h}"
        return None

    def watch_backlight_keys(self):
        """Fn+F11/Fn+F12: corrects the firmware step (see KB_STEP).

        Reads the keyboard without grabbing it and only considers the two
        backlight key codes: all other keys are ignored. LED and popup are
        updated by notify_backlight, so mashing the keys is never slowed down.
        """
        if not self.hw.has_keyboard():
            return
        path = self._keyboard_device()
        if not path:
            log.warning("internal keyboard not found: brightness keys not handled")
            return
        with open(path, "rb", buffering=0) as dev:
            while self.running:
                if not select.select([dev], [], [], 1)[0]:
                    continue
                data = dev.read(INPUT_EVENT.size * 64)
                for i in range(0, len(data) - INPUT_EVENT.size + 1, INPUT_EVENT.size):
                    _, _, etype, code, value = INPUT_EVENT.unpack_from(data, i)
                    if etype == 1 and value in (1, 2) and code in (KEY_KBDILLUMDOWN, KEY_KBDILLUMUP):
                        self.step_backlight(1 if code == KEY_KBDILLUMUP else -1)
                        self._kb_notify.set()

    def notify_backlight(self):
        """After the keys: LED (UPower/Plasma slider) and popup with the latest level."""
        while self.running:
            if not self._kb_notify.wait(1):
                continue
            self._kb_notify.clear()
            with self.lock:
                self._publish_led()
                percent = (self.config.get("keyboard") or {}).get("brightness", 0)
            self._show_osd(percent)

    @staticmethod
    def _show_osd(percent):
        # Plasma popup in the active session; at the login screen nobody answers
        try:
            sid = subprocess.run(["loginctl", "show-seat", "seat0", "--value", "-p", "ActiveSession"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
            uid = int(subprocess.run(["loginctl", "show-session", sid, "--value", "-p", "User"],
                                     capture_output=True, text=True, timeout=2).stdout.strip())
            bus = f"/run/user/{uid}/bus"
            if uid == 0 or not os.path.exists(bus):
                return
            subprocess.run(["setpriv", f"--reuid={uid}", f"--regid={pwd.getpwuid(uid).pw_gid}",
                            "--clear-groups", "env", f"DBUS_SESSION_BUS_ADDRESS=unix:path={bus}"]
                           + OSD_CALL + [str(percent)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            pass

    def step_backlight(self, direction):
        with self.lock:
            kb = dict(self.config.get("keyboard") or self.hw.keyboard_from_driver())
            cur = max(0, min(100, int(kb.get("brightness", 0))))
            if direction < 0:
                new = max(0, -(-cur // KB_STEP) * KB_STEP - KB_STEP)
            else:
                new = min(100, (cur // KB_STEP) * KB_STEP + KB_STEP)
            self._set_backlight(kb, new)

    def _set_backlight(self, kb, brightness):
        kb["brightness"] = brightness
        self.config["keyboard"] = kb
        self.hw.apply_keyboard(kb)  # ~1.5 ms: immediately, even when keys are mashed
        self._schedule_settle()

    def _schedule_settle(self):
        # the firmware applies its own step in parallel: a single check
        # (and save) once the key mashing stops
        if self._kb_settle:
            self._kb_settle.cancel()
        self._kb_settle = threading.Timer(0.3, self._settle_backlight)
        self._kb_settle.daemon = True
        self._kb_settle.start()

    def _settle_backlight(self):
        with self.lock:
            kb = self.config["keyboard"]
            if self.hw.keyboard_brightness_hw() != kb["brightness"]:
                self.hw.apply_keyboard(kb)
            self._save_config()
            log.info("keyboard brightness: %d", kb["brightness"])

    # --- kbd_backlight LED for UPower/Plasma ---------------------------------
    @staticmethod
    def _led_level(brightness):
        return (max(0, min(100, int(brightness))) + KB_STEP // 2) // KB_STEP

    def _publish_led(self):
        """Reports the current level to UPower, which notifies Plasma.

        Going through UPower (instead of writing the LED directly) lets Plasma
        receive the change signal and update the slider and the next step.
        """
        if not self._kb_led:
            return
        level = self._led_level((self.config.get("keyboard") or {}).get("brightness", 0))
        self._kb_published = level
        try:
            subprocess.run(UPOWER_KBD + ["SetBrightness", "i", str(level)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            write(Path("/sys/class/leds") / KB_LED_NAME / "brightness", str(level))

    def watch_backlight_led(self):
        if not self.hw.has_keyboard():
            return
        if not os.path.exists(ULEDS):
            subprocess.run(["modprobe", "uleds"], check=False)
        try:
            fd = os.open(ULEDS, os.O_RDWR)
            os.write(fd, ULEDS_DEV.pack(KB_LED_NAME.encode(), KB_LED_MAX))
        except OSError as e:
            log.warning("LED %s not created (%s): Plasma will not see the brightness", KB_LED_NAME, e)
            return
        with self.lock:
            level = self._led_level((self.config.get("keyboard") or {}).get("brightness", 0))
            write(Path("/sys/class/leds") / KB_LED_NAME / "brightness", str(level))
            self._kb_published = level
            self._kb_led = True
        try:
            while self.running:
                if not select.select([fd], [], [], 1)[0]:
                    continue
                data = os.read(fd, 4)
                if len(data) == 4:
                    self._led_written(struct.unpack("i", data)[0])
        finally:
            os.close(fd)

    def _led_written(self, level):
        """New level written to the LED (by Plasma, UPower or the daemon itself)."""
        with self.lock:
            if level == self._kb_published:
                return  # our own write: meanwhile the keys may have gone further
            self._kb_published = level
            kb = dict(self.config.get("keyboard") or self.hw.keyboard_from_driver())
            level = max(0, min(KB_LED_MAX, level))
            if self._led_level(kb.get("brightness", 0)) != level:
                self._set_backlight(kb, level * KB_STEP)

    # --- state -------------------------------------------------------------
    def state(self):
        hw = self.hw
        battery = {}
        for key in ("battery_limiter", "battery_calibration", "usb_charging"):
            v = hw.feature(key)
            if v is not None:
                battery[key] = int(v)
        return {
            "version": VERSION,
            "model": f"{dmi('sys_vendor')} {dmi('product_name')}".strip(),
            "bios": dmi("bios_version"),
            "laptop_type": hw.laptop_type,
            "driver_version": hw.feature("version") or "",
            "ac": self.ac,
            "profile": {
                "current": self.last_profile,
                "choices": hw.profile_choices(),
                "available": self._available(),
                "auto": bool(self.config.get("auto_profile")),
                "ac": self.config.get("profile_ac"),
                "battery": self.config.get("profile_battery"),
            },
            "fan": dict(self.config["fan"], supported=hw.feature("fan_speed") is not None,
                        locked=self.last_profile in FAN_LOCKED),
            "keyboard": self.config.get("keyboard") if hw.has_keyboard() else None,
            "battery": battery,
        }

    # --- commands ----------------------------------------------------------
    def handle(self, req):
        cmd = req.get("cmd")
        with self.lock:
            if cmd == "get_state":
                return self.state()
            if cmd == "set_profile":
                p = req["profile"]
                if p not in self._available():
                    raise ValueError("this profile requires the power adapter connected")
                if not self.hw.set_profile(p):
                    raise RuntimeError("the firmware rejected the profile")
                self.last_profile = self.hw.profile()
                self.config[self._source_key()] = p
                self._apply_fan()
                self._save_config()
                return self.state()
            if cmd == "set_auto_profile":
                self.config["auto_profile"] = bool(req["enabled"])
                self._save_config()
                return self.state()
            if cmd == "set_fan":
                mode = req.get("mode", "auto")
                if mode not in ("auto", "max", "custom"):
                    raise ValueError("invalid fan mode")
                fan = dict(self.config["fan"], mode=mode)
                for k in ("cpu", "gpu"):
                    if k in req:
                        fan[k] = max(1, min(100, int(req[k])))
                self.config["fan"] = fan
                if not self._apply_fan():
                    raise RuntimeError("could not set the fans")
                self._save_config()
                return self.state()
            if cmd == "set_keyboard":
                kb = dict(self.config.get("keyboard") or self.hw.keyboard_from_driver())
                for k in ("effect", "zones", "brightness", "speed", "direction", "color"):
                    if k in req:
                        kb[k] = req[k]
                if kb["effect"] not in KB_EFFECTS:
                    raise ValueError("invalid effect")
                if not self.hw.apply_keyboard(kb):
                    raise RuntimeError("could not set the keyboard")
                self.config["keyboard"] = kb
                self._save_config()
                self._publish_led()
                return self.state()
            if cmd == "set_battery_limiter":
                self.hw.set_feature("battery_limiter", "1" if req["enabled"] else "0")
                return self.state()
            if cmd == "set_battery_calibration":
                self.hw.set_feature("battery_calibration", "1" if req["enabled"] else "0")
                return self.state()
            if cmd == "set_usb_charging":
                level = int(req["level"])
                if level not in USB_LEVELS:
                    raise ValueError("invalid level")
                self.hw.set_feature("usb_charging", str(level))
                return self.state()
        raise ValueError(f"unknown command: {cmd}")

    # --- server ------------------------------------------------------------
    def client(self, conn):
        with conn, conn.makefile("rwb") as f:
            for line in f:
                try:
                    data = self.handle(json.loads(line))
                    resp = {"ok": True, "data": data}
                except Exception as e:  # error response to the client, the daemon keeps running
                    log.warning("request %r failed: %s", line[:200], e)
                    resp = {"ok": False, "error": str(e)}
                f.write(json.dumps(resp).encode() + b"\n")
                f.flush()

    def serve(self):
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o666)
        srv.listen(8)
        srv.settimeout(1)
        log.info("listening on %s", SOCKET_PATH)
        while self.running:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            threading.Thread(target=self.client, args=(conn,), daemon=True).start()
        srv.close()
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    # the module may show up a moment after boot
    for _ in range(30):
        if DRV.is_dir():
            break
        time.sleep(1)
    d = Daemon()
    log.info("Linux Sense %s — %s, type %s", VERSION, d.state()["model"], d.hw.laptop_type)

    def stop(*_):
        d.running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    d.restore()
    threading.Thread(target=d.watch, daemon=True).start()
    threading.Thread(target=d.watch_backlight_keys, daemon=True).start()
    threading.Thread(target=d.watch_backlight_led, daemon=True).start()
    threading.Thread(target=d.notify_backlight, daemon=True).start()
    d.serve()


if __name__ == "__main__":
    main()
