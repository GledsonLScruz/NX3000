"""Filename normalization helpers."""

from __future__ import annotations

from pathlib import Path
import re
import unicodedata


_INVALID_FILENAME_CHARS_RE = re.compile(r'[\x00-\x1f/\\:*?"<>|]+')


def sanitize_filename(name: str) -> str:
    """Return a filesystem-safe filename stem."""

    normalized = unicodedata.normalize("NFKC", name).strip()
    sanitized = _INVALID_FILENAME_CHARS_RE.sub("_", normalized)
    sanitized = sanitized.rstrip(" .")
    return sanitized or "untitled"


def normalize_extension(ext: str) -> str:
    """Normalize a media format token into a clean file extension."""

    value = ext.strip().lower().lstrip(".")
    if value == "jpeg":
        return "jpg"
    return value or "bin"


def ensure_unique_path(path: Path) -> Path:
    """Return a unique path by appending a numeric suffix if needed."""

    if not path.exists():
        return path

    stem = path.stem
    suffix = path.suffix
    counter = 1
    while True:
        candidate = path.with_name(f"{stem}_{counter}{suffix}")
        if not candidate.exists():
            return candidate
        counter += 1

