"""XML extraction and unescaping helpers."""

from __future__ import annotations

import html

from ..exceptions import ParseError


def extract_xml_payload(raw_response: str) -> str:
    """Extract the XML payload from an HTTP-like response string."""

    marker = raw_response.find("<?xml")
    if marker < 0:
        raise ParseError("Response does not contain an XML payload")
    return raw_response[marker:]


def unescape_embedded_xml(xml_text: str) -> str:
    """Unescape XML fragments embedded as escaped text."""

    return html.unescape(xml_text)

