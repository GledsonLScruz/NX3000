from nx3000.config import CameraConfig
from nx3000.protocol.requests import (
    build_browse_request,
    build_browse_soap_payload,
    build_handshake_request,
)


def test_build_handshake_request_contains_expected_headers() -> None:
    config = CameraConfig(host_mac="02:00:00:00:00:00")

    request_text = build_handshake_request(config).decode("ascii")

    assert request_text.startswith("HEAD /mode/control HTTP/1.0\r\n")
    assert "HOST: http://192.168.107.1:7788\r\n" in request_text
    assert "User-Agent: SEC_MODE_02:00:00:00:00:00\r\n" in request_text
    assert "HOST-Mac: 02:00:00:00:00:00\r\n" in request_text
    assert request_text.endswith("\r\n\r\n")


def test_build_browse_payload_contains_requested_values() -> None:
    payload = build_browse_soap_payload(
        object_id="8",
        starting_index=10,
        requested_count=25,
        sort_criteria="+dc:title",
    )

    assert "<ObjectID>8</ObjectID>" in payload
    assert "<StartingIndex>10</StartingIndex>" in payload
    assert "<RequestedCount>25</RequestedCount>" in payload
    assert "<SortCriteria>+dc:title</SortCriteria>" in payload


def test_build_browse_request_uses_byte_content_length() -> None:
    config = CameraConfig(host_mac="02:00:00:00:00:00")
    payload = build_browse_soap_payload(starting_index=0, requested_count=1) + " caf\u00e9"

    request_bytes = build_browse_request(
        config,
        starting_index=0,
        requested_count=1,
        payload=payload,
    )
    request_text = request_bytes.decode("utf-8")

    assert f"Content-Length: {len(payload.encode('utf-8'))}\r\n" in request_text
    assert request_text.endswith(payload)
