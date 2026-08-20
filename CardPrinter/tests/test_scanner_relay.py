from __future__ import annotations

import unittest

from app.scanner_relay import (
    InvalidScannerPairingCodeError,
    ScannerCapabilityError,
    ScannerDeviceCapabilityError,
    ScannerRelay,
    ScannerSessionAlreadyPairedError,
    ScannerSessionAlreadyUsedError,
    ScannerSessionNotFoundError,
)
from app.upstream import InvalidTokenError


class ScannerRelayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = [100.0]
        self.relay = ScannerRelay(
            session_seconds=30,
            device_seconds=60,
            clock=lambda: self.now[0],
        )

    def test_usb_device_auto_claims_each_new_session(self) -> None:
        device = self.relay.create_device()
        self.assertGreaterEqual(len(device.device_capability), 40)
        self.assertEqual(device.expires_in_seconds, 60)

        created = self.relay.create_session()
        first = self.relay.claim_active_session(
            device_capability=device.device_capability
        )
        self.assertIsNotNone(first)
        self.assertEqual(first.session_id, created.session_id)
        self.assertTrue(self.relay.session(created.session_id).paired)
        self.assertIsNone(self.relay.session(created.session_id).pairing_code)

        repeated = self.relay.claim_active_session(
            device_capability=device.device_capability
        )
        self.assertEqual(repeated, first)
        self.relay.submit_token(
            created.session_id,
            "Abcd_1234",
            scanner_capability=first.scanner_capability,
        )
        self.assertIsNone(
            self.relay.claim_active_session(
                device_capability=device.device_capability
            )
        )

        second = self.relay.create_session()
        second_grant = self.relay.claim_active_session(
            device_capability=device.device_capability
        )
        self.assertEqual(second_grant.session_id, second.session_id)
        self.assertNotEqual(
            second_grant.scanner_capability, first.scanner_capability
        )

    def test_usb_device_grant_is_replaceable_and_expires(self) -> None:
        first_device = self.relay.create_device()
        old_session = self.relay.create_session()
        second_device = self.relay.create_device()
        self.assertEqual(
            self.relay.session(old_session.session_id).session_id,
            old_session.session_id,
        )

        for invalid in (
            first_device.device_capability,
            "é" * len(second_device.device_capability),
        ):
            with self.assertRaises(ScannerDeviceCapabilityError):
                self.relay.claim_active_session(device_capability=invalid)

        self.now[0] += 61
        with self.assertRaises(ScannerDeviceCapabilityError):
            self.relay.claim_active_session(
                device_capability=second_device.device_capability
            )

    def test_device_reconnect_does_not_disrupt_paired_session(self) -> None:
        first_device = self.relay.create_device()
        session = self.relay.create_session()
        grant = self.relay.claim_active_session(
            device_capability=first_device.device_capability
        )

        with self.assertRaises(ScannerSessionAlreadyPairedError):
            self.relay.create_device()

        self.assertEqual(
            self.relay.claim_active_session(
                device_capability=first_device.device_capability
            ),
            grant,
        )
        self.assertEqual(
            self.relay.session(session.session_id).session_id,
            session.session_id,
        )

    def test_device_reconnect_requires_the_expected_active_session(self) -> None:
        session = self.relay.create_session()
        with self.assertRaises(ScannerSessionNotFoundError):
            self.relay.create_device(expected_session_id="different-session-id")

        device = self.relay.create_device(
            expected_session_id=session.session_id
        )
        self.assertGreaterEqual(len(device.device_capability), 40)
        self.assertEqual(
            self.relay.session(session.session_id).session_id,
            session.session_id,
        )

    def test_create_submit_and_read_session(self) -> None:
        created = self.relay.create_session()
        self.assertRegex(created.session_id, r"^[A-Za-z0-9_-]{20,40}$")
        self.assertEqual(created.expires_in_seconds, 30)
        self.assertIsNone(created.token)
        self.assertRegex(created.pairing_code or "", r"^[A-Z2-9]{10}$")
        self.assertFalse(created.paired)

        active = self.relay.active_session()
        self.assertIsNotNone(active)
        self.assertEqual(active.session_id, created.session_id)
        self.assertIsNone(active.token)

        grant = self.relay.pair(created.pairing_code or "")
        self.assertEqual(grant.session_id, created.session_id)
        self.assertGreaterEqual(len(grant.scanner_capability), 40)
        submitted = self.relay.submit_token(
            created.session_id,
            "  Abcd_1234  ",
            scanner_capability=grant.scanner_capability,
        )
        self.assertEqual(submitted.token, "Abcd_1234")
        self.assertEqual(
            self.relay.session(created.session_id).token, "Abcd_1234"
        )

    def test_rejects_invalid_or_second_token(self) -> None:
        created = self.relay.create_session()
        grant = self.relay.pair(created.pairing_code or "")
        with self.assertRaises(InvalidTokenError):
            self.relay.submit_token(
                created.session_id,
                "not a barcode",
                scanner_capability=grant.scanner_capability,
            )
        with self.assertRaises(ScannerCapabilityError):
            self.relay.submit_token(
                created.session_id,
                "Abcd_1234",
                scanner_capability="wrong",
            )
        self.relay.submit_token(
            created.session_id,
            "Abcd_1234",
            scanner_capability=grant.scanner_capability,
        )
        with self.assertRaises(ScannerSessionAlreadyUsedError):
            self.relay.submit_token(
                created.session_id,
                "Efgh_5678",
                scanner_capability=grant.scanner_capability,
            )

    def test_pairing_code_is_one_time_and_case_separator_tolerant(self) -> None:
        created = self.relay.create_session()
        pairing_code = created.pairing_code or ""
        formatted = pairing_code[:5].lower() + "-" + pairing_code[5:].lower()
        self.relay.pair(formatted)
        with self.assertRaises(InvalidScannerPairingCodeError):
            self.relay.pair(pairing_code)

        self.relay.create_session()
        with self.assertRaises(InvalidScannerPairingCodeError):
            self.relay.pair("22222-22222")
        with self.assertRaises(InvalidScannerPairingCodeError):
            self.relay.pair("é" * 10)

    def test_non_ascii_capability_is_rejected_without_type_error(self) -> None:
        created = self.relay.create_session()
        grant = self.relay.pair(created.pairing_code or "")
        non_ascii = "é" * len(grant.scanner_capability)
        with self.assertRaises(ScannerCapabilityError):
            self.relay.submit_token(
                created.session_id,
                "Abcd_1234",
                scanner_capability=non_ascii,
            )

    def test_new_session_invalidates_previous_session(self) -> None:
        first = self.relay.create_session()
        second = self.relay.create_session()
        self.assertNotEqual(first.session_id, second.session_id)
        with self.assertRaises(ScannerSessionNotFoundError):
            self.relay.session(first.session_id)

    def test_session_expires_and_can_be_closed(self) -> None:
        expired = self.relay.create_session()
        self.now[0] += 31
        self.assertIsNone(self.relay.active_session())
        with self.assertRaises(ScannerSessionNotFoundError):
            self.relay.session(expired.session_id)

        active = self.relay.create_session()
        self.relay.close_session(active.session_id)
        self.assertIsNone(self.relay.active_session())
        with self.assertRaises(ScannerSessionNotFoundError):
            self.relay.close_session(active.session_id)


if __name__ == "__main__":
    unittest.main()
