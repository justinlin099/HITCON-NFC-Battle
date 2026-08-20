from __future__ import annotations

from io import BytesIO
import json
import unittest
from urllib.error import HTTPError, URLError

from app.remote_config import (
    DEFAULT_REMOTE_CONFIG_URL,
    REMOTE_CONFIG_MAX_BYTES,
    REMOTE_CONFIG_TIMEOUT_SECONDS,
    RemoteConfigError,
    fetch_remote_api_base_url,
    validate_remote_config_url,
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
        self.headers = {
            "Content-Type": "application/json; charset=utf-8",
            **(headers or {}),
        }
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


def config_body(**overrides) -> bytes:
    document = {
        "schema": 1,
        "api_base_url": "https://nfc-battle-api.hitcon2026.online/",
        **overrides,
    }
    return json.dumps(document).encode("utf-8")


class RemoteConfigUrlTests(unittest.TestCase):
    def test_accepts_only_canonical_document_and_normalizes_default_port(self):
        self.assertEqual(
            validate_remote_config_url(DEFAULT_REMOTE_CONFIG_URL),
            DEFAULT_REMOTE_CONFIG_URL,
        )
        self.assertEqual(
            validate_remote_config_url(
                " HTTPS://GAME.HITCON2026.ONLINE:443/"
                ".well-known/nfc-battle-app-config.json "
            ),
            DEFAULT_REMOTE_CONFIG_URL,
        )

    def test_rejects_other_origins_paths_ports_and_ambiguous_urls(self):
        invalid = (
            "http://game.hitcon2026.online/.well-known/nfc-battle-app-config.json",
            "https://evil.hitcon2026.online/.well-known/nfc-battle-app-config.json",
            "https://game.hitcon2026.online:444/.well-known/nfc-battle-app-config.json",
            "https://game.hitcon2026.online./.well-known/nfc-battle-app-config.json",
            "https://user:pass@game.hitcon2026.online/.well-known/nfc-battle-app-config.json",
            "https://game.hitcon2026.online/.well-known/other.json",
            "https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json?x=1",
            "https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json#x",
            "https://game.hitcon2026.online\\@evil.example/.well-known/nfc-battle-app-config.json",
            "",
        )
        for url in invalid:
            with self.subTest(url=url):
                with self.assertRaises(RemoteConfigError):
                    validate_remote_config_url(url)


class RemoteConfigFetchTests(unittest.TestCase):
    def test_uses_exact_get_timeout_and_public_headers_only(self):
        response = FakeResponse(config_body(), max_chunk_size=5)
        opener = CapturingOpener(response)

        result = fetch_remote_api_base_url(opener=opener)

        self.assertEqual(
            result, "https://nfc-battle-api.hitcon2026.online"
        )
        self.assertTrue(response.closed)
        self.assertEqual(len(opener.calls), 1)
        request, timeout = opener.calls[0]
        self.assertEqual(request.full_url, DEFAULT_REMOTE_CONFIG_URL)
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(timeout, REMOTE_CONFIG_TIMEOUT_SECONDS)
        self.assertEqual(request.get_header("Accept"), "application/json")
        self.assertEqual(request.get_header("Accept-encoding"), "identity")
        self.assertEqual(
            request.get_header("Cache-control"), "no-cache, no-store"
        )
        self.assertIsNone(request.get_header("Authorization"))
        self.assertIsNone(request.get_header("Cookie"))

    def test_custom_timeout_and_exact_size_limit_are_honored(self):
        body = config_body(padding="x" * 30)
        opener = CapturingOpener(FakeResponse(body, max_chunk_size=3))
        result = fetch_remote_api_base_url(
            opener=opener,
            timeout=1.25,
            max_bytes=len(body),
        )
        self.assertEqual(result, "https://nfc-battle-api.hitcon2026.online")
        self.assertEqual(opener.calls[0][1], 1.25)

    def test_rejects_declared_or_streamed_body_over_size_limit(self):
        for response in (
            FakeResponse(
                config_body(),
                headers={"Content-Length": str(REMOTE_CONFIG_MAX_BYTES + 1)},
            ),
            FakeResponse(b"x" * 11, max_chunk_size=2),
        ):
            with self.subTest(headers=response.headers):
                with self.assertRaisesRegex(RemoteConfigError, "too large"):
                    fetch_remote_api_base_url(
                        opener=CapturingOpener(response),
                        max_bytes=10,
                    )
                self.assertTrue(response.closed)

    def test_rejects_non_200_including_redirect_status(self):
        for status in (201, 204, 302, 404, 500):
            response = FakeResponse(config_body(), status=status)
            with self.subTest(status=status):
                with self.assertRaisesRegex(RemoteConfigError, "non-200"):
                    fetch_remote_api_base_url(
                        opener=CapturingOpener(response)
                    )
                self.assertTrue(response.closed)

    def test_rejects_non_json_content_type_invalid_utf8_and_invalid_json(self):
        cases = (
            FakeResponse(config_body(), headers={"Content-Type": "text/html"}),
            FakeResponse(config_body(), headers={"Content-Encoding": "gzip"}),
            FakeResponse(b"\xff"),
            FakeResponse(b"{"),
            FakeResponse(
                b'{"schema":1,"schema":1,'
                b'"api_base_url":"https://nfc-battle-api.hitcon2026.online"}'
            ),
        )
        for response in cases:
            with self.subTest(body=response._stream.getvalue()):
                with self.assertRaises(RemoteConfigError):
                    fetch_remote_api_base_url(
                        opener=CapturingOpener(response)
                    )

    def test_requires_schema_one_as_an_integer(self):
        for schema in (None, True, 0, 2, "1"):
            with self.subTest(schema=schema):
                with self.assertRaisesRegex(RemoteConfigError, "schema"):
                    fetch_remote_api_base_url(
                        opener=CapturingOpener(
                            FakeResponse(config_body(schema=schema))
                        )
                    )

    def test_requires_a_nonempty_trusted_api_base_url(self):
        invalid = (
            None,
            "",
            "http://nfc-battle-api.hitcon2026.online",
            "https://example.com",
            "https://nfc-battle-api.hitcon2026.online.",
            "https://hitcon2026.online:8443",
            "https://hitcon2026.online/a/../b",
            "https://hitcon2026.online/a/%2e%2e/b",
            "https://hitcon2026.online/a/%2f/b",
        )
        for api_base_url in invalid:
            with self.subTest(api_base_url=api_base_url):
                with self.assertRaises(RemoteConfigError):
                    fetch_remote_api_base_url(
                        opener=CapturingOpener(
                            FakeResponse(
                                config_body(api_base_url=api_base_url)
                            )
                        )
                    )

    def test_accepts_app_trusted_subdomain_and_safe_base_path(self):
        result = fetch_remote_api_base_url(
            opener=CapturingOpener(
                FakeResponse(
                    config_body(
                        api_base_url="https://future-api.hitcon2026.online/v1/"
                    )
                )
            )
        )
        self.assertEqual(result, "https://future-api.hitcon2026.online/v1")

    def test_transport_errors_are_typed_and_do_not_retain_details(self):
        secret = "must-not-leak"

        for exception in (
            URLError(secret),
            TimeoutError(secret),
            HTTPError(DEFAULT_REMOTE_CONFIG_URL, 302, secret, {}, None),
            RuntimeError(secret),
        ):
            def fail(request, *, timeout, error=exception):
                raise error

            with self.subTest(exception=type(exception).__name__):
                with self.assertRaises(RemoteConfigError) as caught:
                    fetch_remote_api_base_url(opener=fail)
                self.assertNotIn(secret, str(caught.exception))
                self.assertIsNone(caught.exception.__cause__)

    def test_rejects_nonpositive_timeout_and_size_before_opening(self):
        opener = CapturingOpener(FakeResponse(config_body()))
        with self.assertRaises(ValueError):
            fetch_remote_api_base_url(opener=opener, timeout=0)
        with self.assertRaises(ValueError):
            fetch_remote_api_base_url(opener=opener, max_bytes=0)
        self.assertEqual(opener.calls, [])


if __name__ == "__main__":
    unittest.main()
