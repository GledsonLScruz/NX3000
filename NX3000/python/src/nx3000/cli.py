"""Command-line interface for the NX3000 package."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .client import NX3000Client
from .config import CameraConfig
from .exceptions import NX3000Error
from .interactive import InteractiveMenu, InteractiveState
from .logging_utils import configure_logging


def _add_config_arguments(parser: argparse.ArgumentParser, *, require_mac: bool = True) -> None:
    parser.add_argument("--camera-ip", default="192.168.107.1")
    parser.add_argument("--control-port", type=int, default=7788)
    parser.add_argument("--browse-port", type=int, default=7676)
    parser.add_argument("--mac", required=require_mac)
    parser.add_argument("--host-address", default="192.168.107.11")
    parser.add_argument("--host-port", type=int, default=7788)
    parser.add_argument("--host-pnumber", default="none")
    parser.add_argument("--socket-timeout", type=float, default=5.0)
    parser.add_argument("--http-timeout", type=float, default=30.0)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--debug-raw", action="store_true")


def _build_config(args: argparse.Namespace) -> CameraConfig:
    return CameraConfig(
        host_mac=args.mac,
        camera_ip=args.camera_ip,
        control_port=args.control_port,
        browse_port=args.browse_port,
        host_address=args.host_address,
        host_port=args.host_port,
        host_pnumber=args.host_pnumber,
        socket_timeout_seconds=args.socket_timeout,
        http_timeout_seconds=args.http_timeout,
    )


def _build_client(args: argparse.Namespace) -> NX3000Client:
    logger = configure_logging(args.verbose or args.debug_raw)
    config = _build_config(args)
    return NX3000Client(config, debug=args.debug_raw, logger=logger)


def _build_interactive_state(args: argparse.Namespace) -> InteractiveState:
    return InteractiveState(
        camera_ip=args.camera_ip,
        control_port=args.control_port,
        browse_port=args.browse_port,
        host_mac=args.mac,
        host_address=args.host_address,
        host_port=args.host_port,
        host_pnumber=args.host_pnumber,
        socket_timeout_seconds=args.socket_timeout,
        http_timeout_seconds=args.http_timeout,
        debug_raw=args.debug_raw,
    )


def _print_browse_items(items: list, as_json: bool) -> None:
    if as_json:
        print(json.dumps([item.to_dict() for item in items], indent=2))
        return

    for index, item in enumerate(items):
        print(
            f"[{index}] {item.media_type():5s} "
            f"{item.title} "
            f"{item.date.isoformat()} "
            f".{item.extension}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nx3000")
    subparsers = parser.add_subparsers(dest="command", required=True)

    connect_parser = subparsers.add_parser("connect")
    _add_config_arguments(connect_parser)

    browse_parser = subparsers.add_parser("browse")
    _add_config_arguments(browse_parser)
    browse_parser.add_argument("--start", type=int, default=0)
    browse_parser.add_argument("--count", type=int, default=100)
    browse_parser.add_argument("--object-id", default="8")
    browse_parser.add_argument("--json", action="store_true")
    browse_parser.add_argument("--connect-first", action=argparse.BooleanOptionalAction, default=True)

    download_parser = subparsers.add_parser("download")
    _add_config_arguments(download_parser)
    download_parser.add_argument("--start", type=int, default=0)
    download_parser.add_argument("--count", type=int, default=100)
    download_parser.add_argument("--object-id", default="8")
    download_parser.add_argument("--index", type=int, required=True)
    download_parser.add_argument("--dest", required=True)
    download_parser.add_argument("--overwrite", action="store_true")
    download_parser.add_argument("--connect-first", action=argparse.BooleanOptionalAction, default=True)

    download_all_parser = subparsers.add_parser("download-all")
    _add_config_arguments(download_all_parser)
    download_all_parser.add_argument("--start", type=int, default=0)
    download_all_parser.add_argument("--count", type=int, default=100)
    download_all_parser.add_argument("--object-id", default="8")
    download_all_parser.add_argument("--dest", required=True)
    download_all_parser.add_argument("--overwrite", action="store_true")
    download_all_parser.add_argument("--connect-first", action=argparse.BooleanOptionalAction, default=True)

    interactive_parser = subparsers.add_parser("interactive")
    _add_config_arguments(interactive_parser, require_mac=False)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        client = _build_client(args)

        if args.command == "connect":
            client.handshake()
            print("Handshake completed")
            return 0

        if args.command == "browse":
            items = client.browse(
                start=args.start,
                count=args.count,
                object_id=args.object_id,
                connect_first=args.connect_first,
            )
            _print_browse_items(items, args.json)
            return 0

        if args.command == "download":
            items = client.browse(
                start=args.start,
                count=args.count,
                object_id=args.object_id,
                connect_first=args.connect_first,
            )
            if not 0 <= args.index < len(items):
                raise NX3000Error(
                    f"Requested index {args.index} is out of range for {len(items)} items"
                )
            saved_path = client.download_item(
                items[args.index],
                Path(args.dest).expanduser(),
                overwrite=args.overwrite,
            )
            print(saved_path)
            return 0

        if args.command == "download-all":
            items = client.browse(
                start=args.start,
                count=args.count,
                object_id=args.object_id,
                connect_first=args.connect_first,
            )
            saved_paths = client.download_all(
                items,
                Path(args.dest).expanduser(),
                overwrite=args.overwrite,
            )
            for path in saved_paths:
                print(path)
            return 0

        if args.command == "interactive":
            logger = configure_logging(args.verbose or args.debug_raw)
            menu = InteractiveMenu(_build_interactive_state(args), logger)
            return menu.run()
    except NX3000Error as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    raise AssertionError(f"Unhandled command: {args.command!r}")


def entrypoint() -> None:
    """Console script wrapper."""

    raise SystemExit(main())
