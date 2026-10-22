#!/usr/bin/python3
"""Linux Sense — control panel for Acer Nitro/Predator laptops."""

import json
import os
import platform
import socket
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

from PySide6.QtCore import (QLocale, QMetaObject, QObject, QSize, Qt, QThread, QTimer,
                            Property, Signal, Slot)
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtGui import QFontDatabase, QGuiApplication, QIcon, QImage, QPainter
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtSvg import QSvgRenderer

from i18n import Translator

APP_VERSION = "1.0.0"
HERE = Path(__file__).resolve().parent
SOCKET_PATH = "/run/linux-sense.sock"
HISTORY = 90


class Tr(QObject):
    """Translation object exposed to QML as "tr"."""

    def __init__(self, translator, parent=None):
        super().__init__(parent)
        self._t = translator
        self._language = translator.language

    @Property(str, constant=True)
    def language(self):
        return self._language

    @Slot(str, result=str)
    def t(self, text):
        return self._t.t(text)

    @Slot(str, "QVariantMap", result=str)
    def fmt(self, text, values):
        return self._t.fmt(text, values)


def system_language():
    """Language code from the environment, else from the system locale."""
    override = os.environ.get("LINUX_SENSE_LANG")
    if override:
        return override
    return QLocale.system().name()


def read(path, default=None):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def read_int(path, default=None):
    v = read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def find_hwmon(name):
    for d in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        if read(d / "name") == name:
            return d
    return None


# --------------------------------------------------------------------------
# Icons: Lucide SVGs recolored on the fly -> image://icon/<name>/<rrggbb[aa]>
# --------------------------------------------------------------------------
class IconProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._svg = {}

    def requestImage(self, ident, size, requested):
        name, _, color = ident.partition("/")
        if name not in self._svg:
            self._svg[name] = read(HERE / "icons" / f"{name}.svg", "")
        hexc = color or "ffffff"
        if len(hexc) == 8:  # QML: #aarrggbb
            alpha = int(hexc[:2], 16) / 255
            hexc = hexc[2:]
        else:
            alpha = 1.0
        svg = self._svg[name].replace("currentColor", f"#{hexc}")
        if alpha < 1:
            svg = svg.replace("<svg", f'<svg opacity="{alpha:.3f}"', 1)
        w = requested.width() if requested.width() > 0 else 48
        h = requested.height() if requested.height() > 0 else 48
        img = QImage(w, h, QImage.Format.Format_ARGB32_Premultiplied)
        img.fill(Qt.GlobalColor.transparent)
        renderer = QSvgRenderer(svg.encode())
        p = QPainter(img)
        renderer.render(p)
        p.end()
        if size is not None:
            size.setWidth(w)
            size.setHeight(h)
        return img


