# nx3000 Python Rewrite

This directory contains a standalone Python client and CLI for accessing files from a Samsung NX3000 camera over its Wi-Fi / MobileLink interface.

The project is self-contained and can be copied out of this repository as its own Python package.

## Project Docs

The Python rewrite docs are included locally in this folder:

- `docs/PRD_PYTHON_REWRITE.md`
- `docs/IMPLEMENTATION_SPEC_PYTHON.md`

## What It Does

The package connects to a Samsung NX3000 camera over Wi-Fi, sends the camera control handshake, performs a SOAP browse request, parses the media listing, and can download media files.

## Layout

```text
python/
  pyproject.toml
  README.md
  src/nx3000/
  tests/
```

## Setup

```bash
cd python
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## CLI Examples

```bash
nx3000 connect --mac 02:00:00:00:00:00
nx3000 browse --mac 02:00:00:00:00:00 --start 0 --count 25
nx3000 browse --mac 02:00:00:00:00:00 --json
nx3000 download --mac 02:00:00:00:00:00 --index 0 --dest ~/Pictures/NX3000
nx3000 download-all --mac 02:00:00:00:00:00 --dest ~/Pictures/NX3000
nx3000 interactive --mac 02:00:00:00:00:00
```

## Interactive Mode

Run:

```bash
nx3000 interactive --mac 02:00:00:00:00:00
```

This opens a numbered terminal menu where you can:

- inspect and edit connection settings
- connect to the camera
- browse media and keep the results cached in memory
- inspect item details
- download one or all cached items
- toggle raw request/response debug output

## Library Example

```python
from nx3000 import CameraConfig, NX3000Client

config = CameraConfig(host_mac="02:00:00:00:00:00")
client = NX3000Client(config, debug=True)

client.handshake()
items = client.browse(start=0, count=10)

for item in items:
    print(item)
```

## Notes

- The protocol is reverse-engineered from observed camera behavior.
- Real hardware testing is still required to validate behavior against a physical Samsung NX3000 camera.
- The implementation uses only the Python standard library so the core package stays lightweight.
