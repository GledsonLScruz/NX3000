"""High-level client for the Samsung NX3000 protocol."""

from __future__ import annotations

import logging
from pathlib import Path

from .config import CameraConfig
from .exceptions import BrowseError, HandshakeError
from .models import MediaItem
from .protocol.parsing import parse_browse_response
from .protocol.requests import build_browse_request, build_handshake_request
from .protocol.transport import send_tcp_request


class NX3000Client:
    """Client for connecting to and browsing a Samsung NX3000 camera."""

    def __init__(
        self,
        config: CameraConfig,
        *,
        debug: bool = False,
        logger: logging.Logger | None = None,
    ) -> None:
        self.config = config
        self.debug = debug
        self.logger = logger or logging.getLogger("nx3000")

    def handshake(self) -> str:
        """Perform the camera control handshake."""

        request_bytes = build_handshake_request(self.config)
        try:
            return send_tcp_request(
                self.config.camera_ip,
                self.config.control_port,
                request_bytes,
                self.config.socket_timeout_seconds,
                debug=self.debug,
                logger=self.logger,
            )
        except Exception as exc:  # pragma: no cover - wrapped for API clarity
            if isinstance(exc, HandshakeError):
                raise
            raise HandshakeError(str(exc)) from exc

    def browse(
        self,
        *,
        start: int = 0,
        count: int = 100,
        object_id: str = "8",
        connect_first: bool = False,
    ) -> list[MediaItem]:
        """Browse camera media items."""

        if connect_first:
            self.handshake()

        request_bytes = build_browse_request(
            self.config,
            object_id=object_id,
            starting_index=start,
            requested_count=count,
        )
        try:
            raw_response = send_tcp_request(
                self.config.camera_ip,
                self.config.browse_port,
                request_bytes,
                self.config.socket_timeout_seconds,
                debug=self.debug,
                logger=self.logger,
            )
        except Exception as exc:  # pragma: no cover - wrapped for API clarity
            raise BrowseError(str(exc)) from exc

        return parse_browse_response(raw_response)

    def connect_and_browse(
        self,
        *,
        start: int = 0,
        count: int = 100,
        object_id: str = "8",
    ) -> list[MediaItem]:
        """Convenience method to handshake and browse in sequence."""

        self.handshake()
        return self.browse(start=start, count=count, object_id=object_id)

    def download_item(
        self,
        item: MediaItem,
        dest: str | Path,
        *,
        overwrite: bool = False,
    ) -> Path:
        """Download a single media item."""

        return item.download(dest, overwrite=overwrite)

    def download_all(
        self,
        items: list[MediaItem],
        dest: str | Path,
        *,
        overwrite: bool = False,
    ) -> list[Path]:
        """Download multiple media items sequentially."""

        output_dir = Path(dest).expanduser()
        output_dir.mkdir(parents=True, exist_ok=True)
        return [self.download_item(item, output_dir, overwrite=overwrite) for item in items]

