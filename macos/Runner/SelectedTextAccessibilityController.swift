import Cocoa

#if canImport(FlutterMacOS)
import FlutterMacOS
#endif

enum SelectedTextAccessibilityUpdateOutcome: Equatable {
  case activated
  case updated
  case deactivated
  case unchanged
  case ignoredStaleClear
}

enum SelectedTextAccessibilityControllerError: LocalizedError {
  case invalidArguments(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      return message
    }
  }
}

final class SelectedTextAccessibilityElement: NSAccessibilityElement {
  weak var ownerWindow: NSWindow?
  weak var coordinateView: NSView?

  private(set) var selectedText: String?
  private var frameInView: NSRect?

  var hasSelection: Bool {
    !(selectedText?.isEmpty ?? true)
  }

  @discardableResult
  func update(text: String?, frameInView: NSRect?) -> Bool {
    let normalizedText = text?.isEmpty == false ? text : nil
    let normalizedFrame = normalizedText == nil ? nil : frameInView
    let changed = selectedText != normalizedText || self.frameInView != normalizedFrame
    selectedText = normalizedText
    self.frameInView = normalizedFrame
    return changed
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    .staticText
  }

  override func accessibilityIdentifier() -> String? {
    "com.psyche.kelivo.selected-text"
  }

  override func accessibilityValue() -> Any? {
    selectedText
  }

  override func accessibilitySelectedText() -> String? {
    selectedText
  }

  override func accessibilitySelectedTextRange() -> NSRange {
    fullRange
  }

  override func accessibilitySelectedTextRanges() -> [NSValue]? {
    hasSelection ? [NSValue(range: fullRange)] : []
  }

  override func accessibilityVisibleCharacterRange() -> NSRange {
    fullRange
  }

  override func accessibilityNumberOfCharacters() -> Int {
    utf16Text.length
  }

  override func accessibilityAttributedString(
    for range: NSRange
  ) -> NSAttributedString? {
    guard let string = accessibilityString(for: range) else { return nil }
    return NSAttributedString(string: string)
  }

  override func accessibilityString(for range: NSRange) -> String? {
    guard isValid(range) else { return nil }
    return utf16Text.substring(with: range)
  }

  override func accessibilityLine(for index: Int) -> Int {
    let length = utf16Text.length
    guard index >= 0, index <= length else { return NSNotFound }

    let ranges = lineRanges
    for (line, range) in ranges.enumerated() {
      if range.length == 0 {
        if index == range.location { return line }
      } else if index >= range.location && index < NSMaxRange(range) {
        return line
      }
    }
    return index == length && !ranges.isEmpty ? ranges.count - 1 : NSNotFound
  }

  override func accessibilityRange(forLine lineNumber: Int) -> NSRange {
    let ranges = lineRanges
    guard lineNumber >= 0, lineNumber < ranges.count else {
      return NSRange(location: NSNotFound, length: 0)
    }
    return ranges[lineNumber]
  }

  override func accessibilityFrame(for range: NSRange) -> NSRect {
    guard isValid(range) else { return .zero }
    return accessibilityFrame()
  }

  override func accessibilityFrame() -> NSRect {
    if let coordinateView {
      let localFrame: NSRect
      if let frameInView {
        let visibleFrame = frameInView.intersection(coordinateView.bounds)
        localFrame = visibleFrame.isNull || visibleFrame.isEmpty
          ? frameInView
          : visibleFrame
      } else {
        localFrame = coordinateView.bounds
      }
      return NSAccessibility.screenRect(fromView: coordinateView, rect: localFrame)
    }

    guard let contentView = ownerWindow?.contentView else { return .zero }
    return NSAccessibility.screenRect(fromView: contentView, rect: contentView.bounds)
  }

  override func accessibilityParent() -> Any? {
    ownerWindow
  }

  override func isAccessibilityFocused() -> Bool {
    hasSelection
  }

  override func isAccessibilityElement() -> Bool {
    true
  }

  override func accessibilityIsAttributeSettable(
    _ attribute: NSAccessibility.Attribute
  ) -> Bool {
    false
  }

  private var utf16Text: NSString {
    (selectedText ?? "") as NSString
  }

  private var fullRange: NSRange {
    NSRange(location: 0, length: utf16Text.length)
  }

  private var lineRanges: [NSRange] {
    let text = utf16Text
    guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }

    var ranges: [NSRange] = []
    var location = 0
    while location < text.length {
      let range = text.lineRange(for: NSRange(location: location, length: 0))
      ranges.append(range)
      let nextLocation = NSMaxRange(range)
      guard nextLocation > location else { break }
      location = nextLocation
    }

