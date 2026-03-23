from datetime import datetime

from nx3000.models import PictureItem


def test_suggest_filename_sanitizes_title() -> None:
    item = PictureItem(
        title='IMG:/?"<>|0001',
        date=datetime.fromisoformat("2024-01-02T03:04:05"),
        full_content_uri="http://example.invalid/file.jpg",
        thumbnail_uri=None,
        screen_image_uri=None,
        extension="jpeg",
        protocol_info="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG",
    )

    assert item.suggest_filename() == "IMG_0001.jpg"


def test_to_dict_includes_picture_fields() -> None:
    item = PictureItem(
        title="IMG_0001",
        date=datetime.fromisoformat("2024-01-02T03:04:05"),
        full_content_uri="http://example.invalid/file.jpg",
        thumbnail_uri="http://example.invalid/thumb.jpg",
        screen_image_uri="http://example.invalid/screen.jpg",
        extension="jpg",
        protocol_info="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG",
    )

    data = item.to_dict()

    assert data["media_type"] == "image"
    assert data["screen_image_uri"] == "http://example.invalid/screen.jpg"