# --------------------------------------------------------------------------
# Telemetry (read directly from sysfs, no root needed)
# --------------------------------------------------------------------------
class Telemetry:
    def __init__(self):
        self.k10 = find_hwmon("k10temp")
        self.acer = find_hwmon("acer")
        self.amdgpu = find_hwmon("amdgpu")
        self.nv_pci = None
        for dev in Path("/sys/bus/pci/devices").iterdir():
            if read(dev / "vendor") == "0x10de" and (read(dev / "class") or "").startswith("0x03"):
                self.nv_pci = dev
        self.igpu_busy = None
        for card in Path("/sys/class/drm").glob("card[0-9]"):
            f = card / "device" / "gpu_busy_percent"
            if f.exists() and "amdgpu" in os.path.realpath(card / "device" / "driver"):
                self.igpu_busy = f
        self.bat = next((d for d in Path("/sys/class/power_supply").iterdir()
                         if read(d / "type") == "Battery"), None)
        self._stat = None
        self._tick = 0
        self._nv = {}
        self.cpu_hist = deque([None] * HISTORY, maxlen=HISTORY)
        self.gpu_hist = deque([None] * HISTORY, maxlen=HISTORY)

    def _cpu_usage(self):
        parts = read("/proc/stat", "").splitlines()[0].split()[1:]
        vals = list(map(int, parts))
        idle, total = vals[3] + vals[4], sum(vals)
        usage = None
        if self._stat:
            di, dt = idle - self._stat[0], total - self._stat[1]
            usage = max(0.0, min(100.0, 100.0 * (1 - di / dt))) if dt else 0.0
        self._stat = (idle, total)
        return usage

    def _cpu_freq(self):
        freqs = [read_int(f) for f in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq")]
        freqs = [f for f in freqs if f]
        return (sum(freqs) / len(freqs) / 1e6) if freqs else None

    def _nvidia(self):
        status = read(self.nv_pci / "power" / "runtime_status") if self.nv_pci else None
        if status != "active":
            self._nv = {}
            return status
        # query nvidia-smi only if the GPU is already awake, every 2 seconds
        if self._tick % 2 == 0:
            try:
                out = subprocess.run(
                    ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu,power.draw",
                     "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=3).stdout.strip().split(",")
                self._nv = {"temp": float(out[0]), "util": float(out[1]),
                            "power": float(out[2]) if out[2].strip() not in ("[N/A]", "") else None}
            except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
                self._nv = {}
        return status

    def _battery(self):
        b = self.bat
        if not b:
            return {}
        def num(name):
            return read_int(b / name)
        power = num("power_now")
        if power is None and num("current_now") is not None and num("voltage_now"):
            power = num("current_now") * num("voltage_now") / 1e6
        e_now, e_full, e_design = num("energy_now"), num("energy_full"), num("energy_full_design")
        if e_now is None and num("charge_now") is not None and num("voltage_min_design"):
            v = num("voltage_min_design") / 1e6
            e_now, e_full, e_design = (num("charge_now") * v, num("charge_full") * v,
                                       num("charge_full_design") * v)
        status = read(b / "status", "Unknown")
        hours = None
        if power and power > 0 and e_now is not None:
            if status == "Discharging":
                hours = e_now / power
            elif status == "Charging" and e_full:
                hours = max(0, e_full - e_now) / power
        return {
            "percent": num("capacity"),
            "status": status,
            "power": (power / 1e6) if power else 0.0,
            "energy_now": (e_now / 1e6) if e_now else None,
            "energy_full": (e_full / 1e6) if e_full else None,
            "energy_design": (e_design / 1e6) if e_design else None,
            "health": (100.0 * e_full / e_design) if e_full and e_design else None,
            "cycles": num("cycle_count"),
            "hours": hours,
            "technology": read(b / "technology", ""),
            "manufacturer": read(b / "manufacturer", ""),
        }

    def sample(self):
        self._tick += 1
        mem = {}
        for line in read("/proc/meminfo", "").splitlines():
            k, _, v = line.partition(":")
            mem[k] = int(v.split()[0]) if v.split() else 0
        cpu_temp = read_int(self.k10 / "temp1_input") / 1000 if self.k10 else None
        nv_status = self._nvidia()
        igpu_temp = read_int(self.amdgpu / "temp1_input") / 1000 if self.amdgpu else None
        gpu_temp = self._nv.get("temp")
        self.cpu_hist.append(cpu_temp)
        self.gpu_hist.append(gpu_temp if gpu_temp is not None else igpu_temp)
        fans = [read_int(self.acer / f"fan{i}_input", 0) if self.acer else 0 for i in (1, 2)]
        return {
            "cpu_temp": cpu_temp,
            "cpu_usage": self._cpu_usage(),
            "cpu_freq": self._cpu_freq(),
            "ram_total": mem.get("MemTotal", 0) / 1048576,
            "ram_used": (mem.get("MemTotal", 0) - mem.get("MemAvailable", 0)) / 1048576,
            "igpu_temp": igpu_temp,
            "igpu_busy": read_int(self.igpu_busy) if self.igpu_busy else None,
            "dgpu_status": nv_status or "",
            "dgpu_active": nv_status == "active",
            "dgpu_temp": gpu_temp,
            "dgpu_util": self._nv.get("util"),
            "dgpu_power": self._nv.get("power"),
            "fan_cpu": fans[0],
            "fan_gpu": fans[1],
            "battery": self._battery(),
            "cpu_hist": list(self.cpu_hist),
            "gpu_hist": list(self.gpu_hist),
        }


def system_info():
    cpu = ""
    for line in read("/proc/cpuinfo", "").splitlines():
        if line.startswith("model name"):
            cpu = line.split(":", 1)[1].strip()
            break
    gpus = []
    if " w/ " in cpu:  # AMD APU: the integrated graphics name is in the CPU model
        gpus.append("AMD " + cpu.split(" w/ ", 1)[1].replace(" Graphics", ""))
    try:
        out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=3).stdout
        for line in out.splitlines():
            if ("VGA" in line or "3D controller" in line) and "NVIDIA" in line:
                name = line.split(": ", 1)[1]
                if "[" in name and "]" in name:
                    name = name[name.rfind("[", 0, name.rfind("]")) + 1:name.rfind("]")]
                gpus.append("NVIDIA " + name.replace(" Max-Q / Mobile", " Laptop"))
    except OSError:
        pass
    os_name = ""
    for line in read("/etc/os-release", "").splitlines():
        if line.startswith("PRETTY_NAME="):
            os_name = line.split("=", 1)[1].strip('"')
    return {
        "cpu": cpu.replace(" w/ Radeon 780M Graphics", ""),
        "gpus": gpus,
        "kernel": platform.release(),
        "os": os_name,
        "app_version": APP_VERSION,
        "hostname": platform.node(),
    }


# --------------------------------------------------------------------------
# Worker: talks to the daemon and samples telemetry off the UI thread
# --------------------------------------------------------------------------
class Worker(QObject):
    stateReady = Signal("QVariantMap")
    telemetryReady = Signal("QVariantMap")
    connectionChanged = Signal(bool)
    failed = Signal(str)

    def __init__(self):
        super().__init__()
        self.sock = None
        self.file = None
        self.telemetry = None
        self.connected = None
        self.timer = None

    @Slot()
    def start(self):
        self.telemetry = Telemetry()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.poll)
        self.timer.start(1000)
        self.poll()

    def _set_connected(self, value):
        if value != self.connected:
            self.connected = value
            self.connectionChanged.emit(value)

    def _call(self, req):
        for attempt in (0, 1):
            try:
                if self.sock is None:
                    self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    self.sock.settimeout(5)
                    self.sock.connect(SOCKET_PATH)
                    self.file = self.sock.makefile("rwb")
                self.file.write(json.dumps(req).encode() + b"\n")
                self.file.flush()
                line = self.file.readline()
                if not line:
                    raise ConnectionError("connessione chiusa")
                self._set_connected(True)
                return json.loads(line)
            except (OSError, ConnectionError, ValueError):
                self._close()
                if attempt:
                    self._set_connected(False)
                    return None
        return None

    def _close(self):
        try:
            if self.sock:
                self.sock.close()
        except OSError:
            pass
        self.sock = self.file = None

    @Slot()
    def stop(self):
        if self.timer:
            self.timer.stop()
        self._close()

    @Slot()
    def poll(self):
        resp = self._call({"cmd": "get_state"})
        if resp and resp.get("ok"):
            self.stateReady.emit(resp["data"])
        self.telemetryReady.emit(self.telemetry.sample())

    @Slot("QVariantMap")
    def request(self, req):
        resp = self._call(dict(req))
        if resp is None:
            self.failed.emit("Linux Sense service unreachable")
        elif not resp.get("ok"):
            self.failed.emit(resp.get("error") or "Operation failed")
            self.poll()
        else:
            self.stateReady.emit(resp["data"])