    let trailingRange = text.lineRange(
      for: NSRange(location: text.length, length: 0)
    )
    if trailingRange.location == text.length && trailingRange.length == 0 {
      ranges.append(trailingRange)
    }
    return ranges
  }

  private func isValid(_ range: NSRange) -> Bool {
    let length = utf16Text.length
    return range.location != NSNotFound &&
      range.location >= 0 &&
      range.length >= 0 &&
      range.location <= length &&
      range.length <= length - range.location
  }
}

final class SelectedTextAccessibilityController {
  typealias NotificationPoster =
    (_ element: Any, _ notification: NSAccessibility.Notification) -> Void

  static let channelName = "com.psyche.kelivo/selected_text_accessibility"
  static let methodName = "updateSelection"

  let accessibilityElement: SelectedTextAccessibilityElement

  private weak var ownerWindow: NSWindow?
  private let notificationPoster: NotificationPoster
#if canImport(FlutterMacOS)
  private var channel: FlutterMethodChannel?
#endif
  private(set) var activeSource: String?

  init(
    ownerWindow: NSWindow,
    coordinateView: NSView,
    notificationPoster: @escaping NotificationPoster = { element, notification in
      NSAccessibility.post(element: element, notification: notification)
    }
  ) {
    self.ownerWindow = ownerWindow
    self.notificationPoster = notificationPoster
    accessibilityElement = SelectedTextAccessibilityElement()
    accessibilityElement.ownerWindow = ownerWindow
    accessibilityElement.coordinateView = coordinateView
  }

  var focusedUIElement: Any? {
    accessibilityElement.hasSelection ? accessibilityElement : nil
  }

#if canImport(FlutterMacOS)
  deinit {
    channel?.setMethodCallHandler(nil)
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    channel?.setMethodCallHandler(nil)
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      guard call.method == Self.methodName else {
        result(FlutterMethodNotImplemented)
        return
      }

      do {
        _ = try apply(arguments: call.arguments)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
    self.channel = channel
  }
#endif

  @discardableResult
  func apply(arguments: Any?) throws -> SelectedTextAccessibilityUpdateOutcome {
    guard let arguments = arguments as? [String: Any],
          let source = arguments["source"] as? String,
          !source.isEmpty,
          let text = arguments["text"] as? String else {
      throw SelectedTextAccessibilityControllerError.invalidArguments(
        "Selection updates require non-empty source and string text values."
      )
    }

    let bounds = try Self.parseBounds(arguments["bounds"])
    return updateSelection(text: text, source: source, frameInView: bounds)
  }

  @discardableResult
  func updateSelection(
    text: String,
    source: String,
    frameInView: NSRect?
  ) -> SelectedTextAccessibilityUpdateOutcome {
    guard !source.isEmpty else { return .unchanged }

    let wasActive = accessibilityElement.hasSelection
    if text.isEmpty {
      guard activeSource == source else { return .ignoredStaleClear }

      activeSource = nil
      let changed = accessibilityElement.update(text: nil, frameInView: nil)
      if changed {
        post(.selectedTextChanged, element: accessibilityElement)
      }
      if wasActive {
        postFocusChanged()
        return .deactivated
      }
      return .unchanged
    }

    let previousSource = activeSource
    activeSource = source
    let changed = accessibilityElement.update(
      text: text,
      frameInView: frameInView
    )
    if changed {
      post(.selectedTextChanged, element: accessibilityElement)
    }
    if !wasActive {
      postFocusChanged()
      return .activated
    }
    return changed || previousSource != source ? .updated : .unchanged
  }

  private func post(
    _ notification: NSAccessibility.Notification,
    element: Any
  ) {
    notificationPoster(element, notification)
  }

  private func postFocusChanged() {
    guard let ownerWindow else { return }
    post(.focusedUIElementChanged, element: ownerWindow)
  }

  private static func parseBounds(_ value: Any?) throws -> NSRect? {
    guard let value else { return nil }
    guard let bounds = value as? [String: Any],
          let x = number(bounds["x"]),
          let y = number(bounds["y"]),
          let width = number(bounds["width"]),
          let height = number(bounds["height"]),
          x.isFinite,
          y.isFinite,
          width.isFinite,
          height.isFinite,
          width > 0,
          height > 0 else {
      throw SelectedTextAccessibilityControllerError.invalidArguments(
        "Selection bounds must contain finite x, y, width, and height values."
      )
    }
    return NSRect(x: x, y: y, width: width, height: height)
  }

  private static func number(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return value as? Double
  }
}
