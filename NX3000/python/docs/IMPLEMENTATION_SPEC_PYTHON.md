# Implementation Spec: Samsung NX3000 Python Rewrite

## 1. Purpose

This document defines the technical implementation plan for a Python rewrite of the current C# Samsung NX3000 file-access project.

It is intended to be concrete enough that Codex can implement the project directly with minimal ambiguity.

## 2. Core Design Principles

- Preserve observed protocol behavior from the C# version.
- Separate public API from transport/protocol internals.
- Prefer straightforward synchronous behavior for v1.
- Design internals so async support can be added later without major rewrites.
- Keep parsing deterministic and heavily tested.
- Make raw network behavior inspectable.

## 3. Proposed Package Name

Use package name:

- `nx3000`

Suggested repository structure:

```text
nx3000-python/
  pyproject.toml
  README.md
  src/
    nx3000/
      __init__.py
      client.py
      config.py
      exceptions.py
      models.py
      downloader.py
      logging_utils.py
      cli.py
      protocol/
        __init__.py
        transport.py
        requests.py
        parsing.py
        constants.py
      utils/
        __init__.py
        filenames.py
        xml_utils.py
  tests/
    test_requests.py
    test_parsing.py
    test_models.py
    test_downloader.py
    test_cli.py
    fixtures/
      browse_response_http.txt
      browse_payload.xml
      browse_item_image.xml
      browse_item_video.xml
```

## 4. Suggested Technology Choices

### Runtime

- Python `3.11+`

### Packaging

- `pyproject.toml`
- build backend: `hatchling` or `setuptools`

### CLI

- `typer` preferred for ergonomics
- `argparse` acceptable if zero dependencies are preferred

Recommendation: use `typer`.

### HTTP Downloads

- `httpx` preferred

### Testing

- `pytest`

### Optional Dev Tools

- `ruff`
- `mypy`

## 5. Architecture Overview

The codebase should be organized into five main layers:

1. Configuration layer
2. Protocol request/transport layer
3. XML parsing layer
4. Domain model and download layer
5. CLI and top-level client layer

### Data Flow

1. User creates `CameraConfig`
2. User creates `NX3000Client`
3. Client sends handshake over raw TCP socket
4. Client sends browse SOAP request over raw TCP socket
5. Raw HTTP-like response is captured as text
6. XML payload is extracted and unescaped
7. XML is parsed into `PictureItem` and `VideoItem`
8. User or CLI downloads selected items via returned HTTP URIs

## 6. Module-by-Module Specification

## 6.1 `config.py`

Define dataclasses for configuration.

### `CameraConfig`

Fields:

- `camera_ip: str = "192.168.107.1"`
- `control_port: int = 7788`
- `browse_port: int = 7676`
- `host_mac: str`
- `host_address: str = "192.168.107.11"`
- `host_port: int = 7788`
- `host_pnumber: str = "none"`
- `socket_timeout_seconds: float = 5.0`
- `http_timeout_seconds: float = 30.0`

Validation:

- `camera_ip` must parse as IPv4
- ports must be between 1 and 65535
- `host_mac` must accept common MAC formats
- timeout values must be positive

Optional extension:

- support auto-detecting local IP/MAC in helper functions, but do not make that mandatory for v1

## 6.2 `exceptions.py`

Create explicit exception classes:

- `NX3000Error`
- `ConfigurationError`
- `TransportError`
- `HandshakeError`
- `BrowseError`
- `ParseError`
- `DownloadError`
- `UnsupportedMediaTypeError`

All public-facing failures should raise one of these, not raw low-level exceptions unless wrapped.

## 6.3 `models.py`

Use dataclasses.

### `MediaItem`

Fields:

- `title: str`
- `date: datetime`
- `full_content_uri: str`
- `thumbnail_uri: str | None`
- `extension: str`
- `protocol_info: str`
- `raw_xml: str | None = None`

Methods:

- `media_type() -> str`
- `suggest_filename() -> str`
- `download(dest: PathLike, overwrite: bool = False) -> Path`
- `to_dict() -> dict`
- `__str__()`

