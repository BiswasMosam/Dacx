"""
Dacx Desktop — entry point.
Builds the CustomTkinter window and wires everything together.
"""

import os
import threading

import customtkinter as ctk

from dacx.ws_server import WsServer
from dacx.actions import Actions
from dacx.spotify_ctrl import SpotifyCtrl
from dacx.app_window import AppWindow

# ── Config ────────────────────────────────────────────────────────────────────
USER_DATA = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Dacx")
os.makedirs(USER_DATA, exist_ok=True)

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")


# ── Services ──────────────────────────────────────────────────────────────────
server  = WsServer()
actions = Actions(USER_DATA)
spotify = SpotifyCtrl(USER_DATA)


def on_command(msg: dict) -> dict:
    t = msg.get("type")
    if t == "volume":     return actions.handle_volume(msg)
    if t == "brightness": return actions.handle_brightness(msg)
    if t == "launch":     return actions.launch(msg.get("appId", ""))
    if t == "spotify":    return spotify.handle(msg)
    if t == "get_state":
        return {
            "volume":     actions.get_volume(),
            "brightness": actions.get_brightness(),
            "spotify":    spotify.get_status(),
        }
    raise ValueError(f"Unknown command: {t}")


def main():
    server.on_command = on_command
    server.start_background()

    root = AppWindow(server, actions, spotify)

    def _client_connected(info):
        root.after(0, lambda: root.on_client_connected(info))

    def _client_disconnected(cid):
        root.after(0, lambda: root.on_client_disconnected(cid))

    server.on_connect    = _client_connected
    server.on_disconnect = _client_disconnected

    root.mainloop()


if __name__ == "__main__":
    main()
