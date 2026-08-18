"""Small, stdlib-only client for the HITCON staff print-card endpoint.

The client deliberately exposes only the one upstream operation needed by the
printing workstation.  Error messages are intentionally generic: in
particular, no exception retains or renders the staff JWT.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import re


DEFAULT_API_BASE_URL = "https://nfc-battle-staging.hitcon2026.online"
DEFAULT_TIMEOUT_SECONDS = 20.0
DEFAULT_MAX_RESPONSE_BYTES = 10 * 1024 * 1024
UPSTREAM_USER_AGENT = "HITCON-NFC-Battle-CardPrinter/1.0"
DEFAULT_READ_CHUNK_BYTES = 64 * 1024
TRUSTED_API_DOMAIN = "hitcon2026.online"

TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]{8,32}$")


class UpstreamError(Exception):
    """Base class for safe-to-display upstream failures."""


class InvalidTokenError(UpstreamError):
    """The supplied print-card token is malformed."""


class InvalidBaseUrlError(ValueError):
    """The configured API base URL violates the allow-list policy."""


class MissingStaffJwtError(UpstreamError):
    """No usable staff JWT was supplied."""


class UpstreamHttpError(UpstreamError):
    """The upstream returned a non-success HTTP status."""

    def __init__(self, status_code: int) -> None:
        self.status_code = int(status_code)
        super().__init__(f"Upstream returned HTTP {self.status_code}.")


class UpstreamConnectionError(UpstreamError):
    """The upstream could not be reached or read."""


class UpstreamProtocolError(UpstreamError):
    """The upstream response did not obey the expected byte protocol."""


class UpstreamResponseTooLargeError(UpstreamError):
    """The upstream response exceeded the configured streaming limit."""


def normalize_print_token(token: str) -> str:
    """Trim and validate the app's 8-32 character short-token format."""

    if not isinstance(token, str):
        raise InvalidTokenError("Print-card token is invalid.")
    normalized = token.strip()
    if TOKEN_PATTERN.fullmatch(normalized) is None:
        raise InvalidTokenError("Print-card token is invalid.")
    return normalized


def validate_api_base_url(
    value: str = DEFAULT_API_BASE_URL,
    *,
    allowed_hosts: Optional[Iterable[str]] = None,
    allow_http: bool = False,
) -> str:
    """Validate and normalize an upstream API base URL.

    Production defaults accept HTTPS URLs on ``hitcon2026.online`` or any of
    its subdomains.  Tests may replace that host policy and opt into plain HTTP
    only by supplying both ``allowed_hosts`` and ``allow_http=True``.
    """

    if not isinstance(value, str) or not value.strip():
        raise InvalidBaseUrlError("API base URL is invalid.")
    raw = value.strip()
    if "?" in raw or "#" in raw or "\\" in raw:
        raise InvalidBaseUrlError("API base URL is invalid.")

    try:
        parsed = urlsplit(raw)
        hostname = (parsed.hostname or "").lower().rstrip(".")
        username = parsed.username
        password = parsed.password
    except ValueError:
        raise InvalidBaseUrlError("API base URL is invalid.") from None

    if not hostname or username is not None or password is not None:
        raise InvalidBaseUrlError("API base URL is invalid.")
    if parsed.query or parsed.fragment:
        raise InvalidBaseUrlError("API base URL is invalid.")

    explicit_hosts = None
    if allowed_hosts is not None:
        explicit_hosts = {
            host.strip().lower().rstrip(".")
            for host in allowed_hosts
            if isinstance(host, str) and host.strip()
        }
        if not explicit_hosts or hostname not in explicit_hosts:
            raise InvalidBaseUrlError("API base URL host is not allowed.")
    elif not (
        hostname == TRUSTED_API_DOMAIN
        or hostname.endswith("." + TRUSTED_API_DOMAIN)
    ):
        raise InvalidBaseUrlError("API base URL host is not allowed.")

    scheme = parsed.scheme.lower()
    test_http_allowed = (
        scheme == "http" and allow_http and explicit_hosts is not None
    )
    if scheme != "https" and not test_http_allowed:
        raise InvalidBaseUrlError("API base URL must use HTTPS.")

    normalized_path = parsed.path.rstrip("/")
    return urlunsplit((scheme, parsed.netloc, normalized_path, "", ""))


@dataclass(frozen=True)
class UpstreamResponse:
    """Downloaded body plus the URL-safe token used to retrieve it."""

    token: str
    body: bytes


OpenUrl = Callable[..., object]


class _RejectRedirectHandler(HTTPRedirectHandler):
    """Keep the STAFF bearer token on the one validated upstream URL."""

    def redirect_request(
        self,
        request,
        response,
        code,
        message,
        headers,
        new_url,
    ):
        # urllib otherwise copies the original request headers, including the
        # Authorization value, to the redirect target.  This endpoint has one
        # fixed URL and must never redirect a workstation credential.
        raise HTTPError(
            request.full_url,
            code,
            "Upstream redirects are not allowed.",
            headers,
            response,
        )


