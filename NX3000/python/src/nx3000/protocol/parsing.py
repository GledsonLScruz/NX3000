"""Browse response parsing for the NX3000 protocol."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import xml.etree.ElementTree as ET

from ..exceptions import ParseError, UnsupportedMediaTypeError
from ..models import MediaItem, PictureItem, VideoItem
from ..utils.filenames import normalize_extension
from ..utils.xml_utils import extract_xml_payload, unescape_embedded_xml


@dataclass(slots=True)
class Resource:
    """Parsed media resource entry from a DIDL item."""

    url: str
    protocol_info: str


def _local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    if ":" in tag:
        return tag.rsplit(":", 1)[1]
    return tag


def _first_descendant_text(element: ET.Element, target: str) -> str:
    for node in element.iter():
        if _local_name(node.tag) == target and node.text:
            return node.text.strip()
    raise ParseError(f"Missing required field {target!r} in media item")


def _resource_elements(item_element: ET.Element) -> list[Resource]:
    resources: list[Resource] = []
    for node in item_element.iter():
        if _local_name(node.tag) != "res":
            continue
        url = (node.text or "").strip()
        protocol_info = node.attrib.get("protocolInfo", "").strip()
        if not url or not protocol_info:
            continue
        resources.append(Resource(url=url, protocol_info=protocol_info))
    if not resources:
        raise ParseError("Media item does not contain any resource entries")
    return resources


def _parse_protocol_info(protocol_info: str) -> tuple[str, str]:
    parts = protocol_info.split(":", 3)
    if len(parts) < 4:
        raise ParseError(f"Malformed protocolInfo: {protocol_info!r}")
    mime_type = parts[2]
    if "/" not in mime_type:
        raise ParseError(f"Malformed MIME type in protocolInfo: {protocol_info!r}")
    media_type, extension = mime_type.split("/", 1)
    return media_type, normalize_extension(extension)


def _parse_date(raw_value: str) -> datetime:
    candidate = raw_value.strip()
    candidate = candidate.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(candidate)
    except ValueError as exc:
        raise ParseError(f"Unsupported date format: {raw_value!r}") from exc


def _raw_xml_for_element(element: ET.Element) -> str:
    return ET.tostring(element, encoding="unicode")


def parse_item_element(item_element: ET.Element) -> MediaItem:
    """Parse a single DIDL item element into a media model."""

    title = _first_descendant_text(item_element, "title")
    date = _parse_date(_first_descendant_text(item_element, "date"))
    resources = _resource_elements(item_element)
    media_type, extension = _parse_protocol_info(resources[0].protocol_info)

    common_kwargs = {
        "title": title,
        "date": date,
        "full_content_uri": resources[0].url,
        "thumbnail_uri": resources[1].url if len(resources) > 1 else None,
        "extension": extension,
        "protocol_info": resources[0].protocol_info,
        "raw_xml": _raw_xml_for_element(item_element),
    }

    if media_type == "image":
        return PictureItem(
            screen_image_uri=resources[2].url if len(resources) > 2 else None,
            **common_kwargs,
        )
    if media_type == "video":
        return VideoItem(**common_kwargs)
    raise UnsupportedMediaTypeError(f"Unsupported media type: {media_type!r}")


def parse_browse_response(raw_response: str) -> list[MediaItem]:
    """Parse a browse response into media item objects."""

    xml_payload = extract_xml_payload(raw_response)
    unescaped = unescape_embedded_xml(xml_payload)
    try:
        root = ET.fromstring(unescaped)
    except ET.ParseError as exc:
        raise ParseError(f"Failed to parse browse XML: {exc}") from exc

    items: list[MediaItem] = []
    for node in root.iter():
        if _local_name(node.tag) == "item":
            items.append(parse_item_element(node))
    return items

