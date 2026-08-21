import Cocoa
import FlutterMacOS
import Sparkle

@main
class AppDelegate: FlutterAppDelegate {
  private var sparkleUpdateController: SparkleUpdateController?

  func registerSparkleUpdateChannel(binaryMessenger: FlutterBinaryMessenger) {
    let controller = sparkleUpdateController ?? SparkleUpdateController()
    sparkleUpdateController = controller
    controller.register(binaryMessenger: binaryMessenger)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    let mainWindow = sender.windows.first { $0 is MainFlutterWindow }
      ?? sender.windows.first { $0.canBecomeKey }

    if let window = mainWindow {
      if window.isMiniaturized {
        window.deminiaturize(self)
      }
      window.orderFrontRegardless()
      window.makeKeyAndOrderFront(self)
    }

    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

private protocol SparkleAutomaticUserDriverDelegate: AnyObject {
  var expectedVersion: String? { get }

  func emitProgress(
    phase: String,
    receivedBytes: UInt64,
    totalBytes: UInt64?
  )
  func failUpdate(message: String)
  func finishUpdate()
}

private final class SparkleAutomaticUserDriver: NSObject, SPUUserDriver {
  weak var delegate: SparkleAutomaticUserDriverDelegate?

  private var receivedBytes: UInt64 = 0
  private var totalBytes: UInt64?

  func resetProgress() {
    receivedBytes = 0
    totalBytes = nil
  }

  func show(
    _ request: SPUUpdatePermissionRequest,
    reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(
      SUUpdatePermissionResponse(
        automaticUpdateChecks: false,
        sendSystemProfile: false
      )
    )
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    delegate?.emitProgress(
      phase: "preparing",
      receivedBytes: 0,
      totalBytes: nil
    )
  }

  func showUpdateFound(
    with appcastItem: SUAppcastItem,
    state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    guard !appcastItem.isInformationOnlyUpdate else {
      delegate?.failUpdate(
        message: "This release cannot be installed automatically."
      )
      reply(.dismiss)
      return
    }

    if let expectedVersion = delegate?.expectedVersion,
       appcastItem.displayVersionString != expectedVersion {
      delegate?.failUpdate(
        message: "The update feed does not match version \(expectedVersion)."
      )
      reply(.dismiss)
      return
    }

    reply(.install)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    delegate?.failUpdate(message: (error as NSError).localizedDescription)
    acknowledgement()
  }

  func showUpdaterError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    delegate?.failUpdate(message: (error as NSError).localizedDescription)
    acknowledgement()
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    resetProgress()
    delegate?.emitProgress(
      phase: "downloading",
      receivedBytes: 0,
      totalBytes: nil
    )
  }

  func showDownloadDidReceiveExpectedContentLength(
    _ expectedContentLength: UInt64
  ) {
    totalBytes = expectedContentLength
    delegate?.emitProgress(
      phase: "downloading",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    receivedBytes += length
    delegate?.emitProgress(
      phase: "downloading",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
  }

  func showDownloadDidStartExtractingUpdate() {
    delegate?.emitProgress(
      phase: "preparing",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
  }

  func showExtractionReceivedProgress(_ progress: Double) {
    delegate?.emitProgress(
      phase: "preparing",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
  }

  func showReady(
    toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    delegate?.emitProgress(
      phase: "installing",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
    reply(.install)
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    delegate?.emitProgress(
      phase: "installing",
      receivedBytes: receivedBytes,
      totalBytes: totalBytes
    )
  }

  func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool,
    acknowledgement: @escaping () -> Void
  ) {
    delegate?.finishUpdate()
    acknowledgement()
  }

  func dismissUpdateInstallation() {}
}

private final class SparkleUpdateController:
  NSObject,
  SparkleAutomaticUserDriverDelegate,
  SPUUpdaterDelegate
{
  private static let channelName = "com.psyche.kelivo/sparkle_update"

  private let userDriver = SparkleAutomaticUserDriver()
  private var updater: SPUUpdater!
  private var channel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var startupError: String?
  private var started = false

  private(set) var expectedVersion: String?

  override init() {
    super.init()
    userDriver.delegate = self
    updater = SPUUpdater(
      hostBundle: .main,
      applicationBundle: .main,
      userDriver: userDriver,
      delegate: self
    )
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    if channel == nil {
      let channel = FlutterMethodChannel(
        name: Self.channelName,
        binaryMessenger: binaryMessenger
      )
      self.channel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(
            FlutterError(
              code: "updater_unavailable",
              message: "The update service is unavailable.",
              details: nil
            )
          )
          return
        }
        self.handle(call: call, result: result)
      }
    }

    guard !started, startupError == nil else { return }
    do {
      try updater.start()
      started = true
    } catch {
      startupError = (error as NSError).localizedDescription
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "installAvailableUpdate" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard started else {
      result(
        FlutterError(
          code: "updater_not_configured",
          message: startupError ?? "The update service did not start.",
          details: nil
        )
      )
      return
    }
    guard pendingResult == nil, updater.canCheckForUpdates else {
      result(
        FlutterError(
          code: "updater_busy",
          message: "Another update operation is already running.",
          details: nil
        )
      )
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let expectedVersion = arguments["expectedVersion"] as? String,
          !expectedVersion.isEmpty else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "The expected update version is required.",
          details: nil
        )
      )
      return
    }

    self.expectedVersion = expectedVersion
    pendingResult = result
    userDriver.resetProgress()
    emitProgress(phase: "preparing", receivedBytes: 0, totalBytes: nil)
    updater.checkForUpdates()
  }

  func emitProgress(
    phase: String,
    receivedBytes: UInt64,
    totalBytes: UInt64?
  ) {
    var arguments: [String: Any] = [
      "phase": phase,
      "receivedBytes": NSNumber(value: receivedBytes),
    ]
    if let totalBytes {
      arguments["totalBytes"] = NSNumber(value: totalBytes)
    }
    channel?.invokeMethod("progress", arguments: arguments)
  }

  func failUpdate(message: String) {
    guard let result = takePendingResult() else { return }
    result(
      FlutterError(
        code: "update_failed",
        message: message,
        details: nil
      )
    )
  }

  func finishUpdate() {
    takePendingResult()?(nil)
  }

  private func takePendingResult() -> FlutterResult? {
    let result = pendingResult
    pendingResult = nil
    expectedVersion = nil
    return result
  }
}
