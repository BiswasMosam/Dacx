"""
Async WebSocket server running in a daemon thread.
Handles pairing (6-digit code) then routes commands to registered callbacks.
"""

import asyncio
import json
import secrets
import socket
import threading
import uuid
from typing import Callable, Optional

import websockets
from websockets.server import WebSocketServerProtocol


class WsServer:
    def __init__(self, port: int = 9876):
        self.port = port
        self.pairing_code: str = self._gen_code()
        self._clients: dict[str, dict] = {}   # id → {ws, name, ip}
        self._loop: Optional[asyncio.AbstractEventLoop] = None

        # Callbacks — set from main.py before start_background()
        self.on_command:    Optional[Callable] = None
        self.on_connect:    Optional[Callable] = None
        self.on_disconnect: Optional[Callable] = None

    # ── Public helpers ────────────────────────────────────────────────────────

    @staticmethod
    def _gen_code() -> str:
        return str(secrets.randbelow(900_000) + 100_000)

    @staticmethod
    def _local_ip() -> str:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    def get_info(self) -> dict:
        return {"ip": self._local_ip(), "port": self.port, "code": self.pairing_code}

    def get_clients(self) -> list:
        return [
            {"id": c["id"], "name": c["name"], "ip": c["ip"]}
            for c in self._clients.values()
        ]

    def refresh_code(self) -> str:
        self.pairing_code = self._gen_code()
        return self.pairing_code

    # ── Broadcast to all connected clients ───────────────────────────────────

    def broadcast(self, msg: dict):
        if not self._loop:
            return
        data = json.dumps(msg)

        async def _send():
            dead = []
            for cid, c in list(self._clients.items()):
                ws: WebSocketServerProtocol = c["ws"]
                try:
                    await ws.send(data)
                except Exception:
                    dead.append(cid)
            for cid in dead:
                self._clients.pop(cid, None)

        asyncio.run_coroutine_threadsafe(_send(), self._loop)

    # ── Connection handler ────────────────────────────────────────────────────

    async def _handle(self, ws: WebSocketServerProtocol):
        ip = ws.remote_address[0] if ws.remote_address else "unknown"
        client_id: Optional[str] = None
        authed = False

        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    await ws.send(json.dumps({"type": "error", "message": "bad_json"}))
                    continue

                # ── Pairing handshake ─────────────────────────────────────
                if not authed:
                    if msg.get("type") != "auth" or msg.get("code") != self.pairing_code:
                        await ws.send(json.dumps({"type": "auth_fail", "reason": "wrong_code"}))
                        break

                    client_id = str(uuid.uuid4())
                    authed = True
                    info = {"id": client_id, "name": msg.get("name", "Mobile"), "ip": ip}
                    self._clients[client_id] = {**info, "ws": ws}
                    await ws.send(json.dumps({"type": "auth_ok", "clientId": client_id}))

                    if self.on_connect:
                        threading.Thread(
                            target=self.on_connect, args=(info,), daemon=True
                        ).start()
                    continue

                # ── Authenticated command ─────────────────────────────────
                if self.on_command:
                    loop = asyncio.get_running_loop()
                    try:
                        result = await loop.run_in_executor(None, self.on_command, msg)
                        await ws.send(json.dumps({"type": "result", **(result or {})}))
                    except Exception as e:
                        await ws.send(json.dumps({"type": "error", "message": str(e)}))

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if client_id:
                self._clients.pop(client_id, None)
                if self.on_disconnect:
                    threading.Thread(
                        target=self.on_disconnect, args=(client_id,), daemon=True
                    ).start()

    # ── Server lifecycle ──────────────────────────────────────────────────────

    async def _serve(self):
        async with websockets.serve(self._handle, "0.0.0.0", self.port):
            print(f"[Dacx] WS server on {self._local_ip()}:{self.port}  code={self.pairing_code}")
            await asyncio.Future()   # run forever

    def start_background(self):
        def _run():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            self._loop.run_until_complete(self._serve())

        threading.Thread(target=_run, daemon=True, name="dacx-ws").start()
