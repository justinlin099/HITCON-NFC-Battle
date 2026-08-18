"""Short-lived in-memory relay for an ADB-connected phone scanner."""

from __future__ import annotations

from dataclasses import dataclass
from hmac import compare_digest
from secrets import choice, token_urlsafe
from threading import Lock
from time import monotonic
from typing import Callable, Optional

from .upstream import normalize_print_token


DEFAULT_SESSION_SECONDS = 5 * 60
DEFAULT_DEVICE_SECONDS = 12 * 60 * 60
PAIRING_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ"
PAIRING_CODE_LENGTH = 10
CAPABILITY_ALPHABET = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
)


@dataclass(frozen=True)
class ScannerSessionSnapshot:
    session_id: str
    expires_in_seconds: int
    token: Optional[str]
    pairing_code: Optional[str]
    paired: bool


@dataclass(frozen=True)
class ScannerPairingGrant:
    session_id: str
    scanner_capability: str
    expires_in_seconds: int


@dataclass(frozen=True)
class ScannerDeviceGrant:
    device_capability: str
    expires_in_seconds: int


@dataclass
class _ScannerSession:
    session_id: str
    expires_at: float
    pairing_code: Optional[str]
    scanner_capability: Optional[str] = None
    paired_device_id: Optional[str] = None
    token: Optional[str] = None


@dataclass
class _ScannerDevice:
    device_id: str
    capability: str
    expires_at: float


class ScannerSessionNotFoundError(LookupError):
    """The requested phone-scanner session is absent or expired."""


class ScannerSessionAlreadyUsedError(RuntimeError):
    """A scanner session already contains a token."""


class InvalidScannerPairingCodeError(ValueError):
    """The phone supplied an invalid, stale, or already-used pairing code."""


class ScannerCapabilityError(PermissionError):
    """The phone did not present the capability issued during pairing."""


class ScannerDeviceCapabilityError(PermissionError):
    """The phone did not present the capability issued over USB ADB."""


