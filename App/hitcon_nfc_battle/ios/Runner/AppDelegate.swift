import CoreNFC
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeNfcWriter: NativeNfcWriter?
  private var nativeCollectionNfcScanner: NativeCollectionNfcScanner?
  private var nfcLaunchChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "NativeNfcWriter") {
      let channel = FlutterMethodChannel(
        name: "hitcon_nfc_battle/native_nfc_writer",
        binaryMessenger: registrar.messenger()
      )
      nativeNfcWriter = NativeNfcWriter(channel: channel)
    }
    if let registrar = registry.registrar(forPlugin: "NativeCollectionNfcScanner") {
      let channel = FlutterMethodChannel(
        name: "hitcon_nfc_battle/ios_collection_nfc_scanner",
        binaryMessenger: registrar.messenger()
      )
      nativeCollectionNfcScanner = NativeCollectionNfcScanner(channel: channel)
    }
    if let registrar = registry.registrar(forPlugin: "IosNfcLaunchEvidence") {
      let channel = FlutterMethodChannel(
        name: "hitcon_nfc_battle/nfc_intent",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "takeNfcLaunch" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(IosNfcLaunchEvidenceStore.shared.take())
      }
      nfcLaunchChannel = channel
    }
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    IosNfcLaunchEvidenceStore.shared.capture(userActivity)
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }
}

@available(iOS 13.0, *)
private final class NativeCollectionNfcScanner: NSObject, NFCTagReaderSessionDelegate {
  // Core NFC reports user cancellation before the system sheet has fully
  // released the NFC hardware on older devices (notably iPhone 8 / iOS 16).
  // Keep the Flutter request pending through that dismissal window so the
  // scan button is not re-enabled while a new session would still hang.
  private static let restartCooldown: TimeInterval = 1.5
  private static let activationTimeout: TimeInterval = 2.0

  private let channel: FlutterMethodChannel
  private var session: NFCTagReaderSession?
  private var scanResult: FlutterResult?
  private var pendingPayload: [String: Any]?
  private var stopResults = [FlutterResult]()
  private var scheduledStart: DispatchWorkItem?
  private var activationWatchdog: DispatchWorkItem?
  private var sessionBecameActive = false
  private var lastInvalidatedAt = Date.distantPast

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scan":
      NSLog(
        "[NFCCollection] scan requested session=%@ pendingStart=%@",
        session == nil ? "none" : "active",
        scheduledStart == nil ? "no" : "yes"
      )
      guard NFCTagReaderSession.readingAvailable else {
        NSLog("[NFCCollection] NFC unavailable")
        result([
          "status": "error",
          "type": "unavailable",
          "message": "NFC is unavailable",
        ])
        return
      }
      guard session == nil, scanResult == nil, scheduledStart == nil else {
        NSLog("[NFCCollection] rejected because another scan is still active")
        result([
          "status": "error",
          "type": "systemIsBusy",
          "message": "An NFC scan is already active",
        ])
        return
      }
      scanResult = result
      pendingPayload = nil
      scheduleSessionStart()

