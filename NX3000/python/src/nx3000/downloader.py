"""Media download helpers."""

from __future__ import annotations

from pathlib import Path
from tempfile import NamedTemporaryFile
import shutil
from urllib import error, request

from .exceptions import DownloadError
from .utils.filenames import ensure_unique_path


def download_file(
    url: str,
    destination: str | Path,
    *,
    overwrite: bool = False,
    timeout: float = 30.0,
) -> Path:
    """Download a file to the requested destination path."""

    target = Path(destination).expanduser()
    if target.exists() and target.is_dir():
        raise DownloadError("Destination path must include a filename")

    target.parent.mkdir(parents=True, exist_ok=True)
    final_path = target if overwrite else ensure_unique_path(target)

    try:
        with request.urlopen(url, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status and status >= 400:
                raise DownloadError(f"Download failed with HTTP status {status}")
            with NamedTemporaryFile(delete=False, dir=final_path.parent) as temp_file:
                shutil.copyfileobj(response, temp_file)
                temp_path = Path(temp_file.name)
    except DownloadError:
        raise
    except (OSError, error.URLError) as exc:
        raise DownloadError(f"Failed to download {url!r}: {exc}") from exc

    temp_path.replace(final_path)
    return final_path

