# PRD: Samsung NX3000 File Access Python Rewrite

## 1. Document Purpose

This document defines the product requirements for rewriting the existing C# `NX3000_FileAccess` repository into a Python project that provides the same core behavior:

- connect to a Samsung NX3000 camera over its Wi-Fi / MobileLink interface
- browse the camera's media library
- represent pictures and videos as structured Python objects
- download media files to the local machine

The target development environment is macOS, but the resulting Python package should be cross-platform where practical.

This PRD is intentionally detailed so it can be used as direct input for implementation by Codex or another coding agent.

## 2. Background

The current repository is a small .NET 8 library that interacts directly with a Samsung NX3000 camera using:

- a control handshake over TCP to port `7788`
- a SOAP/UPnP browse request over TCP to port `7676`
- standard HTTP GET downloads for individual media resources

The current implementation is minimal and reverse-engineered. It uses raw sockets and constructs request payloads manually.

The Python rewrite should preserve this direct, low-level approach where needed, but improve:

- code organization
- testability
- configurability
- error handling
- logging
- macOS usability
- packaging and CLI ergonomics

## 3. Product Vision

Build a Python package and CLI tool that lets a macOS user connect to a Samsung NX3000 camera on its local Wi-Fi network, inspect available photos/videos, and download selected files reliably.

The rewrite should feel like a small but professional Python SDK:

- importable as a library
- usable from a terminal CLI
- easy to test with mocked responses
- explicit about network assumptions and failure modes

## 4. Goals

### Primary Goals

- Recreate the current C# functionality in Python.
- Support browsing camera contents.
- Support downloading images and videos.
- Expose a clean Python API for scripting.
- Expose a CLI for non-programmatic use.
- Run cleanly on macOS with Python 3.11+.

### Secondary Goals

- Make host IP, MAC address, ports, and timeouts configurable.
- Add strong parsing and validation around camera responses.
- Add unit tests for parsing and request generation.
- Add fixtures for recorded responses where possible.
- Make the implementation easy to extend for future features.

### Non-Goals

- Building a GUI in the first version.
- Reverse-engineering undocumented camera operations beyond connection, browse, and download.
- Photo editing, metadata editing, or camera remote control.
- iOS/Android apps.

## 5. Users

### Primary User

A technically capable macOS user who wants to access files from a Samsung NX3000 camera over Wi-Fi using Python.

### Secondary User

A developer who wants to automate importing media from the camera into a local workflow.

## 6. Current C# Behavior to Preserve

The Python rewrite must preserve these behaviors from the current repository:

1. Send a control/connection request to the camera.
2. Send a SOAP `Browse` request to retrieve media entries.
3. Parse XML response content into typed media objects.
4. Distinguish between image and video media.
5. Preserve access to multiple URIs when available:
   - full content URI
   - thumbnail URI
   - screen-sized image URI for pictures
6. Download full content to a destination directory.

## 7. Functional Requirements

### FR-1: Camera Connection Configuration

The system must allow configuration of:

- camera IP address
- control port
- browse port
- local host MAC address
- optional local host IP address
- optional local host port
- socket timeout
- HTTP timeout

Defaults should match the existing implementation when not overridden:

- camera IP: `192.168.107.1`
- control port: `7788`
- browse port: `7676`

### FR-2: Control Handshake

The system must support sending the equivalent of the existing control request:

- method: `HEAD`
- path: `/mode/control`
- protocol: `HTTP/1.0`
- Samsung-specific headers:
  - `User-Agent: SEC_MODE_<mac>`
  - `Access-Method: manual`
  - `NTS: alive`
  - `Content-Length: 0`
  - `HOST-Mac`
  - `HOST-Address`
  - `HOST-port`
  - `HOST-PNumber`

The implementation must allow these header values to be configurable even if defaults are provided.

### FR-3: Browse Request

The system must support browsing content using a SOAP request with configurable:

- object ID
- starting index
- requested count
- browse flag
- filter
- sort criteria

The default initial values should mirror the current code:

- object ID: `8`
- browse flag: `BrowseDirectChildren`
- filter: `*`
- starting index: caller-provided
- requested count: caller-provided
- sort criteria: empty

### FR-4: Browse Response Parsing

The system must parse the browse response and produce structured media records.

Each media item should include, where present:

- title
- date
- media type
- extension / format
- full content URI
- thumbnail URI
- screen image URI for pictures
- raw protocol info
- raw XML fragment for debugging

The parser must:

- correctly handle escaped XML content such as `&lt;` and `&gt;`
- validate required fields
- fail gracefully with useful errors when the response is malformed

### FR-5: Media Types

The system must expose at least these media models:

- `MediaItem` base model
- `PictureItem`
- `VideoItem`

The models must support:

- human-readable string representation
- filesystem-safe target filename generation
- download methods

### FR-6: Media Download

The system must support downloading a media item's primary content URI to a local directory.

Requirements:

- create destination directories if missing
- preserve or infer file extension
- sanitize invalid filename characters
- avoid accidental overwrite by default
- support overwrite as an explicit option
- stream content to disk instead of loading full files into memory
- return the output path

### FR-7: CLI

The project must provide a command-line interface with at least these commands:

