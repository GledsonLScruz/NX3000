"""Domain models for camera media items."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .utils.filenames import ensure_unique_path, normalize_extension, sanitize_filename


@dataclass(slots=True)
class MediaItem:
    """Base model for a media object returned by the camera."""

    title: str
    date: datetime
    full_content_uri: str
    thumbnail_uri: str | None
    extension: str
    protocol_info: str
    raw_xml: str | None = None

    def media_type(self) -> str:
        raise NotImplementedError

    def suggest_filename(self) -> str:
        stem = sanitize_filename(self.title)
        extension = normalize_extension(self.extension)
        return f"{stem}.{extension}"

    def download(self, dest: str | Path, overwrite: bool = False) -> Path:
        from .downloader import download_file

        target = Path(dest).expanduser()
        if target.exists() and target.is_dir():
            target = target / self.suggest_filename()
        elif not target.suffix:
            target = target / self.suggest_filename()

        if not overwrite:
            target = ensure_unique_path(target)

        return download_file(
            self.full_content_uri,
            target,
            overwrite=True,
        )

    def to_dict(self) -> dict[str, object]:
        return {
            "title": self.title,
            "date": self.date.isoformat(),
            "media_type": self.media_type(),
            "full_content_uri": self.full_content_uri,
            "thumbnail_uri": self.thumbnail_uri,
            "extension": normalize_extension(self.extension),
            "protocol_info": self.protocol_info,
        }

    def __str__(self) -> str:
        return f"{self.title} {self.date.isoformat()}"


@dataclass(slots=True)
class PictureItem(MediaItem):
    """Picture-specific media item."""

    screen_image_uri: str | None = None

    def media_type(self) -> str:
        return "image"

    def to_dict(self) -> dict[str, object]:
        data = super().to_dict()
        data["screen_image_uri"] = self.screen_image_uri
        return data


@dataclass(slots=True)
class VideoItem(MediaItem):
    """Video-specific media item."""

    def media_type(self) -> str:
        return "video"

