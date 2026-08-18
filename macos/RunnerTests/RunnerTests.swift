import Cocoa
import FlutterMacOS
import XCTest

@testable import kelivo

class RunnerTests: XCTestCase {

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

  func testSelectionReplacementIgnoresStaleClearAndPreservesFocus() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    let coordinateView = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = coordinateView
    var notifications: [NSAccessibility.Notification] = []
    let controller = SelectedTextAccessibilityController(
      ownerWindow: window,
      coordinateView: coordinateView,
      notificationPoster: { _, notification in
        notifications.append(notification)
      }
    )

    XCTAssertEqual(
      controller.updateSelection(
        text: "first",
        source: "source-a",
        frameInView: NSRect(x: 10, y: 20, width: 100, height: 30)
      ),
      .activated
    )
    XCTAssertTrue(
      (controller.focusedUIElement as? SelectedTextAccessibilityElement) ===
        controller.accessibilityElement
    )
    XCTAssertEqual(
      notifications,
      [.selectedTextChanged, .focusedUIElementChanged]
    )

    notifications.removeAll()
    XCTAssertEqual(
      controller.updateSelection(
        text: "replacement",
        source: "source-b",
        frameInView: NSRect(x: 20, y: 30, width: 120, height: 30)
      ),
      .updated
    )
    XCTAssertEqual(notifications, [.selectedTextChanged])

    notifications.removeAll()
    XCTAssertEqual(
      controller.updateSelection(
        text: "",
        source: "source-a",
        frameInView: nil
      ),
      .ignoredStaleClear
    )
    XCTAssertEqual(controller.accessibilityElement.selectedText, "replacement")
    XCTAssertTrue(notifications.isEmpty)

    XCTAssertEqual(
      controller.updateSelection(
        text: "",
        source: "source-b",
        frameInView: nil
      ),
      .deactivated
    )
    XCTAssertNil(controller.focusedUIElement)
    XCTAssertEqual(
      notifications,
      [.selectedTextChanged, .focusedUIElementChanged]
    )
  }

  func testAccessibilityElementUsesUTF16RangesAndIsReadOnly() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    let coordinateView = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = coordinateView
    let controller = SelectedTextAccessibilityController(
      ownerWindow: window,
      coordinateView: coordinateView,
      notificationPoster: { _, _ in }
    )
    controller.updateSelection(
      text: "A😀\nB",
      source: "source-a",
      frameInView: NSRect(x: 10, y: 20, width: 100, height: 60)
    )

    let element = controller.accessibilityElement
    XCTAssertEqual(element.accessibilityRole(), .staticText)
    XCTAssertEqual(element.accessibilityValue() as? String, "A😀\nB")
    XCTAssertEqual(element.accessibilitySelectedText(), "A😀\nB")
    XCTAssertEqual(
      element.accessibilitySelectedTextRange(),
      NSRange(location: 0, length: 5)
    )
    XCTAssertEqual(element.accessibilityNumberOfCharacters(), 5)
    XCTAssertEqual(
      element.accessibilityString(for: NSRange(location: 1, length: 2)),
      "😀"
    )
    XCTAssertEqual(element.accessibilityLine(for: 0), 0)
    XCTAssertEqual(element.accessibilityLine(for: 4), 1)
    XCTAssertEqual(
      element.accessibilityRange(forLine: 0),
      NSRange(location: 0, length: 4)
    )
    XCTAssertEqual(
      element.accessibilityRange(forLine: 1),
      NSRange(location: 4, length: 1)
    )
    let expectedFrame = NSAccessibility.screenRect(
      fromView: coordinateView,
      rect: NSRect(x: 10, y: 20, width: 100, height: 60)
    )
    XCTAssertEqual(element.accessibilityFrame(), expectedFrame)
    XCTAssertEqual(
      element.accessibilityFrame(for: NSRange(location: 0, length: 5)),
      expectedFrame
    )
    XCTAssertFalse(element.accessibilityIsAttributeSettable(.value))
    XCTAssertFalse(element.accessibilityIsAttributeSettable(.selectedText))
  }

  func testControllerValidatesChannelArguments() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    let coordinateView = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = coordinateView
    let controller = SelectedTextAccessibilityController(
      ownerWindow: window,
      coordinateView: coordinateView,
      notificationPoster: { _, _ in }
    )

    XCTAssertThrowsError(
      try controller.apply(arguments: ["source": "", "text": "selected"])
    )
    XCTAssertThrowsError(
      try controller.apply(arguments: [
        "source": "source-a",
        "text": "selected",
        "bounds": ["x": 0, "y": 0, "width": -1, "height": 20],
      ])
    )

    XCTAssertEqual(
      try controller.apply(arguments: [
        "source": "source-a",
        "text": "selected",
        "bounds": ["x": 10, "y": 20, "width": 100, "height": 40],
      ]),
      .activated
    )
  }

}
