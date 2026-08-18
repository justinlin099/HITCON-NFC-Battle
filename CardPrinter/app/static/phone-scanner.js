(() => {
  "use strict";

  const TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,32}$/;
  const SESSION_PATTERN = /^[A-Za-z0-9_-]{20,40}$/;
  const CAPABILITY_PATTERN = /^[A-Za-z0-9_-]{20,128}$/;
  const DEVICE_CAPABILITY_PATTERN = /^[A-Za-z0-9_-]{43}$/;
  const PAIRING_CODE_PATTERN = /^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{10}$/;
  const ACTIVE_POLL_INTERVAL_MS = 1_200;
  const NATIVE_SCAN_INTERVAL_MS = 140;
  const NATIVE_ASSIST_DELAY_MS = 3_000;
  const ZXING_SCAN_INTERVAL_MS = 240;
  const ZXING_ROI_VARIANTS = [
    { widthRatio: 0.9, aspectRatio: 3.4, targetWidth: 1200, contrast: 1.18 },
    { widthRatio: 0.68, aspectRatio: 3.1, targetWidth: 1400, contrast: 1.3 },
  ];

  let deviceFragmentInvalid = false;
  let deviceCapability = consumeDeviceCapabilityFragment();

  const elements = {
    pairingForm: document.querySelector("#pairing-form"),
    pairingCode: document.querySelector("#pairing-code"),
    pairScanner: document.querySelector("#pair-scanner"),
    pairingError: document.querySelector("#pairing-error"),
    relayState: document.querySelector("#relay-state"),
    cameraVideo: document.querySelector("#camera-video"),
    cameraPlaceholder: document.querySelector("#camera-placeholder"),
    startCamera: document.querySelector("#start-camera"),
    refocusCamera: document.querySelector("#refocus-camera"),
    zoomControl: document.querySelector("#zoom-control"),
    cameraZoom: document.querySelector("#camera-zoom"),
    cameraZoomValue: document.querySelector("#camera-zoom-value"),
    scannerStatus: document.querySelector("#scanner-status"),
    scanCanvas: document.querySelector("#scan-canvas"),
  };

  let activeScannerAvailable = false;
  let activeScannerPaired = false;
  let activePollGeneration = 0;
  let activePollTimer = null;
  let activePollController = null;

  let pairingGeneration = 0;
  let pairingInFlight = false;
  let pairingController = null;
  let scannerSessionId = null;
  let scannerCapability = null;
  let scannerExpiresAt = 0;
  let scannerGrantGeneration = 0;
  let deviceGrantValidated = false;
  let tokenSubmitController = null;

  let cameraStream = null;
  let cameraGeneration = 0;
  let nativeDetector = null;
  let nativeScanTimer = null;
  let nativeAssistTimer = null;
  let nativeFailureCount = 0;
  let zxingReader = null;
  let zxingActiveGeneration = 0;
  let zxingScanTimer = null;
  let zxingVariantIndex = 0;
  let scanHandled = false;
  let submittingToken = false;

  let cameraCapabilities = null;
  let cameraBaseConstraints = {};
  let cameraPreferredSettings = {};
  let cameraZoomSetting = null;
  let focusRestoreTimer = null;
  let zoomTimer = null;
  let zoomSequence = 0;
  let zoomApplyInFlight = false;
  let pendingZoomRequest = null;

  class ScannerError extends Error {
    constructor(message, code = "", status = 0) {
      super(message);
      this.code = code;
      this.status = status;
    }
  }

  function consumeDeviceCapabilityFragment() {
    const fragment = window.location.hash;
    const supplied = fragment.length > 0;
    const match = /^#device=([A-Za-z0-9_-]{43})$/.exec(fragment);
    deviceFragmentInvalid = false;
    if (supplied) {
      try {
        window.history.replaceState(
          window.history.state,
          "",
          `${window.location.pathname}${window.location.search}`,
        );
      } catch {
        window.location.hash = "";
      }
    }
    if (!match || !DEVICE_CAPABILITY_PATTERN.test(match[1])) {
      deviceFragmentInvalid = supplied;
      return null;
    }
    return match[1];
  }

  function setStatus(message, state = "info") {
    elements.scannerStatus.dataset.state = state;
    elements.scannerStatus.textContent = message;
  }

  function setRelayState(text, state = "waiting") {
    elements.relayState.dataset.state = state;
    elements.relayState.textContent = text;
  }

  function setPlaceholder(visible, message = "尚未啟動相機") {
    elements.cameraPlaceholder.hidden = !visible;
    const text = elements.cameraPlaceholder.querySelector("p");
    if (text) {
      text.textContent = message;
    }
  }

  function setPairingError(message = "") {
    elements.pairingError.textContent = message;
    elements.pairingError.hidden = !message;
    if (message) {
      elements.pairingCode.setAttribute("aria-invalid", "true");
    } else {
      elements.pairingCode.removeAttribute("aria-invalid");
    }
  }

  function normalizePairingCode(value) {
    return String(value || "")
      .toUpperCase()
      .replace(/[-\s]/g, "");
  }

  function formatPairingInput(value) {
    const compact = String(value || "")
      .toUpperCase()
      .replace(/[^23456789ABCDEFGHJKMNPQRSTVWXYZ]/g, "")
      .slice(0, 10);
    return compact.length > 5 ? `${compact.slice(0, 5)}-${compact.slice(5)}` : compact;
  }

  function deviceModeActive() {
    return Boolean(deviceCapability);
  }

  function updatePairButton() {
    const deviceMode = deviceModeActive();
    const validCode = PAIRING_CODE_PATTERN.test(normalizePairingCode(elements.pairingCode.value));
    elements.pairingForm.hidden = deviceMode;
    elements.pairingCode.disabled = deviceMode || pairingInFlight || Boolean(scannerCapability);
    elements.pairScanner.disabled =
      deviceMode ||
      pairingInFlight ||
      Boolean(scannerCapability) ||
      !activeScannerAvailable ||
      activeScannerPaired ||
      !validCode;
    elements.startCamera.disabled =
      !scannerCapability ||
      submittingToken ||
      (deviceMode && !deviceGrantValidated);
  }

  async function jsonPayload(response) {
    try {
      return await response.json();
    } catch {
      throw new ScannerError("服務回傳了無效資料。");
    }
  }

  function responseError(response, payload, fallback) {
    const message = typeof payload?.message === "string" ? payload.message.trim() : "";
    const code = typeof payload?.code === "string" ? payload.code : "";
    return new ScannerError(message || `${fallback}（HTTP ${response.status}）。`, code, response.status);
  }

  function stopActivePolling() {
    activePollGeneration += 1;
    if (activePollTimer !== null) {
      window.clearTimeout(activePollTimer);
      activePollTimer = null;
    }
    activePollController?.abort();
    activePollController = null;
  }

  function scheduleActivePoll(generation, delay = ACTIVE_POLL_INTERVAL_MS) {
    if (
      generation !== activePollGeneration ||
      document.hidden ||
      (!deviceModeActive() && scannerCapability)
    ) {
      return;
    }
    activePollTimer = window.setTimeout(() => {
      activePollTimer = null;
      void pollActiveSession(generation);
    }, delay);
  }

  async function pollActiveSession(generation) {
    if (deviceModeActive()) {
      await pollDeviceSession(generation, deviceCapability);
    } else {
      await pollManualActiveSession(generation);
    }
  }

  async function pollManualActiveSession(generation) {
    if (
      generation !== activePollGeneration ||
      deviceModeActive() ||
      scannerCapability ||
      document.hidden
    ) {
      return;
    }
    const controller = new AbortController();
    activePollController = controller;
    try {
      const response = await fetch("/api/scanner/sessions/active", {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: controller.signal,
      });
      const payload = await jsonPayload(response);
      if (generation !== activePollGeneration || deviceModeActive() || scannerCapability) {
        return;
      }
      if (!response.ok) {
        throw responseError(response, payload, "讀取 Windows 狀態失敗");
      }
      const scanner = payload?.scanner;
      if (
        !scanner ||
        typeof scanner.available !== "boolean" ||
        typeof scanner.paired !== "boolean" ||
        !Number.isFinite(scanner.expiresInSeconds)
      ) {
        throw new ScannerError("Windows 回傳了無效的掃描狀態。");
      }

      activeScannerAvailable = scanner.available;
      activeScannerPaired = scanner.paired;
      if (!scanner.available) {
        setRelayState("等待 Windows", "waiting");
        setStatus("請先在 Windows 按「用手機掃描」。");
      } else if (scanner.paired) {
        setRelayState("已有配對", "error");
        setStatus("這次掃描已配對；請在 Windows 重新建立配對碼。", "error");
      } else {
        setRelayState("可配對", "ready");
        setStatus("輸入 Windows 顯示的配對碼。");
      }
      updatePairButton();
      scheduleActivePoll(generation);
    } catch (error) {
      if (
        error?.name !== "AbortError" &&
        generation === activePollGeneration &&
        !deviceModeActive()
      ) {
        activeScannerAvailable = false;
        activeScannerPaired = false;
        setRelayState("連線中斷", "error");
        setStatus(
          error instanceof ScannerError ? error.message : "無法連線到 Windows，正在重試。",
          "error",
        );
        updatePairButton();
        scheduleActivePoll(generation, 1_600);
      }
    } finally {
      if (activePollController === controller) {
        activePollController = null;
      }
    }
  }

  function devicePollIsCurrent(generation, capability) {
    return (
      generation === activePollGeneration &&
      deviceCapability === capability &&
      !document.hidden
    );
  }

  function clearDeviceSession() {
    if (submittingToken) {
      setRelayState("USB 已連線", "ready");
      return;
    }
    if (scannerSessionId || scannerCapability || cameraStream) {
      stopCamera("等待 Windows 建立掃描工作");
      clearPairingGrant();
    } else {
      deviceGrantValidated = false;
      activeScannerAvailable = false;
      activeScannerPaired = false;
      updatePairButton();
    }
    setRelayState("USB 已連線", "ready");
    if (!submittingToken) {
      setStatus("等待 Windows 按「用手機掃描」。");
    }
  }

  function installDeviceSession(scanner) {
    const sessionId = String(scanner?.sessionId || "");
    const capability = String(scanner?.capability || "");
    const expiresInSeconds = scanner?.expiresInSeconds;
    if (
      !SESSION_PATTERN.test(sessionId) ||
      !CAPABILITY_PATTERN.test(capability) ||
      !Number.isInteger(expiresInSeconds) ||
      expiresInSeconds < 0 ||
      expiresInSeconds > 86_400
    ) {
      throw new ScannerError("Windows 回傳了無效的 USB 掃描工作。");
    }
    if (expiresInSeconds === 0) {
      clearDeviceSession();
      return;
    }

    const sameGrant = scannerSessionId === sessionId && scannerCapability === capability;
    if (!sameGrant) {
      scannerGrantGeneration += 1;
      tokenSubmitController?.abort();
      if (cameraStream || scannerSessionId || scannerCapability) {
        stopCamera("Windows 已切換掃描工作");
      }
      scannerSessionId = sessionId;
      scannerCapability = capability;
    }
    scannerExpiresAt = Date.now() + expiresInSeconds * 1_000;
    deviceGrantValidated = true;
    activeScannerAvailable = true;
    activeScannerPaired = true;
    updatePairButton();
    setRelayState("USB 已連線", "ready");
    if (!cameraStream && !submittingToken) {
      setStatus("Windows 已準備，按「開始掃描」。", "success");
    }
  }

  function fallBackToManualPairing(message) {
    stopActivePolling();
    deviceCapability = null;
    stopCamera("USB 自動配對已失效");
    clearPairingGrant();
    elements.pairingCode.value = "";
    setPairingError();
    setRelayState("改用手動配對", "error");
    setStatus(message, "error");
    startActivePolling(500);
  }

  async function pollDeviceSession(generation, capability) {
    if (!devicePollIsCurrent(generation, capability)) {
      return;
    }
    const controller = new AbortController();
    activePollController = controller;
    try {
      const response = await fetch("/api/scanner/device/session", {
        method: "GET",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${capability}`,
        },
        cache: "no-store",
        signal: controller.signal,
      });
      if (!devicePollIsCurrent(generation, capability)) {
        return;
      }
      if (response.status === 401 || response.status === 403) {
        fallBackToManualPairing("USB 自動配對已失效，請改用 Windows 顯示的配對碼。");
        return;
      }
      const payload = await jsonPayload(response);
      if (!devicePollIsCurrent(generation, capability)) {
        return;
      }
      if (!response.ok) {
        throw responseError(response, payload, "讀取 USB 掃描工作失敗");
      }
      if (payload?.scanner === null) {
        clearDeviceSession();
      } else if (payload?.scanner && typeof payload.scanner === "object") {
        installDeviceSession(payload.scanner);
      } else {
        throw new ScannerError("Windows 回傳了無效的 USB 掃描狀態。");
      }
      scheduleActivePoll(generation);
    } catch (error) {
      if (error?.name !== "AbortError" && devicePollIsCurrent(generation, capability)) {
        setRelayState("USB 重連中", "error");
        setStatus(
          error instanceof ScannerError ? error.message : "USB 連線暫時中斷，正在重試。",
          "error",
        );
        scheduleActivePoll(generation, 1_600);
      }
    } finally {
      if (activePollController === controller) {
        activePollController = null;
      }
    }
  }

  function startActivePolling(delay = 0) {
    stopActivePolling();
    if (document.hidden || (!deviceModeActive() && scannerCapability)) {
      return;
    }
    const generation = activePollGeneration;
    scheduleActivePoll(generation, delay);
  }

  function clearPairingGrant({ abortSubmit = true } = {}) {
    scannerGrantGeneration += 1;
    if (abortSubmit) {
      tokenSubmitController?.abort();
    }
    scannerSessionId = null;
    scannerCapability = null;
    scannerExpiresAt = 0;
    deviceGrantValidated = false;
    activeScannerAvailable = false;
    activeScannerPaired = false;
    updatePairButton();
  }

  function scannerGrantSnapshot() {
    return {
      generation: scannerGrantGeneration,
      sessionId: scannerSessionId,
      capability: scannerCapability,
    };
  }

  function scannerGrantIsCurrent(grant) {
    return (
      grant?.generation === scannerGrantGeneration &&
      grant.sessionId === scannerSessionId &&
      grant.capability === scannerCapability
    );
  }

  function activateDeviceCapability(capability) {
    if (!DEVICE_CAPABILITY_PATTERN.test(String(capability || ""))) {
      return;
    }
    stopActivePolling();
    pairingGeneration += 1;
    pairingController?.abort();
    pairingController = null;
    pairingInFlight = false;
    deviceCapability = capability;
    stopCamera("正在重新連線到 Windows");
    clearPairingGrant();
    elements.pairingCode.value = "";
    setPairingError();
    setRelayState("USB 連線中", "waiting");
    setStatus("正在透過 USB 連線到 Windows…");
    updatePairButton();
    startActivePolling(0);
  }

  function handleDeviceCapabilityHashChange() {
    if (!window.location.hash) {
      return;
    }
    const capability = consumeDeviceCapabilityFragment();
    if (capability) {
      activateDeviceCapability(capability);
    } else if (!deviceModeActive()) {
      setRelayState("改用手動配對", "error");
      setStatus("USB 連線資訊無效，請使用 Windows 顯示的配對碼。", "error");
      updatePairButton();
    }
  }

  async function pairScanner(event) {
    event.preventDefault();
    if (deviceModeActive() || pairingInFlight || scannerCapability) {
      return;
    }
    const pairingCode = normalizePairingCode(elements.pairingCode.value);
    if (!PAIRING_CODE_PATTERN.test(pairingCode)) {
      setPairingError("請輸入 10 個英文字母（不含 I、L、O、U）或 2–9；連字號可省略。");
      elements.pairingCode.focus();
      return;
    }

    const generation = ++pairingGeneration;
    pairingInFlight = true;
    setPairingError();
    stopActivePolling();
    updatePairButton();
    setRelayState("配對中", "waiting");
    setStatus("正在配對 Windows…");
    const controller = new AbortController();
    pairingController = controller;

    try {
      const response = await fetch("/api/scanner/pair", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ pairingCode }),
        cache: "no-store",
        signal: controller.signal,
      });
      const payload = await jsonPayload(response);
      if (generation !== pairingGeneration) {
        return;
      }
      if (!response.ok) {
        throw responseError(response, payload, "配對失敗");
      }
      const scanner = payload?.scanner;
      const sessionId = String(scanner?.sessionId || "");
      const capability = String(scanner?.capability || "");
      if (
        !SESSION_PATTERN.test(sessionId) ||
        !CAPABILITY_PATTERN.test(capability) ||
        !Number.isFinite(scanner?.expiresInSeconds)
      ) {
        throw new ScannerError("Windows 回傳了無效的配對資料。");
      }

      scannerGrantGeneration += 1;
      scannerSessionId = sessionId;
      scannerCapability = capability;
      scannerExpiresAt = Date.now() + Math.max(0, scanner.expiresInSeconds) * 1_000;
      deviceGrantValidated = false;
      activeScannerAvailable = true;
      activeScannerPaired = true;
      updatePairButton();
      setRelayState("已配對", "ready");
      setStatus("配對完成，按「開始掃描」。", "success");
    } catch (error) {
      if (error?.name !== "AbortError" && generation === pairingGeneration) {
        clearPairingGrant();
        setPairingError(error instanceof ScannerError ? error.message : "無法完成配對。");
        setRelayState("配對失敗", "error");
        setStatus("請核對配對碼後重試。", "error");
        startActivePolling(800);
      }
    } finally {
      if (pairingController === controller) {
        pairingController = null;
      }
      if (generation === pairingGeneration) {
        pairingInFlight = false;
        updatePairButton();
      }
    }
  }

  function cameraTrack() {
    return cameraStream?.getVideoTracks()[0] || null;
  }

  function cameraIsCurrent(generation, track) {
    return generation === cameraGeneration && track && cameraTrack() === track;
  }

  function capabilityModes(value) {
    if (typeof value === "string") {
      return [value];
    }
    try {
      return value ? Array.from(value) : [];
    } catch {
      return [];
    }
  }

  function zoomDetails(value) {
    const min = Number(value?.min);
    const max = Number(value?.max);
    const rawStep = Number(value?.step);
    if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) {
      return null;
    }
    return {
      min,
      max,
      step: Number.isFinite(rawStep) && rawStep > 0 ? rawStep : Math.max(0.1, (max - min) / 100),
    };
  }

  function formatZoom(value) {
    const numeric = Number(value);
    return `${(Number.isFinite(numeric) ? numeric : 1).toFixed(1)}×`;
  }

  function resetLensControls() {
    if (focusRestoreTimer !== null) {
      window.clearTimeout(focusRestoreTimer);
      focusRestoreTimer = null;
    }
    if (zoomTimer !== null) {
      window.clearTimeout(zoomTimer);
      zoomTimer = null;
    }
    zoomSequence += 1;
    pendingZoomRequest = null;
    cameraCapabilities = null;
    cameraBaseConstraints = {};
    cameraPreferredSettings = {};
    cameraZoomSetting = null;
    elements.refocusCamera.hidden = true;
    elements.refocusCamera.disabled = true;
    elements.zoomControl.hidden = true;
    elements.cameraZoom.disabled = true;
    elements.cameraZoom.min = "1";
    elements.cameraZoom.max = "1";
    elements.cameraZoom.step = "0.1";
    elements.cameraZoom.value = "1";
    elements.cameraZoomValue.value = "1.0×";
  }

  function advancedCameraSettings(overrides = {}) {
    return {
      ...cameraPreferredSettings,
      ...(cameraZoomSetting === null ? {} : { zoom: cameraZoomSetting }),
      ...overrides,
    };
  }

  async function applyCameraSettings(track, generation, overrides = {}) {
    if (!cameraIsCurrent(generation, track) || typeof track.applyConstraints !== "function") {
      return false;
    }
    const settings = advancedCameraSettings(overrides);
    const advanced = Object.entries(settings).map(([name, value]) => ({ [name]: value }));
    if (advanced.length === 0) {
      return true;
    }
    try {
      await track.applyConstraints({ ...cameraBaseConstraints, advanced });
    } catch {
      return false;
    }
    return cameraIsCurrent(generation, track);
  }

  async function configureCameraTrack(generation) {
    const track = cameraTrack();
    if (!cameraIsCurrent(generation, track)) {
      return;
    }
    resetLensControls();
    try {
      const { advanced: _advanced, ...baseConstraints } = track.getConstraints?.() || {};
      cameraBaseConstraints = baseConstraints;
    } catch {
      cameraBaseConstraints = {};
    }
    if (
      typeof track.getCapabilities !== "function" ||
      typeof track.applyConstraints !== "function"
    ) {
      return;
    }

    let capabilities;
    try {
      capabilities = track.getCapabilities();
    } catch {
      return;
    }
    if (!cameraIsCurrent(generation, track)) {
      return;
    }
    cameraCapabilities = capabilities || {};
    ["focusMode", "exposureMode", "whiteBalanceMode"].forEach((name) => {
      if (capabilityModes(cameraCapabilities[name]).includes("continuous")) {
        cameraPreferredSettings[name] = "continuous";
      }
    });

    if (capabilityModes(cameraCapabilities.focusMode).includes("single-shot")) {
      elements.refocusCamera.hidden = false;
      elements.refocusCamera.disabled = false;
    }
    const zoom = zoomDetails(cameraCapabilities.zoom);
    if (zoom) {
      let currentZoom = Number(track.getSettings?.().zoom);
      if (!Number.isFinite(currentZoom)) {
        currentZoom = zoom.min;
      }
      currentZoom = Math.min(zoom.max, Math.max(zoom.min, currentZoom));
      elements.cameraZoom.min = String(zoom.min);
      elements.cameraZoom.max = String(zoom.max);
      elements.cameraZoom.step = String(zoom.step);
      elements.cameraZoom.value = String(currentZoom);
      elements.cameraZoomValue.value = formatZoom(currentZoom);
      elements.cameraZoom.disabled = false;
      elements.zoomControl.hidden = false;
    }
    await applyCameraSettings(track, generation);
  }

  async function refocusCamera() {
    const generation = cameraGeneration;
    const track = cameraTrack();
    if (
      !cameraIsCurrent(generation, track) ||
      !capabilityModes(cameraCapabilities?.focusMode).includes("single-shot")
    ) {
      return;
    }
    if (focusRestoreTimer !== null) {
      window.clearTimeout(focusRestoreTimer);
      focusRestoreTimer = null;
    }
    elements.refocusCamera.disabled = true;
    setStatus("正在重新對焦，請保持條碼穩定。");
    const applied = await applyCameraSettings(track, generation, { focusMode: "single-shot" });
    if (!cameraIsCurrent(generation, track)) {
      return;
    }
    elements.refocusCamera.disabled = false;
    setStatus(applied ? "正在掃描 Code 128。" : "無法重新對焦，請把手機拿遠。", applied ? "info" : "error");
    if (applied && cameraPreferredSettings.focusMode === "continuous") {
      focusRestoreTimer = window.setTimeout(() => {
        focusRestoreTimer = null;
        if (cameraIsCurrent(generation, track)) {
          void applyCameraSettings(track, generation);
        }
      }, 900);
    }
  }

  async function applyZoom(track, generation, value, sequence) {
    cameraZoomSetting = value;
    const applied = await applyCameraSettings(track, generation);
    if (!cameraIsCurrent(generation, track) || sequence !== zoomSequence) {
      return;
    }
    if (!applied) {
      const actual = Number(track.getSettings?.().zoom);
      if (Number.isFinite(actual)) {
        cameraZoomSetting = actual;
        elements.cameraZoom.value = String(actual);
        elements.cameraZoomValue.value = formatZoom(actual);
      }
      setStatus("無法套用縮放，請直接調整距離。", "error");
    }
  }

  async function drainZoomRequests() {
    if (zoomApplyInFlight) {
      return;
    }
    zoomApplyInFlight = true;
    try {
      while (pendingZoomRequest) {
        const request = pendingZoomRequest;
        pendingZoomRequest = null;
        if (
          request.sequence === zoomSequence &&
          cameraIsCurrent(request.generation, request.track)
        ) {
          await applyZoom(request.track, request.generation, request.value, request.sequence);
        }
      }
    } finally {
      zoomApplyInFlight = false;
      if (pendingZoomRequest) {
        void drainZoomRequests();
      }
    }
  }

  function scheduleZoom() {
    const zoom = zoomDetails(cameraCapabilities?.zoom);
    const rawValue = Number(elements.cameraZoom.value);
    if (!zoom || !Number.isFinite(rawValue)) {
      return;
    }
    const value = Math.min(zoom.max, Math.max(zoom.min, rawValue));
    elements.cameraZoomValue.value = formatZoom(value);
    cameraZoomSetting = value;
    if (zoomTimer !== null) {
      window.clearTimeout(zoomTimer);
    }
    const generation = cameraGeneration;
    const track = cameraTrack();
    const sequence = ++zoomSequence;
    zoomTimer = window.setTimeout(() => {
      zoomTimer = null;
      if (cameraIsCurrent(generation, track)) {
        pendingZoomRequest = { track, generation, value, sequence };
        void drainZoomRequests();
      }
    }, 90);
  }

  function stopScannerLoops() {
    if (nativeScanTimer !== null) {
      window.clearTimeout(nativeScanTimer);
      nativeScanTimer = null;
    }
    if (nativeAssistTimer !== null) {
      window.clearTimeout(nativeAssistTimer);
      nativeAssistTimer = null;
    }
    if (zxingScanTimer !== null) {
      window.clearTimeout(zxingScanTimer);
      zxingScanTimer = null;
    }
    try {
      zxingReader?.reset?.();
    } catch {
      // Older builds may not expose reset.
    }
    nativeDetector = null;
    nativeFailureCount = 0;
    zxingReader = null;
    zxingActiveGeneration = 0;
    zxingVariantIndex = 0;
  }

  function releaseCameraStream(stream = cameraStream) {
    const releasingCurrent = !stream || stream === cameraStream;
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
    }
    if (stream === cameraStream) {
      cameraStream = null;
    }
    if (elements.cameraVideo.srcObject === stream || (!stream && !cameraStream)) {
      elements.cameraVideo.pause();
      elements.cameraVideo.srcObject = null;
    }
    if (releasingCurrent) {
      resetLensControls();
    }
  }

  function stopCamera(message = "相機已停止") {
    cameraGeneration += 1;
    stopScannerLoops();
    releaseCameraStream();
    elements.startCamera.textContent = "開始掃描";
    elements.startCamera.disabled = !scannerCapability || submittingToken;
    setPlaceholder(true, message);
  }

  async function requestCameraStream() {
    const preferred = {
      facingMode: { ideal: "environment" },
      width: { ideal: 1920 },
      height: { ideal: 1080 },
      frameRate: { ideal: 30 },
    };
    try {
      return await navigator.mediaDevices.getUserMedia({ audio: false, video: preferred });
    } catch (error) {
      if (error?.name === "OverconstrainedError") {
        return navigator.mediaDevices.getUserMedia({ audio: false, video: true });
      }
      throw error;
    }
  }

  async function nativeCode128Detector() {
    if (!("BarcodeDetector" in globalThis)) {
      return null;
    }
    try {
      const formats = await globalThis.BarcodeDetector.getSupportedFormats();
      if (!formats.includes("code_128")) {
        return null;
      }
      return new globalThis.BarcodeDetector({ formats: ["code_128"] });
    } catch {
      return null;
    }
  }

  function zxingText(result) {
    if (typeof result?.getText === "function") {
      return String(result.getText() || "");
    }
    return typeof result?.text === "string" ? result.text : "";
  }

  function isZxingCode128(result) {
    const library = globalThis.ZXingBrowser;
    if (!result || !library?.BarcodeFormat || typeof result.getBarcodeFormat !== "function") {
      return Boolean(result);
    }
    return result.getBarcodeFormat() === library.BarcodeFormat.CODE_128;
  }

  async function submitToken(token, grant, controller) {
    const { sessionId, capability } = grant;
    if (
      !SESSION_PATTERN.test(String(sessionId || "")) ||
      !CAPABILITY_PATTERN.test(String(capability || ""))
    ) {
      throw new ScannerError("配對已失效，請重新配對。", "scanner_session_expired", 404);
    }
    const response = await fetch(
      `/api/scanner/sessions/${encodeURIComponent(sessionId)}/token`,
      {
        method: "POST",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${capability}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ token }),
        cache: "no-store",
        keepalive: true,
        signal: controller.signal,
      },
    );
    const payload = await jsonPayload(response);
    if (!response.ok) {
      const error = responseError(response, payload, "送出 Token 失敗");
      if (response.status === 409 && error.code === "scanner_session_used") {
        return;
      }
      throw error;
    }
  }

  async function acceptScannedToken(rawValue) {
    if (scanHandled || submittingToken) {
      return;
    }
    const token = String(rawValue || "").trim();
    if (!TOKEN_PATTERN.test(token)) {
      setStatus("讀到的條碼不是有效 Token，請重新對準 Code 128。", "error");
      return;
    }
    const grant = scannerGrantSnapshot();
    if (
      !scannerGrantIsCurrent(grant) ||
      !SESSION_PATTERN.test(String(grant.sessionId || "")) ||
      !CAPABILITY_PATTERN.test(String(grant.capability || ""))
    ) {
      setStatus("掃描工作已失效，正在等待 Windows。", "error");
      return;
    }

    scanHandled = true;
    submittingToken = true;
    const controller = new AbortController();
    tokenSubmitController = controller;
    stopCamera("已讀取條碼");
    setRelayState("傳送中", "waiting");
    setStatus("正在把 Token 傳回 Windows…");
    try {
      await submitToken(token, grant, controller);
      if (!scannerGrantIsCurrent(grant)) {
        return;
      }
      clearPairingGrant({ abortSubmit: false });
      elements.pairingCode.value = "";
      setRelayState("已送出", "ready");
      setPlaceholder(true, "條碼已送出");
      setStatus("Token 已送回 Windows；相機已關閉。", "success");
      startActivePolling(1_500);
    } catch (error) {
      if (!scannerGrantIsCurrent(grant)) {
        return;
      }
      const pairingExpired =
        error instanceof ScannerError &&
        ["scanner_session_expired", "scanner_not_paired"].includes(error.code);
      if (pairingExpired) {
        clearPairingGrant({ abortSubmit: false });
        setRelayState(deviceModeActive() ? "USB 已連線" : "配對失效", deviceModeActive() ? "ready" : "error");
        startActivePolling(800);
      } else {
        setRelayState(deviceModeActive() ? "USB 已連線" : "已配對", "ready");
      }
      scanHandled = false;
      setStatus(error instanceof ScannerError ? error.message : "無法送出 Token，請重試。", "error");
    } finally {
      if (tokenSubmitController === controller) {
        tokenSubmitController = null;
      }
      submittingToken = false;
      updatePairButton();
    }
  }

  function startZxingLoop(generation, reader) {
    const canvas = elements.scanCanvas;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context || typeof reader?.decodeFromCanvas !== "function") {
      return false;
    }
    const isCurrent = () =>
      generation === cameraGeneration &&
      zxingActiveGeneration === generation &&
      zxingReader === reader &&
      !scanHandled &&
      Boolean(cameraStream);

    const scan = async () => {
      if (!isCurrent()) {
        return;
      }
      if (elements.cameraVideo.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
        const sourceWidth = elements.cameraVideo.videoWidth;
        const sourceHeight = elements.cameraVideo.videoHeight;
        if (sourceWidth && sourceHeight) {
          const variant = ZXING_ROI_VARIANTS[zxingVariantIndex % ZXING_ROI_VARIANTS.length];
          zxingVariantIndex += 1;
          const cropWidth = Math.max(1, Math.round(sourceWidth * variant.widthRatio));
          const cropHeight = Math.max(
            1,
            Math.min(Math.round(sourceHeight * 0.4), Math.round(cropWidth / variant.aspectRatio)),
          );
          const sourceX = Math.max(0, Math.round((sourceWidth - cropWidth) / 2));
          const sourceY = Math.max(0, Math.round((sourceHeight - cropHeight) / 2));
          const targetWidth = variant.targetWidth;
          const targetHeight = Math.max(1, Math.round(targetWidth * (cropHeight / cropWidth)));
          canvas.width = targetWidth;
          canvas.height = targetHeight;
          context.imageSmoothingEnabled = true;
          if ("imageSmoothingQuality" in context) {
            context.imageSmoothingQuality = "high";
          }
          try {
            context.save();
            try {
              if ("filter" in context) {
                context.filter = `grayscale(1) contrast(${variant.contrast})`;
              }
              context.drawImage(
                elements.cameraVideo,
                sourceX,
                sourceY,
                cropWidth,
                cropHeight,
                0,
                0,
                targetWidth,
                targetHeight,
              );
            } finally {
              context.restore();
            }
            const result = await Promise.resolve(reader.decodeFromCanvas(canvas));
            if (!isCurrent()) {
              return;
            }
            if (isZxingCode128(result)) {
              await acceptScannedToken(zxingText(result));
              if (scanHandled) {
                return;
              }
            }
          } catch {
            // NotFound is expected while the code is outside the frame.
          }
        }
      }
      if (isCurrent()) {
        zxingScanTimer = window.setTimeout(scan, ZXING_SCAN_INTERVAL_MS);
      }
    };
    void scan();
    return true;
  }

  function startZxing(generation, assistingNative = false) {
    if (zxingActiveGeneration === generation && zxingReader) {
      return true;
    }
    const library = globalThis.ZXingBrowser;
    const Reader = library?.BrowserMultiFormatOneDReader || library?.BrowserMultiFormatReader;
    if (!Reader || generation !== cameraGeneration || !cameraStream) {
      return false;
    }
    let hints;
    if (library.DecodeHintType && library.BarcodeFormat) {
      hints = new Map();
      hints.set(library.DecodeHintType.POSSIBLE_FORMATS, [library.BarcodeFormat.CODE_128]);
    }
    try {
      const reader = new Reader(hints, {
        delayBetweenScanAttempts: ZXING_SCAN_INTERVAL_MS,
        delayBetweenScanSuccess: 500,
      });
      zxingReader = reader;
      zxingActiveGeneration = generation;
      if (!startZxingLoop(generation, reader)) {
        zxingReader = null;
        zxingActiveGeneration = 0;
        return false;
      }
      setStatus(
        assistingNative ? "正在使用 ZXing 輔助掃描中央框。" : "正在掃描中央框內的 Code 128。",
      );
      return true;
    } catch {
      zxingReader = null;
      zxingActiveGeneration = 0;
      return false;
    }
  }

  function scheduleNativeAssist(generation) {
    if (nativeAssistTimer !== null || zxingActiveGeneration === generation) {
      return;
    }
    nativeAssistTimer = window.setTimeout(() => {
      nativeAssistTimer = null;
      if (generation === cameraGeneration && nativeDetector && !scanHandled && cameraStream) {
        startZxing(generation, true);
      }
    }, NATIVE_ASSIST_DELAY_MS);
  }

  async function startNativeLoop(generation) {
    if (generation !== cameraGeneration || !nativeDetector || scanHandled || !cameraStream) {
      return;
    }
    scheduleNativeAssist(generation);
    if (elements.cameraVideo.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      try {
        const results = await nativeDetector.detect(elements.cameraVideo);
        if (generation !== cameraGeneration || scanHandled || !cameraStream) {
          return;
        }
        nativeFailureCount = 0;
        const code = results.find((result) => result.format === "code_128" && result.rawValue);
        if (code) {
          await acceptScannedToken(code.rawValue);
          if (scanHandled) {
            return;
          }
        }
      } catch {
        if (generation !== cameraGeneration || scanHandled || !cameraStream) {
          return;
        }
        nativeFailureCount += 1;
        if (nativeFailureCount >= 3) {
          nativeDetector = null;
          if (nativeAssistTimer !== null) {
            window.clearTimeout(nativeAssistTimer);
            nativeAssistTimer = null;
          }
          if (!startZxing(generation)) {
            stopCamera("無法啟用條碼解碼器");
            setStatus("此瀏覽器無法掃描 Code 128，請回 Windows 手動輸入。", "error");
          }
          return;
        }
      }
    }
    if (generation === cameraGeneration && !scanHandled) {
      nativeScanTimer = window.setTimeout(() => {
        void startNativeLoop(generation);
      }, NATIVE_SCAN_INTERVAL_MS);
    }
  }

  function cameraErrorMessage(error) {
    const messages = {
      NotAllowedError: "相機權限未開啟，請在瀏覽器允許相機。",
      NotFoundError: "找不到可用的相機。",
      NotReadableError: "相機正被其他程式使用。",
      SecurityError: "瀏覽器封鎖相機，請用 localhost 開啟此頁。",
      TypeError: "此頁面無法使用相機，請用 localhost 開啟。",
    };
    return messages[error?.name] || "相機啟動失敗，請重試。";
  }

  async function startCamera() {
    if (deviceModeActive() && (!scannerCapability || !deviceGrantValidated)) {
      setStatus("正在確認 USB 掃描工作，請稍候。", "error");
      startActivePolling(0);
      return;
    }
    if (!scannerCapability || !scannerSessionId) {
      setStatus("請先完成配對。", "error");
      return;
    }
    if (Date.now() >= scannerExpiresAt) {
      clearPairingGrant();
      setRelayState(deviceModeActive() ? "USB 已連線" : "配對過期", deviceModeActive() ? "ready" : "error");
      setStatus(
        deviceModeActive()
          ? "掃描工作已到期，正在等待 Windows 建立下一個工作。"
          : "配對已過期，請在 Windows 重新建立配對碼。",
        "error",
      );
      startActivePolling(800);
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setStatus("此頁面無法使用相機，請用 localhost 開啟。", "error");
      return;
    }

    stopCamera("正在啟動相機…");
    scanHandled = false;
    const generation = ++cameraGeneration;
    elements.startCamera.disabled = true;
    setPlaceholder(true, "正在啟動相機…");
    setStatus("等待相機權限…");
    try {
      const stream = await requestCameraStream();
      if (generation !== cameraGeneration) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      cameraStream = stream;
      elements.cameraVideo.srcObject = stream;
      await elements.cameraVideo.play();
      if (generation !== cameraGeneration || cameraStream !== stream) {
        releaseCameraStream(stream);
        return;
      }
      setPlaceholder(false);
      elements.startCamera.textContent = "停止掃描";
      elements.startCamera.disabled = false;
      await configureCameraTrack(generation);
      if (generation !== cameraGeneration || cameraStream !== stream) {
        return;
      }
      const detector = await nativeCode128Detector();
      if (generation !== cameraGeneration || cameraStream !== stream) {
        return;
      }
      nativeDetector = detector;
      if (nativeDetector) {
        setStatus("正在掃描 Code 128。");
        void startNativeLoop(generation);
      } else if (!startZxing(generation)) {
        stopCamera("無法啟用條碼解碼器");
        setStatus("此瀏覽器無法掃描 Code 128，請回 Windows 手動輸入。", "error");
      }
    } catch (error) {
      if (generation !== cameraGeneration) {
        return;
      }
      stopCamera("相機無法啟動");
      setStatus(cameraErrorMessage(error), "error");
    }
  }

  function toggleCamera() {
    if (cameraStream) {
      stopCamera();
      setStatus("相機已停止；可再次開始掃描。");
    } else {
      void startCamera();
    }
  }

  elements.pairingCode.addEventListener("input", () => {
    const formatted = formatPairingInput(elements.pairingCode.value);
    if (elements.pairingCode.value !== formatted) {
      elements.pairingCode.value = formatted;
    }
    setPairingError();
    updatePairButton();
  });
  elements.pairingForm.addEventListener("submit", (event) => {
    void pairScanner(event);
  });
  elements.startCamera.addEventListener("click", toggleCamera);
  elements.refocusCamera.addEventListener("click", () => {
    void refocusCamera();
  });
  elements.cameraZoom.addEventListener("input", scheduleZoom);
  window.addEventListener("hashchange", handleDeviceCapabilityHashChange);

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      stopCamera("相機已暫停");
      stopActivePolling();
      if (deviceModeActive()) {
        deviceGrantValidated = false;
        updatePairButton();
      }
    } else if (deviceModeActive() || !scannerCapability) {
      startActivePolling(0);
    }
  });
  window.addEventListener("pagehide", () => {
    stopCamera("相機已停止");
    stopActivePolling();
    if (deviceModeActive()) {
      deviceGrantValidated = false;
      updatePairButton();
    }
  });
  window.addEventListener("pageshow", (event) => {
    if (
      !document.hidden &&
      ((deviceModeActive() && event.persisted) || (!deviceModeActive() && !scannerCapability))
    ) {
      startActivePolling(0);
    }
  });

  resetLensControls();
  setPlaceholder(true);
  if (deviceModeActive()) {
    elements.pairingCode.value = "";
    setPairingError();
    setRelayState("USB 連線中", "waiting");
    setStatus("正在透過 USB 連線到 Windows…");
  } else if (deviceFragmentInvalid) {
    setRelayState("改用手動配對", "error");
    setStatus("USB 連線資訊無效，請使用 Windows 顯示的配對碼。", "error");
  }
  updatePairButton();
  startActivePolling(0);
})();
