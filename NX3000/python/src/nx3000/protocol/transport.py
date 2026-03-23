"""Low-level TCP transport for the NX3000 protocol."""

from __future__ import annotations

import logging
import socket

from ..exceptions import TransportError


def send_tcp_request(
    host: str,
    port: int,
    request_bytes: bytes,
    timeout: float,
    debug: bool = False,
    logger: logging.Logger | None = None,
) -> str:
    """Send a raw TCP request and return the full decoded response."""

    log = logger or logging.getLogger("nx3000.protocol")
    if debug:
        log.debug("Sending request to %s:%s", host, port)
        log.debug("Raw request:\n%s", request_bytes.decode("ascii", errors="replace"))

    chunks: list[bytes] = []
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(request_bytes)
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
    except OSError as exc:
        raise TransportError(f"Failed to communicate with camera at {host}:{port}: {exc}") from exc

    response = b"".join(chunks).decode("utf-8", errors="replace")
    if debug:
        log.debug("Raw response:\n%s", response)
    return response

