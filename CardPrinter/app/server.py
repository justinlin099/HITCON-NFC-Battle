"""HTTP server for the Windows card-printing workstation.

The browser owns the laptop camera.  This server only proxies the existing
STAFF PNG endpoint and replaces the single image part in the calibrated DOCX.
It intentionally uses only Python's standard library so the Docker image has
no runtime package downloads.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from functools import partial
from hashlib import sha256
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import logging
import os
from pathlib import Path
import re
import sys
from threading import BoundedSemaphore, Thread
from typing import Any, Mapping, Optional, Sequence
from urllib.parse import parse_qs, unquote, urlsplit
import zipfile

from .docx_template import (
    DocxBuildError,
    PngValidationError,
    TemplateMetadata,
    TemplateValidationError,
    build_docx,
    validate_png,
    validate_template,
)
from .scanner_relay import (
    InvalidScannerPairingCodeError,
    ScannerCapabilityError,
    ScannerDeviceCapabilityError,
    ScannerDeviceGrant,
    ScannerPairingGrant,
    ScannerRelay,
    ScannerSessionAlreadyPairedError,
    ScannerSessionAlreadyUsedError,
    ScannerSessionNotFoundError,
    ScannerSessionSnapshot,
)
from .remote_config import (
    DEFAULT_REMOTE_CONFIG_URL,
    OpenUrl as RemoteConfigOpenUrl,
    RemoteConfigError,
    fetch_remote_api_base_url,
    validate_remote_config_url,
)
from .upstream import (
    DEFAULT_API_BASE_URL,
    InvalidBaseUrlError,
    InvalidTokenError,
    MissingStaffJwtError,
    UpstreamClient,
    UpstreamConnectionError,
    UpstreamHttpError,
    UpstreamProtocolError,
    UpstreamResponseTooLargeError,
    normalize_print_token,
)


LOGGER = logging.getLogger("cardprinter")
APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
TEMPLATE_PATH = APP_DIR / "templates" / "card-template.docx"
TEMPLATE_MANIFEST_PATH = (
    APP_DIR / "templates" / "card-template-manifest.json"
)
DOCX_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
)
TOKEN_ROUTE = re.compile(r"^/api/cards/([^/]+)/png$")
TOKEN_LOG_ROUTE = re.compile(r"/api/cards/[^/\s?]+/png")
SCANNER_SESSION_ROUTE = re.compile(
    r"^/api/scanner/sessions/([A-Za-z0-9_-]{20,40})$"
)
SCANNER_SESSION_TOKEN_ROUTE = re.compile(
    r"^/api/scanner/sessions/([A-Za-z0-9_-]{20,40})/token$"
)
SCANNER_SESSION_CLOSE_ROUTE = re.compile(
    r"^/api/scanner/sessions/([A-Za-z0-9_-]{20,40})/close$"
)
SCANNER_LOG_ROUTE = re.compile(
    r"/api/scanner/sessions/[A-Za-z0-9_-]{20,40}"
)
SAFE_DOWNLOAD_STEM = re.compile(r"[^A-Za-z0-9_-]+")
DEFAULT_MAX_PNG_BYTES = 10 * 1024 * 1024
MAX_REQUEST_TARGET_LENGTH = 2048
MAX_DOWNLOAD_STEM_LENGTH = 80
DEFAULT_WEB_HOSTS = ("localhost", "127.0.0.1", "::1")
WEB_HOSTNAME = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"
)

STATIC_CONTENT_TYPES = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
}


class ConfigurationError(RuntimeError):
    """The workstation configuration or retained template is unsafe."""


class ForbiddenWebOriginError(ValueError):
    """The browser request did not originate from this local workstation."""


@dataclass(frozen=True)
class Settings:
    api_base_url: str
    staff_jwt: Optional[str]
    allowed_api_hosts: Optional[tuple[str, ...]]
    allow_http_api: bool
    allowed_web_hosts: tuple[str, ...]
    max_png_bytes: int
    host: str
    port: int
    companion_host: str
    companion_port: int
    remote_config_url: str = DEFAULT_REMOTE_CONFIG_URL
    api_base_url_source: str = "fallback"

    @property
    def auth_mode(self) -> str:
        return "server" if self.staff_jwt else "browser"


@dataclass(frozen=True)
class TemplateBundle:
    document_bytes: bytes
    sha256: str
    metadata: TemplateMetadata
    manifest: Mapping[str, Any]


@dataclass(frozen=True)
class CompanionSettings:
    """Non-secret settings available to the phone-facing listener."""

    allowed_web_hosts: tuple[str, ...]
    max_png_bytes: int = 512


@dataclass(frozen=True)
class CompanionApplication:
    settings: CompanionSettings
    scanner_relay: ScannerRelay


class CardPrinterApplication:
    """Pure application operations shared by the HTTP handler and tests."""

    def __init__(
        self,
        settings: Settings,
        template: TemplateBundle,
        *,
        upstream_client: Optional[UpstreamClient] = None,
        scanner_relay: Optional[ScannerRelay] = None,
    ) -> None:
        self.settings = settings
        self.template = template
        self.upstream = upstream_client or UpstreamClient(
            settings.api_base_url,
            settings.staff_jwt,
            allowed_hosts=settings.allowed_api_hosts,
            allow_http=settings.allow_http_api,
            max_response_bytes=settings.max_png_bytes,
        )
        self.scanner_relay = scanner_relay or ScannerRelay()

    def public_config(self) -> dict[str, Any]:
        page = self.template.manifest.get("page", {})
        image_frame = self.template.manifest.get("imageFrame", {})
        return {
            "authMode": self.settings.auth_mode,
            "apiBaseUrl": self.settings.api_base_url,
            "apiBaseUrlSource": self.settings.api_base_url_source,
            "remoteConfigUrl": self.settings.remote_config_url,
            "maxPngBytes": self.settings.max_png_bytes,
            "template": {
                "sha256": self.template.sha256,
                "pageWidthMillimeters": page.get("widthMillimeters"),
                "pageHeightMillimeters": page.get("heightMillimeters"),
                "imageWidthMillimeters": image_frame.get("widthMillimeters"),
                "imageHeightMillimeters": image_frame.get("heightMillimeters"),
                "horizontalOffsetMillimeters": image_frame.get(
                    "horizontalOffsetMillimeters"
                ),
                "anchorKind": self.template.metadata.anchor_kind,
            },
        }

    def fetch_card_png(
        self, token: str, *, staff_jwt: Optional[str] = None
    ) -> bytes:
        normalized = normalize_print_token(token)
        png_bytes = self.upstream.download_print_card(
            normalized,
            staff_jwt=staff_jwt,
        )
        validate_png(png_bytes, max_bytes=self.settings.max_png_bytes)
        return png_bytes

    def make_document(self, png_bytes: bytes) -> bytes:
        validate_png(png_bytes, max_bytes=self.settings.max_png_bytes)
        result = build_docx(
            self.template.document_bytes,
            png_bytes,
            max_png_bytes=self.settings.max_png_bytes,
        )
        return result.document_bytes


class CardPrinterRequestHandler(BaseHTTPRequestHandler):
    """Small same-origin HTTP surface for one trusted local workstation."""

    protocol_version = "HTTP/1.1"
    server_version = "CardPrinter/1.0"
    sys_version = ""

    def __init__(
        self,
        *args: Any,
        application: CardPrinterApplication | CompanionApplication,
        static_directory: Path = STATIC_DIR,
        **kwargs: Any,
    ) -> None:
        self.application = application
        self.static_directory = static_directory.resolve()
        super().__init__(*args, **kwargs)

    def log_message(self, format: str, *args: Any) -> None:
        # BaseHTTPRequestHandler never logs headers, but using our logger also
        # keeps formatting predictable and prevents accidental JWT diagnostics.
        rendered = format % args
        rendered = TOKEN_LOG_ROUTE.sub(
            "/api/cards/[redacted]/png",
            rendered,
        )
        rendered = SCANNER_LOG_ROUTE.sub(
            "/api/scanner/sessions/[redacted]",
            rendered,
        )
        LOGGER.info("%s - %s", self.client_address[0], rendered)

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        try:
            target = self._parsed_target()
            self._validate_web_request(target.path)
            if target.path == "/healthz":
                self._send_json(
                    HTTPStatus.OK,
                    {"status": "ok", "template": "ready"},
                    cache_control="no-store",
                )
                return
            if target.path == "/api/config":
                self._send_json(
                    HTTPStatus.OK,
                    self.application.public_config(),
                    cache_control="no-store",
                )
                return

            scanner_session_match = SCANNER_SESSION_ROUTE.fullmatch(
                target.path
            )
            if scanner_session_match:
                session = self.application.scanner_relay.session(
                    scanner_session_match.group(1)
                )
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "session": _scanner_session_payload(session),
                    },
                    cache_control="no-store",
                )
                return

            token_match = TOKEN_ROUTE.fullmatch(target.path)
            if token_match:
                token = unquote(token_match.group(1), errors="strict")
                request_jwt = self._request_staff_jwt()
                png_bytes = self.application.fetch_card_png(
                    token,
                    staff_jwt=request_jwt,
                )
                self._send_bytes(
                    HTTPStatus.OK,
                    png_bytes,
                    content_type="image/png",
                    cache_control="no-store",
                    extra_headers={
                        "Content-Disposition": "inline",
                    },
                )
                return

            if target.path == "/favicon.ico":
                self._send_bytes(
                    HTTPStatus.NO_CONTENT,
                    b"",
                    content_type="image/x-icon",
                    cache_control="public, max-age=86400",
                )
                return

            if target.path.startswith("/api/"):
                self._send_error_json(
                    HTTPStatus.NOT_FOUND,
                    "not_found",
                    "找不到指定的 API。",
                )
                return
            self._serve_static(target.path)
        except Exception as error:  # central, redaction-safe mapping
            self._handle_error(error)

    def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
        try:
            target = self._parsed_target()
            self._validate_web_request(target.path)

            if target.path == "/api/scanner/sessions":
                session = self.application.scanner_relay.create_session()
                self._send_json(
                    HTTPStatus.CREATED,
                    {
                        "status": "ok",
                        "session": _scanner_session_payload(
                            session, include_pairing_code=True
                        ),
                    },
                    cache_control="no-store",
                )
                return

            if target.path == "/api/scanner/devices":
                expected_session_id = self.headers.get(
                    "X-Scanner-Session-Id", ""
                ).strip()
                if expected_session_id and not SCANNER_SESSION_ROUTE.fullmatch(
                    f"/api/scanner/sessions/{expected_session_id}"
                ):
                    raise ValueError("Scanner session id is invalid.")
                device = self.application.scanner_relay.create_device(
                    expected_session_id=expected_session_id or None
                )
                self._send_json(
                    HTTPStatus.CREATED,
                    {
                        "status": "ok",
                        "device": _scanner_device_payload(device),
                    },
                    cache_control="no-store",
                )
                return

            scanner_close_match = SCANNER_SESSION_CLOSE_ROUTE.fullmatch(
                target.path
            )
            if scanner_close_match:
                self.application.scanner_relay.close_session(
                    scanner_close_match.group(1)
                )
                self._send_json(
                    HTTPStatus.OK,
                    {"status": "ok"},
                    cache_control="no-store",
                )
                return

            if target.path != "/api/documents":
                self._send_error_json(
                    HTTPStatus.NOT_FOUND,
                    "not_found",
                    "找不到指定的 API。",
                )
                return

            content_type = self.headers.get("Content-Type", "")
            media_type = content_type.split(";", 1)[0].strip().lower()
            if media_type != "image/png":
                self._send_error_json(
                    HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
                    "png_required",
                    "請上傳 PNG 卡面。",
                )
                return

            png_bytes = self._read_request_body(
                max_bytes=self.application.settings.max_png_bytes
            )
            document_bytes = self.application.make_document(png_bytes)
            query = parse_qs(target.query, keep_blank_values=False)
            requested_name = query.get("name", ["hitcon-print-card"])[0]
            download_stem = _safe_download_stem(requested_name)
            self._send_bytes(
                HTTPStatus.OK,
                document_bytes,
                content_type=DOCX_CONTENT_TYPE,
                cache_control="no-store",
                extra_headers={
                    "Content-Disposition": (
                        f'attachment; filename="{download_stem}.docx"'
                    )
                },
            )
        except Exception as error:  # central, redaction-safe mapping
            self._handle_error(error, document_request=True)

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib callback name
        self._send_error_json(
            HTTPStatus.METHOD_NOT_ALLOWED,
            "method_not_allowed",
            "此方法不受支援。",
            include_body=False,
        )

    def do_OPTIONS(self) -> None:  # noqa: N802 - stdlib callback name
        self._send_error_json(
            HTTPStatus.METHOD_NOT_ALLOWED,
            "method_not_allowed",
            "此服務僅供同源網頁使用。",
        )

    def _parsed_target(self):
        if len(self.path) > MAX_REQUEST_TARGET_LENGTH:
            raise ValueError("Request target is too long.")
        return urlsplit(self.path)

    def _validate_web_request(self, request_path: str) -> None:
        host_header = self.headers.get("Host", "")
        host_name, host_port = _parse_request_authority(host_header)
        if host_name not in self.application.settings.allowed_web_hosts:
            raise ForbiddenWebOriginError("Request host is not allowed.")

        if not request_path.startswith("/api/"):
            return

        fetch_site = self.headers.get("Sec-Fetch-Site", "").strip().lower()
        if fetch_site and fetch_site not in {"same-origin", "none"}:
            raise ForbiddenWebOriginError("Cross-origin API request rejected.")

        origin = self.headers.get("Origin", "").strip()
        if not origin:
            return
        try:
            parsed_origin = urlsplit(origin)
            origin_host = _normalize_web_host(parsed_origin.hostname or "")
            origin_port = parsed_origin.port
        except (ConfigurationError, ValueError):
            raise ForbiddenWebOriginError("Request origin is invalid.") from None
        if (
            parsed_origin.scheme.lower() not in {"http", "https"}
            or parsed_origin.username is not None
            or parsed_origin.password is not None
            or parsed_origin.path not in {"", "/"}
            or parsed_origin.query
            or parsed_origin.fragment
        ):
            raise ForbiddenWebOriginError("Request origin is invalid.")

        default_port = 443 if parsed_origin.scheme.lower() == "https" else 80
        if (
            origin_host != host_name
            or (origin_port or default_port) != (host_port or default_port)
        ):
            raise ForbiddenWebOriginError("Cross-origin API request rejected.")

    def _request_staff_jwt(self) -> Optional[str]:
        if self.application.settings.staff_jwt:
            return None
        authorization = self.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            raise MissingStaffJwtError("A staff JWT is required.")
        jwt = authorization[7:].strip()
        if not jwt or "\r" in jwt or "\n" in jwt:
            raise MissingStaffJwtError("A staff JWT is required.")
        return jwt

    def _read_request_body(
        self, *, max_bytes: int, timeout_seconds: int = 20
    ) -> bytes:
        if self.headers.get("Transfer-Encoding"):
            raise ValueError("Chunked request bodies are not supported.")
        raw_length = self.headers.get("Content-Length")
        try:
            content_length = int(raw_length or "")
        except ValueError:
            raise ValueError("Content-Length is required.") from None
        if content_length <= 0:
            raise RequestBodyRequiredError
        if content_length > max_bytes:
            raise RequestEntityTooLargeError
        self.connection.settimeout(timeout_seconds)
        body = self.rfile.read(content_length)
        if len(body) != content_length:
            raise ValueError("Request body ended early.")
        return body

    def _read_json_object(self, *, max_bytes: int) -> Mapping[str, Any]:
        content_type = self.headers.get("Content-Type", "")
        media_type = content_type.split(";", 1)[0].strip().lower()
        if media_type != "application/json":
            raise ValueError("A JSON request body is required.")
        body = self._read_request_body(
            max_bytes=max_bytes,
            timeout_seconds=5,
        )
        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            raise ValueError("The JSON request body is invalid.") from None
        if not isinstance(payload, dict):
            raise ValueError("The JSON request body must be an object.")
        return payload

    def _serve_static(self, request_path: str) -> None:
        relative = "index.html" if request_path in {"", "/"} else request_path.lstrip("/")
        # The HTML uses an explicit /static prefix while vendor assets are
        # mounted at /vendor.  Both resolve inside the same immutable folder.
        if relative.startswith("static/"):
            relative = relative[len("static/") :]
        if not relative or "\\" in relative:
            self._send_error_json(
                HTTPStatus.NOT_FOUND, "not_found", "找不到指定的檔案。"
            )
            return
        candidate = (self.static_directory / relative).resolve()
        try:
            candidate.relative_to(self.static_directory)
        except ValueError:
            self._send_error_json(
                HTTPStatus.NOT_FOUND, "not_found", "找不到指定的檔案。"
            )
            return
        if not candidate.is_file():
            self._send_error_json(
                HTTPStatus.NOT_FOUND, "not_found", "找不到指定的檔案。"
            )
            return
        content_type = STATIC_CONTENT_TYPES.get(candidate.suffix.lower())
        if content_type is None:
            self._send_error_json(
                HTTPStatus.NOT_FOUND, "not_found", "找不到指定的檔案。"
            )
            return
        self._send_bytes(
            HTTPStatus.OK,
            candidate.read_bytes(),
            content_type=content_type,
            cache_control="no-cache",
        )

    def _handle_error(
        self, error: Exception, *, document_request: bool = False
    ) -> None:
        if isinstance(error, ForbiddenWebOriginError):
            self._send_error_json(
                HTTPStatus.FORBIDDEN,
                "forbidden_origin",
                "此工作站只接受本機同源請求。",
            )
            return
        if isinstance(error, ScannerSessionNotFoundError):
            self._send_error_json(
                HTTPStatus.NOT_FOUND,
                "scanner_session_expired",
                "手機掃描工作已結束，請在 Windows 重新開始。",
            )
            return
        if isinstance(error, InvalidScannerPairingCodeError):
            self._send_error_json(
                HTTPStatus.UNAUTHORIZED,
                "scanner_pairing_failed",
                "配對碼錯誤、已使用或已過期。",
            )
            return
        if isinstance(error, ScannerCapabilityError):
            self._send_error_json(
                HTTPStatus.FORBIDDEN,
                "scanner_not_paired",
                "手機掃描器尚未完成配對。",
            )
            return
        if isinstance(error, ScannerDeviceCapabilityError):
            self._send_error_json(
                HTTPStatus.FORBIDDEN,
                "scanner_device_not_authorized",
                "USB 手機連線已失效，請在 Windows 重新執行連線程式。",
            )
            return
        if isinstance(error, ScannerSessionAlreadyUsedError):
            self._send_error_json(
                HTTPStatus.CONFLICT,
                "scanner_session_used",
                "這次手機掃描已收到條碼。",
            )
            return
        if isinstance(error, ScannerSessionAlreadyPairedError):
            self._send_error_json(
                HTTPStatus.CONFLICT,
                "scanner_session_paired",
                "這次手機掃描工作已由另一個掃描器接手。",
            )
            return
        if isinstance(error, InvalidTokenError):
            self._send_error_json(
                HTTPStatus.BAD_REQUEST,
                "invalid_token",
                "短碼必須是 8–32 個英文字母、數字、底線或連字號。",
            )
            return
        if isinstance(error, MissingStaffJwtError):
            self._send_error_json(
                HTTPStatus.UNAUTHORIZED,
                "staff_jwt_required",
                "需要有效的 STAFF JWT 才能下載卡面。",
            )
            return
        if isinstance(error, UpstreamHttpError):
            status = error.status_code
            if status == 401:
                self._send_error_json(
                    HTTPStatus.UNAUTHORIZED,
                    "staff_auth_failed",
                    "STAFF 憑證無效或已過期。",
                )
            elif status == 403:
                self._send_error_json(
                    HTTPStatus.FORBIDDEN,
                    "staff_permission_denied",
                    "此憑證沒有 STAFF 列印權限。",
                )
            elif status == 404:
                self._send_error_json(
                    HTTPStatus.NOT_FOUND,
                    "card_not_found",
                    "找不到這個列印短碼，請確認條碼後重試。",
                )
            elif status == 429:
                self._send_error_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    "upstream_busy",
                    "伺服器目前忙碌，請稍後重試。",
                )
            else:
                self._send_error_json(
                    HTTPStatus.BAD_GATEWAY,
                    "upstream_error",
                    "卡面伺服器暫時無法完成請求。",
                )
            return
        if isinstance(error, UpstreamResponseTooLargeError):
            self._send_error_json(
                HTTPStatus.BAD_GATEWAY,
                "upstream_too_large",
                f"下載的 PNG 超過 {self._png_limit_label()} 限制。",
            )
            return
        if isinstance(error, (UpstreamConnectionError, UpstreamProtocolError)):
            self._send_error_json(
                HTTPStatus.BAD_GATEWAY,
                "upstream_unavailable",
                "無法連線到卡面伺服器，請檢查網路後重試。",
            )
            return
        if isinstance(error, PngValidationError):
            status = HTTPStatus.BAD_REQUEST if document_request else HTTPStatus.BAD_GATEWAY
            code = "invalid_png" if document_request else "invalid_upstream_png"
            message = (
                "PNG 必須是直式卡面，且長寬比需符合列印模板。"
                if document_request
                else "伺服器回傳的卡面不是可列印的 PNG。"
            )
            self._send_error_json(status, code, message)
            return
        if isinstance(error, RequestEntityTooLargeError):
            if document_request:
                self._send_error_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    "png_too_large",
                    f"PNG 超過 {self._png_limit_label()} 限制。",
                )
            else:
                self._send_error_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    "request_too_large",
                    "請求內容過大。",
                )
            return
        if isinstance(error, RequestBodyRequiredError):
            self._send_error_json(
                HTTPStatus.BAD_REQUEST,
                "png_required" if document_request else "bad_request",
                "請上傳 PNG 卡面。" if document_request else "請求內容不可空白。",
            )
            return
        if isinstance(error, TimeoutError):
            self._send_error_json(
                HTTPStatus.REQUEST_TIMEOUT,
                "request_timeout",
                "請求逾時。",
            )
            return
        if isinstance(error, (TemplateValidationError, DocxBuildError)):
            LOGGER.error("Calibrated template validation/build failed: %s", type(error).__name__)
            self._send_error_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                "template_error",
                "校正版 Word 模板無法使用，請聯絡維護人員。",
            )
            return
        if isinstance(error, (UnicodeError, ValueError)):
            self._send_error_json(
                HTTPStatus.BAD_REQUEST,
                "bad_request",
                "請求格式不正確。",
            )
            return

        LOGGER.exception("Unhandled request failure")
        self._send_error_json(
            HTTPStatus.INTERNAL_SERVER_ERROR,
            "internal_error",
            "發生未預期的錯誤。",
        )

    def _png_limit_label(self) -> str:
        value = self.application.settings.max_png_bytes / (1024 * 1024)
        rendered = str(int(value)) if value.is_integer() else f"{value:.1f}"
        return f"{rendered} MiB"

    def _send_error_json(
        self,
        status: HTTPStatus,
        code: str,
        message: str,
        *,
        include_body: bool = True,
    ) -> None:
        self._send_json(
            status,
            {"status": "error", "code": code, "message": message},
            cache_control="no-store",
            include_body=include_body,
        )

    def _send_json(
        self,
        status: HTTPStatus,
        payload: Mapping[str, Any],
        *,
        cache_control: str,
        include_body: bool = True,
    ) -> None:
        body = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        self._send_bytes(
            status,
            body,
            content_type="application/json; charset=utf-8",
            cache_control=cache_control,
            include_body=include_body,
        )

    def _send_bytes(
        self,
        status: HTTPStatus,
        body: bytes,
        *,
        content_type: str,
        cache_control: str,
        extra_headers: Optional[Mapping[str, str]] = None,
        include_body: bool = True,
    ) -> None:
        # One request per connection keeps malformed or deliberately rejected
        # POST bodies from being parsed as a subsequent HTTP request.
        self.close_connection = True
        self.send_response(int(status))
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache_control)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(self)")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Connection", "close")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' blob: data:; media-src 'self' blob:; "
            "connect-src 'self'; object-src 'none'; base-uri 'none'; "
            "frame-ancestors 'none'; form-action 'self'",
        )
        if extra_headers:
            for name, value in extra_headers.items():
                self.send_header(name, value)
        self.end_headers()
        if include_body and body:
            self.wfile.write(body)


class CompanionRequestHandler(CardPrinterRequestHandler):
    """Capability-limited listener exposed only through ``adb reverse``.

    This handler intentionally has no route to the STAFF proxy, template, or
    document builder. Even a native Android process that ignores browser
    Origin rules can only read scanner state and submit one validated token.
    """

    server_version = "CardPrinterCompanion/1.0"
    _STATIC_PATHS = {
        "/phone-scanner.html",
        "/static/phone-scanner.css",
        "/static/phone-scanner.js",
        "/vendor/zxing-browser.min.js",
    }

    def setup(self) -> None:
        self.request.settimeout(5)
        super().setup()

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        try:
            target = self._parsed_target()
            self._validate_web_request(target.path)
            if target.path == "/healthz":
                self._send_json(
                    HTTPStatus.OK,
                    {"status": "ok", "service": "phone-scanner"},
                    cache_control="no-store",
                )
                return
            if target.path in {"", "/", "/phone-scanner.html"}:
                self._serve_static("/phone-scanner.html")
                return
            if target.path in self._STATIC_PATHS:
                self._serve_static(target.path)
                return
            if target.path == "/api/scanner/sessions/active":
                active = self.application.scanner_relay.active_session()
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "scanner": {
                            "available": active is not None,
                            "sessionId": (
                                active.session_id if active else None
                            ),
                            "paired": active.paired if active else False,
                            "expiresInSeconds": (
                                active.expires_in_seconds if active else 0
                            ),
                        },
                    },
                    cache_control="no-store",
                )
                return
            if target.path == "/api/scanner/device/session":
                authorization = self.headers.get("Authorization", "")
                if not authorization.startswith("Bearer "):
                    raise ScannerDeviceCapabilityError(
                        "Scanner device capability is required."
                    )
                device_capability = authorization[7:].strip()
                if not device_capability or any(
                    character in device_capability for character in "\r\n"
                ):
                    raise ScannerDeviceCapabilityError(
                        "Scanner device capability is required."
                    )
                grant = self.application.scanner_relay.claim_active_session(
                    device_capability=device_capability
                )
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "scanner": (
                            _scanner_pairing_payload(grant)
                            if grant is not None
                            else None
                        ),
                    },
                    cache_control="no-store",
                )
                return
            self._send_error_json(
                HTTPStatus.NOT_FOUND,
                "not_found",
                "找不到指定的手機掃描功能。",
            )
        except Exception as error:
            self._handle_error(error)

    def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
        try:
            target = self._parsed_target()
            self._validate_web_request(target.path)

            if target.path == "/api/scanner/pair":
                payload = self._read_json_object(max_bytes=512)
                pairing_code = payload.get("pairingCode")
                if not isinstance(pairing_code, str):
                    raise ValueError("Scanner pairing code is required.")
                grant = self.application.scanner_relay.pair(pairing_code)
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        "scanner": _scanner_pairing_payload(grant),
                    },
                    cache_control="no-store",
                )
                return

            scanner_token_match = SCANNER_SESSION_TOKEN_ROUTE.fullmatch(
                target.path
            )
            if scanner_token_match is None:
                self._send_error_json(
                    HTTPStatus.NOT_FOUND,
                    "not_found",
                    "找不到指定的手機掃描功能。",
                )
                return
            payload = self._read_json_object(max_bytes=512)
            raw_token = payload.get("token")
            if not isinstance(raw_token, str):
                raise ValueError("Scanner token is required.")
            authorization = self.headers.get("Authorization", "")
            if not authorization.startswith("Bearer "):
                raise ScannerCapabilityError(
                    "Scanner capability is required."
                )
            scanner_capability = authorization[7:].strip()
            if not scanner_capability or any(
                character in scanner_capability for character in "\r\n"
            ):
                raise ScannerCapabilityError(
                    "Scanner capability is required."
                )
            session = self.application.scanner_relay.submit_token(
                scanner_token_match.group(1),
                raw_token,
                scanner_capability=scanner_capability,
            )
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "session": _scanner_session_payload(
                        session, include_token=False
                    ),
                },
                cache_control="no-store",
            )
        except Exception as error:
            self._handle_error(error)


class RequestEntityTooLargeError(Exception):
    """The browser declared a request body larger than the configured cap."""


class RequestBodyRequiredError(ValueError):
    """A request endpoint expected a non-empty body."""


class BoundedCompanionServer(ThreadingHTTPServer):
    """Limit phone-facing request threads so ADB cannot starve the main UI."""

    request_queue_size = 8

    def __init__(self, *args: Any, max_request_threads: int = 16, **kwargs: Any):
        self._request_slots = BoundedSemaphore(max_request_threads)
        super().__init__(*args, **kwargs)

    def process_request(self, request: Any, client_address: Any) -> None:
        if not self._request_slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self._request_slots.release()
            raise

    def process_request_thread(self, request: Any, client_address: Any) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._request_slots.release()


def load_settings(environ: Optional[Mapping[str, str]] = None) -> Settings:
    source = os.environ if environ is None else environ
    api_base_url = source.get("API_BASE_URL", DEFAULT_API_BASE_URL).strip()
    raw_remote_config_url = source.get(
        "REMOTE_CONFIG_URL", DEFAULT_REMOTE_CONFIG_URL
    ).strip()
    try:
        remote_config_url = validate_remote_config_url(raw_remote_config_url)
    except RemoteConfigError as error:
        raise ConfigurationError(str(error)) from None
    staff_jwt = source.get("STAFF_JWT", "").strip() or None
    raw_hosts = source.get("CARDPRINTER_ALLOWED_API_HOSTS", "")
    allowed_hosts = tuple(
        host.strip() for host in raw_hosts.split(",") if host.strip()
    ) or None
    allow_http_api = _parse_bool(
        source.get("CARDPRINTER_ALLOW_HTTP_API", "false"),
        name="CARDPRINTER_ALLOW_HTTP_API",
    )
    if allow_http_api and allowed_hosts is None:
        raise ConfigurationError(
            "CARDPRINTER_ALLOW_HTTP_API requires CARDPRINTER_ALLOWED_API_HOSTS."
        )
    raw_web_hosts = source.get("CARDPRINTER_ALLOWED_WEB_HOSTS", "")
    allowed_web_hosts = tuple(
        dict.fromkeys(
            DEFAULT_WEB_HOSTS
            + tuple(
                _normalize_web_host(host)
                for host in raw_web_hosts.split(",")
                if host.strip()
            )
        )
    )
    max_png_bytes = _parse_int(
        source.get("CARDPRINTER_MAX_PNG_BYTES", str(DEFAULT_MAX_PNG_BYTES)),
        name="CARDPRINTER_MAX_PNG_BYTES",
        minimum=1024,
        maximum=100 * 1024 * 1024,
    )
    host = source.get("CARDPRINTER_HOST", "127.0.0.1").strip() or "127.0.0.1"
    port = _parse_int(
        source.get("CARDPRINTER_PORT", "8000"),
        name="CARDPRINTER_PORT",
        minimum=1,
        maximum=65535,
    )
    companion_host = (
        source.get("CARDPRINTER_COMPANION_HOST", "127.0.0.1").strip()
        or "127.0.0.1"
    )
    companion_port = _parse_int(
        source.get("CARDPRINTER_COMPANION_PORT", "8001"),
        name="CARDPRINTER_COMPANION_PORT",
        minimum=1,
        maximum=65535,
    )
    if host == companion_host and port == companion_port:
        raise ConfigurationError(
            "The workstation and phone-scanner listeners need different ports."
        )

    # Validate once during startup instead of failing after the first scan.
    try:
        fallback_client = UpstreamClient(
            api_base_url,
            staff_jwt,
            allowed_hosts=allowed_hosts,
            allow_http=allow_http_api,
            max_response_bytes=max_png_bytes,
        )
    except (InvalidBaseUrlError, ValueError) as error:
        raise ConfigurationError(str(error)) from None
    api_base_url = fallback_client.base_url
    explicit_development_override = allowed_hosts is not None
    if (
        not explicit_development_override
        and api_base_url != DEFAULT_API_BASE_URL
    ):
        raise ConfigurationError(
            "API_BASE_URL must use the production API unless an explicit "
            "development host allow-list is configured."
        )

    return Settings(
        api_base_url=api_base_url,
        staff_jwt=staff_jwt,
        allowed_api_hosts=allowed_hosts,
        allow_http_api=allow_http_api,
        allowed_web_hosts=allowed_web_hosts,
        max_png_bytes=max_png_bytes,
        host=host,
        port=port,
        companion_host=companion_host,
        companion_port=companion_port,
        remote_config_url=remote_config_url,
        api_base_url_source=(
            "override" if explicit_development_override else "fallback"
        ),
    )


def resolve_remote_settings(
    settings: Settings,
    *,
    opener: Optional[RemoteConfigOpenUrl] = None,
) -> Settings:
    """Resolve the App's current API before constructing ``UpstreamClient``."""

    if settings.api_base_url_source == "override":
        LOGGER.info("Explicit development API override selected; skipping Remote Config.")
        return settings
    try:
        remote_api_base_url = fetch_remote_api_base_url(
            settings.remote_config_url,
            opener=opener,
        )
    except RemoteConfigError:
        LOGGER.warning(
            "Remote App config unavailable; using the configured API fallback."
        )
        return settings
    LOGGER.info("Remote App config selected API %s", remote_api_base_url)
    return replace(
        settings,
        api_base_url=remote_api_base_url,
        api_base_url_source="remote",
    )


