"""
PyWebView JS-API bridge.  Every public method is callable from JavaScript as
  window.pywebview.api.method_name(args)   →  Promise
"""

import json
import io
import base64
import webbrowser
from typing import TYPE_CHECKING

import qrcode

if TYPE_CHECKING:
    import webview
    from .ws_server import WsServer
    from .actions import Actions
    from .spotify_ctrl import SpotifyCtrl


class Api:
    def __init__(self, server: "WsServer", actions: "Actions", spotify: "SpotifyCtrl"):
        self._server  = server
        self._actions = actions
        self._spotify = spotify
        self._window  = None

    def set_window(self, window: "webview.Window"):
        self._window = window

    # ── Push an event into the renderer ──────────────────────────────────────

    def _push(self, name: str, data=None):
        if self._window:
            self._window.evaluate_js(
                f"window._dacxEvent({json.dumps(name)}, {json.dumps(data)})"
            )

    # ── Server info ───────────────────────────────────────────────────────────

    def get_server_info(self) -> dict:
        return self._server.get_info()

    def get_clients(self) -> list:
        return self._server.get_clients()

    def generate_qr(self, data: str) -> str:
        img = qrcode.make(data, error_correction=qrcode.constants.ERROR_CORRECT_M)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()
        return f"data:image/png;base64,{b64}"

    # ── System ────────────────────────────────────────────────────────────────

    def get_volume(self) -> int:
        return self._actions.get_volume()

    def get_brightness(self) -> int:
        return self._actions.get_brightness()

    def get_apps(self) -> list:
        return self._actions.get_apps()

    def save_apps(self, apps: list) -> dict:
        return self._actions.save_apps(apps)

    # ── Spotify ───────────────────────────────────────────────────────────────

    def spotify_auth(self, creds: dict) -> dict:
        return self._spotify.authorize(creds["clientId"], creds["clientSecret"])

    def spotify_status(self):
        return self._spotify.get_status()

    def spotify_is_connected(self) -> bool:
        return self._spotify.is_connected()

    # ── Shell / window ────────────────────────────────────────────────────────

    def open_external(self, url: str):
        webbrowser.open(url)

    def window_minimize(self):
        if self._window:
            self._window.minimize()

    def window_close(self):
        if self._window:
            self._window.hide()