    case "stop":
      if let pendingStart = scheduledStart {
        NSLog("[NFCCollection] cancelled before Core NFC session began")
        pendingStart.cancel()
        scheduledStart = nil
        let pendingResult = scanResult
        scanResult = nil
        pendingPayload = nil
        pendingResult?(["status": "cancelled"])
        result(nil)
        return
      }
      guard let activeSession = session else {
        result(nil)
        return
      }
      stopResults.append(result)
      if pendingPayload == nil {
        pendingPayload = ["status": "cancelled"]
      }
      NSLog("[NFCCollection] stop requested for active session")
      activeSession.invalidate()

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scheduleSessionStart() {
    let elapsed = Date().timeIntervalSince(lastInvalidatedAt)
    let delay = max(0, Self.restartCooldown - elapsed)
    let workItem = DispatchWorkItem { [weak self] in
      self?.beginScheduledSession()
    }
    scheduledStart = workItem
    NSLog("[NFCCollection] scheduling Core NFC begin in %.0fms", delay * 1000)
    if delay == 0 {
      DispatchQueue.main.async(execute: workItem)
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
  }

  private func beginScheduledSession() {
    scheduledStart = nil
    guard scanResult != nil, session == nil else {
      NSLog("[NFCCollection] scheduled begin abandoned")
      return
    }
    guard let newSession = NFCTagReaderSession(
      pollingOption: [.iso14443],
      delegate: self,
      queue: .main
    ) else {
      let result = scanResult
      scanResult = nil
      result?([
        "status": "error",
        "type": "unavailable",
        "message": "Cannot create NFC session",
      ])
      return
    }

    sessionBecameActive = false
    session = newSession
    newSession.alertMessage = "請將卡片靠近 iPhone 頂部"
    NSLog("[NFCCollection] calling Core NFC begin")
    newSession.begin()
    startActivationWatchdog(for: newSession)
  }

  private func startActivationWatchdog(for watchedSession: NFCTagReaderSession) {
    activationWatchdog?.cancel()
    let workItem = DispatchWorkItem { [weak self, weak watchedSession] in
      guard let self,
            let watchedSession,
            self.session === watchedSession,
            !self.sessionBecameActive else {
        return
      }
      NSLog("[NFCCollection] activation timed out; invalidating stuck session")
      self.pendingPayload = [
        "status": "error",
        "type": "systemIsBusy",
        "message": "Core NFC session did not become active",
      ]
      watchedSession.invalidate()
    }
    activationWatchdog = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.activationTimeout,
      execute: workItem
    )
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    guard self.session === session else {
      return
    }
    sessionBecameActive = true
    activationWatchdog?.cancel()
    activationWatchdog = nil
    NSLog("[NFCCollection] Core NFC session became active")
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    guard self.session === session else {
      return
    }

    activationWatchdog?.cancel()
    activationWatchdog = nil
    sessionBecameActive = false
    lastInvalidatedAt = Date()
    let payload = pendingPayload ?? errorPayload(error)
    let readerCode = (error as? NFCReaderError)?.code.rawValue ?? -1
    NSLog("[NFCCollection] session invalidated code=%ld payload=%@", readerCode, String(describing: payload))
    self.session = nil
    pendingPayload = nil

    let result = scanResult
    scanResult = nil
    if payload["status"] as? String == "cancelled" {
      NSLog(
        "[NFCCollection] holding cancellation result for %.0fms cooldown",
        Self.restartCooldown * 1000
      )
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.restartCooldown
      ) {
        result?(payload)
      }
    } else {
      result?(payload)
    }

    let pendingStops = stopResults
    stopResults.removeAll()
    pendingStops.forEach { $0(nil) }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard self.session === session else {
      return
    }
    guard tags.count == 1, let tag = tags.first else {
      session.alertMessage = "一次只能感應一張卡片"
      session.restartPolling()
      return
    }

    session.connect(to: tag) { [weak self, weak session] error in
      guard let self, let session, self.session === session else {
        return
      }
      guard error == nil else {
        session.alertMessage = "讀取失敗，請再靠近一次"
        session.restartPolling()
        return
      }

      let uid = self.tagIdentifier(tag)
      guard let ndefTag = self.ndefTag(from: tag) else {
        self.finishScan(session: session, uid: uid, userId: "")
        return
      }

      ndefTag.readNDEF { [weak self, weak session] message, _ in
        guard let self, let session, self.session === session else {
          return
        }
        self.finishScan(
          session: session,
          uid: uid,
          userId: self.targetUserId(from: message)
        )
      }
    }
  }

  private func finishScan(session: NFCTagReaderSession, uid: String, userId: String) {
    guard self.session === session, pendingPayload == nil else {
      return
    }
    pendingPayload = [
      "status": "scanned",
      "uid": uid,
      "userId": userId,
    ]
    session.alertMessage = "讀取完成"
    session.invalidate()
  }

  private func targetUserId(from message: NFCNDEFMessage?) -> String {
    guard let message else {
      return ""
    }
    for record in message.records {
      guard let uri = parseUriPayload(record),
            let components = URLComponents(string: uri),
            components.host?.lowercased() == "game.hitcon2026.online",
            components.path == "/b" || components.path == "/b/" else {
        continue
      }
      return components.queryItems?.first(where: { $0.name == "u" })?.value ?? ""
    }
    return ""
  }

  private func parseUriPayload(_ payload: NFCNDEFPayload) -> String? {
    guard payload.typeNameFormat == .nfcWellKnown,
          payload.type == Data([0x55]),
          let code = payload.payload.first else {
      return nil
    }
    let prefixes = ["", "http://www.", "https://www.", "http://", "https://"]
    let prefix = Int(code) < prefixes.count ? prefixes[Int(code)] : ""
    guard let body = String(data: Data(payload.payload.dropFirst()), encoding: .utf8) else {
      return nil
    }
    return prefix + body
  }

  private func ndefTag(from tag: NFCTag) -> NFCNDEFTag? {
    switch tag {
    case .feliCa(let tag): return tag
    case .miFare(let tag): return tag
    case .iso7816(let tag): return tag
    case .iso15693(let tag): return tag
    @unknown default: return nil
    }
  }

  private func tagIdentifier(_ tag: NFCTag) -> String {
    switch tag {
    case .feliCa(let tag): return hex(tag.currentIDm)
    case .miFare(let tag): return hex(tag.identifier)
    case .iso7816(let tag): return hex(tag.identifier)
    case .iso15693(let tag): return hex(tag.identifier)
    @unknown default: return ""
    }
  }

  private func errorPayload(_ error: Error) -> [String: Any] {
    guard let readerError = error as? NFCReaderError else {
      return [
        "status": "error",
        "type": "unknown",
        "message": error.localizedDescription,
      ]
    }

    switch readerError.code {
    case .readerSessionInvalidationErrorUserCanceled:
      return ["status": "cancelled"]
    case .readerSessionInvalidationErrorSessionTimeout:
      return [
        "status": "error",
        "type": "sessionTimeout",
        "message": readerError.localizedDescription,
      ]
    case .readerSessionInvalidationErrorSystemIsBusy:
      return [
        "status": "error",
        "type": "systemIsBusy",
        "message": readerError.localizedDescription,
      ]
    default:
      return [
        "status": "error",
        "type": "unknown",
        "message": readerError.localizedDescription,
      ]
    }
  }

  private func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: ":")
  }
}

