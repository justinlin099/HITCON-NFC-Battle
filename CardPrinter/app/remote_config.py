"""Resolve the App's public runtime API configuration at workstation startup."""

from __future__ import annotations

from typing import Callable, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import json

from .upstream import InvalidBaseUrlError, validate_api_base_url


DEFAULT_REMOTE_CONFIG_URL = (
    "https://game.hitcon2026.online/"
    ".well-known/nfc-battle-app-config.json"
)
REMOTE_CONFIG_TIMEOUT_SECONDS = 4.0
REMOTE_CONFIG_MAX_BYTES = 16 * 1024
REMOTE_CONFIG_USER_AGENT = "HITCON-NFC-Battle-CardPrinter/1.0"
REMOTE_CONFIG_HOST = "game.hitcon2026.online"
REMOTE_CONFIG_PATH = "/.well-known/nfc-battle-app-config.json"
READ_CHUNK_BYTES = 4096


class RemoteConfigError(RuntimeError):
    """The public remote config was unavailable or invalid."""


OpenUrl = Callable[..., object]


class _RejectRedirectHandler(HTTPRedirectHandler):
    def redirect_request(
        self,
        request,
        response,
        code,
        message,
        headers,
        new_url,
    ):
        raise HTTPError(
            request.full_url,
            code,
            "Remote config redirects are not allowed.",
            headers,
            response,
        )


def validate_remote_config_url(value: str) -> str:
    """Accept only the canonical HTTPS App remote-config document."""

    if not isinstance(value, str) or not value.strip():
        raise RemoteConfigError("Remote config URL is invalid.")
    raw = value.strip()
    if "\\" in raw or "?" in raw or "#" in raw:
        raise RemoteConfigError("Remote config URL is invalid.")
    try:
        parsed = urlsplit(raw)
        parsed_host = parsed.hostname or ""
        if parsed_host.endswith("."):
            raise RemoteConfigError("Remote config URL is invalid.")
        host = parsed_host.lower()
        port = parsed.port
    except ValueError:
        raise RemoteConfigError("Remote config URL is invalid.") from None
    if (
        parsed.scheme.lower() != "https"
        or host != REMOTE_CONFIG_HOST
        or parsed.username is not None
        or parsed.password is not None
        or (port is not None and port != 443)
        or parsed.path != REMOTE_CONFIG_PATH
        or parsed.query
        or parsed.fragment
    ):
        raise RemoteConfigError("Remote config URL is not trusted.")
    return urlunsplit(("https", REMOTE_CONFIG_HOST, REMOTE_CONFIG_PATH, "", ""))


def fetch_remote_api_base_url(
    config_url: str = DEFAULT_REMOTE_CONFIG_URL,
    *,
    timeout: float = REMOTE_CONFIG_TIMEOUT_SECONDS,
    max_bytes: int = REMOTE_CONFIG_MAX_BYTES,
    opener: Optional[OpenUrl] = None,
) -> str:
    """Fetch schema 1 and return its validated API base URL.

    The request contains no workstation credential. Redirects are rejected and
    the response is streamed under the same 16 KiB cap used by the Flutter App.
    """

    if timeout <= 0:
        raise ValueError("timeout must be positive")
    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    trusted_url = validate_remote_config_url(config_url)
    request = Request(
        trusted_url,
        method="GET",
        headers={
            "Accept": "application/json",
            "Accept-Encoding": "identity",
            "Cache-Control": "no-cache, no-store",
            "User-Agent": REMOTE_CONFIG_USER_AGENT,
        },
    )
    open_url = opener or build_opener(_RejectRedirectHandler()).open
    response = None
    try:
        response = open_url(request, timeout=float(timeout))
        status = getattr(response, "status", None)
        if status is None and hasattr(response, "getcode"):
            status = response.getcode()
        if status is None or int(status) != 200:
            raise RemoteConfigError("Remote config returned a non-200 status.")

        headers = getattr(response, "headers", {})
        content_type = str(headers.get("Content-Type", ""))
        if content_type.split(";", 1)[0].strip().lower() != "application/json":
            raise RemoteConfigError("Remote config did not return JSON.")
        content_encoding = str(headers.get("Content-Encoding", "")).strip().lower()
        if content_encoding not in {"", "identity"}:
            raise RemoteConfigError("Remote config uses an unsupported encoding.")
        raw_length = headers.get("Content-Length")
        if raw_length not in {None, ""}:
            try:
                content_length = int(raw_length)
            except (TypeError, ValueError):
                raise RemoteConfigError(
                    "Remote config has an invalid content length."
                ) from None
            if content_length < 0 or content_length > max_bytes:
                raise RemoteConfigError("Remote config is too large.")

        body = bytearray()
        while True:
            chunk = response.read(min(READ_CHUNK_BYTES, max_bytes + 1))
            if not chunk:
                break
            body.extend(chunk)
            if len(body) > max_bytes:
                raise RemoteConfigError("Remote config is too large.")
        try:
            document = json.loads(
                bytes(body).decode("utf-8"),
                object_pairs_hook=_object_without_duplicate_keys,
            )
        except (UnicodeError, json.JSONDecodeError):
            raise RemoteConfigError("Remote config JSON is invalid.") from None
        if not isinstance(document, dict):
            raise RemoteConfigError("Remote config must be a JSON object.")
        schema = document.get("schema")
        if type(schema) is not int or schema != 1:
            raise RemoteConfigError("Remote config schema is unsupported.")
        api_base_url = document.get("api_base_url")
        if not isinstance(api_base_url, str) or not api_base_url.strip():
            raise RemoteConfigError("Remote config has no API base URL.")
        return validate_remote_api_base_url(api_base_url)
    except RemoteConfigError:
        raise
    except HTTPError as error:
        try:
            error.close()
        except Exception:
            pass
        raise RemoteConfigError("Remote config request was rejected.") from None
    except (URLError, TimeoutError, OSError):
        raise RemoteConfigError("Remote config is unavailable.") from None
    except Exception:
        raise RemoteConfigError("Remote config could not be read.") from None
    finally:
        if response is not None:
            close = getattr(response, "close", None)
            if callable(close):
                try:
                    close()
                except Exception:
                    pass


def validate_remote_api_base_url(value: str) -> str:
    """Apply the same trusted HITCON API URL policy used by the App."""

    if not isinstance(value, str):
        raise RemoteConfigError("Remote config API base URL is not trusted.")
    try:
        candidate = urlsplit(value.strip())
    except ValueError:
        raise RemoteConfigError(
            "Remote config API base URL is not trusted."
        ) from None
    if (candidate.hostname or "").endswith("."):
        raise RemoteConfigError("Remote config API base URL is not trusted.")
    try:
        normalized = validate_api_base_url(value)
    except InvalidBaseUrlError:
        raise RemoteConfigError(
            "Remote config API base URL is not trusted."
        ) from None
    return normalized


def _object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RemoteConfigError("Remote config contains duplicate keys.")
        result[key] = value
    return result