def load_template_bundle(
    template_path: Path = TEMPLATE_PATH,
    manifest_path: Path = TEMPLATE_MANIFEST_PATH,
) -> TemplateBundle:
    try:
        template_bytes = template_path.read_bytes()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConfigurationError("Could not load the calibrated DOCX template.") from error
    if not isinstance(manifest, dict):
        raise ConfigurationError("Template manifest must be a JSON object.")

    actual_template_hash = sha256(template_bytes).hexdigest()
    expected_template_hash = str(manifest.get("templateSha256", "")).lower()
    if actual_template_hash != expected_template_hash:
        raise ConfigurationError("Calibrated DOCX template checksum mismatch.")

    expected_parts = {
        "word/document.xml": str(manifest.get("documentXmlSha256", "")).lower(),
        "word/_rels/document.xml.rels": str(
            manifest.get("documentRelationshipsSha256", "")
        ).lower(),
    }
    try:
        with zipfile.ZipFile(template_path, "r") as package:
            for name, expected_hash in expected_parts.items():
                if sha256(package.read(name)).hexdigest() != expected_hash:
                    raise ConfigurationError(
                        f"Calibrated template part checksum mismatch: {name}."
                    )
    except (zipfile.BadZipFile, KeyError, OSError):
        raise ConfigurationError("Calibrated DOCX template is invalid.") from None

    metadata = validate_template(template_bytes)
    if metadata.image_part != manifest.get("imagePart"):
        raise ConfigurationError("Calibrated template image part changed.")
    if metadata.relationship_id != manifest.get("imageRelationshipId"):
        raise ConfigurationError("Calibrated template image relationship changed.")

    return TemplateBundle(
        document_bytes=template_bytes,
        sha256=actual_template_hash,
        metadata=metadata,
        manifest=manifest,
    )


