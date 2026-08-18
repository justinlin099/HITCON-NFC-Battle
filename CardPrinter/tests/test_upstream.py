from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
import threading
import unittest
from urllib.error import HTTPError

from app.upstream import (
    InvalidBaseUrlError,
    InvalidTokenError,
    MissingStaffJwtError,
    UpstreamClient,
    UpstreamConnectionError,
    UpstreamHttpError,
    UpstreamResponseTooLargeError,
    normalize_print_token,
    validate_api_base_url,
)


class FakeResponse:
    def __init__(
        self,
        body: bytes,
        *,
        status: int = 200,
        headers=None,
        max_chunk_size=None,
    ) -> None:
        self.status = status
        self.headers = headers or {}
        self._stream = BytesIO(body)
        self._max_chunk_size = max_chunk_size
        self.closed = False

    def read(self, size=-1):
        if self._max_chunk_size is not None and size >= 0:
            size = min(size, self._max_chunk_size)
        return self._stream.read(size)

    def close(self):
        self.closed = True


class CapturingOpener:
    def __init__(self, response: FakeResponse) -> None:
        self.response = response
        self.calls = []

    def __call__(self, request, *, timeout):
        self.calls.append((request, timeout))
        return self.response


class TokenTests(unittest.TestCase):
    def test_accepts_app_short_token_alphabet_and_bounds(self):
        self.assertEqual(normalize_print_token("  Abc_12-3  "), "Abc_12-3")
        self.assertEqual(normalize_print_token("a" * 8), "a" * 8)
        self.assertEqual(normalize_print_token("Z" * 32), "Z" * 32)

    def test_rejects_wrong_length_or_characters(self):
        for token in ("a" * 7, "a" * 33, "abcd/1234", "abcd.1234", ""):
            with self.subTest(token=token):
                with self.assertRaises(InvalidTokenError):
                    normalize_print_token(token)


class BaseUrlTests(unittest.TestCase):
    def test_accepts_official_origin_and_subdomains(self):
        self.assertEqual(
            validate_api_base_url("https://hitcon2026.online/"),
            "https://hitcon2026.online",
        )
        self.assertEqual(
            validate_api_base_url(
                "https://nfc-battle-staging.hitcon2026.online/v1/"
            ),
            "https://nfc-battle-staging.hitcon2026.online/v1",
        )

    def test_rejects_untrusted_or_ambiguous_urls(self):
        invalid = (
            "http://nfc-battle-staging.hitcon2026.online",
            "https://hitcon2026.online.example.com",
            "https://example-hitcon2026.online",
            "https://user:pass@hitcon2026.online",
            "https://hitcon2026.online?next=evil",
            "https://hitcon2026.online#fragment",
            "https://hitcon2026.online\\@evil.example",
            "ftp://hitcon2026.online",
        )
        for url in invalid:
            with self.subTest(url=url):
                with self.assertRaises(InvalidBaseUrlError):
                    validate_api_base_url(url)

    def test_test_host_requires_explicit_host_and_http_opt_in(self):
        url = "http://127.0.0.1:8765/api/"
        with self.assertRaises(InvalidBaseUrlError):
            validate_api_base_url(url, allow_http=True)
        with self.assertRaises(InvalidBaseUrlError):
            validate_api_base_url(url, allowed_hosts={"127.0.0.1"})
        self.assertEqual(
            validate_api_base_url(
                url,
                allowed_hosts={"127.0.0.1"},
                allow_http=True,
            ),
            "http://127.0.0.1:8765/api",
        )


