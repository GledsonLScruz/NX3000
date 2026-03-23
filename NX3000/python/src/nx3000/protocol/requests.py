"""HTTP-like request builders for the NX3000 protocol."""

from __future__ import annotations

from ..config import CameraConfig
from .constants import (
    BROWSE_PATH,
    BROWSE_SOAP_ACTION,
    CONTROL_PATH,
    DEFAULT_BROWSE_FLAG,
    DEFAULT_FILTER,
    DEFAULT_OBJECT_ID,
)


def _join_http_lines(lines: list[str], body: bytes = b"") -> bytes:
    head = "\r\n".join(lines) + "\r\n\r\n"
    return head.encode("ascii") + body


def build_handshake_request(config: CameraConfig) -> bytes:
    """Build the control handshake request."""

    return _join_http_lines(
        [
            f"HEAD {CONTROL_PATH} HTTP/1.0",
            f"HOST: http://{config.camera_ip}:{config.control_port}",
            f"User-Agent: SEC_MODE_{config.host_mac}",
            "Access-Method: manual",
            "NTS: alive",
            "Content-Length: 0",
            f"HOST-Mac: {config.host_mac}",
            f"HOST-Address: {config.host_address}",
            f"HOST-port: {config.host_port}",
            f"HOST-PNumber: {config.host_pnumber}",
        ]
    )


def build_browse_soap_payload(
    *,
    object_id: str = DEFAULT_OBJECT_ID,
    starting_index: int,
    requested_count: int,
    browse_flag: str = DEFAULT_BROWSE_FLAG,
    filter_value: str = DEFAULT_FILTER,
    sort_criteria: str = "",
) -> str:
    """Build the SOAP payload for a ContentDirectory Browse request."""

    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\n'
        "<s:Body>\n"
        '<u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">\n'
        f"<ObjectID>{object_id}</ObjectID>\n"
        f"<BrowseFlag>{browse_flag}</BrowseFlag>\n"
        f"<Filter>{filter_value}</Filter>\n"
        f"<StartingIndex>{starting_index}</StartingIndex>\n"
        f"<RequestedCount>{requested_count}</RequestedCount>\n"
        f"<SortCriteria>{sort_criteria}</SortCriteria>\n"
        "</u:Browse>\n"
        "</s:Body>\n"
        "</s:Envelope>"
    )


def build_browse_request(
    config: CameraConfig,
    *,
    object_id: str = DEFAULT_OBJECT_ID,
    starting_index: int,
    requested_count: int,
    browse_flag: str = DEFAULT_BROWSE_FLAG,
    filter_value: str = DEFAULT_FILTER,
    sort_criteria: str = "",
    payload: str | None = None,
) -> bytes:
    """Build the browse request with a correctly encoded Content-Length."""

    soap_payload = payload or build_browse_soap_payload(
        object_id=object_id,
        starting_index=starting_index,
        requested_count=requested_count,
        browse_flag=browse_flag,
        filter_value=filter_value,
        sort_criteria=sort_criteria,
    )
    payload_bytes = soap_payload.encode("utf-8")
    return _join_http_lines(
        [
            f"POST {BROWSE_PATH} HTTP/1.0",
            'Content-Type: text/xml; charset="utf-8"',
            f"HOST: {config.camera_ip}",
            f"Content-Length: {len(payload_bytes)}",
            f"SOAPACTION: {BROWSE_SOAP_ACTION}",
            "Connection: close",
        ],
        body=payload_bytes,
    )