class ScannerRelay:
    """Keep exactly one short-lived phone-scanner session in memory.

    The relay deliberately stores no card artwork, credentials, or durable
    history. Creating a new session invalidates the previous one, which fits a
    single Windows workstation and prevents an old phone tab from replaying a
    scan into a later operator action.
    """

    def __init__(
        self,
        *,
        session_seconds: int = DEFAULT_SESSION_SECONDS,
        device_seconds: int = DEFAULT_DEVICE_SECONDS,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        if session_seconds < 1:
            raise ValueError("session_seconds must be positive")
        if device_seconds < 1:
            raise ValueError("device_seconds must be positive")
        self._session_seconds = session_seconds
        self._device_seconds = device_seconds
        self._clock = clock
        self._lock = Lock()
        self._session: Optional[_ScannerSession] = None
        self._device: Optional[_ScannerDevice] = None

    def create_device(self) -> ScannerDeviceGrant:
        """Issue a low-privilege grant delivered only through ``adb shell``.

        Reconnecting replaces the prior phone grant and clears any unfinished
        card session.  The device grant can only claim a future scanner
        session; it cannot fetch artwork or access workstation credentials.
        """

        with self._lock:
            now = self._clock()
            self._device = _ScannerDevice(
                device_id=token_urlsafe(18),
                capability=token_urlsafe(32),
                expires_at=now + self._device_seconds,
            )
            self._session = None
            return ScannerDeviceGrant(
                device_capability=self._device.capability,
                expires_in_seconds=max(
                    0, int(self._device.expires_at - now)
                ),
            )

    def claim_active_session(
        self, *, device_capability: str
    ) -> Optional[ScannerPairingGrant]:
        """Auto-pair the connected USB phone with the current card session."""

        with self._lock:
            now = self._clock()
            device = self._current_device(now)
            supplied = str(device_capability)
            if (
                device is None
                or not self._valid_capability(supplied, device.capability)
            ):
                raise ScannerDeviceCapabilityError(
                    "Scanner device capability is missing or invalid."
                )

            session, _ = self._current(now=now)
            if session is None or session.token is not None:
                return None
            if session.scanner_capability is None:
                session.pairing_code = None
                session.scanner_capability = token_urlsafe(32)
                session.paired_device_id = device.device_id
            elif session.paired_device_id != device.device_id:
                # A manually paired phone owns this one card session.
                return None
            return ScannerPairingGrant(
                session_id=session.session_id,
                scanner_capability=session.scanner_capability,
                expires_in_seconds=max(0, int(session.expires_at - now)),
            )

    def create_session(self) -> ScannerSessionSnapshot:
        with self._lock:
            now = self._clock()
            self._session = _ScannerSession(
                session_id=token_urlsafe(18),
                expires_at=now + self._session_seconds,
                pairing_code="".join(
                    choice(PAIRING_ALPHABET)
                    for _ in range(PAIRING_CODE_LENGTH)
                ),
            )
            return self._snapshot(self._session, now)

    def active_session(self) -> Optional[ScannerSessionSnapshot]:
        with self._lock:
            session, now = self._current()
            if session is None:
                return None
            return self._snapshot(session, now)

    def session(self, session_id: str) -> ScannerSessionSnapshot:
        with self._lock:
            session, now = self._require(session_id)
            return self._snapshot(session, now)

    def pair(self, raw_pairing_code: str) -> ScannerPairingGrant:
        normalized = "".join(
            character
            for character in str(raw_pairing_code).upper()
            if character not in {"-", " "}
        )
        with self._lock:
            session, now = self._current()
            expected = session.pairing_code if session is not None else None
            if (
                expected is None
                or len(normalized) != PAIRING_CODE_LENGTH
                or any(
                    character not in PAIRING_ALPHABET
                    for character in normalized
                )
                or not compare_digest(normalized, expected)
            ):
                raise InvalidScannerPairingCodeError(
                    "Scanner pairing code is invalid or expired."
                )
            capability = token_urlsafe(32)
            session.pairing_code = None
            session.scanner_capability = capability
            return ScannerPairingGrant(
                session_id=session.session_id,
                scanner_capability=capability,
                expires_in_seconds=max(0, int(session.expires_at - now)),
            )

    def submit_token(
        self,
        session_id: str,
        raw_token: str,
        *,
        scanner_capability: str,
    ) -> ScannerSessionSnapshot:
        with self._lock:
            session, now = self._require(session_id)
            expected = session.scanner_capability
            supplied = str(scanner_capability)
            if expected is None or not self._valid_capability(
                supplied, expected
            ):
                raise ScannerCapabilityError(
                    "Scanner capability is missing or invalid."
                )
            normalized = normalize_print_token(raw_token)
            if session.token is not None:
                raise ScannerSessionAlreadyUsedError(
                    "Scanner session already contains a token."
                )
            session.token = normalized
            return self._snapshot(session, now)

    def close_session(self, session_id: str) -> None:
        with self._lock:
            session, _ = self._require(session_id)
            if self._session is session:
                self._session = None

    def _current(
        self, *, now: Optional[float] = None
    ) -> tuple[Optional[_ScannerSession], float]:
        if now is None:
            now = self._clock()
        if self._session is not None and self._session.expires_at <= now:
            self._session = None
        return self._session, now

    def _current_device(self, now: float) -> Optional[_ScannerDevice]:
        if self._device is not None and self._device.expires_at <= now:
            self._device = None
        return self._device

    @staticmethod
    def _valid_capability(supplied: str, expected: str) -> bool:
        return (
            len(supplied) == len(expected)
            and supplied.isascii()
            and all(
                character in CAPABILITY_ALPHABET for character in supplied
            )
            and compare_digest(supplied, expected)
        )

    def _require(self, session_id: str) -> tuple[_ScannerSession, float]:
        session, now = self._current()
        if session is None or session.session_id != str(session_id):
            raise ScannerSessionNotFoundError(
                "Scanner session is absent or expired."
            )
        return session, now

    @staticmethod
    def _snapshot(
        session: _ScannerSession,
        now: float,
        *,
        include_token: bool = True,
    ) -> ScannerSessionSnapshot:
        return ScannerSessionSnapshot(
            session_id=session.session_id,
            expires_in_seconds=max(0, int(session.expires_at - now)),
            token=session.token if include_token else None,
            pairing_code=session.pairing_code,
            paired=session.scanner_capability is not None,
        )
