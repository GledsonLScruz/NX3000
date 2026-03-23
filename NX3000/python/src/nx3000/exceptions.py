"""Exception hierarchy for the NX3000 package."""


class NX3000Error(Exception):
    """Base exception for package errors."""


class ConfigurationError(NX3000Error):
    """Raised when client configuration is invalid."""


class TransportError(NX3000Error):
    """Raised for low-level socket communication failures."""


class HandshakeError(NX3000Error):
    """Raised when the control handshake fails."""


class BrowseError(NX3000Error):
    """Raised when a browse request fails."""


class ParseError(NX3000Error):
    """Raised when the camera response cannot be parsed."""


class DownloadError(NX3000Error):
    """Raised when downloading media fails."""


class UnsupportedMediaTypeError(NX3000Error):
    """Raised when a browse item has an unsupported media type."""