### `PictureItem(MediaItem)`

Additional fields:

- `screen_image_uri: str | None`

`media_type()` returns `"image"`

### `VideoItem(MediaItem)`

No extra mandatory fields for v1

`media_type()` returns `"video"`

### Filename Logic

- sanitize title
- preserve extension
- if title is empty, generate fallback like `untitled_<timestamp>.<ext>`
- if file exists and `overwrite=False`, append counter suffix

## 6.4 `utils/filenames.py`

Functions:

- `sanitize_filename(name: str) -> str`
- `ensure_unique_path(path: Path) -> Path`
- `normalize_extension(ext: str) -> str`

macOS considerations:

- strip `/`
- strip null bytes
- trim trailing spaces
- optionally normalize Unicode

## 6.5 `protocol/constants.py`

Define defaults and protocol strings:

- default camera IP
- control port
- browse port
- request path constants
- SOAP action string
- object ID default
- browse flag default

This keeps string literals out of business logic.

## 6.6 `protocol/requests.py`

This module builds request strings only. No network I/O.

### `build_handshake_request(config: CameraConfig) -> bytes`

Must produce the equivalent of:

```http
HEAD /mode/control HTTP/1.0
HOST: http://192.168.107.1:7788
User-Agent: SEC_MODE_<MAC>
Access-Method: manual
NTS: alive
Content-Length: 0
HOST-Mac: <value>
HOST-Address: <value>
HOST-port: <value>
HOST-PNumber: <value>

```

Implementation notes:

- use CRLF line endings
- return encoded ASCII bytes
- parameterize camera host in `HOST`
- do not hardcode `MY_MAC`; fix the bug from current C#

### `build_browse_soap_payload(...) -> str`

Inputs:

- `object_id: str = "8"`
- `starting_index: int`
- `requested_count: int`
- `browse_flag: str = "BrowseDirectChildren"`
- `filter_value: str = "*"`
- `sort_criteria: str = ""`

Must render the SOAP envelope used by the C# project.

### `build_browse_request(config: CameraConfig, ..., payload: str | None = None) -> bytes`

Build:

- `POST /smp_4_ HTTP/1.0`
- `Content-Type: text/xml; charset="utf-8"`
- `HOST: <camera_ip>`
- `Content-Length: <payload_byte_length>`
- `SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#Browse"`
- `Connection: close`

Then append the SOAP payload.

Important:

- content length must be byte length, not Python string length when encoded

## 6.7 `protocol/transport.py`

This module handles raw TCP I/O.

### `send_tcp_request(host: str, port: int, request_bytes: bytes, timeout: float, debug: bool = False) -> str`

Behavior:

- open TCP socket
- set timeout
- connect
- send all bytes
- read until EOF
- decode as ASCII with fallback error strategy
- return raw response text

Requirements:

- ensure socket closes in all cases
- wrap failures in `TransportError`
- optionally log request and response

Do not mix request-building and transport concerns.

## 6.8 `utils/xml_utils.py`

Functions:

- `extract_xml_payload(raw_response: str) -> str`
- `unescape_embedded_xml(xml_text: str) -> str`

Behavior:

- find first `<?xml`
- slice from there to end
- unescape `&lt;` and `&gt;`
- optionally unescape `&amp;` carefully if needed

Implementation note:

The current C# code attempts unescaping, then overwrites the result. The Python rewrite must fix this cleanly.

## 6.9 `protocol/parsing.py`

This module parses browse responses into model objects.

### `parse_browse_response(raw_response: str) -> list[MediaItem]`

Flow:

1. extract XML payload
2. unescape if needed
3. parse root XML
4. find all descendants with local-name `item`
5. parse each item

### `parse_item_element(item_element) -> MediaItem`

Required extraction:

- title from descendant `title`
- date from descendant `date`
- resources from descendant `res`

### Resource Parsing

The first `res` element's `protocolInfo` drives:

- media type
- extension

Expected pattern resembles:

- `http-get:*:image/jpeg:DLNA.ORG_...`
- `http-get:*:video/mp4:DLNA.ORG_...`

