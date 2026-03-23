"""Configuration models for the NX3000 client."""

from __future__ import annotations

from dataclasses import dataclass
import ipaddress
import re

from .exceptions import ConfigurationError


_MAC_RE = re.compile(r"^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$")


def _normalize_mac(value: str) -> str:
    candidate = value.strip()
    if not _MAC_RE.fullmatch(candidate):
        raise ConfigurationError(f"Invalid MAC address: {value!r}")
    return candidate.replace("-", ":").upper()


def _validate_ipv4(value: str, field_name: str) -> str:
    try:
        parsed = ipaddress.ip_address(value)
    except ValueError as exc:
        raise ConfigurationError(f"Invalid IP address for {field_name}: {value!r}") from exc
    if parsed.version != 4:
        raise ConfigurationError(f"{field_name} must be an IPv4 address: {value!r}")
    return value


def _validate_port(value: int, field_name: str) -> int:
    if not 1 <= value <= 65535:
        raise ConfigurationError(f"{field_name} must be between 1 and 65535")
    return value


def _validate_timeout(value: float, field_name: str) -> float:
    if value <= 0:
        raise ConfigurationError(f"{field_name} must be positive")
    return value


@dataclass(slots=True)
class CameraConfig:
    """Connection parameters for the Samsung NX3000 camera."""

    host_mac: str
    camera_ip: str = "192.168.107.1"
    control_port: int = 7788
    browse_port: int = 7676
    host_address: str = "192.168.107.11"
    host_port: int = 7788
    host_pnumber: str = "none"
    socket_timeout_seconds: float = 5.0
    http_timeout_seconds: float = 30.0

    def __post_init__(self) -> None:
        self.host_mac = _normalize_mac(self.host_mac)
        self.camera_ip = _validate_ipv4(self.camera_ip, "camera_ip")
        self.host_address = _validate_ipv4(self.host_address, "host_address")
        self.control_port = _validate_port(self.control_port, "control_port")
        self.browse_port = _validate_port(self.browse_port, "browse_port")
        self.host_port = _validate_port(self.host_port, "host_port")
        self.socket_timeout_seconds = _validate_timeout(
            self.socket_timeout_seconds,
            "socket_timeout_seconds",
        )
        self.http_timeout_seconds = _validate_timeout(
            self.http_timeout_seconds,
            "http_timeout_seconds",
        )

