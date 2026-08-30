import Cocoa

final class TextInputContextRecovery {
  typealias Recovery = () -> Bool
  typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> Void

  private let notificationCenter: NotificationCenter
  private let recovery: Recovery
  private let scheduler: Scheduler
  private let fallbackDelay: TimeInterval
  private var observer: NSObjectProtocol?
  private var recoveryPending = false

  init(
    notificationCenter: NotificationCenter = .default,
    fallbackDelay: TimeInterval = 0.03,
    scheduler: @escaping Scheduler = { delay, action in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    },
    recovery: @escaping Recovery
  ) {
    self.notificationCenter = notificationCenter
    self.fallbackDelay = fallbackDelay
    self.scheduler = scheduler
    self.recovery = recovery

    observer = notificationCenter.addObserver(
      forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.inputSourceDidChange()
    }
  }

  deinit {
    if let observer {
      notificationCenter.removeObserver(observer)
    }
  }

  @discardableResult
  func recoverBeforeKeyDown() -> Bool {
    guard recoveryPending else { return false }
    recoveryPending = false
    return recovery()
  }

  func requestRecovery() {
    guard !recoveryPending else { return }
    recoveryPending = true
    scheduler(fallbackDelay) { [weak self] in
      _ = self?.recoverBeforeKeyDown()
    }
  }

  private func inputSourceDidChange() {
    requestRecovery()
  }
}
