"""Active client connection registry.

Owns the ``client_id -> websocket`` mapping and the broadcast loop.
The pipeline keeps ``EnhancedAsyncPipeline.connections: ConnectionRegistry``
and exposes ``register_client`` / ``unregister_client`` as thin pass-through
methods so existing callers in ``api/endpoints/voice/streaming.py`` keep
working unchanged.

Per-chunk overhead of one extra attribute lookup is negligible against
the per-frame ``json.dumps`` + ``await ws.send`` already happening here.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Iterator, List, Optional, Tuple


class ConnectionRegistry:
    def __init__(self, logger: logging.Logger) -> None:
        self._clients: Dict[str, Any] = {}
        self._logger = logger

    def register(self, client_id: str, websocket: Any) -> None:
        self._clients[client_id] = websocket
        self._logger.info(f"Client registered: {client_id}")

    async def unregister(self, client_id: str) -> None:
        if client_id in self._clients:
            del self._clients[client_id]
            self._logger.info(f"Client unregistered: {client_id}")

    def get(self, client_id: str) -> Optional[Any]:
        return self._clients.get(client_id)

    def __contains__(self, client_id: str) -> bool:
        return client_id in self._clients

    def __len__(self) -> int:
        return len(self._clients)

    def items(self) -> Iterator[Tuple[str, Any]]:
        return iter(self._clients.items())

    async def send_to_all(
        self,
        frame: Dict[str, Any],
        chunk_id: str,
        binary_data: Optional[bytes] = None,
    ) -> Tuple[int, int]:
        """Broadcast a frame to every connected client; drop dead ones.

        Returns ``(sent_count, failed_count)``. Disconnected clients are
        unregistered before this returns.
        """
        if not self._clients:
            return (0, 0)

        sent_count = 0
        disconnected: List[str] = []

        for client_id, websocket in self._clients.items():
            try:
                frame_json = json.dumps(frame)
                if binary_data:
                    if hasattr(websocket, "send_text") and hasattr(
                        websocket, "send_bytes"
                    ):
                        await websocket.send_text(frame_json)
                        await websocket.send_bytes(binary_data)
                    elif hasattr(websocket, "send"):
                        await websocket.send(frame_json)
                    else:
                        await websocket.send(frame_json)
                else:
                    if hasattr(websocket, "send_text"):
                        await websocket.send_text(frame_json)
                    elif hasattr(websocket, "send"):
                        await websocket.send(frame_json)
                    else:
                        await websocket(frame_json)
                sent_count += 1
            except Exception as exc:  # noqa: BLE001
                self._logger.warning(
                    f"Failed to send chunk {chunk_id} to client {client_id}: {exc}"
                )
                disconnected.append(client_id)

        for client_id in disconnected:
            await self.unregister(client_id)

        return (sent_count, len(disconnected))
