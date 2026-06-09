"""
Main application window built entirely in CustomTkinter.
"""

import io
import threading
import webbrowser
from typing import TYPE_CHECKING

import customtkinter as ctk
from PIL import Image
import qrcode

if TYPE_CHECKING:
    from .ws_server import WsServer
    from .actions import Actions
    from .spotify_ctrl import SpotifyCtrl

# ── Palette ───────────────────────────────────────────────────────────────────
BG          = "#08080f"
SURFACE     = "#111119"
SURFACE2    = "#1a1a28"
BORDER      = "#1f1f30"
ACCENT      = "#6d28d9"
ACCENT_HI   = "#7c3aed"
TEXT        = "#e5e7eb"
MUTED       = "#6b7280"
SUCCESS     = "#10b981"
DANGER      = "#ef4444"

FONT_TITLE  = ("Segoe UI", 22, "bold")
FONT_LABEL  = ("Segoe UI", 10)
FONT_MONO   = ("Consolas", 13)
FONT_CODE   = ("Consolas", 26, "bold")
FONT_BODY   = ("Segoe UI", 12)
FONT_SMALL  = ("Segoe UI", 10)
FONT_BTN    = ("Segoe UI", 11, "bold")


def _card(parent, **kw) -> ctk.CTkFrame:
    return ctk.CTkFrame(
        parent,
        fg_color=SURFACE,
        corner_radius=12,
        border_width=1,
        border_color=BORDER,
        **kw,
    )


def _section_label(parent, text: str):
    ctk.CTkLabel(
        parent, text=text.upper(),
        font=("Segoe UI", 9, "bold"),
        text_color=MUTED,
    ).pack(anchor="w", padx=16, pady=(12, 0))


