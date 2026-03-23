"""Logging helpers for the NX3000 package."""

from __future__ import annotations

import logging


def configure_logging(verbose: bool = False) -> logging.Logger:
    """Configure a package logger for CLI usage."""

    logger = logging.getLogger("nx3000")
    level = logging.DEBUG if verbose else logging.INFO
    logger.setLevel(level)

    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        logger.addHandler(handler)

    return logger

