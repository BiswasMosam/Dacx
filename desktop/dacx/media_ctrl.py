"""
System-wide media control through the Windows media session (GSMTC), the
same thing the volume flyout talks to. That makes Play and Pause separate
commands and tells us what's playing in any app (Spotify, a browser, VLC).

The winrt calls run on their own thread and event loop so their apartment
never collides with pycaw's COM calls. Without winrt installed, or with no
media session open, it falls back to the global media keys.
"""

import asyncio
import threading
from typing import Optional

try:
    from winrt.windows.media.control import (
        GlobalSystemMediaTransportControlsSessionManager as _SessionManager,
    )
except ImportError:
    _SessionManager = None

_PLAYING = 4   # GlobalSystemMediaTransportControlsSessionPlaybackStatus.PLAYING


class MediaCtrl:
    def __init__(self, actions):
        self._actions = actions   # media keys + system volume
        self._mgr = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        if _SessionManager is not None:
            self._loop = asyncio.new_event_loop()
            threading.Thread(
                target=self._loop.run_forever, daemon=True, name="dacx-media"
            ).start()

    def _run(self, coro, timeout: float = 3.0):
        return asyncio.run_coroutine_threadsafe(coro, self._loop).result(timeout)

    async def _session(self):
        if self._mgr is None:
            self._mgr = await _SessionManager.request_async()
        return self._mgr.get_current_session()

    # ── Now playing ───────────────────────────────────────────────────────────

    async def _now_playing(self) -> Optional[dict]:
        s = await self._session()
        if s is None:
            return None
        info  = s.get_playback_info()
        props = await s.try_get_media_properties_async()
        return {
            "app":     s.source_app_user_model_id,
            "title":   props.title or "",
            "artist":  props.artist or "",
            "playing": int(info.playback_status) == _PLAYING,
        }

    def now_playing(self) -> Optional[dict]:
        if self._loop is None:
            return None
        try:
            return self._run(self._now_playing())
        except Exception:
            return None

    def get_state(self) -> dict:
        return {
            "volume":  self._actions.get_volume(),
            "muted":   self._actions.get_muted(),
            "session": self.now_playing(),
        }

    # ── Transport ─────────────────────────────────────────────────────────────

    async def _transport(self, action: str) -> bool:
        s = await self._session()
        if s is None:
            return False
        if action == "play":       await s.try_play_async()
        elif action == "pause":    await s.try_pause_async()
        elif action == "play_pause": await s.try_toggle_play_pause_async()
        elif action == "next":     await s.try_skip_next_async()
        elif action == "prev":     await s.try_skip_previous_async()
        return True

    _KEYS = {"play": "play_pause", "pause": "play_pause", "play_pause": "play_pause",
             "next": "next", "prev": "prev"}

    def handle(self, msg: dict) -> dict:
        a = msg.get("action")
        if a == "state":
            return self.get_state()
        if a not in self._KEYS:
            raise ValueError(f"Unknown media action: {a}")

        done = False
        if self._loop is not None:
            try:
                done = self._run(self._transport(a))
            except Exception:
                done = False
        if not done:
            self._actions.media_key(self._KEYS[a])
        return {"session": self.now_playing()}
