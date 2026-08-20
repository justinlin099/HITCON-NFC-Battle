(() => {
  "use strict";

  const TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,32}$/;
  const SCANNER_SESSION_PATTERN = /^[A-Za-z0-9_-]{20,40}$/;
  const SCANNER_PAIRING_CODE_PATTERN = /^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{10}$/;
  const SAFE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/;
  const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const ZIP_SIGNATURES = [
    [0x50, 0x4b, 0x03, 0x04],
    [0x50, 0x4b, 0x05, 0x06],
    [0x50, 0x4b, 0x07, 0x08],
  ];
  const MAX_PNG_BYTES = 10 * 1024 * 1024;
  const MAX_DOCX_BYTES = 40 * 1024 * 1024;
  const MAX_PNG_DIMENSION = 20_000;
  const MAX_PNG_PIXELS = 50_000_000;
  const DEFAULT_TEMPLATE_ASPECT_RATIO = 456 / 720;
  const TEMPLATE_ASPECT_RATIO_TOLERANCE = 0.02;
  const NATIVE_SCAN_INTERVAL_MS = 150;
  const NATIVE_ZXING_ASSIST_DELAY_MS = 3_500;
  const PHONE_SCANNER_POLL_INTERVAL_MS = 650;
  const ZXING_SCAN_INTERVAL_MS = 260;
  const ZXING_ROI_VARIANTS = [
    { widthRatio: 0.84, aspectRatio: 3.15, targetWidth: 1120, contrast: 1.16 },
    { widthRatio: 0.64, aspectRatio: 3.0, targetWidth: 1360, contrast: 1.3 },
  ];
  const WINDOWS_RESERVED_NAME = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i;

  const elements = {
    cardForm: document.querySelector("#card-form"),
    token: document.querySelector("#card-token"),
    tokenError: document.querySelector("#token-error"),
    jwtField: document.querySelector("#jwt-field"),
    jwt: document.querySelector("#staff-jwt"),
    jwtError: document.querySelector("#jwt-error"),
    toggleJwt: document.querySelector("#toggle-jwt"),
    loadCard: document.querySelector("#load-card"),
    scanCard: document.querySelector("#scan-card"),
    scanCardPhone: document.querySelector("#scan-card-phone"),
    chooseLocalPng: document.querySelector("#choose-local-png"),
    localPng: document.querySelector("#local-png"),
    configBadge: document.querySelector("#config-badge"),
    configDetails: document.querySelector("#config-details"),
    operationStatus: document.querySelector("#operation-status"),
    statusTitle: document.querySelector("#status-heading"),
    statusDetail: document.querySelector("#status-detail"),
    previewStage: document.querySelector("#preview-stage"),
    previewEmpty: document.querySelector("#preview-empty"),
    previewImage: document.querySelector("#preview-image"),
    previewState: document.querySelector("#preview-state"),
    previewSource: document.querySelector("#preview-source"),
    previewDimensions: document.querySelector("#preview-dimensions"),
    documentName: document.querySelector("#document-name"),
    filenameError: document.querySelector("#filename-error"),
    previewConfirmed: document.querySelector("#preview-confirmed"),
    downloadWord: document.querySelector("#download-word"),
    cameraDialog: document.querySelector("#camera-dialog"),
    cameraVideo: document.querySelector("#camera-video"),
    cameraSelect: document.querySelector("#camera-select"),
    switchCamera: document.querySelector("#switch-camera"),
    refocusCamera: document.querySelector("#refocus-camera"),
    zoomControl: document.querySelector("#zoom-control"),
    cameraZoom: document.querySelector("#camera-zoom"),
    cameraZoomValue: document.querySelector("#camera-zoom-value"),
    cameraLensHint: document.querySelector("#camera-lens-hint"),
    closeCamera: document.querySelector("#close-camera"),
    cameraDone: document.querySelector("#camera-done"),
    cameraStatus: document.querySelector("#camera-status"),
    cameraPlaceholder: document.querySelector("#camera-placeholder"),
    scanCanvas: document.querySelector("#scan-canvas"),
    phoneScannerDialog: document.querySelector("#phone-scanner-dialog"),
    closePhoneScanner: document.querySelector("#close-phone-scanner"),
    phoneScannerDone: document.querySelector("#phone-scanner-done"),
    restartPhoneScanner: document.querySelector("#restart-phone-scanner"),
    phonePairingCode: document.querySelector("#phone-pairing-code"),
    phonePairingExpiry: document.querySelector("#phone-pairing-expiry"),
    phoneScannerStatus: document.querySelector("#phone-scanner-status"),
  };

  let workstationConfig = null;
  let configReady = false;
  let working = false;
  let currentPngBlob = null;
  let currentPreviewUrl = null;
  let currentPreviewLabel = "";
  let cardFetchController = null;
  let previewGeneration = 0;
  const temporaryDownloadUrls = new Set();

  let phoneSessionId = null;
  let phonePairingCode = "";
  let phoneSessionGeneration = 0;
  let phonePollTimer = null;
  let phonePollController = null;
  let phoneRestartRequested = false;
  let phoneTransitionPromise = null;
  let phoneTokenHandled = false;

  let cameraStream = null;
  let cameraDevices = [];
  let cameraGeneration = 0;
  let cameraStarting = false;
  let cameraDeviceListenerAttached = false;
  let nativeDetector = null;
  let nativeScanTimer = null;
  let nativeAssistTimer = null;
  let nativeAssistAttempted = false;
  let nativeFailureCount = 0;
  let zxingReader = null;
  let zxingActiveGeneration = 0;
  let zxingCanvasTimer = null;
  let zxingRoiVariantIndex = 0;
  let cameraCapabilities = null;
  let cameraBaseConstraints = {};
  let cameraPreferredSettings = {};
  let cameraZoomSetting = null;
  let cameraBaseLensHint = "";
  let focusRestoreTimer = null;
  let zoomApplyTimer = null;
  let zoomApplySequence = 0;
  let zoomApplyInFlight = false;
  let pendingZoomRequest = null;
  let scanHandled = false;

  class UiError extends Error {}

  function setStatus(state, title, detail) {
    elements.operationStatus.dataset.state = state;
    elements.statusTitle.textContent = title;
    elements.statusDetail.textContent = detail;
  }

  function setConfigBadge(state, text) {
    elements.configBadge.className = "pixel-badge";
    if (state === "ready") {
      elements.configBadge.classList.add("pixel-badge--ready");
    } else if (state === "error") {
      elements.configBadge.classList.add("pixel-badge--error");
    } else {
      elements.configBadge.classList.add("pixel-badge--muted");
    }
    elements.configBadge.textContent = text;
  }

  function setCameraStatus(message, state = "info") {
    elements.cameraStatus.dataset.state = state;
    elements.cameraStatus.textContent = message;
  }

  function setPhoneScannerStatus(message, state = "info") {
    elements.phoneScannerStatus.dataset.state = state;
    elements.phoneScannerStatus.textContent = message;
  }

  function setCameraPlaceholder(visible, message = "正在啟動相機…", state = "loading") {
    elements.cameraPlaceholder.hidden = !visible;
    elements.cameraPlaceholder.dataset.state = state;
    const text = elements.cameraPlaceholder.querySelector("p");
    if (text) {
      text.textContent = message;
    }
  }

  function setFieldError(input, errorElement, message = "") {
    errorElement.textContent = message;
    errorElement.hidden = !message;
    if (message) {
      input.setAttribute("aria-invalid", "true");
    } else {
      input.removeAttribute("aria-invalid");
    }
  }

  function setWorking(value) {
    working = value;
    updateControls();
  }

  function updateControls() {
    const remoteEnabled = configReady && !working;
    const browserAuth = workstationConfig?.authMode === "browser";

    elements.token.disabled = !remoteEnabled;
    elements.loadCard.disabled = !remoteEnabled;
    elements.scanCard.disabled = !remoteEnabled;
    elements.scanCardPhone.disabled = !remoteEnabled;
    elements.jwt.disabled = !remoteEnabled || !browserAuth;
    elements.toggleJwt.disabled = !remoteEnabled || !browserAuth;
    elements.localPng.disabled = working;
    elements.chooseLocalPng.disabled = working;
    elements.documentName.disabled = !currentPngBlob || working;
    elements.previewConfirmed.disabled = !currentPngBlob || working;
    elements.downloadWord.disabled =
      !currentPngBlob || !elements.previewConfirmed.checked || working;
  }

  function appendConfigRow(label, value) {
    const row = document.createElement("div");
    const term = document.createElement("dt");
    const description = document.createElement("dd");
    term.textContent = label;
    description.textContent = value;
    row.append(term, description);
    elements.configDetails.append(row);
  }

  function humanizeTemplateKey(key) {
    const labels = {
      sha256: "模板校驗碼",
      name: "模板",
      file: "模板檔案",
      fileName: "模板檔案",
      filename: "模板檔案",
      source: "模板來源",
      sourceName: "模板來源",
      mediaPath: "圖片插槽",
      imagePart: "圖片插槽",
      widthMm: "卡面寬度",
      heightMm: "卡面高度",
      xOffsetMm: "水平校正",
      yOffsetMm: "垂直校正",
      pageWidthMillimeters: "頁面寬度",
      pageHeightMillimeters: "頁面高度",
      imageWidthMillimeters: "圖片寬度",
      imageHeightMillimeters: "圖片高度",
      horizontalOffsetMillimeters: "水平校正",
      anchorKind: "定位方式",
      profileVersion: "校正版號",
    };
    return labels[key] || key.replace(/([a-z0-9])([A-Z])/g, "$1 $2");
  }

  function renderConfigDetails(config) {
    elements.configDetails.replaceChildren();
    appendConfigRow(
      "認證模式",
      config.authMode === "browser" ? "瀏覽器提供 STAFF JWT" : "伺服器管理 STAFF 憑證",
    );
    appendConfigRow("上游 API", config.apiBaseUrl || "由伺服器管理");
    appendConfigRow(
      "API 設定來源",
      config.apiBaseUrlSource === "remote"
        ? "App 遠端設定"
        : config.apiBaseUrlSource === "override"
          ? "本機開發覆寫"
          : "本機備援設定",
    );
    if (config.remoteConfigUrl) {
      appendConfigRow("App 遠端設定", config.remoteConfigUrl);
    }
    if (Number.isFinite(config.maxPngBytes) && config.maxPngBytes > 0) {
      appendConfigRow("PNG 上限", `${(config.maxPngBytes / 1024 / 1024).toFixed(0)} MiB`);
    }

    const template = config.template && typeof config.template === "object" ? config.template : {};
    const entries = Object.entries(template)
      .filter(([, value]) => ["string", "number", "boolean"].includes(typeof value))
      .slice(0, 8);

    if (entries.length === 0) {
      appendConfigRow("校正模板", "已由伺服器載入");
      return;
    }

    entries.forEach(([key, value]) => {
      const suffix = /(?:width|height|offset)(?:Mm|Millimeters)$/i.test(key) ? " mm" : "";
      appendConfigRow(humanizeTemplateKey(key), `${String(value)}${suffix}`);
    });
  }

  async function responseErrorMessage(response, action) {
    const messages = {
      400: "輸入資料格式不正確。",
      401: "STAFF JWT 無效或已過期，請更新後再試。",
      403: "此憑證沒有 STAFF 列印權限。",
      404: "找不到這組 Token 對應的卡面。",
      409: "目前資料狀態不允許執行這個動作。",
      413: "卡面圖檔超過服務允許的大小。",
      415: "服務不接受這個圖片格式，請使用 PNG。",
      422: "卡面或檔名未通過服務驗證。",
      429: "操作太頻繁，請稍候再試。",
      502: "本機服務暫時無法連到卡片 API。",
      503: "列印服務尚未就緒，請稍候再試。",
    };

    let serverDetail = "";
    const contentType = response.headers.get("content-type") || "";
    try {
      if (contentType.includes("application/json")) {
        const payload = await response.json();
        const detail = payload?.detail ?? payload?.message ?? payload?.error;
        if (typeof detail === "string" && detail.length <= 240) {
          serverDetail = detail.trim();
        }
      }
    } catch {
      serverDetail = "";
    }

    const base = messages[response.status] || `${action}失敗（HTTP ${response.status}）。`;
    return serverDetail && !base.includes(serverDetail) ? `${base} ${serverDetail}` : base;
  }

  function unexpectedErrorMessage(error, fallback) {
    if (error instanceof UiError) {
      return error.message;
    }
    if (error?.name === "AbortError") {
      return "操作已取消。";
    }
    return fallback;
  }

  async function loadConfig() {
    setConfigBadge("loading", "設定載入中");
    setStatus("loading", "正在讀取工作站設定", "請稍候，正在確認 API 與校正模板。");
    updateControls();

    try {
      const response = await fetch("/api/config", {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
      if (!response.ok) {
        throw new UiError(await responseErrorMessage(response, "讀取設定"));
      }

      const payload = await response.json();
      if (!payload || !["server", "browser"].includes(payload.authMode)) {
        throw new UiError("工作站設定缺少有效的認證模式。");
      }

      workstationConfig = {
        authMode: payload.authMode,
        apiBaseUrl: typeof payload.apiBaseUrl === "string" ? payload.apiBaseUrl : "",
        apiBaseUrlSource: ["remote", "override"].includes(payload.apiBaseUrlSource)
          ? payload.apiBaseUrlSource
          : "fallback",
        remoteConfigUrl:
          typeof payload.remoteConfigUrl === "string" ? payload.remoteConfigUrl : "",
        maxPngBytes:
          Number.isFinite(payload.maxPngBytes) && payload.maxPngBytes > 0
            ? payload.maxPngBytes
            : MAX_PNG_BYTES,
        template: payload.template && typeof payload.template === "object" ? payload.template : {},
      };
      configReady = true;
      elements.jwtField.hidden = workstationConfig.authMode !== "browser";
      elements.jwt.required = workstationConfig.authMode === "browser";
      if (workstationConfig.authMode === "server") {
        elements.jwt.value = "";
      }
      renderConfigDetails(workstationConfig);
      setConfigBadge("ready", "工作站就緒");
      setStatus(
        "success",
        "工作站就緒",
        workstationConfig.authMode === "browser"
          ? "輸入 Token 與 STAFF JWT，或啟動相機掃描條碼。"
          : "輸入 Token 或啟動相機掃描條碼。",
      );
    } catch (error) {
      configReady = false;
      workstationConfig = null;
      setConfigBadge("error", "設定失敗");
      elements.configDetails.replaceChildren();
      appendConfigRow("連線", "本機服務設定無法讀取");
      setStatus(
        "error",
        "無法讀取工作站設定",
        `${unexpectedErrorMessage(error, "請確認 Docker 服務正在執行後重新整理頁面。")} 仍可使用本機 PNG。`,
      );
    } finally {
      updateControls();
    }
  }

  function validateToken(rawValue) {
    const token = rawValue.trim();
    if (!TOKEN_PATTERN.test(token)) {
      setFieldError(
        elements.token,
        elements.tokenError,
        "Token 必須是 8 至 32 個英數字、底線或連字號。",
      );
      throw new UiError("Token 格式不正確，請檢查後再試。");
    }
    setFieldError(elements.token, elements.tokenError);
    elements.token.value = token;
    return token;
  }

  function cardRequestHeaders() {
    const headers = { Accept: "image/png" };
    if (workstationConfig?.authMode === "browser") {
      const jwt = elements.jwt.value.trim();
      if (!jwt) {
        setFieldError(elements.jwt, elements.jwtError, "請輸入有效的 STAFF JWT。");
        throw new UiError("需要 STAFF JWT 才能下載卡面。");
      }
      setFieldError(elements.jwt, elements.jwtError);
      headers.Authorization = `Bearer ${jwt}`;
    }
    return headers;
  }

  function crc32(bytes) {
    let crc = 0xffffffff;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit += 1) {
        const mask = -(crc & 1);
        crc = (crc >>> 1) ^ (0xedb88320 & mask);
      }
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function templateAspectRatio() {
    const template = workstationConfig?.template;
    if (!template || typeof template !== "object") {
      return DEFAULT_TEMPLATE_ASPECT_RATIO;
    }

    const configuredRatio = Number(
      template.aspectRatio ?? template.imageAspectRatio ?? template.sourceImage?.aspectRatio,
    );
    if (Number.isFinite(configuredRatio) && configuredRatio > 0) {
      return configuredRatio;
    }

    const width = Number(
      template.imageWidthPixels ??
        template.widthPixels ??
        template.imageWidthMillimeters ??
        template.widthMm,
    );
    const height = Number(
      template.imageHeightPixels ??
        template.heightPixels ??
        template.imageHeightMillimeters ??
        template.heightMm,
    );
    if (Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0) {
      return width / height;
    }
    return DEFAULT_TEMPLATE_ASPECT_RATIO;
  }

  async function validatePngBlob(blob) {
    if (!(blob instanceof Blob) || blob.size < 33) {
      throw new UiError("收到的檔案不是有效的 PNG。");
    }
    const maxBytes = workstationConfig?.maxPngBytes || MAX_PNG_BYTES;
    if (blob.size > maxBytes) {
      const limitMiB = Math.max(1, Math.round(maxBytes / 1024 / 1024));
      throw new UiError(`PNG 超過 ${limitMiB} MiB，請確認來源檔案。`);
    }
    const header = new Uint8Array(await blob.slice(0, 33).arrayBuffer());
    if (!PNG_SIGNATURE.every((value, index) => header[index] === value)) {
      throw new UiError("收到的檔案不是有效的 PNG。");
    }

    const view = new DataView(header.buffer, header.byteOffset, header.byteLength);
    const isIhdr = [0x49, 0x48, 0x44, 0x52].every(
      (value, index) => header[12 + index] === value,
    );
    if (view.getUint32(8, false) !== 13 || !isIhdr) {
      throw new UiError("PNG 必須以完整的 13-byte IHDR 開頭。");
    }

    const storedCrc = view.getUint32(29, false);
    const calculatedCrc = crc32(header.subarray(12, 29));
    if (storedCrc !== calculatedCrc) {
      throw new UiError("PNG 的 IHDR 校驗碼無效，請重新取得圖檔。");
    }

    const width = view.getUint32(16, false);
    const height = view.getUint32(20, false);
    if (width === 0 || height === 0) {
      throw new UiError("PNG 尺寸必須大於 0。");
    }
    if (width > MAX_PNG_DIMENSION || height > MAX_PNG_DIMENSION) {
      throw new UiError(`PNG 單邊不可超過 ${MAX_PNG_DIMENSION.toLocaleString()} px。`);
    }
    if (width * height > MAX_PNG_PIXELS) {
      throw new UiError("PNG 總像素不可超過 50 MP。");
    }
    if (height <= width) {
      throw new UiError("卡面 PNG 必須是直式圖片。");
    }

    const expectedRatio = templateAspectRatio();
    const relativeDifference = Math.abs(width / height - expectedRatio) / expectedRatio;
    if (relativeDifference > TEMPLATE_ASPECT_RATIO_TOLERANCE) {
      throw new UiError("PNG 長寬比與校正模板不相容，請使用 App 下載的直式卡面。");
    }

    return { width, height };
  }

  async function imageDimensions(objectUrl) {
    const probe = new Image();
    probe.decoding = "async";
    probe.src = objectUrl;
    if (typeof probe.decode === "function") {
      await probe.decode();
    } else {
      await new Promise((resolve, reject) => {
        probe.addEventListener("load", resolve, { once: true });
        probe.addEventListener("error", reject, { once: true });
      });
    }
    if (!probe.naturalWidth || !probe.naturalHeight) {
      throw new UiError("瀏覽器無法解碼這張 PNG。");
    }
    return { width: probe.naturalWidth, height: probe.naturalHeight };
  }

  function suggestedDocumentName(source) {
    let value = String(source || "hitcon-card")
      .replace(/\.png$/i, "")
      .normalize("NFKD")
      .replace(/[^A-Za-z0-9_-]+/g, "-")
      .replace(/^[_-]+|[_-]+$/g, "")
      .slice(0, 72);
    if (!value) {
      value = "hitcon-card";
    }
    if (WINDOWS_RESERVED_NAME.test(value)) {
      value = `hitcon-${value}`;
    }
    return value;
  }

  function clearPreview() {
    if (currentPreviewUrl) {
      URL.revokeObjectURL(currentPreviewUrl);
      currentPreviewUrl = null;
    }
    currentPngBlob = null;
    currentPreviewLabel = "";
    elements.previewImage.removeAttribute("src");
    elements.previewImage.hidden = true;
    elements.previewEmpty.hidden = false;
    elements.previewState.textContent = "尚未載入";
    elements.previewState.dataset.ready = "false";
    elements.previewSource.textContent = "來源：—";
    elements.previewDimensions.textContent = "尺寸：—";
    elements.documentName.value = "";
    elements.previewConfirmed.checked = false;
    setFieldError(elements.documentName, elements.filenameError);
    updateControls();
  }

  async function showPreview(blob, { sourceLabel, suggestedName }, isCurrent = () => true) {
    const metadata = await validatePngBlob(blob);
    if (!isCurrent()) {
      return false;
    }

    const objectUrl = URL.createObjectURL(blob);
    let dimensions;
    try {
      dimensions = await imageDimensions(objectUrl);
    } catch (error) {
      URL.revokeObjectURL(objectUrl);
      if (error instanceof UiError) {
        throw error;
      }
      throw new UiError("瀏覽器無法解碼這張 PNG。");
    }

    if (!isCurrent()) {
      URL.revokeObjectURL(objectUrl);
      return false;
    }
    if (dimensions.width !== metadata.width || dimensions.height !== metadata.height) {
      URL.revokeObjectURL(objectUrl);
      throw new UiError("PNG 解碼尺寸與 IHDR 不一致，請重新取得圖檔。");
    }

    if (currentPreviewUrl) {
      URL.revokeObjectURL(currentPreviewUrl);
    }
    currentPreviewUrl = objectUrl;
    currentPngBlob = blob;
    currentPreviewLabel = sourceLabel;
    elements.previewImage.src = objectUrl;
    elements.previewImage.hidden = false;
    elements.previewEmpty.hidden = true;
    elements.previewState.textContent = "預覽就緒";
    elements.previewState.dataset.ready = "true";
    elements.previewSource.textContent = `來源：${sourceLabel}`;
    elements.previewDimensions.textContent = `尺寸：${dimensions.width} × ${dimensions.height} px`;
    elements.documentName.value = suggestedDocumentName(suggestedName);
    elements.previewConfirmed.checked = false;
    setFieldError(elements.documentName, elements.filenameError);
    updateControls();
    elements.previewStage.focus({ preventScroll: false });
    return true;
  }

  async function loadRemoteCard(rawToken = elements.token.value) {
    if (!configReady) {
      setStatus("error", "工作站尚未就緒", "請重新整理頁面；也可改用本機 PNG。");
      return;
    }

    let token;
    let headers;
    try {
      token = validateToken(rawToken);
      headers = cardRequestHeaders();
    } catch (error) {
      setStatus("error", "無法載入卡面", unexpectedErrorMessage(error, "請檢查輸入資料。"));
      if (!TOKEN_PATTERN.test(elements.token.value.trim())) {
        elements.token.focus();
      } else if (workstationConfig?.authMode === "browser" && !elements.jwt.value.trim()) {
        elements.jwt.focus();
      }
      return;
    }

    cardFetchController?.abort();
    const controller = new AbortController();
    cardFetchController = controller;
    const generation = ++previewGeneration;
    const isCurrent = () =>
      generation === previewGeneration &&
      cardFetchController === controller &&
      !controller.signal.aborted;
    clearPreview();
    setWorking(true);
    setStatus("loading", "正在下載卡面", `正在查詢 Token ${token}，請稍候。`);

    try {
      const response = await fetch(`/api/cards/${encodeURIComponent(token)}/png`, {
        method: "GET",
        headers,
        cache: "no-store",
        signal: controller.signal,
      });
      if (!isCurrent()) {
        return;
      }
      if (!response.ok) {
        const message = await responseErrorMessage(response, "下載卡面");
        if (!isCurrent()) {
          return;
        }
        throw new UiError(message);
      }
      const contentType = response.headers.get("content-type") || "";
      if (contentType && !contentType.toLowerCase().includes("image/png")) {
        throw new UiError("卡片 API 回傳了非 PNG 格式的檔案。");
      }
      const blob = await response.blob();
      if (!isCurrent()) {
        return;
      }
      const shown = await showPreview(
        blob,
        {
          sourceLabel: `卡片 API · ${token}`,
          suggestedName: `hitcon-card-${token}`,
        },
        isCurrent,
      );
      if (!shown || !isCurrent()) {
        return;
      }
      setStatus("success", "卡面預覽已就緒", "請核對畫面與方向，勾選確認後再下載校正 Word。");
    } catch (error) {
      if (error?.name !== "AbortError" && isCurrent()) {
        clearPreview();
        setStatus(
          "error",
          "卡面載入失敗",
          unexpectedErrorMessage(error, "無法連線到本機服務，請確認 Docker 與網路狀態。"),
        );
      }
    } finally {
      if (cardFetchController === controller && generation === previewGeneration) {
        cardFetchController = null;
        setWorking(false);
      }
    }
  }

  async function loadLocalPng(file) {
    if (!file) {
      return;
    }

    cardFetchController?.abort();
    cardFetchController = null;
    const generation = ++previewGeneration;
    const isCurrent = () => generation === previewGeneration;
    clearPreview();
    setWorking(true);
    setStatus("loading", "正在讀取本機 PNG", "正在驗證圖片格式與尺寸。");
    try {
      const shown = await showPreview(
        file,
        {
          sourceLabel: `本機檔案 · ${file.name}`,
          suggestedName: file.name,
        },
        isCurrent,
      );
      if (!shown || !isCurrent()) {
        return;
      }
      setStatus("success", "本機 PNG 已載入", "請核對畫面與方向，勾選確認後再下載校正 Word。");
    } catch (error) {
      if (isCurrent()) {
        clearPreview();
        setStatus(
          "error",
          "無法載入本機 PNG",
          unexpectedErrorMessage(error, "請重新選擇有效的 PNG 圖檔。"),
        );
      }
    } finally {
      elements.localPng.value = "";
      if (isCurrent()) {
        setWorking(false);
      }
    }
  }

  function validatedDocumentName() {
    const raw = elements.documentName.value.trim().replace(/\.docx$/i, "");
    if (
      !SAFE_NAME_PATTERN.test(raw) ||
      WINDOWS_RESERVED_NAME.test(raw)
    ) {
      setFieldError(
        elements.documentName,
        elements.filenameError,
        "請使用 1 至 80 個英數字、底線或連字號；不可使用 Windows 保留檔名。",
      );
      throw new UiError("Word 檔名格式不正確。");
    }
    setFieldError(elements.documentName, elements.filenameError);
    elements.documentName.value = raw;
    return raw;
  }

  async function validateDocxBlob(blob) {
    if (!(blob instanceof Blob) || blob.size < 4) {
      throw new UiError("服務沒有回傳有效的 Word 檔。");
    }
    if (blob.size > MAX_DOCX_BYTES) {
      throw new UiError("Word 檔超過 40 MiB，請確認服務狀態。");
    }
    const bytes = new Uint8Array(await blob.slice(0, 4).arrayBuffer());
    const isZip = ZIP_SIGNATURES.some((signature) =>
      signature.every((value, index) => bytes[index] === value),
    );
    if (!isZip) {
      throw new UiError("服務回傳的檔案不是有效的 DOCX。");
    }
  }

  function filenameFromDisposition(header, fallback) {
    if (!header) {
      return fallback;
    }
    let candidate = "";
    const encoded = header.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
    if (encoded) {
      try {
        candidate = decodeURIComponent(encoded[1].trim().replace(/^"|"$/g, ""));
      } catch {
        candidate = "";
      }
    }
    if (!candidate) {
      const plain = header.match(/filename\s*=\s*(?:"([^"]+)"|([^;]+))/i);
      candidate = (plain?.[1] || plain?.[2] || "").trim();
    }
    candidate = candidate
      .split(/[\\/]/)
      .pop()
      .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "-")
      .replace(/[. ]+$/g, "")
      .slice(0, 120);
    if (!candidate || WINDOWS_RESERVED_NAME.test(candidate)) {
      return fallback;
    }
    return candidate.toLowerCase().endsWith(".docx") ? candidate : `${candidate}.docx`;
  }

  function triggerDownload(blob, filename) {
    const objectUrl = URL.createObjectURL(blob);
    temporaryDownloadUrls.add(objectUrl);
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = filename;
    link.hidden = true;
    document.body.append(link);
    link.click();
    link.remove();
    window.setTimeout(() => {
      URL.revokeObjectURL(objectUrl);
      temporaryDownloadUrls.delete(objectUrl);
    }, 1500);
  }

  async function downloadDocument() {
    if (!currentPngBlob) {
      setStatus("error", "尚未載入卡面", "請先載入 Token 或選擇本機 PNG。");
      return;
    }
    if (!elements.previewConfirmed.checked) {
      setStatus("warning", "請先確認預覽", "確認卡面與方向後勾選核對方塊。");
      elements.previewConfirmed.focus();
      return;
    }

    let name;
    try {
      name = validatedDocumentName();
    } catch (error) {
      setStatus("error", "無法產生 Word", unexpectedErrorMessage(error, "請檢查檔名。"));
      elements.documentName.focus();
      return;
    }

    const sourceBlob = currentPngBlob;
    setWorking(true);
    setStatus("loading", "正在套用校正模板", "正在把確認過的 PNG 放入 Word 固定位置。");
    try {
      const response = await fetch(`/api/documents?name=${encodeURIComponent(name)}`, {
        method: "POST",
        headers: {
          Accept: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "Content-Type": "image/png",
        },
        body: sourceBlob,
        cache: "no-store",
      });
      if (!response.ok) {
        throw new UiError(await responseErrorMessage(response, "產生 Word"));
      }
      const documentBlob = await response.blob();
      await validateDocxBlob(documentBlob);
      const fallback = `${name}.docx`;
      const filename = filenameFromDisposition(response.headers.get("content-disposition"), fallback);
      triggerDownload(documentBlob, filename);
      setStatus(
        "success",
        "校正 Word 已下載",
        `${filename} 已交給瀏覽器下載；請使用 Windows Word 以 100% 比例列印。`,
      );
    } catch (error) {
      setStatus(
        "error",
        "Word 下載失敗",
        unexpectedErrorMessage(error, "無法連線到本機文件服務，請確認 Docker 狀態。"),
      );
    } finally {
      setWorking(false);
    }
  }

  function clearPhonePolling() {
    if (phonePollTimer !== null) {
      window.clearTimeout(phonePollTimer);
      phonePollTimer = null;
    }
    phonePollController?.abort();
    phonePollController = null;
  }

  function resetPhoneScannerUi(message = "尚未建立配對工作。") {
    phonePairingCode = "";
    elements.phonePairingCode.value = "----------";
    elements.phonePairingExpiry.textContent = message;
    elements.restartPhoneScanner.disabled = true;
  }

  async function scannerJsonPayload(response) {
    try {
      return await response.json();
    } catch {
      throw new UiError("手機掃描服務回傳了無效資料。");
    }
  }

  function scannerPayloadError(response, payload, fallback) {
    const message = typeof payload?.message === "string" ? payload.message.trim() : "";
    return new UiError(message || `${fallback}（HTTP ${response.status}）。`);
  }

  async function closePhoneSessionId(sessionId) {
    if (!SCANNER_SESSION_PATTERN.test(String(sessionId || ""))) {
      return;
    }
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 1_500);
    try {
      await fetch(`/api/scanner/sessions/${encodeURIComponent(sessionId)}/close`, {
        method: "POST",
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: controller.signal,
      });
    } catch {
      // Sessions are short-lived; closing the precise id is best effort.
    } finally {
      window.clearTimeout(timeout);
    }
  }

  function bestEffortClosePhoneSession(sessionId) {
    if (!SCANNER_SESSION_PATTERN.test(String(sessionId || ""))) {
      return;
    }
    const target = `/api/scanner/sessions/${encodeURIComponent(sessionId)}/close`;
    try {
      if (typeof navigator.sendBeacon === "function" && navigator.sendBeacon(target)) {
        return;
      }
    } catch {
      // Fall through to keepalive fetch.
    }
    try {
      void fetch(target, {
        method: "POST",
        headers: { Accept: "application/json" },
        cache: "no-store",
        keepalive: true,
      }).catch(() => {});
    } catch {
      // The relay expires automatically if the page is already unloading.
    }
  }

  function invalidatePhoneSession({ resetUi = true } = {}) {
    const sessionId = phoneSessionId;
    phoneSessionGeneration += 1;
    clearPhonePolling();
    phoneSessionId = null;
    phoneTokenHandled = false;
    if (resetUi) {
      resetPhoneScannerUi();
    } else {
      phonePairingCode = "";
    }
    return sessionId;
  }

  async function stopPhoneSession({ resetUi = true } = {}) {
    const sessionId = invalidatePhoneSession({ resetUi });
    if (sessionId) {
      await closePhoneSessionId(sessionId);
    }
  }

  function phoneSessionIsCurrent(generation, sessionId) {
    return (
      generation === phoneSessionGeneration &&
      phoneSessionId === sessionId &&
      !phoneTokenHandled
    );
  }

  function updatePhoneSessionExpiry(expiresInSeconds) {
    const seconds = Math.max(0, Math.floor(Number(expiresInSeconds) || 0));
    elements.phonePairingExpiry.textContent =
      seconds > 0 ? `配對工作剩餘 ${seconds} 秒` : "配對工作即將到期";
  }

  function expirePhoneSession(generation, sessionId, message) {
    if (!phoneSessionIsCurrent(generation, sessionId)) {
      return;
    }
    phoneSessionGeneration += 1;
    clearPhonePolling();
    phoneSessionId = null;
    phonePairingCode = "";
    phoneTokenHandled = false;
    elements.phonePairingCode.value = "----------";
    elements.phonePairingExpiry.textContent = "配對工作已結束";
    elements.restartPhoneScanner.disabled = false;
    setPhoneScannerStatus(message, "error");
  }

  function schedulePhoneSessionPoll(generation, sessionId, delay = PHONE_SCANNER_POLL_INTERVAL_MS) {
    if (!phoneSessionIsCurrent(generation, sessionId)) {
      return;
    }
    if (phonePollTimer !== null) {
      window.clearTimeout(phonePollTimer);
    }
    phonePollTimer = window.setTimeout(() => {
      phonePollTimer = null;
      void pollPhoneSession(generation, sessionId);
    }, delay);
  }

  async function acceptPhoneSessionToken(generation, sessionId, token) {
    if (!phoneSessionIsCurrent(generation, sessionId) || !TOKEN_PATTERN.test(token)) {
      return;
    }
    phoneTokenHandled = true;
    clearPhonePolling();
    elements.restartPhoneScanner.disabled = true;
    setPhoneScannerStatus(`手機已讀取 ${token}，正在載入預覽。`, "success");

    const acceptanceGeneration = ++phoneSessionGeneration;
    phoneSessionId = null;
    phonePairingCode = "";
    await closePhoneSessionId(sessionId);
    if (phoneSessionGeneration !== acceptanceGeneration) {
      return;
    }

    elements.token.value = token;
    setFieldError(elements.token, elements.tokenError);
    if (elements.phoneScannerDialog.open && typeof elements.phoneScannerDialog.close === "function") {
      elements.phoneScannerDialog.close();
    } else {
      elements.phoneScannerDialog.removeAttribute("open");
    }
    await loadRemoteCard(token);
  }

  async function pollPhoneSession(generation, sessionId) {
    if (!phoneSessionIsCurrent(generation, sessionId)) {
      return;
    }
    const controller = new AbortController();
    phonePollController = controller;
    try {
      const response = await fetch(`/api/scanner/sessions/${encodeURIComponent(sessionId)}`, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: controller.signal,
      });
      const payload = await scannerJsonPayload(response);
      if (!phoneSessionIsCurrent(generation, sessionId)) {
        return;
      }
      if (!response.ok) {
        if (response.status === 404) {
          expirePhoneSession(
            generation,
            sessionId,
            typeof payload?.message === "string"
              ? payload.message
              : "手機掃描工作已到期，請重新建立掃描工作。",
          );
          return;
        }
        throw scannerPayloadError(response, payload, "讀取手機掃描狀態失敗");
      }

      const session = payload?.session;
      if (
        !session ||
        session.id !== sessionId ||
        typeof session.paired !== "boolean" ||
        !Number.isFinite(session.expiresInSeconds)
      ) {
        throw new UiError("手機掃描服務回傳了無效的工作狀態。");
      }
      updatePhoneSessionExpiry(session.expiresInSeconds);
      if (session.token !== null && session.token !== undefined) {
        const token = String(session.token).trim();
        if (!TOKEN_PATTERN.test(token)) {
          bestEffortClosePhoneSession(sessionId);
          expirePhoneSession(generation, sessionId, "手機回傳的 Token 格式無效，請重新建立掃描工作。");
          return;
        }
        await acceptPhoneSessionToken(generation, sessionId, token);
        return;
      }

      setPhoneScannerStatus(
        session.paired
          ? "手機已配對，等待掃描條碼。"
          : "等待 USB 手機自動連線；未連線時才使用配對碼。",
        session.paired ? "success" : "info",
      );
      schedulePhoneSessionPoll(generation, sessionId);
    } catch (error) {
      if (error?.name !== "AbortError" && phoneSessionIsCurrent(generation, sessionId)) {
        setPhoneScannerStatus(
          unexpectedErrorMessage(error, "暫時無法讀取手機狀態，正在重試。"),
          "error",
        );
        schedulePhoneSessionPoll(generation, sessionId, 1_000);
      }
    } finally {
      if (phonePollController === controller) {
        phonePollController = null;
      }
    }
  }

  async function createPhoneSession() {
    const generation = ++phoneSessionGeneration;
    phoneTokenHandled = false;
    resetPhoneScannerUi("正在建立配對工作…");
    setPhoneScannerStatus("正在建立手機掃描工作…", "info");

    try {
      const response = await fetch("/api/scanner/sessions", {
        method: "POST",
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
      const payload = await scannerJsonPayload(response);
      if (!response.ok) {
        throw scannerPayloadError(response, payload, "建立手機掃描工作失敗");
      }
      const session = payload?.session;
      if (
        !session ||
        !SCANNER_SESSION_PATTERN.test(String(session.id || "")) ||
        !SCANNER_PAIRING_CODE_PATTERN.test(String(session.pairingCode || "")) ||
        !Number.isFinite(session.expiresInSeconds)
      ) {
        throw new UiError("手機掃描服務回傳了無效的配對資料。");
      }

      const sessionId = String(session.id);
      if (generation !== phoneSessionGeneration || !elements.phoneScannerDialog.open) {
        bestEffortClosePhoneSession(sessionId);
        return;
      }
      phoneSessionId = sessionId;
      phonePairingCode = String(session.pairingCode);
      elements.phonePairingCode.value = phonePairingCode;
      updatePhoneSessionExpiry(session.expiresInSeconds);
      elements.restartPhoneScanner.disabled = false;
      setPhoneScannerStatus("等待 USB 手機自動連線；未連線時才使用配對碼。", "info");
      schedulePhoneSessionPoll(generation, sessionId, 0);
    } catch (error) {
      if (generation === phoneSessionGeneration && elements.phoneScannerDialog.open) {
        resetPhoneScannerUi("無法建立配對工作");
        elements.restartPhoneScanner.disabled = false;
        setPhoneScannerStatus(
          unexpectedErrorMessage(error, "無法連線到手機掃描服務。"),
          "error",
        );
      }
    }
  }

  async function runPhoneSessionTransitions() {
    while (phoneRestartRequested) {
      phoneRestartRequested = false;
      await stopPhoneSession();
      if (elements.phoneScannerDialog.open) {
        await createPhoneSession();
      }
    }
  }

  function requestPhoneSessionRestart() {
    phoneRestartRequested = true;
    if (phoneTransitionPromise) {
      return phoneTransitionPromise;
    }
    phoneTransitionPromise = runPhoneSessionTransitions().finally(() => {
      phoneTransitionPromise = null;
      if (phoneRestartRequested) {
        void requestPhoneSessionRestart();
      }
    });
    return phoneTransitionPromise;
  }

  function openPhoneScannerDialog() {
    if (!configReady) {
      setStatus("error", "工作站尚未就緒", "請重新整理頁面，或改用本機 PNG。");
      return;
    }
    if (workstationConfig?.authMode === "browser" && !elements.jwt.value.trim()) {
      setFieldError(elements.jwt, elements.jwtError, "請先輸入 STAFF JWT，再使用手機掃描。");
      setStatus("warning", "需要 STAFF JWT", "手機送回 Token 後會載入預覽，請先提供 STAFF 憑證。");
      elements.jwt.focus();
      return;
    }
    setFieldError(elements.jwt, elements.jwtError);
    if (typeof elements.phoneScannerDialog.showModal === "function") {
      elements.phoneScannerDialog.showModal();
    } else {
      elements.phoneScannerDialog.setAttribute("open", "");
    }
    void requestPhoneSessionRestart();
  }

  function closePhoneScannerDialog() {
    phoneRestartRequested = false;
    if (elements.phoneScannerDialog.open && typeof elements.phoneScannerDialog.close === "function") {
      elements.phoneScannerDialog.close();
    } else {
      elements.phoneScannerDialog.removeAttribute("open");
      void stopPhoneSession();
      elements.scanCardPhone.focus();
    }
  }

  function handlePhoneScannerPageHide() {
    phoneRestartRequested = false;
    const sessionId = invalidatePhoneSession({ resetUi: false });
    if (sessionId) {
      bestEffortClosePhoneSession(sessionId);
    }
  }

  function cameraErrorMessage(error) {
    const messages = {
      NotAllowedError: "相機權限未開啟。請在瀏覽器網址列允許相機後重試。",
      NotFoundError: "找不到可用的相機，請確認裝置已連接。",
      NotReadableError: "相機目前被其他程式占用，請關閉該程式後重試。",
      OverconstrainedError: "選擇的相機不支援所需設定，請改用其他相機。",
      SecurityError: "瀏覽器封鎖了相機。請使用 http://localhost 或受信任的 HTTPS。",
      TypeError: "此頁面無法使用相機。請以 http://localhost 開啟工作站。",
    };
    return messages[error?.name] || "相機啟動失敗，請關閉後手動輸入 Token。";
  }

  function attachDeviceChangeListener() {
    if (cameraDeviceListenerAttached || !navigator.mediaDevices?.addEventListener) {
      return;
    }
    navigator.mediaDevices.addEventListener("devicechange", handleCameraDeviceChange);
    cameraDeviceListenerAttached = true;
  }

  function detachDeviceChangeListener() {
    if (!cameraDeviceListenerAttached || !navigator.mediaDevices?.removeEventListener) {
      return;
    }
    navigator.mediaDevices.removeEventListener("devicechange", handleCameraDeviceChange);
    cameraDeviceListenerAttached = false;
  }

  async function handleCameraDeviceChange() {
    if (elements.cameraDialog.open && cameraStream) {
      await populateCameraDevices();
    }
  }

  async function populateCameraDevices() {
    if (!navigator.mediaDevices?.enumerateDevices) {
      return;
    }
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      cameraDevices = devices.filter((device) => device.kind === "videoinput");
      const activeDeviceId = cameraStream?.getVideoTracks()[0]?.getSettings()?.deviceId || "";
      elements.cameraSelect.replaceChildren();

      if (cameraDevices.length === 0) {
        const option = new Option("找不到相機", "");
        elements.cameraSelect.add(option);
        elements.cameraSelect.disabled = true;
        elements.switchCamera.disabled = true;
        return;
      }

      cameraDevices.forEach((device, index) => {
        const option = new Option(device.label || `相機 ${index + 1}`, device.deviceId);
        elements.cameraSelect.add(option);
      });
      if (activeDeviceId && cameraDevices.some((device) => device.deviceId === activeDeviceId)) {
        elements.cameraSelect.value = activeDeviceId;
      }
      elements.cameraSelect.disabled = cameraStarting || cameraDevices.length < 1;
      elements.switchCamera.disabled = cameraStarting || cameraDevices.length < 2;
    } catch {
      elements.cameraSelect.disabled = true;
      elements.switchCamera.disabled = true;
    }
  }

  function currentCameraTrack() {
    return cameraStream?.getVideoTracks()[0] || null;
  }

  function cameraSessionIsCurrent(generation, track) {
    return generation === cameraGeneration && track && currentCameraTrack() === track;
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

  function formatZoom(value) {
    const numeric = Number(value);
    return `${(Number.isFinite(numeric) ? numeric : 1).toFixed(1)}×`;
  }

  function resetCameraEnhancementControls() {
    if (focusRestoreTimer !== null) {
      window.clearTimeout(focusRestoreTimer);
      focusRestoreTimer = null;
    }
    if (zoomApplyTimer !== null) {
      window.clearTimeout(zoomApplyTimer);
      zoomApplyTimer = null;
    }
    zoomApplySequence += 1;
    pendingZoomRequest = null;
    cameraCapabilities = null;
    cameraBaseConstraints = {};
    cameraPreferredSettings = {};
    cameraZoomSetting = null;
    cameraBaseLensHint = "";
    elements.refocusCamera.disabled = true;
    elements.zoomControl.hidden = true;
    elements.cameraZoom.disabled = true;
    elements.cameraZoom.min = "1";
    elements.cameraZoom.max = "1";
    elements.cameraZoom.step = "0.1";
    elements.cameraZoom.value = "1";
    elements.cameraZoomValue.value = "1.0×";
    elements.cameraLensHint.textContent = "";
  }

  function cameraAdvancedSettings(overrides = {}) {
    return {
      ...cameraPreferredSettings,
      ...(cameraZoomSetting === null ? {} : { zoom: cameraZoomSetting }),
      ...overrides,
    };
  }

  async function applyCameraAdvancedSettings(track, generation, overrides = {}) {
    if (!cameraSessionIsCurrent(generation, track) || typeof track.applyConstraints !== "function") {
      return false;
    }
    const settings = cameraAdvancedSettings(overrides);
    const advanced = Object.entries(settings).map(([name, value]) => ({ [name]: value }));
    if (advanced.length === 0) {
      return true;
    }
    try {
      await track.applyConstraints({ ...cameraBaseConstraints, advanced });
    } catch {
      return false;
    }
    return cameraSessionIsCurrent(generation, track);
  }

  function zoomCapabilityDetails(capability) {
    const min = Number(capability?.min);
    const max = Number(capability?.max);
    const rawStep = Number(capability?.step);
    if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) {
      return null;
    }
    return {
      min,
      max,
      step: Number.isFinite(rawStep) && rawStep > 0 ? rawStep : Math.max(0.1, (max - min) / 100),
    };
  }

  async function configureCameraEnhancements(generation) {
    const track = currentCameraTrack();
    if (!cameraSessionIsCurrent(generation, track)) {
      return;
    }
    resetCameraEnhancementControls();
    if (!cameraSessionIsCurrent(generation, track)) {
      return;
    }
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
      cameraBaseLensHint = "此瀏覽器無法控制對焦；模糊時請把條碼拿遠。";
      elements.cameraLensHint.textContent = cameraBaseLensHint;
      return;
    }

    let capabilities;
    try {
      capabilities = track.getCapabilities();
    } catch {
      cameraBaseLensHint = "無法讀取鏡頭控制；模糊時請把條碼拿遠。";
      elements.cameraLensHint.textContent = cameraBaseLensHint;
      return;
    }
    if (!cameraSessionIsCurrent(generation, track)) {
      return;
    }

    cameraCapabilities = capabilities || {};
    ["focusMode", "exposureMode", "whiteBalanceMode"].forEach((name) => {
      if (capabilityModes(cameraCapabilities[name]).includes("continuous")) {
        cameraPreferredSettings[name] = "continuous";
      }
    });

    const focusModes = capabilityModes(cameraCapabilities.focusMode);
    const canRefocus = focusModes.includes("single-shot");
    elements.refocusCamera.disabled = !canRefocus;

    const zoom = zoomCapabilityDetails(cameraCapabilities.zoom);
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

    if (canRefocus) {
      cameraBaseLensHint = zoom
        ? "畫面模糊時可重新對焦；條碼太小可調整縮放。"
        : "畫面模糊時可按「重新對焦」。";
    } else if (focusModes.includes("continuous")) {
      cameraBaseLensHint = zoom
        ? "鏡頭會持續對焦；條碼太小可調整縮放。"
        : "鏡頭會持續對焦；請保持條碼穩定。";
    } else {
      cameraBaseLensHint = zoom
        ? "無網頁對焦控制：請把條碼拿遠，可再調整縮放。"
        : "無網頁對焦控制：請把條碼稍微拿遠並保持平行。";
    }
    elements.cameraLensHint.textContent = cameraBaseLensHint;

    const applied = await applyCameraAdvancedSettings(track, generation);
    if (
      cameraSessionIsCurrent(generation, track) &&
      !applied &&
      Object.keys(cameraPreferredSettings).length > 0
    ) {
      elements.cameraLensHint.textContent = "無法套用鏡頭自動設定；請調整距離與光線。";
    }
  }

  async function refocusActiveCamera() {
    const generation = cameraGeneration;
    const track = currentCameraTrack();
    const focusModes = capabilityModes(cameraCapabilities?.focusMode);
    if (!cameraSessionIsCurrent(generation, track) || !focusModes.includes("single-shot")) {
      elements.refocusCamera.disabled = true;
      return;
    }

    if (focusRestoreTimer !== null) {
      window.clearTimeout(focusRestoreTimer);
      focusRestoreTimer = null;
    }
    elements.refocusCamera.disabled = true;
    elements.cameraLensHint.textContent = "正在重新對焦，請保持條碼穩定。";
    const applied = await applyCameraAdvancedSettings(track, generation, {
      focusMode: "single-shot",
    });
    if (!cameraSessionIsCurrent(generation, track)) {
      return;
    }
    if (!applied) {
      elements.cameraLensHint.textContent = "無法重新對焦；請把條碼稍微拿遠。";
      elements.refocusCamera.disabled = false;
      return;
    }

    elements.cameraLensHint.textContent = "已要求重新對焦，請等待畫面清晰。";
    elements.refocusCamera.disabled = false;
    if (cameraPreferredSettings.focusMode === "continuous") {
      focusRestoreTimer = window.setTimeout(() => {
        focusRestoreTimer = null;
        if (cameraSessionIsCurrent(generation, track)) {
          void applyCameraAdvancedSettings(track, generation);
          elements.cameraLensHint.textContent = cameraBaseLensHint;
        }
      }, 900);
    }
  }

  async function applyZoomValue(track, generation, value, sequence) {
    cameraZoomSetting = value;
    const applied = await applyCameraAdvancedSettings(track, generation);
    if (!cameraSessionIsCurrent(generation, track) || sequence !== zoomApplySequence) {
      return;
    }
    if (applied) {
      elements.cameraLensHint.textContent = `${cameraBaseLensHint} 目前 ${formatZoom(value)}。`;
      return;
    }

    const actualZoom = Number(track.getSettings?.().zoom);
    if (Number.isFinite(actualZoom)) {
      cameraZoomSetting = actualZoom;
      elements.cameraZoom.value = String(actualZoom);
      elements.cameraZoomValue.value = formatZoom(actualZoom);
    }
    elements.cameraLensHint.textContent = "無法套用縮放；請直接調整條碼距離。";
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
          request.sequence === zoomApplySequence &&
          cameraSessionIsCurrent(request.generation, request.track)
        ) {
          await applyZoomValue(
            request.track,
            request.generation,
            request.value,
            request.sequence,
          );
        }
      }
    } finally {
      zoomApplyInFlight = false;
      if (pendingZoomRequest) {
        void drainZoomRequests();
      }
    }
  }

  function scheduleZoomChange() {
    const value = Number(elements.cameraZoom.value);
    const zoom = zoomCapabilityDetails(cameraCapabilities?.zoom);
    if (!zoom || !Number.isFinite(value)) {
      return;
    }
    const clamped = Math.min(zoom.max, Math.max(zoom.min, value));
    elements.cameraZoomValue.value = formatZoom(clamped);
    if (zoomApplyTimer !== null) {
      window.clearTimeout(zoomApplyTimer);
    }
    const generation = cameraGeneration;
    const track = currentCameraTrack();
    const sequence = ++zoomApplySequence;
    cameraZoomSetting = clamped;
    zoomApplyTimer = window.setTimeout(() => {
      zoomApplyTimer = null;
      if (cameraSessionIsCurrent(generation, track)) {
        pendingZoomRequest = { track, generation, value: clamped, sequence };
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
    if (zxingCanvasTimer !== null) {
      window.clearTimeout(zxingCanvasTimer);
      zxingCanvasTimer = null;
    }
    try {
      zxingReader?.reset?.();
    } catch {
      // Older ZXing builds do not expose reset consistently.
    }
    zxingReader = null;
    zxingActiveGeneration = 0;
    zxingRoiVariantIndex = 0;
    nativeDetector = null;
    nativeAssistAttempted = false;
    nativeFailureCount = 0;
  }

  function releaseCameraStream(stream = cameraStream) {
    const releasingCurrentStream = !stream || cameraStream === stream;
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
    }
    if (cameraStream === stream) {
      cameraStream = null;
    }
    if (elements.cameraVideo.srcObject === stream || (!stream && !cameraStream)) {
      elements.cameraVideo.pause();
      elements.cameraVideo.srcObject = null;
    }
    if (releasingCurrentStream) {
      resetCameraEnhancementControls();
    }
  }

  async function stopCamera() {
    cameraGeneration += 1;
    cameraStarting = false;
    stopScannerLoops();
    releaseCameraStream();
    detachDeviceChangeListener();
    elements.cameraSelect.disabled = true;
    elements.switchCamera.disabled = true;
  }

  async function requestCameraStream(deviceId) {
    const video = deviceId
      ? {
          deviceId: { exact: deviceId },
          width: { ideal: 1920 },
          height: { ideal: 1080 },
          frameRate: { ideal: 30 },
        }
      : {
          facingMode: { ideal: "environment" },
          width: { ideal: 1920 },
          height: { ideal: 1080 },
          frameRate: { ideal: 30 },
        };
    try {
      return await navigator.mediaDevices.getUserMedia({ audio: false, video });
    } catch (error) {
      if (!deviceId && error?.name === "OverconstrainedError") {
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

  function zxingResultText(result) {
    if (!result) {
      return "";
    }
    if (typeof result.getText === "function") {
      return String(result.getText() || "");
    }
    return typeof result.text === "string" ? result.text : "";
  }

  function isZxingCode128(result) {
    const library = globalThis.ZXingBrowser;
    if (!result || !library?.BarcodeFormat || typeof result.getBarcodeFormat !== "function") {
      return true;
    }
    return result.getBarcodeFormat() === library.BarcodeFormat.CODE_128;
  }

  async function acceptScannedValue(rawValue) {
    if (scanHandled) {
      return;
    }
    const token = String(rawValue || "").trim();
    if (!TOKEN_PATTERN.test(token)) {
      setCameraStatus("讀到的條碼不是有效的列印 Token，請重新對準 Code 128。", "error");
      return;
    }

    scanHandled = true;
    setCameraStatus(`已讀取 ${token}，正在載入預覽。`, "success");
    await stopCamera();
    elements.token.value = token;
    setFieldError(elements.token, elements.tokenError);
    if (elements.cameraDialog.open) {
      elements.cameraDialog.close();
    } else {
      elements.cameraDialog.removeAttribute("open");
    }
    await loadRemoteCard(token);
  }

  function clearNativeAssistTimer() {
    if (nativeAssistTimer !== null) {
      window.clearTimeout(nativeAssistTimer);
      nativeAssistTimer = null;
    }
  }

  function scheduleNativeZxingAssist(generation) {
    if (
      nativeAssistAttempted ||
      nativeAssistTimer !== null ||
      zxingActiveGeneration === generation
    ) {
      return;
    }
    nativeAssistTimer = window.setTimeout(() => {
      nativeAssistTimer = null;
      if (
        generation !== cameraGeneration ||
        scanHandled ||
        !nativeDetector ||
        !cameraStream
      ) {
        return;
      }
      nativeAssistAttempted = true;
      startZxingScanner(generation, { assistingNative: true });
    }, NATIVE_ZXING_ASSIST_DELAY_MS);
  }

  async function startNativeScanLoop(generation) {
    if (
      generation !== cameraGeneration ||
      scanHandled ||
      !nativeDetector ||
      !cameraStream
    ) {
      return;
    }
    scheduleNativeZxingAssist(generation);

    if (elements.cameraVideo.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      try {
        const results = await nativeDetector.detect(elements.cameraVideo);
        if (generation !== cameraGeneration || scanHandled || !cameraStream) {
          return;
        }
        nativeFailureCount = 0;
        const code = results.find((result) => result.format === "code_128" && result.rawValue);
        if (code) {
          await acceptScannedValue(code.rawValue);
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
          clearNativeAssistTimer();
          nativeAssistAttempted = true;
          nativeDetector = null;
          const zxingStarted = startZxingScanner(generation);
          if (generation !== cameraGeneration) {
            return;
          }
          if (zxingStarted) {
            return;
          }
          handleMissingDecoder(generation);
          return;
        }
      }
    }

    if (generation === cameraGeneration && !scanHandled) {
      nativeScanTimer = window.setTimeout(() => {
        void startNativeScanLoop(generation);
      }, NATIVE_SCAN_INTERVAL_MS);
    }
  }

  function startZxingCanvasLoop(generation, reader) {
    const canvas = elements.scanCanvas;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context || typeof reader?.decodeFromCanvas !== "function") {
      return false;
    }

    const sessionIsCurrent = () =>
      generation === cameraGeneration &&
      zxingActiveGeneration === generation &&
      zxingReader === reader &&
      !scanHandled &&
      Boolean(cameraStream);

    const scan = async () => {
      if (!sessionIsCurrent()) {
        return;
      }
      if (elements.cameraVideo.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
        const sourceWidth = elements.cameraVideo.videoWidth;
        const sourceHeight = elements.cameraVideo.videoHeight;
        if (sourceWidth && sourceHeight) {
          const variant = ZXING_ROI_VARIANTS[zxingRoiVariantIndex % ZXING_ROI_VARIANTS.length];
          zxingRoiVariantIndex += 1;
          const cropWidth = Math.max(1, Math.round(sourceWidth * variant.widthRatio));
          const cropHeight = Math.max(
            1,
            Math.min(
              Math.round(sourceHeight * 0.58),
              Math.round(cropWidth / variant.aspectRatio),
            ),
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
            if (!sessionIsCurrent()) {
              return;
            }
            if (isZxingCode128(result)) {
              await acceptScannedValue(zxingResultText(result));
              if (scanHandled) {
                return;
              }
            }
          } catch {
            // NotFound is the normal result while the barcode is outside the frame.
          }
        }
      }
      if (sessionIsCurrent()) {
        zxingCanvasTimer = window.setTimeout(scan, ZXING_SCAN_INTERVAL_MS);
      }
    };

    void scan();
    return true;
  }

  function startZxingScanner(generation, { assistingNative = false } = {}) {
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
      if (!startZxingCanvasLoop(generation, reader)) {
        if (zxingReader === reader) {
          zxingReader = null;
          zxingActiveGeneration = 0;
        }
        return false;
      }
      setCameraStatus(
        assistingNative
          ? "仍在掃描；已啟用離線 ZXing 中央區域輔助。"
          : "相機已啟動，請把條碼放在中央綠框內。",
        "info",
      );
      return true;
    } catch {
      zxingReader = null;
      zxingActiveGeneration = 0;
      return false;
    }
  }

  function handleMissingDecoder(generation) {
    if (generation !== cameraGeneration) {
      return false;
    }
    stopScannerLoops();
    releaseCameraStream();
    detachDeviceChangeListener();
    elements.cameraSelect.disabled = true;
    elements.switchCamera.disabled = true;
    setCameraPlaceholder(
      true,
      "瀏覽器沒有可用的 Code 128 解碼器",
      "error",
    );
    setCameraStatus(
      "無法啟用 BarcodeDetector 或離線 ZXing。請關閉相機並手動輸入 Token。",
      "error",
    );
    return true;
  }

  async function startCamera(deviceId = "") {
    if (cameraStarting) {
      return;
    }
    cameraStarting = true;
    await stopCamera();
    cameraStarting = true;
    scanHandled = false;
    const generation = ++cameraGeneration;
    elements.cameraSelect.disabled = true;
    elements.switchCamera.disabled = true;
    setCameraPlaceholder(true, "正在啟動相機…", "loading");
    setCameraStatus("等待相機權限…", "info");

    if (!navigator.mediaDevices?.getUserMedia) {
      cameraStarting = false;
      setCameraPlaceholder(true, "此頁面無法使用相機", "error");
      setCameraStatus(
        "請使用 http://localhost 或受信任的 HTTPS 開啟工作站，或改為手動輸入 Token。",
        "error",
      );
      return;
    }

    try {
      const stream = await requestCameraStream(deviceId);
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
      cameraStarting = false;
      setCameraPlaceholder(false);
      attachDeviceChangeListener();
      await populateCameraDevices();
      if (generation !== cameraGeneration || cameraStream !== stream) {
        return;
      }
      await configureCameraEnhancements(generation);
      if (generation !== cameraGeneration || cameraStream !== stream) {
        return;
      }

      setCameraStatus("正在檢查瀏覽器的 Code 128 掃描引擎…", "info");
      const detector = await nativeCode128Detector();
      if (generation !== cameraGeneration || cameraStream !== stream) {
        return;
      }
      nativeDetector = detector;
      if (nativeDetector) {
        setCameraStatus("相機已啟動，使用瀏覽器原生引擎掃描 Code 128。", "info");
        void startNativeScanLoop(generation);
        return;
      }
      const zxingStarted = startZxingScanner(generation);
      if (generation !== cameraGeneration) {
        return;
      }
      if (zxingStarted) {
        return;
      }
      handleMissingDecoder(generation);
    } catch (error) {
      if (generation !== cameraGeneration) {
        return;
      }
      cameraStarting = false;
      stopScannerLoops();
      releaseCameraStream();
      detachDeviceChangeListener();
      setCameraPlaceholder(true, "相機無法啟動", "error");
      setCameraStatus(cameraErrorMessage(error), "error");
    }
  }

  async function openCameraDialog() {
    if (!configReady) {
      setStatus("error", "工作站尚未就緒", "請重新整理頁面，或改用本機 PNG。");
      return;
    }
    if (workstationConfig?.authMode === "browser" && !elements.jwt.value.trim()) {
      setFieldError(elements.jwt, elements.jwtError, "請先輸入 STAFF JWT，再掃描條碼。");
      setStatus("warning", "需要 STAFF JWT", "掃描後會立即載入預覽，請先提供 STAFF 憑證。");
      elements.jwt.focus();
      return;
    }
    setFieldError(elements.jwt, elements.jwtError);
    if (typeof elements.cameraDialog.showModal === "function") {
      elements.cameraDialog.showModal();
    } else {
      elements.cameraDialog.setAttribute("open", "");
    }
    await startCamera();
  }

  async function closeCameraDialog() {
    await stopCamera();
    if (elements.cameraDialog.open && typeof elements.cameraDialog.close === "function") {
      elements.cameraDialog.close();
    } else {
      elements.cameraDialog.removeAttribute("open");
      elements.scanCard.focus();
    }
  }

  async function switchToNextCamera() {
    if (cameraDevices.length < 2 || cameraStarting) {
      return;
    }
    const active = elements.cameraSelect.value;
    const currentIndex = cameraDevices.findIndex((device) => device.deviceId === active);
    const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % cameraDevices.length : 0;
    await startCamera(cameraDevices[nextIndex].deviceId);
  }

  function toggleJwtVisibility() {
    const showing = elements.jwt.type === "text";
    elements.jwt.type = showing ? "password" : "text";
    elements.toggleJwt.textContent = showing ? "顯示" : "隱藏";
    elements.toggleJwt.setAttribute("aria-pressed", String(!showing));
    elements.toggleJwt.setAttribute("aria-label", showing ? "顯示 STAFF JWT" : "隱藏 STAFF JWT");
    elements.jwt.focus();
  }

  elements.cardForm.addEventListener("submit", (event) => {
    event.preventDefault();
    void loadRemoteCard();
  });

  elements.token.addEventListener("input", () => {
    setFieldError(elements.token, elements.tokenError);
  });

  elements.jwt.addEventListener("input", () => {
    setFieldError(elements.jwt, elements.jwtError);
  });

  elements.toggleJwt.addEventListener("click", toggleJwtVisibility);
  elements.scanCard.addEventListener("click", () => {
    void openCameraDialog();
  });
  elements.scanCardPhone.addEventListener("click", openPhoneScannerDialog);
  elements.chooseLocalPng.addEventListener("click", () => {
    elements.localPng.click();
  });
  elements.localPng.addEventListener("change", () => {
    void loadLocalPng(elements.localPng.files?.[0]);
  });
  elements.previewConfirmed.addEventListener("change", updateControls);
  elements.documentName.addEventListener("input", () => {
    setFieldError(elements.documentName, elements.filenameError);
  });
  elements.downloadWord.addEventListener("click", () => {
    void downloadDocument();
  });

  elements.closeCamera.addEventListener("click", () => {
    void closeCameraDialog();
  });
  elements.cameraDone.addEventListener("click", () => {
    void closeCameraDialog();
  });
  elements.switchCamera.addEventListener("click", () => {
    void switchToNextCamera();
  });
  elements.refocusCamera.addEventListener("click", () => {
    void refocusActiveCamera();
  });
  elements.cameraZoom.addEventListener("input", scheduleZoomChange);
  elements.cameraSelect.addEventListener("change", () => {
    const deviceId = elements.cameraSelect.value;
    if (deviceId) {
      void startCamera(deviceId);
    }
  });
  elements.cameraDialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    void closeCameraDialog();
  });
  elements.cameraDialog.addEventListener("close", () => {
    void stopCamera();
    elements.scanCard.focus();
  });

  elements.closePhoneScanner.addEventListener("click", closePhoneScannerDialog);
  elements.phoneScannerDone.addEventListener("click", closePhoneScannerDialog);
  elements.restartPhoneScanner.addEventListener("click", () => {
    void requestPhoneSessionRestart();
  });
  elements.phoneScannerDialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    closePhoneScannerDialog();
  });
  elements.phoneScannerDialog.addEventListener("close", () => {
    phoneRestartRequested = false;
    void stopPhoneSession();
    elements.scanCardPhone.focus();
  });

  window.addEventListener("pagehide", handlePhoneScannerPageHide);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      resetPhoneScannerUi();
      if (elements.phoneScannerDialog.open) {
        void requestPhoneSessionRestart();
      }
    }
  });

  window.addEventListener("beforeunload", () => {
    cardFetchController?.abort();
    elements.jwt.value = "";
    stopScannerLoops();
    releaseCameraStream();
    detachDeviceChangeListener();
    if (currentPreviewUrl) {
      URL.revokeObjectURL(currentPreviewUrl);
    }
    temporaryDownloadUrls.forEach((url) => URL.revokeObjectURL(url));
    temporaryDownloadUrls.clear();
  });

  clearPreview();
  void loadConfig();
})();
