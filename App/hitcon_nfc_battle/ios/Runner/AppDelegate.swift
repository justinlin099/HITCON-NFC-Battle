import CoreNFC
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeNfcWriter: NativeNfcWriter?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "NativeNfcWriter") {
      let channel = FlutterMethodChannel(
        name: "hitcon_nfc_battle/native_nfc_writer",
        binaryMessenger: registrar.messenger()
      )
      nativeNfcWriter = NativeNfcWriter(channel: channel)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
