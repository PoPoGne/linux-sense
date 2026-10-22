#!/usr/bin/python3
"""Linux Sense daemon.

Servizio root che espone i controlli del driver linuwu_sense (profili termici,
ventole, tastiera RGB, batteria) tramite un socket Unix con JSON a righe.

Rispetto al demone DAMX originale:
- il profilo si legge/scrive sul gestore platform-profile "acer-wmi" e non
  sull'interfaccia legacy /sys/firmware/acpi/platform_profile, che con più
  gestori (acer-wmi + amd-pmf) restituisce "custom" quando divergono;
- un thread osserva il profilo: i cambi fatti col tasto fisico vengono
  rilevati, propagati agli altri gestori (amd-pmf) e ricordati;
- il profilo viene ricordato separatamente per batteria e alimentatore.
"""

import json
import logging
import os
import select
import signal
import socket
import struct
import subprocess
import threading
import time
from pathlib import Path

VERSION = "1.0.0"
SOCKET_PATH = "/run/linux-sense.sock"
CONFIG_PATH = Path("/etc/linux-sense/config.json")

DRV = Path("/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi")
KB = DRV / "four_zoned_kb"
PROFILE_CLASS = Path("/sys/class/platform-profile")
POWER_SUPPLY = Path("/sys/class/power_supply")

# Profilo Acer -> preferenze per gli altri gestori (es. amd-pmf), in ordine
SECONDARY_MAP = {
    "low-power": ["low-power", "quiet", "cool", "balanced"],
    "quiet": ["quiet", "low-power", "cool", "balanced"],
    "balanced": ["balanced"],
    "balanced-performance": ["balanced-performance", "performance", "balanced"],
    "performance": ["performance", "balanced-performance", "balanced"],
}

# Il firmware (e il driver) accetta questi profili solo con l'alimentatore collegato
AC_ONLY = {"quiet", "balanced-performance", "performance"}
# In Eco/Silenzioso il driver forza le ventole in automatico
FAN_LOCKED = {"low-power", "quiet"}
# Al cambio di alimentazione tuned-ppd applica il suo profilo (es. "balanced" a rete)
# e riscrive platform_profile subito dopo di noi: per qualche secondo i cambi esterni
# vengono annullati invece di essere ricordati come scelta dell'utente.
POWER_SETTLE = 5

# Tasti Fn+F11/Fn+F12 (rimappati da hwdb su KEY_KBDILLUMDOWN/UP).
# Il firmware cambia la luminosità di ±25 ma senza limiti: sotto 0 o sopra 100 il
# valore "si riavvolge" (es. 8 - 25 = 239) e la tastiera impazzisce. Su Windows
# NitroSense intercetta i tasti; qui lo fa il demone, a scatti di 25 con spegnimento.
KEY_KBDILLUMDOWN = 229
KEY_KBDILLUMUP = 230
KB_STEP = 25
INPUT_EVENT = struct.Struct("llHHi")

