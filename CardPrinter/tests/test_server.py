from __future__ import annotations

import binascii
from http.client import HTTPConnection
import json
from pathlib import Path
import struct
import threading
import unittest
from urllib.parse import quote
import zipfile
from io import BytesIO
import zlib

from app.docx_template import IMAGE_PART
from app.server import (
    DOCX_CONTENT_TYPE,
    CardPrinterApplication,
    ConfigurationError,
    Settings,
    create_companion_server,
    create_server,
    load_settings,
    load_template_bundle,
)
from app.scanner_relay import ScannerRelay
from app.upstream import UpstreamHttpError


def _chunk(chunk_type: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type + data) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", checksum)
    )


def valid_png(width: int = 456, height: int = 720) -> bytes:
    pixel = b"\x20\x90\xe0\xff"
    scanline = b"\x00" + pixel * width
    raw = scanline * height
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(raw, level=9))
        + _chunk(b"IEND", b"")
    )


class FakeUpstream:
    def __init__(self, body: bytes, error: Exception | None = None) -> None:
        self.body = body
        self.error = error
        self.calls: list[tuple[str, str | None]] = []

    def download_print_card(
        self, token: str, *, staff_jwt: str | None = None
    ) -> bytes:
        self.calls.append((token, staff_jwt))
        if self.error is not None:
            raise self.error
        return self.body


def settings(*, staff_jwt: str | None = None) -> Settings:
    return Settings(
        api_base_url="https://nfc-battle-staging.hitcon2026.online",
        staff_jwt=staff_jwt,
        allowed_api_hosts=None,
        allow_http_api=False,
        allowed_web_hosts=("localhost", "127.0.0.1", "::1"),
        max_png_bytes=10 * 1024 * 1024,
        host="127.0.0.1",
        port=0,
        companion_host="127.0.0.1",
        companion_port=0,
    )


class TemplateIntegrationTests(unittest.TestCase):
    def test_checked_in_template_matches_manifest_and_anchor(self):
        bundle = load_template_bundle()
        self.assertEqual(
            bundle.sha256,
            "b78877fc7e7f2b8ea8413ec727c44e71de0b6066576d8c14697e3daddefb01a1",
        )
        self.assertEqual(bundle.metadata.relationship_id, "rId6")
        self.assertEqual(bundle.metadata.anchor_kind, "anchor")
        self.assertEqual(
            (bundle.metadata.anchor_width, bundle.metadata.anchor_height),
            (1_895_475, 2_995_295),
        )

    def test_generated_document_changes_only_the_png_part(self):
        bundle = load_template_bundle()
        replacement = valid_png()
        application = CardPrinterApplication(
            settings(), bundle, upstream_client=FakeUpstream(replacement)
        )
        result = application.make_document(replacement)

        with zipfile.ZipFile(BytesIO(bundle.document_bytes), "r") as source:
            source_parts = {name: source.read(name) for name in source.namelist()}
        with zipfile.ZipFile(BytesIO(result), "r") as generated:
            self.assertEqual(generated.read(IMAGE_PART), replacement)
            for name, original in source_parts.items():
                if name != IMAGE_PART:
                    self.assertEqual(generated.read(name), original, name)


class SettingsTests(unittest.TestCase):
    def test_blank_server_jwt_selects_in_memory_browser_auth(self):
        loaded = load_settings({"STAFF_JWT": ""})
        self.assertEqual(loaded.auth_mode, "browser")
        self.assertEqual(loaded.host, "127.0.0.1")
        self.assertEqual(loaded.companion_host, "127.0.0.1")
        self.assertEqual(loaded.companion_port, 8001)
        self.assertIn("localhost", loaded.allowed_web_hosts)

    def test_rejects_same_address_for_privileged_and_companion_listeners(self):
        with self.assertRaisesRegex(
            ConfigurationError, "listeners need different ports"
        ):
            load_settings(
                {
                    "CARDPRINTER_HOST": "127.0.0.1",
                    "CARDPRINTER_PORT": "8000",
                    "CARDPRINTER_COMPANION_HOST": "127.0.0.1",
                    "CARDPRINTER_COMPANION_PORT": "8000",
                }
            )

    def test_server_jwt_selects_server_auth_without_exposing_value(self):
        loaded = load_settings({"STAFF_JWT": "secret"})
        bundle = load_template_bundle()
        public = CardPrinterApplication(
            loaded, bundle, upstream_client=FakeUpstream(valid_png())
        ).public_config()
        self.assertEqual(public["authMode"], "server")
        self.assertNotIn("secret", json.dumps(public))