class DownloadTests(unittest.TestCase):
    def make_client(self, opener, **kwargs):
        return UpstreamClient(
            "http://127.0.0.1:8765/api/",
            allowed_hosts={"127.0.0.1"},
            allow_http=True,
            opener=opener,
            **kwargs,
        )

    def test_builds_fixed_get_with_required_headers_and_timeout(self):
        response = FakeResponse(b"png-bytes", max_chunk_size=3)
        opener = CapturingOpener(response)
        client = self.make_client(opener, staff_jwt="default-secret")

        body = client.download_print_card("Abc_12-3")

        self.assertEqual(body, b"png-bytes")
        self.assertTrue(response.closed)
        self.assertEqual(len(opener.calls), 1)
        request, timeout = opener.calls[0]
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(
            request.full_url,
            "http://127.0.0.1:8765/api/staff/print-cards/Abc_12-3",
        )
        self.assertEqual(request.get_header("Accept"), "image/png")
        self.assertEqual(
            request.get_header("Authorization"), "Bearer default-secret"
        )
        self.assertEqual(
            request.get_header("User-agent"),
            "HITCON-NFC-Battle-CardPrinter/1.0",
        )
        self.assertEqual(timeout, 20.0)

    def test_per_call_jwt_overrides_constructor_value(self):
        response = FakeResponse(b"ok")
        opener = CapturingOpener(response)
        client = self.make_client(opener, staff_jwt="old-secret")
        client.download_print_card("12345678", staff_jwt="new-secret")
        request, _ = opener.calls[0]
        self.assertEqual(
            request.get_header("Authorization"), "Bearer new-secret"
        )

    def test_requires_a_staff_jwt(self):
        opener = CapturingOpener(FakeResponse(b"unused"))
        client = self.make_client(opener)
        with self.assertRaises(MissingStaffJwtError):
            client.download_print_card("12345678")
        self.assertEqual(opener.calls, [])

    def test_rejects_content_length_over_limit_before_reading(self):
        response = FakeResponse(
            b"not-read",
            headers={"Content-Length": "11"},
        )
        client = self.make_client(
            CapturingOpener(response),
            staff_jwt="secret",
            max_response_bytes=10,
        )
        with self.assertRaises(UpstreamResponseTooLargeError):
            client.download_print_card("12345678")

    def test_streaming_cap_applies_without_content_length(self):
        response = FakeResponse(b"01234567890", max_chunk_size=4)
        client = self.make_client(
            CapturingOpener(response),
            staff_jwt="secret",
            max_response_bytes=10,
        )
        with self.assertRaises(UpstreamResponseTooLargeError):
            client.download_print_card("12345678")

    def test_exact_size_limit_is_accepted(self):
        response = FakeResponse(b"0123456789", max_chunk_size=4)
        client = self.make_client(
            CapturingOpener(response),
            staff_jwt="secret",
            max_response_bytes=10,
        )
        self.assertEqual(client.download_print_card("12345678"), b"0123456789")

    def test_non_2xx_response_becomes_typed_error(self):
        client = self.make_client(
            CapturingOpener(FakeResponse(b"denied", status=403)),
            staff_jwt="secret",
        )
        with self.assertRaises(UpstreamHttpError) as caught:
            client.download_print_card("12345678")
        self.assertEqual(caught.exception.status_code, 403)

    def test_http_error_does_not_leak_jwt(self):
        secret = "super-secret-staff-jwt"

        def fail(request, *, timeout):
            raise HTTPError(request.full_url, 401, secret, {}, None)

        client = self.make_client(fail, staff_jwt=secret)
        with self.assertRaises(UpstreamHttpError) as caught:
            client.download_print_card("12345678")
        rendered = str(caught.exception) + repr(caught.exception)
        self.assertNotIn(secret, rendered)
        self.assertIsNone(caught.exception.__cause__)

    def test_arbitrary_transport_error_does_not_leak_jwt(self):
        secret = "transport-secret"

        def fail(request, *, timeout):
            raise RuntimeError(secret)

        client = self.make_client(fail, staff_jwt=secret)
        with self.assertRaises(UpstreamConnectionError) as caught:
            client.download_print_card("12345678")
        self.assertNotIn(secret, str(caught.exception))
        self.assertIsNone(caught.exception.__cause__)

    def test_default_opener_rejects_redirect_without_forwarding_jwt(self):
        received_authorization = []

        class CaptureHandler(BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802 - stdlib callback name
                received_authorization.append(
                    self.headers.get("Authorization")
                )
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"ok")

            def log_message(self, format, *args):
                pass

        capture = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        capture_thread = threading.Thread(
            target=capture.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        capture_thread.start()
        capture_port = capture.server_address[1]
        redirect_target = f"http://127.0.0.1:{capture_port}/stolen"

        class RedirectHandler(BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802 - stdlib callback name
                self.send_response(302)
                self.send_header("Location", redirect_target)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, format, *args):
                pass

        redirect = ThreadingHTTPServer(("127.0.0.1", 0), RedirectHandler)
        redirect_thread = threading.Thread(
            target=redirect.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        redirect_thread.start()

        try:
            client = UpstreamClient(
                f"http://127.0.0.1:{redirect.server_address[1]}",
                "redirect-secret",
                allowed_hosts={"127.0.0.1"},
                allow_http=True,
            )
            with self.assertRaises(UpstreamHttpError) as caught:
                client.download_print_card("12345678")
            self.assertEqual(caught.exception.status_code, 302)
            self.assertEqual(received_authorization, [])
        finally:
            redirect.shutdown()
            redirect.server_close()
            redirect_thread.join(timeout=2)
            capture.shutdown()
            capture.server_close()
            capture_thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