# ── App window ────────────────────────────────────────────────────────────────
class AppWindow(ctk.CTk):
    def __init__(self, server: "WsServer", actions: "Actions", spotify: "SpotifyCtrl"):
        super().__init__(fg_color=BG)
        self._server  = server
        self._actions = actions
        self._spotify = spotify

        self.title("Dacx")
        self.geometry("480x720")
        self.resizable(False, False)
        self.overrideredirect(True)   # frameless
        self._drag_x = self._drag_y = 0

        self._build()
        self._load_initial_state()

        # Periodic refresh
        self._poll_system()
        self._poll_spotify()

    # ── Drag support (frameless window) ───────────────────────────────────────

    def _start_drag(self, e):
        self._drag_x = e.x_root - self.winfo_x()
        self._drag_y = e.y_root - self.winfo_y()

    def _do_drag(self, e):
        self.geometry(f"+{e.x_root - self._drag_x}+{e.y_root - self._drag_y}")

    # ── Layout ────────────────────────────────────────────────────────────────

    def _build(self):
        # ── Title bar ─────────────────────────────────────────────────────────
        tbar = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=46,
                            border_width=0)
        tbar.pack(fill="x")
        tbar.pack_propagate(False)
        tbar.bind("<ButtonPress-1>",   self._start_drag)
        tbar.bind("<B1-Motion>",       self._do_drag)

        ctk.CTkLabel(
            tbar, text="DACX",
            font=("Segoe UI", 14, "bold"), text_color=ACCENT_HI,
        ).pack(side="left", padx=(16, 4), pady=12)
        ctk.CTkLabel(
            tbar, text="desktop",
            font=FONT_SMALL, text_color=MUTED,
        ).pack(side="left", pady=12)

        ctk.CTkButton(
            tbar, text="✕", width=30, height=28,
            fg_color="transparent", hover_color=DANGER,
            text_color=MUTED, font=("Segoe UI", 13),
            command=self._on_close,
        ).pack(side="right", padx=(0, 6), pady=9)

        ctk.CTkButton(
            tbar, text="—", width=30, height=28,
            fg_color="transparent", hover_color=SURFACE2,
            text_color=MUTED, font=("Segoe UI", 13),
            command=self.iconify,
        ).pack(side="right", pady=9)

        # ── Scrollable body ───────────────────────────────────────────────────
        self._scroll = ctk.CTkScrollableFrame(
            self, fg_color=BG, corner_radius=0,
            scrollbar_button_color=SURFACE2,
            scrollbar_button_hover_color=ACCENT,
        )
        self._scroll.pack(fill="both", expand=True)

        self._build_connection()
        self._build_devices()
        self._build_system()
        self._build_spotify()
        self._build_apps()

    # ── Connection card ───────────────────────────────────────────────────────

    def _build_connection(self):
        info = self._server.get_info()

        card = _card(self._scroll)
        card.pack(fill="x", padx=12, pady=(10, 0))
        _section_label(card, "Connection")

        body = ctk.CTkFrame(card, fg_color="transparent")
        body.pack(fill="x", padx=16, pady=(4, 14))
        body.columnconfigure(0, weight=1)

        # Info rows
        rows = ctk.CTkFrame(body, fg_color="transparent")
        rows.grid(row=0, column=0, sticky="nsew")

        def _row(label, value, value_font=FONT_MONO, value_color=TEXT):
            r = ctk.CTkFrame(rows, fg_color="transparent")
            r.pack(fill="x", pady=2)
            ctk.CTkLabel(r, text=label, font=FONT_SMALL, text_color=MUTED,
                         width=40, anchor="w").pack(side="left")
            return ctk.CTkLabel(r, text=value, font=value_font,
                                text_color=value_color, anchor="w")

        _row("IP",   info["ip"]).pack(side="left")
        _row("PORT", str(info["port"])).pack(side="left")

        code_lbl = _row("CODE", self._fmt_code(info["code"]),
                        value_font=FONT_CODE, value_color=ACCENT_HI)
        code_lbl.pack(side="left")
        self._code_lbl = code_lbl

        # Status pill
        self._server_pill = ctk.CTkLabel(
            rows, text="● Online",
            font=FONT_SMALL, text_color=SUCCESS,
        )
        self._server_pill.pack(anchor="w", pady=(6, 0))

        ctk.CTkLabel(rows,
                     text="Scan QR or enter code in Dacx Mobile",
                     font=FONT_SMALL, text_color=MUTED,
                     wraplength=200, justify="left",
                     ).pack(anchor="w", pady=(4, 0))

        # QR code
        qr_frame = ctk.CTkFrame(body, fg_color="transparent")
        qr_frame.grid(row=0, column=1, padx=(12, 0), sticky="n")
        self._qr_label = ctk.CTkLabel(qr_frame, text="")
        self._qr_label.pack()
        threading.Thread(target=self._render_qr, args=(info,), daemon=True).start()

    def _fmt_code(self, code: str) -> str:
        return f"{code[:3]} {code[3:]}"

    def _render_qr(self, info: dict):
        uri = f"dacx://{info['ip']}:{info['port']}?code={info['code']}"
        img = qrcode.make(uri, error_correction=qrcode.constants.ERROR_CORRECT_M)
        img = img.resize((150, 150), Image.LANCZOS)
        ctk_img = ctk.CTkImage(img, size=(150, 150))
        self.after(0, lambda: self._qr_label.configure(image=ctk_img))

    # ── Devices card ──────────────────────────────────────────────────────────

    def _build_devices(self):
        card = _card(self._scroll)
        card.pack(fill="x", padx=12, pady=(10, 0))

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(12, 0))
        _section_label(hdr, "Devices")
        self._device_badge = ctk.CTkLabel(
            hdr, text=" 0 ", font=FONT_SMALL,
            fg_color=ACCENT, corner_radius=10, text_color="white",
        )
        self._device_badge.pack(side="right", pady=(2, 0))

        self._device_list = ctk.CTkFrame(card, fg_color="transparent")
        self._device_list.pack(fill="x", padx=16, pady=(6, 14))

        self._no_devices_lbl = ctk.CTkLabel(
            self._device_list, text="No devices connected",
            font=FONT_SMALL, text_color=MUTED,
        )
        self._no_devices_lbl.pack(anchor="w")

    def on_client_connected(self, info: dict):
        self._refresh_devices()

    def on_client_disconnected(self, cid: str):
        self._refresh_devices()

    def _refresh_devices(self):
        clients = self._server.get_clients()
        # Clear existing
        for w in self._device_list.winfo_children():
            w.destroy()

        self._device_badge.configure(text=f" {len(clients)} ")

        if not clients:
            ctk.CTkLabel(
                self._device_list, text="No devices connected",
                font=FONT_SMALL, text_color=MUTED,
            ).pack(anchor="w")
            return

        for c in clients:
            row = ctk.CTkFrame(self._device_list, fg_color=SURFACE2, corner_radius=8)
            row.pack(fill="x", pady=3)
            ctk.CTkLabel(row, text="●", text_color=SUCCESS,
                         font=FONT_SMALL).pack(side="left", padx=(10, 4), pady=8)
            ctk.CTkLabel(row, text=c["name"], font=FONT_BODY,
                         text_color=TEXT).pack(side="left", pady=8)
            ctk.CTkLabel(row, text=c["ip"], font=FONT_MONO,
                         text_color=MUTED).pack(side="right", padx=10, pady=8)

    # ── System card (volume + brightness) ─────────────────────────────────────

    def _build_system(self):
        card = _card(self._scroll)
        card.pack(fill="x", padx=12, pady=(10, 0))
        _section_label(card, "System")

        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="x", padx=16, pady=(6, 14))

        self._vol_slider, self._vol_val   = self._bar_row(inner, "Volume")
        self._bright_slider, self._bright_val = self._bar_row(inner, "Brightness")

    def _bar_row(self, parent, label: str):
        row = ctk.CTkFrame(parent, fg_color="transparent")
        row.pack(fill="x", pady=5)

        ctk.CTkLabel(row, text=label, font=FONT_SMALL, text_color=MUTED,
                     width=70, anchor="w").pack(side="left")

        slider = ctk.CTkSlider(
            row, from_=0, to=100, width=260,
            button_color=ACCENT_HI, button_hover_color=ACCENT,
            progress_color=ACCENT, fg_color=SURFACE2,
        )
        slider.pack(side="left", padx=(0, 8))
        slider.set(50)

        val_lbl = ctk.CTkLabel(row, text="50%", font=FONT_MONO,
                               text_color=TEXT, width=38, anchor="e")
        val_lbl.pack(side="left")
        return slider, val_lbl

    def _update_volume(self, pct: int):
        self._vol_slider.set(pct)
        self._vol_val.configure(text=f"{pct}%")

    def _update_brightness(self, pct: int):
        self._bright_slider.set(pct)
        self._bright_val.configure(text=f"{pct}%")

    # ── Spotify card ──────────────────────────────────────────────────────────

    def _build_spotify(self):
        card = _card(self._scroll)
        card.pack(fill="x", padx=12, pady=(10, 0))

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(12, 0))
        ctk.CTkLabel(hdr, text="SPOTIFY", font=("Segoe UI", 9, "bold"),
                     text_color=MUTED).pack(side="left")
        self._sp_btn = ctk.CTkButton(
            hdr, text="Connect", width=80, height=26,
            fg_color=ACCENT, hover_color=ACCENT_HI,
            font=FONT_BTN, command=self._open_spotify_dialog,
        )
        self._sp_btn.pack(side="right")

        # Disconnected state
        self._sp_disc = ctk.CTkLabel(
            card,
            text="Link your Spotify account to control playback from your phone.",
            font=FONT_SMALL, text_color=MUTED,
            wraplength=400, justify="left",
        )
        self._sp_disc.pack(anchor="w", padx=16, pady=(6, 14))

        # Now-playing state (hidden by default)
        self._sp_row = ctk.CTkFrame(card, fg_color="transparent")
        self._sp_art   = ctk.CTkLabel(self._sp_row, text="", width=52, height=52)
        self._sp_art.pack(side="left", padx=(0, 10))

        info_col = ctk.CTkFrame(self._sp_row, fg_color="transparent")
        info_col.pack(side="left", fill="x", expand=True)
        self._sp_track  = ctk.CTkLabel(info_col, text="—", font=FONT_BODY,
                                       text_color=TEXT, anchor="w")
        self._sp_track.pack(anchor="w")
        self._sp_artist = ctk.CTkLabel(info_col, text="—", font=FONT_SMALL,
                                       text_color=MUTED, anchor="w")
        self._sp_artist.pack(anchor="w")
        self._sp_state  = ctk.CTkLabel(info_col, text="—", font=FONT_SMALL,
                                       text_color=ACCENT_HI, anchor="w")
        self._sp_state.pack(anchor="w")
        self._sp_row_pad = card   # parent for pack/unpack

    def _open_spotify_dialog(self):
        SpotifyDialog(self, self._spotify, self._on_spotify_authed)

    def _on_spotify_authed(self):
        self._sp_btn.configure(text="Reconnect")
        self._poll_spotify()

    def _update_spotify_ui(self, status):
        if not status or not status.get("track"):
            self._sp_row.pack_forget()
            self._sp_disc.pack(anchor="w", padx=16, pady=(6, 14))
            return

        self._sp_disc.pack_forget()
        self._sp_row.pack(fill="x", padx=16, pady=(6, 14))
        self._sp_track.configure(text=status["track"])
        self._sp_artist.configure(text=status["artist"])
        self._sp_state.configure(
            text="▶ Playing" if status.get("playing") else "⏸ Paused"
        )
        self._sp_btn.configure(text="Reconnect")

        art_url = status.get("albumArt")
        if art_url:
            threading.Thread(target=self._load_album_art,
                             args=(art_url,), daemon=True).start()

    def _load_album_art(self, url: str):
        try:
            import urllib.request
            with urllib.request.urlopen(url, timeout=5) as r:
                data = r.read()
            img = Image.open(io.BytesIO(data)).resize((52, 52), Image.LANCZOS)
            ctk_img = ctk.CTkImage(img, size=(52, 52))
            self.after(0, lambda: self._sp_art.configure(image=ctk_img, text=""))
        except Exception:
            pass

    # ── App shortcuts card ────────────────────────────────────────────────────

    def _build_apps(self):
        card = _card(self._scroll)
        card.pack(fill="x", padx=12, pady=(10, 14))

        hdr = ctk.CTkFrame(card, fg_color="transparent")
        hdr.pack(fill="x", padx=16, pady=(12, 0))
        ctk.CTkLabel(hdr, text="APP SHORTCUTS", font=("Segoe UI", 9, "bold"),
                     text_color=MUTED).pack(side="left")
        ctk.CTkButton(
            hdr, text="Manage", width=70, height=26,
            fg_color=SURFACE2, hover_color=ACCENT,
            font=FONT_BTN, text_color=MUTED,
            command=self._open_apps_dialog,
        ).pack(side="right")

        self._apps_grid = ctk.CTkFrame(card, fg_color="transparent")
        self._apps_grid.pack(fill="x", padx=16, pady=(8, 14))
        self._render_apps_grid()

    def _render_apps_grid(self):
        for w in self._apps_grid.winfo_children():
            w.destroy()
        apps = self._actions.get_apps()
        cols = 4
        for i, app in enumerate(apps):
            chip = ctk.CTkFrame(self._apps_grid, fg_color=SURFACE2,
                                corner_radius=8, width=90, height=54)
            chip.grid(row=i // cols, column=i % cols, padx=3, pady=3, sticky="nsew")
            chip.grid_propagate(False)
            ctk.CTkLabel(chip, text=app["label"], font=FONT_SMALL,
                         text_color=MUTED, wraplength=82,
                         justify="center").place(relx=.5, rely=.5, anchor="center")

    def _open_apps_dialog(self):
        AppsDialog(self, self._actions, self._render_apps_grid)

    # ── Polling ───────────────────────────────────────────────────────────────

    def _load_initial_state(self):
        threading.Thread(target=self._fetch_system, daemon=True).start()

    def _poll_system(self):
        threading.Thread(target=self._fetch_system, daemon=True).start()
        self.after(8_000, self._poll_system)

    def _fetch_system(self):
        vol    = self._actions.get_volume()
        bright = self._actions.get_brightness()
        self.after(0, lambda: self._update_volume(vol))
        self.after(0, lambda: self._update_brightness(bright))

    def _poll_spotify(self):
        threading.Thread(target=self._fetch_spotify, daemon=True).start()
        self.after(5_000, self._poll_spotify)

    def _fetch_spotify(self):
        status = self._spotify.get_status()
        self.after(0, lambda: self._update_spotify_ui(status))

    # ── Window close → minimise ───────────────────────────────────────────────

    def _on_close(self):
        self.iconify()


# ── Spotify credentials dialog ────────────────────────────────────────────────

class SpotifyDialog(ctk.CTkToplevel):
    def __init__(self, parent, spotify: "SpotifyCtrl", on_success):
        super().__init__(parent, fg_color=SURFACE)
        self._spotify    = spotify
        self._on_success = on_success

        self.title("Connect Spotify")
        self.geometry("380x310")
        self.resizable(False, False)
        self.grab_set()

        ctk.CTkLabel(self, text="Connect Spotify",
                     font=FONT_TITLE, text_color=TEXT).pack(pady=(20, 4))
        ctk.CTkLabel(
            self,
            text=(
                "Create a Spotify app at developer.spotify.com\n"
                "and set redirect URI: http://localhost:8888/callback"
            ),
            font=FONT_SMALL, text_color=MUTED, justify="center",
        ).pack(pady=(0, 16))

        ctk.CTkLabel(self, text="Client ID", font=FONT_SMALL,
                     text_color=MUTED, anchor="w").pack(fill="x", padx=24)
        self._id_entry = ctk.CTkEntry(self, placeholder_text="Paste Client ID",
                                      height=36)
        self._id_entry.pack(fill="x", padx=24, pady=(2, 10))

        ctk.CTkLabel(self, text="Client Secret", font=FONT_SMALL,
                     text_color=MUTED, anchor="w").pack(fill="x", padx=24)
        self._sec_entry = ctk.CTkEntry(self, placeholder_text="Paste Client Secret",
                                       show="•", height=36)
        self._sec_entry.pack(fill="x", padx=24, pady=(2, 16))

        btns = ctk.CTkFrame(self, fg_color="transparent")
        btns.pack(fill="x", padx=24)
        ctk.CTkButton(btns, text="Cancel", fg_color=SURFACE2,
                      hover_color=BORDER, font=FONT_BTN,
                      command=self.destroy).pack(side="left", expand=True, padx=(0, 4))
        self._auth_btn = ctk.CTkButton(
            btns, text="Authorize",
            fg_color=ACCENT, hover_color=ACCENT_HI, font=FONT_BTN,
            command=self._do_auth,
        )
        self._auth_btn.pack(side="left", expand=True, padx=(4, 0))

    def _do_auth(self):
        cid = self._id_entry.get().strip()
        sec = self._sec_entry.get().strip()
        if not cid or not sec:
            return
        self._auth_btn.configure(text="Waiting for browser…", state="disabled")
        threading.Thread(target=self._run_auth, args=(cid, sec), daemon=True).start()

    def _run_auth(self, cid: str, sec: str):
        try:
            self._spotify.authorize(cid, sec)
            self.after(0, self._on_success)
            self.after(0, self.destroy)
        except Exception as e:
            self.after(0, lambda: self._auth_btn.configure(
                text=f"Failed: {e}", state="normal"
            ))


# ── App shortcuts manager dialog ──────────────────────────────────────────────

class AppsDialog(ctk.CTkToplevel):
    def __init__(self, parent, actions: "Actions", on_save):
        super().__init__(parent, fg_color=SURFACE)
        self._actions  = actions
        self._on_save  = on_save
        self._rows: list[dict] = []

        self.title("App Shortcuts")
        self.geometry("460x460")
        self.resizable(False, False)
        self.grab_set()

        ctk.CTkLabel(self, text="App Shortcuts",
                     font=FONT_TITLE, text_color=TEXT).pack(pady=(20, 4))
        ctk.CTkLabel(self, text="These apps appear as buttons in Dacx Mobile.",
                     font=FONT_SMALL, text_color=MUTED).pack(pady=(0, 10))

        self._list_frame = ctk.CTkScrollableFrame(self, fg_color=SURFACE2,
                                                   corner_radius=8, height=280)
        self._list_frame.pack(fill="x", padx=20, pady=(0, 8))

        import copy
        self._apps = copy.deepcopy(actions.get_apps())
        self._render_rows()

        ctk.CTkButton(self, text="+ Add App", fg_color="transparent",
                      border_width=1, border_color=BORDER,
                      hover_color=SURFACE2, text_color=MUTED,
                      font=FONT_BTN, command=self._add_row).pack(fill="x", padx=20)

        btns = ctk.CTkFrame(self, fg_color="transparent")
        btns.pack(fill="x", padx=20, pady=12)
        ctk.CTkButton(btns, text="Cancel", fg_color=SURFACE2,
                      hover_color=BORDER, font=FONT_BTN,
                      command=self.destroy).pack(side="left", expand=True, padx=(0, 4))
        ctk.CTkButton(btns, text="Save", fg_color=ACCENT,
                      hover_color=ACCENT_HI, font=FONT_BTN,
                      command=self._save).pack(side="left", expand=True, padx=(4, 0))

    def _render_rows(self):
        for w in self._list_frame.winfo_children():
            w.destroy()
        self._rows = []
        for app in self._apps:
            self._add_rendered_row(app)

    def _add_row(self):
        self._apps.append({"id": f"app_{len(self._apps)}", "label": "", "path": ""})
        self._render_rows()

    def _add_rendered_row(self, app: dict):
        row = ctk.CTkFrame(self._list_frame, fg_color="transparent")
        row.pack(fill="x", pady=4)

        lbl_e = ctk.CTkEntry(row, placeholder_text="Label", width=100, height=32)
        lbl_e.insert(0, app.get("label", ""))
        lbl_e.pack(side="left", padx=(0, 6))

        path_e = ctk.CTkEntry(row, placeholder_text=r"C:\path\app.exe", height=32)
        path_e.insert(0, app.get("path", ""))
        path_e.pack(side="left", expand=True, fill="x", padx=(0, 6))

        self._rows.append({"id": app["id"], "label": lbl_e, "path": path_e})

        ctk.CTkButton(
            row, text="✕", width=28, height=28,
            fg_color="transparent", hover_color=DANGER,
            text_color=MUTED, font=("Segoe UI", 12),
            command=lambda r=row, idx=len(self._rows) - 1: self._remove(r, idx),
        ).pack(side="left")

    def _remove(self, row_widget, idx: int):
        row_widget.destroy()
        self._rows.pop(idx)

    def _save(self):
        updated = [
            {"id": r["id"], "label": r["label"].get().strip(), "path": r["path"].get().strip()}
            for r in self._rows
            if r["label"].get().strip() and r["path"].get().strip()
        ]
        self._actions.save_apps(updated)
        self._on_save()
        self.destroy()