def create_server(
    settings: Optional[Settings] = None,
    template: Optional[TemplateBundle] = None,
    *,
    upstream_client: Optional[UpstreamClient] = None,
    scanner_relay: Optional[ScannerRelay] = None,
    static_directory: Path = STATIC_DIR,
) -> ThreadingHTTPServer:
    resolved_settings = settings or load_settings()
    resolved_template = template or load_template_bundle()
    application = CardPrinterApplication(
        resolved_settings,
        resolved_template,
        upstream_client=upstream_client,
        scanner_relay=scanner_relay,
    )
    handler = partial(
        CardPrinterRequestHandler,
        application=application,
        static_directory=static_directory,
    )
    server = ThreadingHTTPServer(
        (resolved_settings.host, resolved_settings.port), handler
    )
    server.daemon_threads = True
    server.cardprinter_application = application  # type: ignore[attr-defined]
    return server


def create_companion_server(
    scanner_relay: ScannerRelay,
    *,
    allowed_web_hosts: Sequence[str] = DEFAULT_WEB_HOSTS,
    host: str = "127.0.0.1",
    port: int = 8001,
    static_directory: Path = STATIC_DIR,
) -> ThreadingHTTPServer:
    """Create the capability-limited listener used by ``adb reverse``."""

    application = CompanionApplication(
        settings=CompanionSettings(
            allowed_web_hosts=tuple(allowed_web_hosts),
        ),
        scanner_relay=scanner_relay,
    )
    handler = partial(
        CompanionRequestHandler,
        application=application,
        static_directory=static_directory,
    )
    server = BoundedCompanionServer(
        (host, port),
        handler,
    )
    server.daemon_threads = True
    server.cardprinter_application = application  # type: ignore[attr-defined]
    return server


