import Cocoa

enum TransientPasteboardTextCapture {
  // Typeless marks the temporary clipboard item before synthesizing Cmd+V.
  static let markerType = NSPasteboard.PasteboardType(
    "org.nspasteboard.TransientType"
  )

  static func capture(event: NSEvent, pasteboard: NSPasteboard) -> String? {
    guard isPlainCommandV(event), event.type == .keyDown else { return nil }
    guard let item = pasteboard.pasteboardItems?.first,
          item.types.contains(markerType) else {
      return nil
    }
    guard let text = item.string(forType: .string), !text.isEmpty else {
      return nil
    }
    return text
  }

  static func isVKeyEvent(_ event: NSEvent) -> Bool {
    event.keyCode == 9 || event.charactersIgnoringModifiers?.lowercased() == "v"
  }

  static func isPlainCommandV(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown || event.type == .keyUp else { return false }
    guard isVKeyEvent(event) else { return false }
    let modifiers = event.modifierFlags.intersection(
      .deviceIndependentFlagsMask
    )
    return modifiers.contains(.command)
      && !modifiers.contains(.control)
      && !modifiers.contains(.option)
      && !modifiers.contains(.shift)
  }
}
