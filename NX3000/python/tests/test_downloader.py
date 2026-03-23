from io import BytesIO
from pathlib import Path
from urllib.error import URLError

import pytest

from nx3000.downloader import download_file
from nx3000.exceptions import DownloadError


class DummyResponse(BytesIO):
    def __init__(self, payload: bytes, status: int = 200) -> None:
        super().__init__(payload)
        self.status = status

    def __enter__(self) -> "DummyResponse":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()


def test_download_file_writes_stream_to_disk(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(
        "nx3000.downloader.request.urlopen",
        lambda url, timeout=30.0: DummyResponse(b"hello world"),
    )

    output_path = download_file("http://camera.local/file.jpg", tmp_path / "file.jpg")

    assert output_path.read_bytes() == b"hello world"


def test_download_file_raises_for_http_error(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(
        "nx3000.downloader.request.urlopen",
        lambda url, timeout=30.0: DummyResponse(b"", status=500),
    )

    with pytest.raises(DownloadError):
        download_file("http://camera.local/file.jpg", tmp_path / "file.jpg")


def test_download_file_raises_for_url_error(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    def raise_url_error(url: str, timeout: float = 30.0) -> DummyResponse:
        raise URLError("no route")

    monkeypatch.setattr("nx3000.downloader.request.urlopen", raise_url_error)

    with pytest.raises(DownloadError):
        download_file("http://camera.local/file.jpg", tmp_path / "file.jpg")