class Backend(QObject):
    stateChanged = Signal()
    telemetryChanged = Signal()
    connectedChanged = Signal()
    toast = Signal(str, bool)
    _send = Signal("QVariantMap")

    def __init__(self):
        super().__init__()
        self._state = {}
        self._telemetry = {}
        self._connected = True
        self._info = system_info()
        self.thread = QThread()
        self.worker = Worker()
        self.worker.moveToThread(self.thread)
        self.thread.started.connect(self.worker.start)
        self.worker.stateReady.connect(self._on_state)
        self.worker.telemetryReady.connect(self._on_telemetry)
        self.worker.connectionChanged.connect(self._on_connection)
        self.worker.failed.connect(lambda msg: self.toast.emit(msg, True))
        self._send.connect(self.worker.request)
        self.thread.start()

    def shutdown(self):
        QMetaObject.invokeMethod(self.worker, "stop", Qt.ConnectionType.BlockingQueuedConnection)
        self.thread.quit()
        self.thread.wait(2000)

    def _on_state(self, s):
        self._state = s
        self.stateChanged.emit()

    def _on_telemetry(self, t):
        self._telemetry = t
        self.telemetryChanged.emit()

    def _on_connection(self, ok):
        self._connected = ok
        self.connectedChanged.emit()

    @Property("QVariantMap", notify=stateChanged)
    def state(self):
        return self._state

    @Property("QVariantMap", notify=telemetryChanged)
    def telemetry(self):
        return self._telemetry

    @Property(bool, notify=connectedChanged)
    def connected(self):
        return self._connected

    @Property("QVariantMap", constant=True)
    def info(self):
        return self._info

    @Slot(str)
    def setProfile(self, profile):
        self._send.emit({"cmd": "set_profile", "profile": profile})

    @Slot(bool)
    def setAutoProfile(self, enabled):
        self._send.emit({"cmd": "set_auto_profile", "enabled": enabled})

    @Slot(str, int, int)
    def setFan(self, mode, cpu, gpu):
        self._send.emit({"cmd": "set_fan", "mode": mode, "cpu": cpu, "gpu": gpu})

    @Slot("QVariantMap")
    def setKeyboard(self, kb):
        req = {"cmd": "set_keyboard"}
        req.update(kb)
        self._send.emit(req)

    @Slot(bool)
    def setBatteryLimiter(self, enabled):
        self._send.emit({"cmd": "set_battery_limiter", "enabled": enabled})

    @Slot(bool)
    def setBatteryCalibration(self, enabled):
        self._send.emit({"cmd": "set_battery_calibration", "enabled": enabled})

    @Slot(int)
    def setUsbCharging(self, level):
        self._send.emit({"cmd": "set_usb_charging", "level": level})


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    QGuiApplication.setApplicationName("Linux Sense")
    QGuiApplication.setOrganizationName("linux-sense")
    QGuiApplication.setDesktopFileName("linux-sense")
    app = QGuiApplication(sys.argv)
    app.setWindowIcon(QIcon(str(HERE / "logo" / "linux-sense.svg")))

    # single instance: if the app is already open (e.g. the N key pressed again),
    # pass the Wayland activation token to the existing window and exit
    instance = f"linux-sense-{os.getuid()}"
    probe = QLocalSocket()
    probe.connectToServer(instance)
    if probe.waitForConnected(300):
        probe.write((os.environ.get("XDG_ACTIVATION_TOKEN", "") + "\n").encode())
        probe.flush()
        probe.waitForBytesWritten(500)
        return
    QLocalServer.removeServer(instance)
    server = QLocalServer()
    server.listen(instance)
    QQuickStyle.setStyle("Basic")
    for f in sorted((HERE / "fonts").glob("*.ttf")):
        QFontDatabase.addApplicationFont(str(f))

    backend = Backend()
    translator = Translator(system_language())
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("tr", Tr(translator, engine))
    engine.addImageProvider("icon", IconProvider())
    engine.addImportPath(str(HERE / "qml"))
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("logoUrl", (HERE / "logo" / "linux-sense.svg").as_uri())
    engine.load(HERE / "qml" / "Main.qml")
    if not engine.rootObjects():
        sys.exit(1)
    window = engine.rootObjects()[0]

    def raise_window():
        conn = server.nextPendingConnection()

        def activate():
            token = bytes(conn.readAll()).decode().strip()
            if token:
                os.environ["XDG_ACTIVATION_TOKEN"] = token
            if window.visibility() == window.Visibility.Minimized:
                window.showNormal()
            window.raise_()
            window.requestActivate()
            conn.disconnectFromServer()
        conn.readyRead.connect(activate)
    server.newConnection.connect(raise_window)

    code = app.exec()
    del engine
    backend.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