final class IosNfcLaunchEvidenceStore {
  static let shared = IosNfcLaunchEvidenceStore()

  private let lock = NSLock()
  private var pending: [String: Any]?

  private init() {}

  func capture(_ userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else {
      return
    }
    let records = userActivity.ndefMessagePayload.records
    let isNfcIntent: Bool
    if let firstRecord = records.first {
      isNfcIntent = firstRecord.typeNameFormat != .empty
    } else {
      isNfcIntent = false
    }
    lock.lock()
    pending = [
      "uid": "",
      "isNfcIntent": isNfcIntent,
      "hasEvidence": true,
    ]
    lock.unlock()
  }

  func take() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    guard let pending else {
      return [
        "uid": "",
        "isNfcIntent": false,
        "hasEvidence": false,
      ]
    }
    self.pending = nil
    return pending
  }
}

@available(iOS 13.0, *)
private final class NativeNfcWriter: NSObject, NFCTagReaderSessionDelegate {
  private let channel: FlutterMethodChannel
  private var session: NFCTagReaderSession?
  private var targetUri = ""
  private var secretKey = ""
  private var autoWrite = true
  private var lastTagId = ""
  private var lastReadAt = Date.distantPast
  private var didRequestStop = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startContinuousWrite":
      guard NFCTagReaderSession.readingAvailable else {
        result(FlutterError(code: "unavailable", message: "NFC is unavailable", details: nil))
        return
      }

      let arguments = call.arguments as? [String: Any] ?? [:]
      targetUri = arguments["uri"] as? String ?? ""
      secretKey = arguments["secretKey"] as? String ?? ""
      autoWrite = arguments["autoWrite"] as? Bool ?? true

      if let session {
        session.alertMessage = "請將 NTag 靠近 iPhone 頂部"
        result(nil)
        return
      }

      didRequestStop = false
      lastTagId = ""
      lastReadAt = Date.distantPast

