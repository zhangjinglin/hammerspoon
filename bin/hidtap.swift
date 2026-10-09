import CoreGraphics
import Foundation

// Post one modifier tap at HID level (where hardware keys enter).
// Session-level posts (hs.eventtap / System Events) are ignored by Doubao IME,
// so mouse_voice.lua calls this helper instead of synthesizing in-process.
// Usage: hidtap <keycode>  (61 = right option, 59 = control, 63 = fn)
let code: CGKeyCode = CGKeyCode(Int(CommandLine.arguments.dropFirst().first ?? "61") ?? 61)

if let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) {
    down.post(tap: .cghidEventTap)
}
Thread.sleep(forTimeInterval: 0.12)
if let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
    up.post(tap: .cghidEventTap)
}