def _scanner_session_payload(
    session: ScannerSessionSnapshot,
    *,
    include_token: bool = True,
    include_pairing_code: bool = False,
) -> dict[str, Any]:
    return {
        "id": session.session_id,
        "expiresInSeconds": session.expires_in_seconds,
        "token": session.token if include_token else None,
        "paired": session.paired,
        "pairingCode": (
            session.pairing_code if include_pairing_code else None
        ),
    }


def _scanner_pairing_payload(grant: ScannerPairingGrant) -> dict[str, Any]:
    return {
        "sessionId": grant.session_id,
        "capability": grant.scanner_capability,
        "expiresInSeconds": grant.expires_in_seconds,
    }


def _scanner_device_payload(grant: ScannerDeviceGrant) -> dict[str, Any]:
    return {
        "capability": grant.device_capability,
        "expiresInSeconds": grant.expires_in_seconds,
    }


def _safe_download_stem(value: str) -> str:
    normalized = str(value).strip().replace("\\", "-").replace("/", "-")
    normalized = normalized.removesuffix(".docx").removesuffix(".png")
    normalized = SAFE_DOWNLOAD_STEM.sub("-", normalized).strip("-_")
    if not normalized:
        normalized = "hitcon-print-card"
    return normalized[:MAX_DOWNLOAD_STEM_LENGTH]


