# Dacx

Turn your phone into a wireless control deck for your PC — volume, brightness, app shortcuts, and Spotify, all from your pocket.

No hardware. No cloud. Just your local WiFi.

---

## How it works

```
┌─────────────────┐          WiFi (LAN only)         ┌──────────────────────┐
│   Dacx Mobile   │ ◄──────── WebSocket ────────────► │   Dacx Desktop       │
│   (Flutter)     │            port 9876              │   (Python)           │
│                 │         nothing leaves            │                      │
│  tap buttons    │            your router            │  controls your PC    │
└─────────────────┘                                   └──────────────────────┘
```

Both devices must be on the same WiFi network. The desktop app generates a **6-digit pairing code** and a **QR code** — scan or enter it on mobile to connect instantly.

---

## Features

| Feature | Desktop | Mobile |
|---|---|---|
| Volume control (up / down / mute / set) | Windows Core Audio (pycaw) | Slider + buttons |
| Brightness control | WMI / screen-brightness-control | Slider + buttons |
| App shortcuts | Configurable list | Custom button grid |
| Spotify control | Spotify Web API (spotipy) | Special Spotify UI |
| Media keys (play / pause / next / prev) | ctypes keybd_event | Buttons |
| Pairing | 6-digit code + QR | Scan or type code |

> Spotify is the only feature that touches the internet (Spotify's own API). Everything else is fully local.

---

## Desktop App

Built with **Python** + **CustomTkinter**. Runs on Windows.

### Setup

```bash
cd desktop
pip install -r requirements.txt
python main.py
```

### Structure

```
desktop/
├── main.py               # Entry point
├── requirements.txt
└── dacx/
    ├── app_window.py     # Full CustomTkinter UI
    ├── ws_server.py      # asyncio WebSocket server (LAN)
    ├── actions.py        # Volume · Brightness · App launcher · Media keys
    └── spotify_ctrl.py   # Spotify OAuth + playback control
```

### Spotify setup

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
2. Create an app → set redirect URI to `http://localhost:8888/callback`
3. Copy Client ID and Client Secret
4. Click **Connect** in the Dacx desktop app and paste them in

---

## Mobile App

Built with **Flutter**. Connects over LAN — no internet required.

> Coming soon.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Desktop UI | Python · CustomTkinter |
| Desktop system actions | pycaw · screen-brightness-control · ctypes |
| Desktop ↔ Mobile transport | asyncio WebSocket (`ws`) |
| Spotify | spotipy · Spotify Web API |
| Mobile | Flutter · Dart |
| Pairing | 6-digit local code + QR (LAN only) |

---

## Privacy

- No data is sent to any server other than Spotify's own API (for Spotify control)
- The pairing code, QR code, and all commands are generated and transmitted locally
- No accounts, no sign-up, no telemetry
