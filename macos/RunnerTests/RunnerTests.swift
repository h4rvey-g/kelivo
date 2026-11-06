import Cocoa
import FlutterMacOS
import XCTest

@testable import kelivo

class RunnerTests: XCTestCase {

  func testTextInputContextRecoveryRunsBeforeFirstKeyDown() {
    let notificationCenter = NotificationCenter()
    var scheduledActions: [() -> Void] = []
    var recoveryCount = 0
    let recovery = TextInputContextRecovery(
      notificationCenter: notificationCenter,
      scheduler: { _, action in scheduledActions.append(action) },
      recovery: {
        recoveryCount += 1
        return true
      }
    )

    recovery.requestRecovery()

    XCTAssertTrue(recovery.recoverBeforeKeyDown())
    XCTAssertEqual(recoveryCount, 1)
    scheduledActions.forEach { $0() }
    XCTAssertEqual(recoveryCount, 1)
  }

  func testTextInputContextRecoveryCoalescesFallbacks() {
    let notificationCenter = NotificationCenter()
    var scheduledActions: [() -> Void] = []
    var recoveryCount = 0
    let recovery = TextInputContextRecovery(
      notificationCenter: notificationCenter,
      scheduler: { _, action in scheduledActions.append(action) },
      recovery: {
        recoveryCount += 1
        return true
      }
    )

    notificationCenter.post(
      name: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil
    )
    notificationCenter.post(
      name: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil
    )

    XCTAssertEqual(scheduledActions.count, 1)
    scheduledActions.forEach { $0() }
    XCTAssertEqual(recoveryCount, 1)
    withExtendedLifetime(recovery) {}
  }

  func testTextInputContextRecoveryClearsIneligibleRequest() {
    let notificationCenter = NotificationCenter()
    var scheduledActions: [() -> Void] = []
    var recoveryCount = 0
    let recovery = TextInputContextRecovery(
      notificationCenter: notificationCenter,
      scheduler: { _, action in scheduledActions.append(action) },
      recovery: {
        recoveryCount += 1
        return false
      }
    )

    notificationCenter.post(
      name: NSTextInputContext.keyboardSelectionDidChangeNotification,
      object: nil
    )
    scheduledActions.forEach { $0() }

    XCTAssertEqual(recoveryCount, 1)
    XCTAssertFalse(recovery.recoverBeforeKeyDown())
    XCTAssertEqual(recoveryCount, 1)
  }

  func testTransientCommandVCapturesPasteboardText() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    let item = NSPasteboardItem()
    item.setString("transcript", forType: .string)
    item.setData(Data(), forType: TransientPasteboardTextCapture.markerType)
    XCTAssertTrue(pasteboard.writeObjects([item]))

    XCTAssertEqual(
      TransientPasteboardTextCapture.capture(
        event: try commandVEvent(), pasteboard: pasteboard
      ),
      "transcript"
    )
  }

  func testOrdinaryClipboardIsNotCaptured() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setString("ordinary", forType: .string)

    XCTAssertNil(
      TransientPasteboardTextCapture.capture(
        event: try commandVEvent(), pasteboard: pasteboard
      )
    )
  }

  func testTransientCaptureRejectsModifiedShortcut() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    let item = NSPasteboardItem()
    item.setString("transcript", forType: .string)
    item.setData(Data(), forType: TransientPasteboardTextCapture.markerType)
    XCTAssertTrue(pasteboard.writeObjects([item]))

    XCTAssertNil(
      TransientPasteboardTextCapture.capture(
        event: try commandVEvent(modifiers: [.command, .option]),
        pasteboard: pasteboard
      )
    )
  }

  func testTransientCaptureAcceptsSyntheticVKeyCodeWithoutCharacters() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    let item = NSPasteboardItem()
    item.setString("transcript", forType: .string)
    item.setData(Data(), forType: TransientPasteboardTextCapture.markerType)
    XCTAssertTrue(pasteboard.writeObjects([item]))

    XCTAssertEqual(
      TransientPasteboardTextCapture.capture(
        event: try commandVEvent(characters: ""),
        pasteboard: pasteboard
      ),
      "transcript"
    )
  }

  private func commandVEvent(
    modifiers: NSEvent.ModifierFlags = [.command],
    characters: String = "v"
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: 9
      )
    )
  }

}
