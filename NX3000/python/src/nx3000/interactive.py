"""Interactive numbered-menu terminal interface for the NX3000 client."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path

from .client import NX3000Client
from .config import CameraConfig
from .exceptions import NX3000Error
from .models import MediaItem


@dataclass(slots=True)
class InteractiveState:
    """Mutable interactive session state."""

    camera_ip: str = "192.168.107.1"
    control_port: int = 7788
    browse_port: int = 7676
    host_mac: str | None = None
    host_address: str = "192.168.107.11"
    host_port: int = 7788
    host_pnumber: str = "none"
    socket_timeout_seconds: float = 5.0
    http_timeout_seconds: float = 30.0
    debug_raw: bool = False
    cached_items: list[MediaItem] = field(default_factory=list)

    def build_config(self) -> CameraConfig:
        """Build a validated CameraConfig from the current state."""

        if not self.host_mac:
            raise NX3000Error("Host MAC is not set. Choose option 2 to edit settings first.")
        return CameraConfig(
            host_mac=self.host_mac,
            camera_ip=self.camera_ip,
            control_port=self.control_port,
            browse_port=self.browse_port,
            host_address=self.host_address,
            host_port=self.host_port,
            host_pnumber=self.host_pnumber,
            socket_timeout_seconds=self.socket_timeout_seconds,
            http_timeout_seconds=self.http_timeout_seconds,
        )


class InteractiveMenu:
    """Simple numbered-menu interface for the NX3000 client."""

    def __init__(self, state: InteractiveState, logger) -> None:
        self.state = state
        self.logger = logger

    def run(self) -> int:
        """Run the interactive loop until the user quits."""

        print("NX3000 interactive mode")
        print("Use the menu to configure the camera, browse files, and download media.")

        while True:
            print()
            print("1. Show current settings")
            print("2. Edit settings")
            print("3. Connect to camera")
            print("4. Browse media")
            print("5. Show last browse results")
            print("6. Show item details")
            print("7. Download one item")
            print("8. Download all cached items")
            print("9. Toggle raw debug")
            print("0. Quit")
            choice = input("Choose an option: ").strip()

            try:
                if choice == "1":
                    self.show_settings()
                elif choice == "2":
                    self.edit_settings()
                elif choice == "3":
                    self.connect()
                elif choice == "4":
                    self.browse()
                elif choice == "5":
                    self.show_cached_items()
                elif choice == "6":
                    self.show_item_details()
                elif choice == "7":
                    self.download_one()
                elif choice == "8":
                    self.download_all()
                elif choice == "9":
                    self.toggle_debug()
                elif choice == "0":
                    print("Exiting interactive mode.")
                    return 0
                else:
                    print("Invalid option.")
            except (EOFError, KeyboardInterrupt):
                print()
                print("Exiting interactive mode.")
                return 0
            except NX3000Error as exc:
                print(f"Error: {exc}")

    def _build_client(self) -> NX3000Client:
        return NX3000Client(
            self.state.build_config(),
            debug=self.state.debug_raw,
            logger=self.logger,
        )

    def _prompt(self, label: str, current: str) -> str:
        value = input(f"{label} [{current}]: ").strip()
        return value or current

    def _prompt_bool(self, label: str, default: bool) -> bool:
        suffix = "Y/n" if default else "y/N"
        value = input(f"{label} [{suffix}]: ").strip().lower()
        if not value:
            return default
        return value in {"y", "yes", "true", "1"}

    def _prompt_int(self, label: str, current: int) -> int:
        value = self._prompt(label, str(current))
        try:
            return int(value)
        except ValueError as exc:
            raise NX3000Error(f"{label} must be an integer") from exc

    def _prompt_float(self, label: str, current: float) -> float:
        value = self._prompt(label, str(current))
        try:
            return float(value)
        except ValueError as exc:
            raise NX3000Error(f"{label} must be a number") from exc

    def _require_cached_items(self) -> list[MediaItem]:
        if not self.state.cached_items:
            raise NX3000Error("No cached browse results. Choose option 4 first.")
        return self.state.cached_items

    def _prompt_index(self) -> int:
        items = self._require_cached_items()
        value = input(f"Item index [0-{len(items) - 1}]: ").strip()
        try:
            index = int(value)
        except ValueError as exc:
            raise NX3000Error("Item index must be an integer") from exc
        if not 0 <= index < len(items):
            raise NX3000Error(f"Item index {index} is out of range")
        return index

    def show_settings(self) -> None:
        """Print the current in-memory session settings."""

        settings = {
            "camera_ip": self.state.camera_ip,
            "control_port": self.state.control_port,
            "browse_port": self.state.browse_port,
            "host_mac": self.state.host_mac,
            "host_address": self.state.host_address,
            "host_port": self.state.host_port,
            "host_pnumber": self.state.host_pnumber,
            "socket_timeout_seconds": self.state.socket_timeout_seconds,
            "http_timeout_seconds": self.state.http_timeout_seconds,
            "debug_raw": self.state.debug_raw,
            "cached_items": len(self.state.cached_items),
        }
        print(json.dumps(settings, indent=2))

    def edit_settings(self) -> None:
        """Interactively edit connection settings."""

        self.state.camera_ip = self._prompt("Camera IP", self.state.camera_ip)
        self.state.control_port = self._prompt_int("Control port", self.state.control_port)
        self.state.browse_port = self._prompt_int("Browse port", self.state.browse_port)
        self.state.host_mac = self._prompt("Host MAC", self.state.host_mac or "")
        self.state.host_address = self._prompt("Host address", self.state.host_address)
        self.state.host_port = self._prompt_int("Host port", self.state.host_port)
        self.state.host_pnumber = self._prompt("Host PNumber", self.state.host_pnumber)
        self.state.socket_timeout_seconds = self._prompt_float(
            "Socket timeout seconds",
            self.state.socket_timeout_seconds,
        )
        self.state.http_timeout_seconds = self._prompt_float(
            "HTTP timeout seconds",
            self.state.http_timeout_seconds,
        )
        self.state.build_config()
        print("Settings updated.")

    def connect(self) -> None:
        """Perform the camera handshake."""

        self._build_client().handshake()
        print("Handshake completed.")

    def browse(self) -> None:
        """Browse media from the camera and cache the results."""

        start = self._prompt_int("Starting index", 0)
        count = self._prompt_int("Requested count", 100)
        object_id = self._prompt("Object ID", "8")
        connect_first = self._prompt_bool("Connect before browse", True)
        self.state.cached_items = self._build_client().browse(
            start=start,
            count=count,
            object_id=object_id,
            connect_first=connect_first,
        )
        print(f"Loaded {len(self.state.cached_items)} items.")

    def show_cached_items(self) -> None:
        """Print the current cached browse results."""

        items = self._require_cached_items()
        for index, item in enumerate(items):
            print(
                f"[{index}] {item.media_type():5s} "
                f"{item.title} "
                f"{item.date.isoformat()} "
                f".{item.extension}"
            )

    def show_item_details(self) -> None:
        """Print detailed JSON for a single cached item."""

        items = self._require_cached_items()
        index = self._prompt_index()
        item = items[index]
        print(json.dumps(item.to_dict(), indent=2))

    def download_one(self) -> None:
        """Download one cached item to a destination directory or file."""

        items = self._require_cached_items()
        index = self._prompt_index()
        destination = input("Destination path: ").strip()
        if not destination:
            raise NX3000Error("Destination path is required")
        overwrite = self._prompt_bool("Overwrite existing files", False)
        saved_path = self._build_client().download_item(
            items[index],
            Path(destination).expanduser(),
            overwrite=overwrite,
        )
        print(f"Saved to {saved_path}")

    def download_all(self) -> None:
        """Download all cached items to a destination directory."""

        items = self._require_cached_items()
        destination = input("Destination directory: ").strip()
        if not destination:
            raise NX3000Error("Destination directory is required")
        overwrite = self._prompt_bool("Overwrite existing files", False)
        saved_paths = self._build_client().download_all(
            items,
            Path(destination).expanduser(),
            overwrite=overwrite,
        )
        print(f"Downloaded {len(saved_paths)} items.")

    def toggle_debug(self) -> None:
        """Toggle raw request/response logging."""

        self.state.debug_raw = not self.state.debug_raw
        print(f"Raw debug is now {'enabled' if self.state.debug_raw else 'disabled'}.")