      guard let newSession = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self) else {
        result(FlutterError(code: "unavailable", message: "Cannot create NFC session", details: nil))
        return
      }

      newSession.alertMessage = "請將 NTag 靠近 iPhone 頂部"
      session = newSession
      newSession.begin()
      result(nil)

    case "stop":
      didRequestStop = true
      session?.invalidate()
      session = nil
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    invoke("onSessionActive", arguments: [:])
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    self.session = nil

    if didRequestStop {
      didRequestStop = false
      return
    }

    let mapped = mapError(error)
    invoke("onSessionEnded", arguments: mapped)
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard tags.count == 1, let tag = tags.first else {
      session.alertMessage = "一次只能感應一張 NTag"
      restart(session, after: 0.8)
      return
    }

    session.connect(to: tag) { [weak self, weak session] error in
      guard let self, let session, self.session === session else {
        return
      }

      if let error {
        self.invoke("onScan", arguments: [
          "uid": "",
          "records": [],
          "writeMessage": "（連線失敗：\(error.localizedDescription)）",
        ])
        self.restart(session, after: 0.8)
        return
      }

      self.handleConnectedTag(tag, session: session)
    }
  }

  private func handleConnectedTag(_ tag: NFCTag, session: NFCTagReaderSession) {
    let uid = tagIdentifier(tag)
    let now = Date()
    if !uid.isEmpty && uid == lastTagId && now.timeIntervalSince(lastReadAt) < 1.2 {
      session.alertMessage = "請先移開目前的 NTag"
      restart(session, after: 0.8)
      return
    }

    lastTagId = uid
    lastReadAt = now

    guard let ndefTag = ndefTag(from: tag) else {
      invoke("onScan", arguments: [
        "uid": uid,
        "records": [],
        "writeMessage": "（Tag 不支援 NDEF）",
      ])
      restart(session, after: 0.8)
      return
    }

    ndefTag.queryNDEFStatus { [weak self, weak session] status, _, _ in
      guard let self, let session, self.session === session else {
        return
      }

      if status == .notSupported {
        self.invoke("onScan", arguments: [
          "uid": uid,
          "records": [],
          "writeMessage": "（Tag 不支援 NDEF）",
        ])
        self.restart(session, after: 0.8)
        return
      }

      ndefTag.readNDEF { [weak self, weak session] message, _ in
        guard let self, let session, self.session === session else {
          return
        }

        let parsed = self.parseMessage(message)
        self.writeIfNeeded(
          uid: uid,
          records: parsed.records,
          existingSecrets: parsed.secrets,
          ndefTag: ndefTag,
          status: status,
          session: session
        )
      }
    }
  }

  private func writeIfNeeded(
    uid: String,
    records: [String],
    existingSecrets: [String],
    ndefTag: NFCNDEFTag,
    status: NFCNDEFStatus,
    session: NFCTagReaderSession
  ) {
    guard autoWrite else {
      invoke("onScan", arguments: [
        "uid": uid,
        "records": records,
        "writeMessage": "",
      ])
      restart(session, after: 0.8)
      return
    }

    let uriMatches = records.contains(targetUri)
    let secretMatches = secretKey.isEmpty
      ? existingSecrets.isEmpty
      : existingSecrets.count == 1 && existingSecrets.first == secretKey

    if uriMatches && secretMatches {
      let writeMessage = secretKey.isEmpty
        ? "（Tag 已是目標 URI，略過寫入）"
        : "（Tag 已是目標 URI + secret，略過寫入）"
      invoke("onScan", arguments: [
        "uid": uid,
        "records": records,
        "writeMessage": writeMessage,
      ])
      restart(session, after: 0.8)
      return
    }

    guard status == .readWrite else {
      invoke("onScan", arguments: [
        "uid": uid,
        "records": records,
        "writeMessage": "（無法寫入：Tag 不支援寫入）",
      ])
      restart(session, after: 0.8)
      return
    }

    ndefTag.writeNDEF(buildMessage()) { [weak self, weak session] error in
      guard let self, let session, self.session === session else {
        return
      }

      let writeMessage: String
      if let error {
        writeMessage = "（寫入失敗：\(error.localizedDescription)）"
      } else {
        writeMessage = self.secretKey.isEmpty ? "（已寫入 URI）" : "（已寫入 URI + secret）"
      }

      self.invoke("onScan", arguments: [
        "uid": uid,
        "records": records,
        "writeMessage": writeMessage,
      ])
      self.restart(session, after: error == nil ? 1.0 : 0.8)
    }
  }

  private func restart(_ session: NFCTagReaderSession, after delay: TimeInterval) {
    session.alertMessage = "請移開目前的 NTag"
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak session] in
      guard let self, let session, self.session === session else {
        return
      }

      session.alertMessage = "請將下一張 NTag 靠近 iPhone 頂部"
      session.restartPolling()
    }
  }

  private func buildMessage() -> NFCNDEFMessage {
    var payloads = [buildUriRecord(targetUri)]
    if !secretKey.isEmpty {
      payloads.append(buildTextRecord(identifier: "secret_key", text: secretKey))
    }
    return NFCNDEFMessage(records: payloads)
  }

  private func buildUriRecord(_ uri: String) -> NFCNDEFPayload {
    let prefixes = ["", "http://www.", "https://www.", "http://", "https://"]
    var prefixIndex = 0
    var body = uri

    for index in stride(from: prefixes.count - 1, through: 1, by: -1) {
      let prefix = prefixes[index]
      if uri.hasPrefix(prefix) {
        prefixIndex = index
        body = String(uri.dropFirst(prefix.count))
        break
      }
    }

    var payload = Data([UInt8(prefixIndex)])
    payload.append(contentsOf: body.utf8)

    return NFCNDEFPayload(
      format: .nfcWellKnown,
      type: Data([0x55]),
      identifier: Data(),
      payload: payload
    )
  }

  private func buildTextRecord(identifier: String, text: String) -> NFCNDEFPayload {
    var payload = Data([0x02])
    payload.append(contentsOf: "en".utf8)
    payload.append(contentsOf: text.utf8)

    return NFCNDEFPayload(
      format: .nfcWellKnown,
      type: Data([0x54]),
      identifier: Data(identifier.utf8),
      payload: payload
    )
  }

  private func parseMessage(_ message: NFCNDEFMessage?) -> (records: [String], secrets: [String]) {
    guard let message else {
      return ([], [])
    }

    var records = [String]()
    var secrets = [String]()

    for payload in message.records {
      let value = parsePayload(payload)
      records.append(value)

      if payload.typeNameFormat == .nfcWellKnown,
         payload.type == Data([0x54]),
         String(data: payload.identifier, encoding: .utf8) == "secret_key",
         let secret = parseTextPayload(payload) {
        secrets.append(secret)
      }
    }

    return (records, secrets)
  }

  private func parsePayload(_ payload: NFCNDEFPayload) -> String {
    if payload.typeNameFormat == .nfcWellKnown,
       payload.type == Data([0x54]),
       let text = parseTextPayload(payload) {
      return text
    }

    if payload.typeNameFormat == .nfcWellKnown,
       payload.type == Data([0x55]),
       let uri = parseUriPayload(payload) {
      return uri
    }

    return "TNF=\(payload.typeNameFormat.rawValue), type=\(hex(payload.type)), payload=\(hex(payload.payload))"
  }

  private func parseTextPayload(_ payload: NFCNDEFPayload) -> String? {
    let data = payload.payload
    guard data.count > 1 else {
      return nil
    }

    let languageLength = Int(data[0] & 0x3f)
    let textStart = 1 + languageLength
    guard data.count > textStart else {
      return nil
    }

    return String(data: data.subdata(in: textStart..<data.count), encoding: .utf8)
  }

  private func parseUriPayload(_ payload: NFCNDEFPayload) -> String? {
    let prefixes = ["", "http://www.", "https://www.", "http://", "https://"]
    let data = payload.payload
    guard let code = data.first else {
      return nil
    }

    let prefix = Int(code) < prefixes.count ? prefixes[Int(code)] : ""
    let bodyData = data.dropFirst()
    guard let body = String(data: Data(bodyData), encoding: .utf8) else {
      return nil
    }

    return prefix + body
  }

  private func ndefTag(from tag: NFCTag) -> NFCNDEFTag? {
    switch tag {
    case .feliCa(let tag): return tag
    case .miFare(let tag): return tag
    case .iso7816(let tag): return tag
    case .iso15693(let tag): return tag
    @unknown default: return nil
    }
  }

  private func tagIdentifier(_ tag: NFCTag) -> String {
    switch tag {
    case .feliCa(let tag): return hex(tag.currentIDm)
    case .miFare(let tag): return hex(tag.identifier)
    case .iso7816(let tag): return hex(tag.identifier)
    case .iso15693(let tag): return hex(tag.identifier)
    @unknown default: return ""
    }
  }

  private func mapError(_ error: Error) -> [String: Any] {
    if let readerError = error as? NFCReaderError {
      let type: String
      switch readerError.code {
      case .readerSessionInvalidationErrorSessionTimeout:
        type = "sessionTimeout"
      case .readerSessionInvalidationErrorSystemIsBusy:
        type = "systemIsBusy"
      case .readerSessionInvalidationErrorUserCanceled:
        type = "userCanceled"
      default:
        type = "unknown"
      }

      return [
        "type": type,
        "message": readerError.localizedDescription,
      ]
    }

    return [
      "type": "unknown",
      "message": error.localizedDescription,
    ]
  }

  private func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: ":")
  }

  private func invoke(_ method: String, arguments: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod(method, arguments: arguments)
    }
  }
}