class HttpApiTests(unittest.TestCase):
    def setUp(self):
        self.png = valid_png()
        self.fake_upstream = FakeUpstream(self.png)
        self.scanner_relay = ScannerRelay()
        self.server = create_server(
            settings(),
            load_template_bundle(),
            upstream_client=self.fake_upstream,
            scanner_relay=self.scanner_relay,
        )
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        self.thread.start()
        self.port = self.server.server_address[1]

        self.companion_server = create_companion_server(
            self.scanner_relay,
            allowed_web_hosts=settings().allowed_web_hosts,
            host="127.0.0.1",
            port=0,
        )
        self.companion_thread = threading.Thread(
            target=self.companion_server.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        self.companion_thread.start()
        self.companion_port = self.companion_server.server_address[1]

    def tearDown(self):
        self.companion_server.shutdown()
        self.companion_server.server_close()
        self.companion_thread.join(timeout=2)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method: str, path: str, body=None, headers=None):
        connection = HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        response_body = response.read()
        response_headers = dict(response.getheaders())
        connection.close()
        return response.status, response_headers, response_body

    def companion_request(
        self, method: str, path: str, body=None, headers=None
    ):
        connection = HTTPConnection(
            "127.0.0.1", self.companion_port, timeout=5
        )
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        response_body = response.read()
        response_headers = dict(response.getheaders())
        connection.close()
        return response.status, response_headers, response_body

    def test_config_and_static_responses_include_camera_security_policy(self):
        status, headers, body = self.request("GET", "/api/config")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["authMode"], "browser")
        self.assertEqual(headers["Permissions-Policy"], "camera=(self)")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Connection"], "close")

        status, headers, body = self.request("GET", "/static/app.js")
        self.assertEqual(status, 200)
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertIn(b"BarcodeDetector", body)

    def test_png_proxy_requires_jwt_and_forwards_it_only_in_memory(self):
        token = "Abc_12-3"
        status, _, body = self.request(
            "GET", f"/api/cards/{quote(token)}/png"
        )
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(body)["code"], "staff_jwt_required")

        status, headers, body = self.request(
            "GET",
            f"/api/cards/{quote(token)}/png",
            headers={
                "Authorization": "Bearer browser-secret",
                "Host": f"127.0.0.1:{self.port}",
                "Origin": f"http://127.0.0.1:{self.port}",
                "Sec-Fetch-Site": "same-origin",
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "image/png")
        self.assertEqual(body, self.png)
        self.assertEqual(
            self.fake_upstream.calls,
            [(token, "browser-secret")],
        )

    def test_access_log_redacts_the_print_token(self):
        token = "Secret_1234"
        with self.assertLogs("cardprinter", level="INFO") as captured:
            status, _, _ = self.request(
                "GET",
                f"/api/cards/{token}/png",
                headers={"Authorization": "Bearer browser-secret"},
            )
        self.assertEqual(status, 200)
        rendered = "\n".join(captured.output)
        self.assertNotIn(token, rendered)
        self.assertIn("/api/cards/[redacted]/png", rendered)

    def test_document_endpoint_returns_downloadable_docx(self):
        name = "hitcon-print-card-Abc_12-3"
        status, headers, body = self.request(
            "POST",
            "/api/documents?name=" + quote(name),
            body=self.png,
            headers={
                "Content-Type": "image/png",
                "Content-Length": str(len(self.png)),
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], DOCX_CONTENT_TYPE)
        self.assertEqual(
            headers["Content-Disposition"],
            f'attachment; filename="{name}.docx"',
        )
        with zipfile.ZipFile(BytesIO(body), "r") as generated:
            self.assertEqual(generated.read(IMAGE_PART), self.png)

    def test_phone_scanner_session_relays_only_a_normalized_token(self):
        status, _, body = self.request("POST", "/api/scanner/sessions")
        self.assertEqual(status, 201)
        created = json.loads(body)["session"]
        session_id = created["id"]
        pairing_code = created["pairingCode"]
        self.assertRegex(session_id, r"^[A-Za-z0-9_-]{20,40}$")
        self.assertRegex(pairing_code, r"^[A-Z2-9]{10}$")
        self.assertIsNone(created["token"])

        status, _, body = self.companion_request(
            "GET", "/api/scanner/sessions/active"
        )
        self.assertEqual(status, 200)
        active = json.loads(body)["scanner"]
        self.assertTrue(active["available"])
        self.assertFalse(active["paired"])

        pair_body = json.dumps({"pairingCode": pairing_code}).encode(
            "utf-8"
        )
        status, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=pair_body,
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 200)
        pairing = json.loads(body)["scanner"]
        self.assertEqual(pairing["sessionId"], session_id)
        capability = pairing["capability"]

        encoded = json.dumps({"token": "  Abcd_1234  "}).encode("utf-8")
        with self.assertLogs("cardprinter", level="INFO") as captured:
            status, _, body = self.companion_request(
                "POST",
                f"/api/scanner/sessions/{session_id}/token",
                body=encoded,
                headers={
                    "Authorization": f"Bearer {capability}",
                    "Content-Type": "application/json",
                    "Content-Length": str(len(encoded)),
                },
            )
        self.assertEqual(status, 200)
        self.assertNotIn(session_id, "\n".join(captured.output))

        status, _, body = self.request(
            "GET", f"/api/scanner/sessions/{session_id}"
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["session"]["token"], "Abcd_1234")

        status, _, _ = self.request(
            "POST", f"/api/scanner/sessions/{session_id}/close"
        )
        self.assertEqual(status, 200)
        status, _, body = self.request(
            "GET", f"/api/scanner/sessions/{session_id}"
        )
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(body)["code"], "scanner_session_expired")

    def test_usb_device_auto_pairs_without_a_per_card_code(self):
        status, _, body = self.request("POST", "/api/scanner/devices")
        self.assertEqual(status, 201)
        device = json.loads(body)["device"]
        device_capability = device["capability"]
        self.assertRegex(device_capability, r"^[A-Za-z0-9_-]{40,60}$")
        self.assertGreater(device["expiresInSeconds"], 0)

        status, _, body = self.companion_request(
            "GET",
            "/api/scanner/device/session",
            headers={"Authorization": f"Bearer {device_capability}"},
        )
        self.assertEqual(status, 200)
        self.assertIsNone(json.loads(body)["scanner"])

        _, _, body = self.request("POST", "/api/scanner/sessions")
        session_id = json.loads(body)["session"]["id"]
        status, _, body = self.companion_request(
            "GET",
            "/api/scanner/device/session",
            headers={"Authorization": f"Bearer {device_capability}"},
        )
        self.assertEqual(status, 200)
        grant = json.loads(body)["scanner"]
        self.assertEqual(grant["sessionId"], session_id)

        # Polling is idempotent for the same USB phone and card session.
        _, _, repeated_body = self.companion_request(
            "GET",
            "/api/scanner/device/session",
            headers={"Authorization": f"Bearer {device_capability}"},
        )
        repeated = json.loads(repeated_body)["scanner"]
        self.assertEqual(repeated["sessionId"], grant["sessionId"])
        self.assertEqual(repeated["capability"], grant["capability"])

        encoded = json.dumps({"token": "Abcd_1234"}).encode("utf-8")
        status, _, _ = self.companion_request(
            "POST",
            f"/api/scanner/sessions/{session_id}/token",
            body=encoded,
            headers={
                "Authorization": f'Bearer {grant["capability"]}',
                "Content-Type": "application/json",
            },
        )
        self.assertEqual(status, 200)
        _, _, body = self.request(
            "GET", f"/api/scanner/sessions/{session_id}"
        )
        self.assertEqual(json.loads(body)["session"]["token"], "Abcd_1234")

        # A consumed card is not offered again; the device keeps waiting.
        _, _, body = self.companion_request(
            "GET",
            "/api/scanner/device/session",
            headers={"Authorization": f"Bearer {device_capability}"},
        )
        self.assertIsNone(json.loads(body)["scanner"])

    def test_usb_device_capability_is_isolated_and_replaceable(self):
        _, _, body = self.request("POST", "/api/scanner/devices")
        old_capability = json.loads(body)["device"]["capability"]
        self.request("POST", "/api/scanner/sessions")
        _, _, body = self.request("POST", "/api/scanner/devices")
        new_capability = json.loads(body)["device"]["capability"]

        for invalid in (
            old_capability,
            "é" * len(new_capability),
        ):
            status, _, body = self.companion_request(
                "GET",
                "/api/scanner/device/session",
                headers={"Authorization": f"Bearer {invalid}"},
            )
            self.assertEqual(status, 403)
            self.assertEqual(
                json.loads(body)["code"],
                "scanner_device_not_authorized",
            )

        status, _, _ = self.companion_request(
            "POST", "/api/scanner/devices"
        )
        self.assertEqual(status, 404)

    def test_phone_scanner_rejects_invalid_json_and_token(self):
        _, _, body = self.request("POST", "/api/scanner/sessions")
        created = json.loads(body)["session"]
        session_id = created["id"]
        pair_body = json.dumps(
            {"pairingCode": created["pairingCode"]}
        ).encode("utf-8")
        _, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=pair_body,
            headers={"Content-Type": "application/json"},
        )
        capability = json.loads(body)["scanner"]["capability"]

        status, _, body = self.companion_request(
            "POST",
            f"/api/scanner/sessions/{session_id}/token",
            body=b'{"token":"not a barcode"}',
            headers={
                "Authorization": f"Bearer {capability}",
                "Content-Type": "application/json",
            },
        )
        self.assertEqual(status, 400)
        self.assertEqual(json.loads(body)["code"], "invalid_token")

        status, _, body = self.companion_request(
            "POST",
            f"/api/scanner/sessions/{session_id}/token",
            body=b"{}",
            headers={
                "Authorization": f"Bearer {capability}",
                "Content-Type": "application/json",
            },
        )
        self.assertEqual(status, 400)
        self.assertEqual(json.loads(body)["code"], "bad_request")

    def test_companion_listener_cannot_reach_privileged_routes(self):
        companion_application = self.companion_server.cardprinter_application
        self.assertFalse(hasattr(companion_application, "upstream"))
        self.assertFalse(hasattr(companion_application.settings, "staff_jwt"))

        status, headers, body = self.companion_request("GET", "/")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Permissions-Policy"], "camera=(self)")
        self.assertIn(b"phone-scanner.js", body)
        status, _, body = self.companion_request(
            "GET", "/static/phone-scanner.js"
        )
        self.assertEqual(status, 200)
        self.assertIn(b"BarcodeDetector", body)

        for method, path in (
            ("GET", "/api/config"),
            ("GET", "/api/cards/Abcd_1234/png"),
            ("POST", "/api/documents"),
            ("POST", "/api/scanner/sessions"),
            ("POST", "/api/scanner/devices"),
        ):
            status, _, _ = self.companion_request(method, path)
            self.assertEqual(status, 404, (method, path))
        self.assertEqual(self.fake_upstream.calls, [])

    def test_companion_json_body_errors_are_not_reported_as_png_errors(self):
        status, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=b"",
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(json.loads(body)["code"], "bad_request")

        oversized = b'{' + b'"padding":"' + (b"a" * 600) + b'"}'
        status, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=oversized,
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 413)
        payload = json.loads(body)
        self.assertEqual(payload["code"], "request_too_large")
        self.assertNotIn("PNG", payload["message"])

    def test_companion_rejects_non_ascii_pairing_and_capability(self):
        _, _, body = self.request("POST", "/api/scanner/sessions")
        created = json.loads(body)["session"]

        invalid_pairing = json.dumps(
            {"pairingCode": "é" * 10}, ensure_ascii=False
        ).encode("utf-8")
        status, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=invalid_pairing,
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(body)["code"], "scanner_pairing_failed")

        pair_body = json.dumps(
            {"pairingCode": created["pairingCode"]}
        ).encode("utf-8")
        _, _, body = self.companion_request(
            "POST",
            "/api/scanner/pair",
            body=pair_body,
            headers={"Content-Type": "application/json"},
        )
        grant = json.loads(body)["scanner"]
        token_body = json.dumps({"token": "Abcd_1234"}).encode("utf-8")
        status, _, body = self.companion_request(
            "POST",
            f'/api/scanner/sessions/{grant["sessionId"]}/token',
            body=token_body,
            headers={
                "Authorization": "Bearer " + ("é" * len(grant["capability"])),
                "Content-Type": "application/json",
            },
        )
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body)["code"], "scanner_not_paired")

    def test_upstream_not_found_is_a_local_json_404(self):
        self.fake_upstream.error = UpstreamHttpError(404)
        status, headers, body = self.request(
            "GET",
            "/api/cards/12345678/png",
            headers={"Authorization": "Bearer browser-secret"},
        )
        self.assertEqual(status, 404)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(json.loads(body)["code"], "card_not_found")

    def test_upstream_authentication_and_permission_are_distinct(self):
        for upstream_status, expected_status, expected_code in (
            (401, 401, "staff_auth_failed"),
            (403, 403, "staff_permission_denied"),
        ):
            with self.subTest(upstream_status=upstream_status):
                self.fake_upstream.error = UpstreamHttpError(
                    upstream_status
                )
                status, _, body = self.request(
                    "GET",
                    "/api/cards/12345678/png",
                    headers={"Authorization": "Bearer browser-secret"},
                )
                self.assertEqual(status, expected_status)
                self.assertEqual(json.loads(body)["code"], expected_code)

    def test_rejects_untrusted_host_and_cross_origin_api_requests(self):
        status, _, body = self.request(
            "GET",
            "/api/config",
            headers={"Host": "printer.attacker.example"},
        )
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body)["code"], "forbidden_origin")

        status, _, body = self.request(
            "GET",
            "/api/cards/12345678/png",
            headers={
                "Authorization": "Bearer browser-secret",
                "Host": f"127.0.0.1:{self.port}",
                "Origin": "https://attacker.example",
                "Sec-Fetch-Site": "cross-site",
            },
        )
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body)["code"], "forbidden_origin")
        self.assertEqual(self.fake_upstream.calls, [])


if __name__ == "__main__":
    unittest.main()