def _normalize_web_host(value: str) -> str:
    normalized = str(value).strip().lower().rstrip(".")
    if normalized.startswith("[") and normalized.endswith("]"):
        normalized = normalized[1:-1]
    if not normalized or any(character.isspace() for character in normalized):
        raise ConfigurationError("CARDPRINTER_ALLOWED_WEB_HOSTS is invalid.")
    try:
        return ipaddress.ip_address(normalized).compressed.lower()
    except ValueError:
        if WEB_HOSTNAME.fullmatch(normalized) is None:
            raise ConfigurationError(
                "CARDPRINTER_ALLOWED_WEB_HOSTS is invalid."
            ) from None
        return normalized


def _parse_request_authority(value: str) -> tuple[str, Optional[int]]:
    raw = str(value).strip()
    if (
        not raw
        or len(raw) > 255
        or any(character.isspace() for character in raw)
        or any(character in raw for character in "/\\?#@,")
    ):
        raise ForbiddenWebOriginError("Request host is invalid.")
    try:
        parsed = urlsplit("//" + raw)
        host_name = _normalize_web_host(parsed.hostname or "")
        port = parsed.port
    except (ConfigurationError, ValueError):
        raise ForbiddenWebOriginError("Request host is invalid.") from None
    if parsed.username is not None or parsed.password is not None or parsed.path:
        raise ForbiddenWebOriginError("Request host is invalid.")
    return host_name, port


