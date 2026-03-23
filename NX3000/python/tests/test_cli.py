from datetime import datetime
from pathlib import Path
import json

from nx3000.cli import main
from nx3000.models import PictureItem


class FakeClient:
    def __init__(self, config, *, debug=False, logger=None) -> None:
        self.config = config
        self.debug = debug
        self.logger = logger

    def handshake(self) -> str:
        return "ok"

    def browse(self, *, start=0, count=100, object_id="8", connect_first=False):
        return [
            PictureItem(
                title="IMG_0001",
                date=datetime.fromisoformat("2024-01-02T03:04:05"),
                full_content_uri="http://camera.local/file.jpg",
                thumbnail_uri="http://camera.local/thumb.jpg",
                screen_image_uri="http://camera.local/screen.jpg",
                extension="jpg",
                protocol_info="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG",
            )
        ]

    def download_item(self, item, dest, *, overwrite=False):
        return Path(dest) / item.suggest_filename()

    def download_all(self, items, dest, *, overwrite=False):
        return [Path(dest) / item.suggest_filename() for item in items]


def test_cli_browse_json(monkeypatch, capsys) -> None:
    monkeypatch.setattr("nx3000.cli.NX3000Client", FakeClient)

    exit_code = main(["browse", "--mac", "02:00:00:00:00:00", "--json"])

    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert exit_code == 0
    assert payload[0]["title"] == "IMG_0001"


def test_cli_download(monkeypatch, capsys, tmp_path: Path) -> None:
    monkeypatch.setattr("nx3000.cli.NX3000Client", FakeClient)

    exit_code = main(
        [
            "download",
            "--mac",
            "02:00:00:00:00:00",
            "--index",
            "0",
            "--dest",
            str(tmp_path),
        ]
    )

    captured = capsys.readouterr()
    assert exit_code == 0
    assert "IMG_0001.jpg" in captured.out

