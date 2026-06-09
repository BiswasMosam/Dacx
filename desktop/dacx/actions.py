"""
System actions: volume (pycaw / Windows Core Audio), brightness
(screen-brightness-control), app launching, and media keys (ctypes).
"""

import ctypes
import json
import os
import subprocess
from pathlib import Path
from typing import Optional


# ── COM init helper (pycaw needs COM on the calling thread) ──────────────────

def _com_init():
    try:
        import pythoncom
        pythoncom.CoInitialize()
    except Exception:
        pass


# ── Default app list ─────────────────────────────────────────────────────────

_APPDATA = os.environ.get("APPDATA", "")

DEFAULT_APPS = [
    {"id": "chrome",    "label": "Chrome",     "path": r"C:\Program Files\Google\Chrome\Application\chrome.exe"},
    {"id": "vscode",    "label": "VS Code",    "path": r"C:\Program Files\Microsoft VS Code\Code.exe"},
    {"id": "explorer",  "label": "Explorer",   "path": "explorer.exe"},
    {"id": "spotify",   "label": "Spotify",    "path": str(Path(_APPDATA) / "Spotify" / "Spotify.exe")},
    {"id": "notepad",   "label": "Notepad",    "path": "notepad.exe"},
    {"id": "calc",      "label": "Calculator", "path": "calc.exe"},
]


class Actions:
    def __init__(self, user_data: str):
        self._config = os.path.join(user_data, "apps.json")
        self._apps   = self._load_apps()
        self._vol_ep = None   # cached IAudioEndpointVolume

    # ── App config ────────────────────────────────────────────────────────────

    def _load_apps(self) -> list:
        try:
            with open(self._config) as f:
                return json.load(f)
        except Exception:
            return list(DEFAULT_APPS)

    def save_apps(self, apps: list) -> dict:
        self._apps = apps
        with open(self._config, "w") as f:
            json.dump(apps, f, indent=2)
        return {"ok": True}

    def get_apps(self) -> list:
        return self._apps

    # ── Volume (pycaw → Windows Core Audio) ──────────────────────────────────

    def _endpoint(self):
        if self._vol_ep is not None:
            return self._vol_ep
        _com_init()
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume
        from comtypes import CLSCTX_ALL

        dev  = AudioUtilities.GetSpeakers()
        iface = dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        self._vol_ep = iface.QueryInterface(IAudioEndpointVolume)
        return self._vol_ep

    def get_volume(self) -> int:
        try:
            return round(self._endpoint().GetMasterVolumeLevelScalar() * 100)
        except Exception:
            return 50

    def set_volume(self, level: int) -> dict:
        level = max(0, min(100, int(level)))
        self._endpoint().SetMasterVolumeLevelScalar(level / 100.0, None)
        return {"volume": level}

    def toggle_mute(self) -> dict:
        ep  = self._endpoint()
        now = ep.GetMute()
        ep.SetMute(not now, None)
        return {"muted": not now}

    def handle_volume(self, msg: dict) -> dict:
        a = msg.get("action")
        if a == "set":  return self.set_volume(msg["value"])
        if a == "up":   return self.set_volume(self.get_volume() + msg.get("step", 5))
        if a == "down": return self.set_volume(self.get_volume() - msg.get("step", 5))
        if a == "mute": return self.toggle_mute()
        raise ValueError(f"Unknown volume action: {a}")

    # ── Brightness ────────────────────────────────────────────────────────────

    def get_brightness(self) -> int:
        try:
            import screen_brightness_control as sbc
            return sbc.get_brightness(display=0)[0]
        except Exception:
            return 50

    def set_brightness(self, level: int) -> dict:
        level = max(0, min(100, int(level)))
        import screen_brightness_control as sbc
        sbc.set_brightness(level, display=0)
        return {"brightness": level}

    def handle_brightness(self, msg: dict) -> dict:
        a = msg.get("action")
        if a == "set":  return self.set_brightness(msg["value"])
        if a == "up":   return self.set_brightness(self.get_brightness() + msg.get("step", 10))
        if a == "down": return self.set_brightness(self.get_brightness() - msg.get("step", 10))
        raise ValueError(f"Unknown brightness action: {a}")

    # ── App launcher ──────────────────────────────────────────────────────────

    def launch(self, app_id: str) -> dict:
        app = next((a for a in self._apps if a["id"] == app_id), None)
        if not app:
            raise ValueError(f'App "{app_id}" not configured')
        subprocess.Popen(
            app["path"],
            shell=True,
            creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        return {"launched": app_id}

    # ── Media keys (global, works for any player) ─────────────────────────────

    _MEDIA_VK = {"play_pause": 0xB3, "next": 0xB0, "prev": 0xB1}

    def media_key(self, key: str) -> dict:
        vk = self._MEDIA_VK.get(key)
        if not vk:
            raise ValueError(f"Unknown media key: {key}")
        KEYEVENTF_KEYUP = 0x0002
        ctypes.windll.user32.keybd_event(vk, 0, 0, 0)
        ctypes.windll.user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)
        return {"ok": True}
