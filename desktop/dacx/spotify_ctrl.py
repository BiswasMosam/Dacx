"""
Spotify playback control via spotipy + OAuth PKCE flow.
authorize() blocks the calling thread until the browser callback arrives —
that's fine because pywebview runs API calls off the GUI thread.
"""

import json
import os
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
from typing import Optional

import spotipy
from spotipy.oauth2 import SpotifyOAuth

# Spotify rejects "localhost" redirect URIs since 2025; loopback has to be the IP.
REDIRECT_URI = "http://127.0.0.1:8888/callback"
SCOPE = (
    "user-read-playback-state "
    "user-modify-playback-state "
    "user-read-currently-playing"
)

_CALLBACK_HTML = (
    "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Dacx</title>"
    "<style>*{margin:0;padding:0}body{background:#08080f;color:#e5e7eb;"
    "font-family:-apple-system,sans-serif;display:flex;align-items:center;"
    "justify-content:center;height:100vh;flex-direction:column;gap:12px}"
    "h2{color:#7c3aed;letter-spacing:.1em}p{color:#6b7280;font-size:14px}"
    "</style></head><body>"
    "<h2>DACX</h2><p>Spotify connected. You can close this tab.</p>"
    "</body></html>"
).encode("utf-8")


class SpotifyCtrl:
    def __init__(self, user_data: str):
        self._cfg_path   = os.path.join(user_data, "spotify.json")
        self._cache_path = os.path.join(user_data, "spotify_token.cache")
        self._sp: Optional[spotipy.Spotify] = None
        self._oauth: Optional[SpotifyOAuth] = None
        self._init()

    # ── Init / restore from saved credentials ────────────────────────────────

    def _init(self):
        try:
            with open(self._cfg_path) as f:
                cfg = json.load(f)
            self._oauth = SpotifyOAuth(
                client_id=cfg["clientId"],
                client_secret=cfg["clientSecret"],
                redirect_uri=REDIRECT_URI,
                scope=SCOPE,
                cache_path=self._cache_path,
                open_browser=False,
            )
            token = self._oauth.get_cached_token()
            if token:
                self._sp = spotipy.Spotify(auth_manager=self._oauth)
        except Exception:
            pass

    def is_connected(self) -> bool:
        return self._sp is not None

    # ── OAuth flow ────────────────────────────────────────────────────────────

    def authorize(self, client_id: str, client_secret: str) -> dict:
        self._oauth = SpotifyOAuth(
            client_id=client_id,
            client_secret=client_secret,
            redirect_uri=REDIRECT_URI,
            scope=SCOPE,
            cache_path=self._cache_path,
            open_browser=False,
        )

        auth_url = self._oauth.get_authorize_url()
        webbrowser.open(auth_url)

        # Persist credentials so we can re-init after restart
        with open(self._cfg_path, "w") as f:
            json.dump({"clientId": client_id, "clientSecret": client_secret}, f)

        # Block until callback arrives (runs in a pywebview API thread, not GUI)
        result: dict = {}

        class _Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path != "/callback":
                    self.send_response(404); self.end_headers(); return
                qs = parse_qs(parsed.query)
                result["code"]  = qs.get("code",  [None])[0]
                result["error"] = qs.get("error", [None])[0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(_CALLBACK_HTML)

            def log_message(self, *args):  # silence request log
                pass

        httpd = HTTPServer(("127.0.0.1", 8888), _Handler)
        httpd.timeout = 120
        httpd.handle_request()

        if result.get("error") or not result.get("code"):
            raise RuntimeError(result.get("error") or "No authorization code returned")

        self._oauth.get_access_token(result["code"], as_dict=False)
        self._sp = spotipy.Spotify(auth_manager=self._oauth)
        return {"ok": True}

    # ── Status ────────────────────────────────────────────────────────────────

    def get_status(self) -> Optional[dict]:
        if not self._sp:
            return None
        try:
            pb = self._sp.current_playback()
            if not pb or not pb.get("item"):
                return {"connected": True, "playing": False}
            item = pb["item"]
            device = pb.get("device") or {}
            images = item["album"].get("images", [])
            return {
                "connected":  True,
                "playing":    pb["is_playing"],
                "trackId":    item.get("id"),
                "track":      item["name"],
                "artist":     ", ".join(a["name"] for a in item["artists"]),
                "album":      item["album"]["name"],
                "albumArt":   images[0]["url"] if images else None,
                "progress":   pb.get("progress_ms"),
                "duration":   item["duration_ms"],
                "shuffle":    pb.get("shuffle_state", False),
                "repeat":     pb.get("repeat_state", "off"),   # off | context | track
                "volume":     device.get("volume_percent"),
                "supportsVolume": device.get("supports_volume", True),
                "deviceId":   device.get("id"),
                "deviceName": device.get("name"),
                "deviceType": device.get("type"),
            }
        except Exception as e:
            print(f"[Dacx] Spotify status: {e}")
            return None

    # ── Command router ────────────────────────────────────────────────────────

    # ── Queue & devices ───────────────────────────────────────────────────────

    @staticmethod
    def _track_row(item: dict) -> dict:
        album  = item.get("album") or {}
        images = album.get("images") or (item.get("images") or [])
        return {
            "id":     item.get("id"),
            "name":   item.get("name", ""),
            "artist": ", ".join(a["name"] for a in item.get("artists", []))
                      or (item.get("show") or {}).get("name", ""),
            "image":  images[-1]["url"] if images else None,   # smallest
        }

    def get_queue(self) -> dict:
        q = self._sp.queue() or {}
        now = q.get("currently_playing")
        return {
            "current": self._track_row(now) if now else None,
            "queue":   [self._track_row(i) for i in (q.get("queue") or [])[:30]],
        }

    def get_devices(self) -> dict:
        devices = (self._sp.devices() or {}).get("devices", [])
        return {"devices": [
            {
                "id":     d.get("id"),
                "name":   d.get("name", ""),
                "type":   d.get("type", ""),
                "active": d.get("is_active", False),
                "volume": d.get("volume_percent"),
            }
            for d in devices
        ]}

    # ── Command router ────────────────────────────────────────────────────────

    _REASONS = {
        "NO_ACTIVE_DEVICE": "No active Spotify device. Pick one in Devices.",
        "PREMIUM_REQUIRED": "Spotify Premium is needed to control playback.",
        "VOLUME_CONTROL_DISALLOW": "This device doesn't allow volume control.",
    }

    def handle(self, msg: dict) -> dict:
        a = msg.get("action")
        if a == "status":
            return {"authorized": self.is_connected(), "spotify": self.get_status()}
        if not self._sp:
            raise RuntimeError("Spotify isn't linked. Connect it in Dacx on your PC.")

        try:
            if a == "queue":   return self.get_queue()
            if a == "devices": return self.get_devices()

            if a == "play":       self._sp.start_playback()
            elif a == "pause":    self._sp.pause_playback()
            elif a == "next":     self._sp.next_track()
            elif a == "previous": self._sp.previous_track()
            elif a == "volume":   self._sp.volume(max(0, min(100, int(msg.get("value", 50)))))
            elif a == "seek":     self._sp.seek_track(int(msg.get("position", 0)))
            elif a == "shuffle":  self._sp.shuffle(bool(msg.get("value")))
            elif a == "repeat":   self._sp.repeat(msg.get("value", "off"))
            elif a == "transfer": self._sp.transfer_playback(msg["deviceId"], force_play=True)
            else: raise ValueError(f"Unknown Spotify action: {a}")
        except spotipy.SpotifyException as e:
            raise RuntimeError(self._REASONS.get(e.reason or "", e.msg or str(e))) from e

        return {"authorized": True, "spotify": self.get_status()}