def _parse_bool(value: str, *, name: str) -> bool:
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off", ""}:
        return False
    raise ConfigurationError(f"{name} must be true or false.")


def _parse_int(
    value: str, *, name: str, minimum: int, maximum: int
) -> int:
    try:
        parsed = int(str(value).strip())
    except ValueError:
        raise ConfigurationError(f"{name} must be an integer.") from None
    if not minimum <= parsed <= maximum:
        raise ConfigurationError(
            f"{name} must be between {minimum} and {maximum}."
        )
    return parsed


def main() -> int:
    logging.basicConfig(
        level=os.environ.get("CARDPRINTER_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    server: Optional[ThreadingHTTPServer] = None
    companion_server: Optional[ThreadingHTTPServer] = None
    try:
        settings = resolve_remote_settings(load_settings())
        template = load_template_bundle()
        relay = ScannerRelay()
        server = create_server(
            settings,
            template,
            scanner_relay=relay,
        )
        companion_server = create_companion_server(
            relay,
            allowed_web_hosts=settings.allowed_web_hosts,
            host=settings.companion_host,
            port=settings.companion_port,
        )
    except (ConfigurationError, TemplateValidationError, OSError) as error:
        if companion_server is not None:
            companion_server.server_close()
        if server is not None:
            server.server_close()
        LOGGER.error("Startup failed: %s", error)
        return 1

    address, port = server.server_address[:2]
    LOGGER.info("CardPrinter listening on http://%s:%s", address, port)
    companion_address, companion_port = companion_server.server_address[:2]
    LOGGER.info(
        "Phone scanner companion listening on http://%s:%s",
        companion_address,
        companion_port,
    )
    companion_thread = Thread(
        target=companion_server.serve_forever,
        kwargs={"poll_interval": 0.5},
        name="cardprinter-phone-scanner",
        daemon=True,
    )
    companion_thread.start()
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        LOGGER.info("Stopping CardPrinter")
    finally:
        companion_server.shutdown()
        companion_server.server_close()
        companion_thread.join(timeout=2)
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