- `connect`
- `browse`
- `download`
- `download-all`

Example usage expectations:

```bash
nx3000 connect --mac 02:00:00:00:00:00
nx3000 browse --start 0 --count 100
nx3000 download --index 0 --dest ~/Pictures/NX3000
nx3000 download-all --dest ~/Pictures/NX3000 --count 100
```

The CLI should support JSON output for scripting.

### FR-8: Logging and Debugging

The system must support:

- normal user-facing output
- verbose logging
- optional raw request/response logging
- optional persistence of raw responses for diagnostics

### FR-9: Library API

The library must expose a stable programmatic API such as:

```python
from nx3000 import NX3000Client, CameraConfig
```

Core operations:

- create client
- perform handshake
- browse media
- download one item
- download many items

### FR-10: Error Handling

The system must provide explicit exceptions for:

- camera connection failure
- handshake failure
- browse request failure
- parse failure
- download failure
- unsupported media type
- invalid configuration

## 8. User Stories

### Connection

- As a macOS user, I want to point the tool at my camera IP and MAC configuration so that I can connect without editing source code.

### Browse

- As a user, I want to list media on the camera so I can inspect what is available before downloading.

### Download One

- As a user, I want to download a single file by index so I can test connectivity and transfer behavior.

### Download Many

- As a user, I want to bulk-download all listed files to a local folder.

### Automate

- As a developer, I want a Python API so I can integrate the camera into my own workflows and scripts.

### Debug

- As a reverse-engineering user, I want access to raw requests/responses so I can troubleshoot protocol mismatches.

## 9. macOS-Specific Requirements

The rewrite should explicitly support macOS developer workflows:

- installation via `python -m venv` and `pip install -e .`
- path handling using `pathlib`
- no Windows-only APIs
- no Linux-specific assumptions
- documentation that explains how to determine current local IP and MAC on macOS
- downloadable paths that expand `~`

Optional but useful:

- Homebrew-friendly documentation
- `make` or simple shell targets for local development

## 10. UX Requirements for CLI

The CLI should be simple and explicit.

### Human Output

For `browse`, display:

- index
- type
- title
- date
- extension
- full URI or shortened URI

### JSON Output

For automation, output structured JSON with stable field names.

### Errors

Errors should:

- explain what failed
- mention likely causes when known
- suggest using `--verbose` or `--debug-raw`

## 11. Technical Constraints

- Python 3.11 or newer
- Prefer standard library for raw socket communication
- May use `httpx` or `requests` for media downloads; `httpx` is preferred for modern async/sync flexibility
- XML parsing should use a safe standard-library approach unless there is a strong reason otherwise
- Package should be installable with `pyproject.toml`

## 12. Quality Requirements

### Reliability

- Connection and browse operations must fail predictably with typed exceptions.
- Downloads must not silently truncate files.

### Maintainability

- Codebase should be modular, typed, and documented.
- Public API should be separated from protocol internals.

### Testability

- Parsing must be testable from static fixtures.
- Request generation must be testable without camera hardware.
- Download behavior should be testable via mocks.

### Observability

- Logs should expose enough detail to debug protocol issues without attaching a debugger.

## 13. Success Criteria

The rewrite is successful when:

1. A macOS user can install the package locally.
2. The user can send a handshake request to the camera.
3. The user can browse at least the first N media items.
4. The user can download at least one image and one video when available.
5. The CLI and library API both work.
6. Unit tests cover request building and XML parsing.

## 14. Risks

### Reverse-Engineered Protocol Risk

The Samsung protocol is not formally documented in this repository. Some fields may need adjustment after testing against actual hardware.

### Network Environment Risk

The camera may expect specific host IP/MAC patterns or network behavior.

### Response Shape Risk

Different firmware versions may return browse XML in slightly different forms.

### Filename Risk

Media titles may contain characters unsafe for filesystem use.

## 15. Assumptions

- The user can connect their Mac to the camera's Wi-Fi network.
- The camera is reachable at the configured IP.
- The protocol used by the current C# implementation is still valid for the user's camera and firmware.
- Direct media download URIs returned by browse are accessible from the Mac once connected.

## 16. Deliverables

The rewrite project should include:

- Python package source
- CLI entrypoint
- typed data models
- protocol/request builder layer
- XML response parser
- downloader
- tests
- fixtures
- README with setup and usage
- developer documentation

## 17. Release Scope for v1

### In Scope

- connect
- browse
- parse into media objects
- download media
- CLI
- logging
- unit tests

### Out of Scope

- GUI
- camera settings control
- live view
- upload/delete actions
- remote shutter

## 18. Recommended Milestones

### Milestone 1: Project Skeleton

- package structure
- pyproject
- lint/test tooling
- base models and config

### Milestone 2: Protocol Layer

- handshake request builder
- browse request builder
- raw TCP transport

### Milestone 3: Parsing Layer

- SOAP/XML extraction
- media item parsing
- typed exceptions

### Milestone 4: Downloader

- HTTP media download
- filename sanitization
- overwrite controls

### Milestone 5: CLI

- connect command
- browse command
- download commands

### Milestone 6: Tests and Docs

- parser fixtures
- request generation tests
- CLI smoke tests
- README and troubleshooting docs