class UpstreamClient:
    """Client for ``GET /staff/print-cards/{short_token}``."""

    def __init__(
        self,
        base_url: str = DEFAULT_API_BASE_URL,
        staff_jwt: Optional[str] = None,
        *,
        allowed_hosts: Optional[Iterable[str]] = None,
        allow_http: bool = False,
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
        max_response_bytes: int = DEFAULT_MAX_RESPONSE_BYTES,
        opener: Optional[OpenUrl] = None,
    ) -> None:
        self._base_url = validate_api_base_url(
            base_url,
            allowed_hosts=allowed_hosts,
            allow_http=allow_http,
        )
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        if max_response_bytes <= 0:
            raise ValueError("max_response_bytes must be positive")
        self._staff_jwt = staff_jwt
        self._timeout = float(timeout)
        self._max_response_bytes = int(max_response_bytes)
        self._opener: OpenUrl = opener or build_opener(
            _RejectRedirectHandler()
        ).open

    @property
    def base_url(self) -> str:
        return self._base_url

    @property
    def timeout(self) -> float:
        return self._timeout

    @property
    def max_response_bytes(self) -> int:
        return self._max_response_bytes

    def download_print_card(
        self,
        token: str,
        *,
        staff_jwt: Optional[str] = None,
    ) -> bytes:
        """Download one print-ready PNG without buffering beyond the cap."""

        normalized_token = normalize_print_token(token)
        jwt = self._resolve_staff_jwt(staff_jwt)
        encoded_token = quote(normalized_token, safe="")
        url = (
            f"{self._base_url}/staff/print-cards/{encoded_token}"
        )
        request = Request(
            url,
            method="GET",
            headers={
                "Accept": "image/png",
                "Authorization": f"Bearer {jwt}",
                # Cloudflare rejects urllib's default Python fingerprint with
                # Error 1010 before the request reaches the API worker.
                "User-Agent": UPSTREAM_USER_AGENT,
            },
        )

        response = None
        try:
            response = self._opener(request, timeout=self._timeout)
            status = getattr(response, "status", None)
            if status is None and hasattr(response, "getcode"):
                status = response.getcode()
            if status is not None and not 200 <= int(status) < 300:
                raise UpstreamHttpError(int(status))

            content_length = self._content_length(response)
            if (
                content_length is not None
                and content_length > self._max_response_bytes
            ):
                raise UpstreamResponseTooLargeError(
                    "Upstream response exceeds the size limit."
                )
            return self._read_limited(response)
        except UpstreamError:
            raise
        except HTTPError as error:
            try:
                error.close()
            except Exception:
                pass
            raise UpstreamHttpError(error.code) from None
        except (URLError, TimeoutError, OSError):
            raise UpstreamConnectionError(
                "Could not reach the upstream print-card service."
            ) from None
        except Exception:
            # Do not chain arbitrary transport exceptions: a custom opener may
            # include request headers (and therefore the JWT) in its message.
            raise UpstreamConnectionError(
                "Could not read the upstream print-card response."
            ) from None
        finally:
            if response is not None:
                close = getattr(response, "close", None)
                if callable(close):
                    try:
                        close()
                    except Exception:
                        pass

    def download(
        self,
        token: str,
        *,
        staff_jwt: Optional[str] = None,
    ) -> UpstreamResponse:
        """Variant that also returns the normalized token as metadata."""

        normalized = normalize_print_token(token)
        return UpstreamResponse(
            token=normalized,
            body=self.download_print_card(normalized, staff_jwt=staff_jwt),
        )

    def _resolve_staff_jwt(self, override: Optional[str]) -> str:
        raw = override if override is not None else self._staff_jwt
        if not isinstance(raw, str):
            raise MissingStaffJwtError("A staff JWT is required.")
        normalized = raw.strip()
        if not normalized or "\r" in normalized or "\n" in normalized:
            raise MissingStaffJwtError("A staff JWT is required.")
        return normalized

    def _content_length(self, response: object) -> Optional[int]:
        headers = getattr(response, "headers", None)
        if headers is None:
            return None
        try:
            value = headers.get("Content-Length")
        except Exception:
            return None
        if value is None:
            return None
        try:
            parsed = int(value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed >= 0 else None

    def _read_limited(self, response: object) -> bytes:
        read = getattr(response, "read", None)
        if not callable(read):
            raise UpstreamProtocolError("Upstream response is not readable.")

        body = bytearray()
        while True:
            remaining = self._max_response_bytes - len(body)
            chunk = read(min(DEFAULT_READ_CHUNK_BYTES, remaining + 1))
            if not chunk:
                break
            if not isinstance(chunk, (bytes, bytearray, memoryview)):
                raise UpstreamProtocolError(
                    "Upstream response did not contain bytes."
                )
            body.extend(chunk)
            if len(body) > self._max_response_bytes:
                raise UpstreamResponseTooLargeError(
                    "Upstream response exceeds the size limit."
                )
        return bytes(body)


def download_staff_print_card(
    token: str,
    *,
    staff_jwt: str,
    base_url: str = DEFAULT_API_BASE_URL,
    allowed_hosts: Optional[Iterable[str]] = None,
    allow_http: bool = False,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    max_response_bytes: int = DEFAULT_MAX_RESPONSE_BYTES,
    opener: Optional[OpenUrl] = None,
) -> bytes:
    """Functional convenience wrapper around :class:`UpstreamClient`."""

    return UpstreamClient(
        base_url,
        staff_jwt,
        allowed_hosts=allowed_hosts,
        allow_http=allow_http,
        timeout=timeout,
        max_response_bytes=max_response_bytes,
        opener=opener,
    ).download_print_card(token)