Parse rules:

- media type is token before `/`
- extension/format is token after `/` before next `:`

Do not use brittle substring arithmetic if a split-based parser is clearer and safer.

### URI Mapping

Current observed C# assumptions:

- image:
  - `links[0]` = full content
  - `links[1]` = thumbnail
  - `links[2]` = screen image
- video:
  - `links[0]` = full content
  - `links[1]` = thumbnail

Spec for Python:

- preserve this order as default behavior
- guard against missing links
- set missing optional values to `None`
- if resource ordering differs, retain raw resource list internally if helpful

### Date Parsing

Implement robust date parsing:

- prefer `datetime.fromisoformat` if compatible
- add fallback parser logic for expected Samsung date strings
- if parsing fails, raise `ParseError` with item context

### XML Namespace Handling

Ignore namespace prefixes and match by local name only.

### Raw XML Preservation

Store the item's raw XML string on the model for debugging.

## 6.10 `downloader.py`

Provide a reusable download function:

### `download_file(url: str, destination: Path, overwrite: bool = False, timeout: float = 30.0) -> Path`

Behavior:

- expand `~`
- create parent directory
- if destination is a directory, derive filename
- stream download in chunks
- verify HTTP success
- write atomically if practical
- return final path

Errors:

- wrap network and file errors in `DownloadError`

### Model Integration

`MediaItem.download(...)` should call this helper.

## 6.11 `client.py`

Expose the main high-level client.

### `NX3000Client`

Constructor:

- `NX3000Client(config: CameraConfig, *, debug: bool = False, logger: Logger | None = None)`

Methods:

### `handshake() -> str`

- build handshake request
- send via transport
- return raw response
- optionally validate that response is not empty

### `browse(start: int = 0, count: int = 100, object_id: str = "8") -> list[MediaItem]`

- build browse request
- send via transport
- parse response
- return items

### `connect_and_browse(...) -> list[MediaItem]`

- convenience method:
  - handshake
  - browse

### `download_item(item: MediaItem, dest: str | Path, overwrite: bool = False) -> Path`

### `download_all(items: list[MediaItem], dest: str | Path, overwrite: bool = False) -> list[Path]`

Optional behavior:

- continue-on-error flag for batch downloads in future versions

## 6.12 `cli.py`

CLI should expose these commands:

### `connect`

Inputs:

- config options
- `--verbose`
- `--debug-raw`

Behavior:

- instantiate client
- perform handshake
- print success/failure

### `browse`

Inputs:

- config options
- `--start`
- `--count`
- `--json`
- `--connect-first/--no-connect-first`

Behavior:

- optionally handshake first
- browse contents
- print table or JSON

### `download`

Inputs:

- all browse inputs
- `--index`
- `--dest`
- `--overwrite`

Behavior:

- browse
- select item by index
- download selected item

### `download-all`

Inputs:

- browse inputs
- `--dest`
- `--overwrite`

Behavior:

- browse
- download each item sequentially
- show progress

### Shared CLI Options

- `--camera-ip`
- `--control-port`
- `--browse-port`
- `--mac`
- `--host-address`
- `--host-port`
- `--timeout`
- `--verbose`

## 7. Logging Specification

Use standard library `logging`.

### Loggers

- `nx3000`
- `nx3000.protocol`
- `nx3000.download`

### Debug Modes

Normal:

- concise operational messages

Verbose:

- request targets
- item counts
- download destinations

Raw debug:

- full raw request text
- full raw response text

Be careful not to log binary media data.

## 8. Testing Specification

## 8.1 Unit Tests

### `test_requests.py`

Test:

- handshake request contains expected headers
- handshake request uses CRLF
- browse request content length equals encoded byte length
- browse request payload contains expected SOAP values

### `test_parsing.py`

Test:

- raw HTTP response XML extraction
- unescaping of embedded XML entities
- parsing one image item
- parsing one video item
- missing optional URIs handled correctly
- malformed `protocolInfo` raises `ParseError`

### `test_models.py`

Test:

