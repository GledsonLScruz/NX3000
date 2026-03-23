from pathlib import Path
import xml.etree.ElementTree as ET

import pytest

from nx3000.exceptions import ParseError
from nx3000.models import PictureItem, VideoItem
from nx3000.protocol.parsing import parse_browse_response, parse_item_element
from nx3000.utils.xml_utils import extract_xml_payload, unescape_embedded_xml


FIXTURES = Path(__file__).parent / "fixtures"


def _read_fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_extract_xml_payload_from_http_response() -> None:
    raw_response = _read_fixture("browse_response_http.txt")

    xml_payload = extract_xml_payload(raw_response)

    assert xml_payload.startswith("<?xml")


def test_unescape_embedded_xml_expands_item_markup() -> None:
    xml_payload = _read_fixture("browse_payload.xml")

    unescaped = unescape_embedded_xml(xml_payload)

    assert "<DIDL-Lite" in unescaped
    assert "<item" in unescaped


def test_parse_item_element_for_image() -> None:
    element = ET.fromstring(_read_fixture("browse_item_image.xml"))

    item = parse_item_element(element)

    assert isinstance(item, PictureItem)
    assert item.title == "IMG_0001"
    assert item.extension == "jpg"
    assert item.screen_image_uri and item.screen_image_uri.endswith("SC_IMG_0001.JPG")


def test_parse_item_element_for_video() -> None:
    element = ET.fromstring(_read_fixture("browse_item_video.xml"))

    item = parse_item_element(element)

    assert isinstance(item, VideoItem)
    assert item.title == "VID_0002"
    assert item.extension == "mp4"
    assert item.thumbnail_uri and item.thumbnail_uri.endswith("TN_VID_0002.JPG")


def test_parse_browse_response_returns_all_items() -> None:
    raw_response = _read_fixture("browse_response_http.txt")

    items = parse_browse_response(raw_response)

    assert len(items) == 2
    assert isinstance(items[0], PictureItem)
    assert isinstance(items[1], VideoItem)


def test_parse_item_rejects_bad_protocol_info() -> None:
    element = ET.fromstring(
        """
        <item xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Bad</dc:title>
          <dc:date>2024-01-02T03:04:05</dc:date>
          <res protocolInfo="bad">http://example.invalid/file</res>
        </item>
        """
    )

    with pytest.raises(ParseError):
        parse_item_element(element)