# Il driver non registra un LED "kbd_backlight", quindi UPower e Plasma non vedono la
# tastiera (popup sempre allo 0%). Il demone ne crea uno da userspace (modulo uleds)
# con un livello per scatto: Plasma gestisce i tasti e mostra il popup, il demone
# riceve il nuovo livello e lo applica. Se nessuno scrive il LED entro KB_KEY_FALLBACK
# secondi dal tasto (es. alla schermata di accesso) lo scatto lo fa il demone.
ULEDS = "/dev/uleds"
ULEDS_DEV = struct.Struct("64si")
KB_LED_NAME = "acer::kbd_backlight"
KB_LED_MAX = 100 // KB_STEP
KB_KEY_FALLBACK = 0.2
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
        log.error("scrittura %s = %r fallita: %s", path, value, e)
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
        # ogni lettura di queste feature è una chiamata WMI al firmware: le
        # memorizziamo e le aggiorniamo solo quando le cambiamo noi
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
        """File da osservare: il kernel li notifica quando il profilo cambia."""
        acer, _ = self._handlers()
        files = [acer / "profile"] if acer else []
        return files + [Path("/sys/firmware/acpi/platform_profile")]

    def set_profile(self, profile):
        if profile not in self.profile_choices():
            raise ValueError(f"profilo non valido: {profile}")
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
            # None/-1: assente o non supportata dal firmware
            self._cache[name] = None if v is None or v == "-1" else v
        return self._cache[name]

    def set_feature(self, name, value):
        if self.feature(name) is None:
            raise ValueError(f"funzione non supportata: {name}")
        ok = write(self.base / name, value)
        self._cache.pop(name, None)
        return ok

    # --- ventole -----------------------------------------------------------
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
        """Luminosità attuale secondo il firmware (lettura WMI)."""
        try:
            return int(read(KB / "four_zone_mode").split(",")[2])
        except (IndexError, ValueError):
            return None

    # --- tastiera ----------------------------------------------------------
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
                    raise ValueError(f"colore non valido: {z}")
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
        self._kb_key = None  # scatto in attesa di Plasma (vedi KB_KEY_FALLBACK)
        self._kb_led = False

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

    # --- avvio e osservazione ---------------------------------------------
    def restore(self):
        with self.lock:
            if self.config.get("auto_profile"):
                wanted = self.config.get(self._source_key())
                if wanted in self._available():
                    try:
                        self.hw.set_profile(wanted)
                    except (ValueError, OSError) as e:
                        log.warning("ripristino profilo fallito: %s", e)
            self.hw.sync_secondary(self.hw.profile())
            self.last_profile = self.hw.profile()
            self._apply_fan()
            if self.config.get("keyboard") and self.hw.has_keyboard():
                try:
                    self.hw.apply_keyboard(self.config["keyboard"])
                except (ValueError, KeyError) as e:
                    log.warning("stato tastiera non valido: %s", e)

    def watch(self):
        """Segue tasto fisico, cambi esterni e collegamento dell'alimentatore.

        Leggere il profilo Acer è una chiamata WMI da ~9 ms: invece di interrogarlo
        di continuo aspettiamo la notifica sysfs del kernel, con una verifica di
        sicurezza ogni 10 secondi.
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
                files[fd].read()  # riarma la notifica
            ticks += 1
            with self.lock:
                ac = self._ac_online()
                if ac != self.ac:
                    self.ac = ac
                    log.info("alimentazione: %s", "rete" if ac else "batteria")
                    if self.config.get("auto_profile"):
                        wanted = self.config.get(self._source_key())
                        if wanted in self._available() and wanted != self.last_profile:
                            try:
                                self.hw.set_profile(wanted)
                            except (ValueError, OSError) as e:
                                log.warning("cambio profilo automatico fallito: %s", e)
                            self.last_profile = self.hw.profile()
                            self._apply_fan()
                        if wanted in self._available():
                            self._power_settle = (time.monotonic() + POWER_SETTLE, wanted)
                settling = self._power_settle and time.monotonic() < self._power_settle[0]
                if not events and ticks % 10 and not settling:
                    continue
                cur = self.hw.profile()
                if settling and cur and cur != self._power_settle[1]:
                    log.info("profilo cambiato esternamente dopo il cambio di alimentazione: "
                             "%s -> %s, rimetto %s", self.last_profile, cur, self._power_settle[1])
                    try:
                        self.hw.set_profile(self._power_settle[1])
                    except (ValueError, OSError) as e:
                        log.warning("ripristino profilo fallito: %s", e)
                    self.last_profile = self.hw.profile()
                    self._apply_fan()
                elif cur and cur != self.last_profile:
                    log.info("profilo cambiato esternamente: %s -> %s", self.last_profile, cur)
                    self.last_profile = cur
                    self.hw.sync_secondary(cur)
                    self._apply_fan()
                    if cur in self.hw.profile_choices():
                        self.config[self._source_key()] = cur
                        self._save_config()

    def _apply_fan(self):
        """Ventole secondo config, tranne nei profili in cui il driver le blocca."""
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
        """Fn+F11/Fn+F12: corregge il passo del firmware (vedi KB_STEP).

        Legge la tastiera senza bloccarla e considera solo i due codici della
        retroilluminazione: tutti gli altri tasti vengono ignorati. Lo scatto vero
        lo fa Plasma tramite il LED (vedi ULEDS); il demone interviene da solo se
        il LED manca o se nessuno lo aggiorna in tempo.
        """
        if not self.hw.has_keyboard():
            return
        path = self._keyboard_device()
        if not path:
            log.warning("tastiera interna non trovata: tasti luminosità non gestiti")
            return
        with open(path, "rb", buffering=0) as dev:
            while self.running:
                if not select.select([dev], [], [], 1)[0]:
                    continue
                data = dev.read(INPUT_EVENT.size * 64)
                for i in range(0, len(data) - INPUT_EVENT.size + 1, INPUT_EVENT.size):
                    _, _, etype, code, value = INPUT_EVENT.unpack_from(data, i)
                    if etype == 1 and value in (1, 2) and code in (KEY_KBDILLUMDOWN, KEY_KBDILLUMUP):
                        self._backlight_key(1 if code == KEY_KBDILLUMUP else -1)

    def _backlight_key(self, direction):
        with self.lock:
            if not self._kb_led:
                self.step_backlight(direction)
                return
            if self._kb_key is None:
                self._kb_key = [[], threading.Timer(KB_KEY_FALLBACK, self._backlight_key_fallback)]
                self._kb_key[1].daemon = True
                self._kb_key[1].start()
            self._kb_key[0].append(direction)
            self._schedule_settle()

    def _backlight_key_fallback(self):
        with self.lock:
            if self._kb_key is None:
                return
            pending, self._kb_key = self._kb_key[0], None
            for direction in pending:
                self.step_backlight(direction)
            self._publish_led()

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
        self.hw.apply_keyboard(kb)  # ~1,5 ms: subito, anche premendo a raffica
        self._schedule_settle()

    def _schedule_settle(self):
        # il firmware applica il proprio passo in parallelo: una sola verifica
        # (e il salvataggio) a raffica finita
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
            log.info("luminosità tastiera: %d", kb["brightness"])

    # --- LED kbd_backlight per UPower/Plasma ---------------------------------
    @staticmethod
    def _led_level(brightness):
        return (max(0, min(100, int(brightness))) + KB_STEP // 2) // KB_STEP

    def _publish_led(self):
        """Comunica il livello attuale a UPower, che avvisa Plasma.

        Passando da UPower (e non scrivendo direttamente il LED) Plasma riceve il
        segnale di cambio e aggiorna il cursore e il prossimo scatto.
        """
        if not self._kb_led:
            return
        level = self._led_level((self.config.get("keyboard") or {}).get("brightness", 0))
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
            log.warning("LED %s non creato (%s): Plasma non vedrà la luminosità", KB_LED_NAME, e)
            return
        with self.lock:
            level = self._led_level((self.config.get("keyboard") or {}).get("brightness", 0))
            write(Path("/sys/class/leds") / KB_LED_NAME / "brightness", str(level))
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
        """Nuovo livello scritto sul LED (da Plasma, UPower o dal demone stesso)."""
        with self.lock:
            if self._kb_key is not None:
                self._kb_key[0].pop(0)  # lo scatto del tasto l'ha fatto Plasma
                if not self._kb_key[0]:
                    self._kb_key[1].cancel()
                    self._kb_key = None
            kb = dict(self.config.get("keyboard") or self.hw.keyboard_from_driver())
            level = max(0, min(KB_LED_MAX, level))
            if self._led_level(kb.get("brightness", 0)) != level:
                self._set_backlight(kb, level * KB_STEP)

    # --- stato -------------------------------------------------------------
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

    # --- comandi -----------------------------------------------------------
    def handle(self, req):
        cmd = req.get("cmd")
        with self.lock:
            if cmd == "get_state":
                return self.state()
            if cmd == "set_profile":
                p = req["profile"]
                if p not in self._available():
                    raise ValueError("questo profilo richiede l'alimentatore collegato")
                if not self.hw.set_profile(p):
                    raise RuntimeError("il firmware ha rifiutato il profilo")
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
                    raise ValueError("modalità ventole non valida")
                fan = dict(self.config["fan"], mode=mode)
                for k in ("cpu", "gpu"):
                    if k in req:
                        fan[k] = max(1, min(100, int(req[k])))
                self.config["fan"] = fan
                if not self._apply_fan():
                    raise RuntimeError("impossibile impostare le ventole")
                self._save_config()
                return self.state()
            if cmd == "set_keyboard":
                kb = dict(self.config.get("keyboard") or self.hw.keyboard_from_driver())
                for k in ("effect", "zones", "brightness", "speed", "direction", "color"):
                    if k in req:
                        kb[k] = req[k]
                if kb["effect"] not in KB_EFFECTS:
                    raise ValueError("effetto non valido")
                if not self.hw.apply_keyboard(kb):
                    raise RuntimeError("impossibile impostare la tastiera")
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
                    raise ValueError("livello non valido")
                self.hw.set_feature("usb_charging", str(level))
                return self.state()
        raise ValueError(f"comando sconosciuto: {cmd}")

    # --- server ------------------------------------------------------------
    def client(self, conn):
        with conn, conn.makefile("rwb") as f:
            for line in f:
                try:
                    data = self.handle(json.loads(line))
                    resp = {"ok": True, "data": data}
                except Exception as e:  # risposta d'errore al client, il demone continua
                    log.warning("richiesta %r fallita: %s", line[:200], e)
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
        log.info("in ascolto su %s", SOCKET_PATH)
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
    # il modulo può comparire qualche istante dopo l'avvio
    for _ in range(30):
        if DRV.is_dir():
            break
        time.sleep(1)
    d = Daemon()
    log.info("Linux Sense %s — %s, tipo %s", VERSION, d.state()["model"], d.hw.laptop_type)

    def stop(*_):
        d.running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    d.restore()
    threading.Thread(target=d.watch, daemon=True).start()
    threading.Thread(target=d.watch_backlight_keys, daemon=True).start()
    threading.Thread(target=d.watch_backlight_led, daemon=True).start()
    d.serve()


if __name__ == "__main__":
    main()