- filename sanitization
- unique filename generation
- `to_dict()` output shape

### `test_downloader.py`

Test:

- successful streamed download to temp directory
- non-200 response raises `DownloadError`
- overwrite behavior

### `test_cli.py`

Test:

- browse JSON mode
- download command with mocked client
- connect command success/failure

## 8.2 Fixtures

Create stable text fixtures for:

- realistic raw browse HTTP response
- escaped XML inner payload
- image item XML fragment
- video item XML fragment

Fixtures should be derived from observed response shape, but sanitized if needed.

## 8.3 Hardware Integration Testing

Mark hardware tests separately:

- `@pytest.mark.integration`
- do not run by default

Integration tests can use environment variables:

- `NX3000_CAMERA_IP`
- `NX3000_HOST_MAC`
- `NX3000_HOST_ADDRESS`

## 9. README Specification

The README must include:

1. What the package does
2. Samsung NX3000 compatibility note
3. macOS setup instructions
4. virtualenv setup
5. install command
6. CLI examples
7. library usage example
8. troubleshooting section
9. note that protocol is reverse-engineered

## 10. Recommended Public API

`src/nx3000/__init__.py` should export:

```python
from .client import NX3000Client
from .config import CameraConfig
from .exceptions import (
    NX3000Error,
    ConfigurationError,
    TransportError,
    HandshakeError,
    BrowseError,
    ParseError,
    DownloadError,
    UnsupportedMediaTypeError,
)
from .models import MediaItem, PictureItem, VideoItem
```

## 11. Example Library Usage

```python
from pathlib import Path

from nx3000 import CameraConfig, NX3000Client

config = CameraConfig(
    camera_ip="192.168.107.1",
    host_mac="02:00:00:00:00:00",
    host_address="192.168.107.11",
)

client = NX3000Client(config, debug=True)
client.handshake()
items = client.browse(start=0, count=100)

for idx, item in enumerate(items):
    print(idx, item.media_type(), item.title, item.date)

if items:
    saved = items[0].download(Path("~/Pictures/NX3000").expanduser())
    print(saved)
```

## 12. Implementation Order

Implement in this order:

1. Create project scaffold and packaging
2. Add exceptions and config
3. Add protocol request builders
4. Add raw TCP transport
5. Add XML extraction utilities
6. Add browse parser
7. Add models
8. Add downloader
9. Add high-level client
10. Add CLI
11. Add tests
12. Add README

This order minimizes ambiguity and keeps the parser testable before hardware access.

## 13. Explicit Differences from Current C# Code

The Python rewrite should intentionally improve these issues in the current C# implementation:

1. Do not hardcode camera host headers when values should come from config.
2. Do not leave `HOST-Mac: MY_MAC`; use the real configured MAC.
3. Do not overwrite the unescaped response with the original raw response.
4. Do not parse protocol info using fragile substring indexing when split-based parsing is clearer.
5. Do not assume links always exist without validation.
6. Do not silently swallow exceptions by printing to console only.
7. Do not build filenames directly from untrusted titles without sanitization.

## 14. Suggested Backlog After v1

- async API
- retry support
- progress bars for downloads
- richer media metadata extraction
- auto-detection helpers for current Mac IP/MAC
- batch filtering by type or date
- export browse results to CSV/JSON

## 15. Codex Build Prompt Template

Use the following as a direct implementation brief for Codex:

```text
Build a Python 3.11+ package named nx3000 that rewrites the behavior of this repository's C# library for Samsung NX3000 cameras. Follow docs/PRD_PYTHON_REWRITE.md and docs/IMPLEMENTATION_SPEC_PYTHON.md exactly.

Requirements:
- package under src/nx3000
- typed dataclasses for config and media models
- raw TCP request builders for handshake and browse
- SOAP browse parsing into PictureItem and VideoItem
- httpx-based downloads
- Typer CLI with connect, browse, download, download-all
- pytest test suite with fixtures
- robust exceptions and logging
- README for macOS setup and usage

Use apply_patch for edits, preserve existing repo contents, and implement incrementally with tests.
```

