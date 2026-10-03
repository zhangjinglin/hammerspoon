// doubao_voice_watch.swift
// 常驻监控：轮询 CGWindowList，只关注 owner == "豆包输入法" 且 layer >= 3 的浮窗
// （语音悬浮条实测为 layer=3 124x32），出现打 VOICE ON，消失打 VOICE OFF。
import CoreGraphics
import Foundation

let targetOwner = "豆包输入法"

func voiceWindows() -> Set<String> {
    let infos = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    var s = Set<String>()
    for w in infos {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == targetOwner else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard layer >= 3 else { continue }
        let num = w[kCGWindowNumber as String] as? Int ?? 0
        let b = w[kCGWindowBounds as String] as? [String: Any]
        let wh = "\(b?["Width"] ?? "?")x\(b?["Height"] ?? "?")"
        s.insert("\(num) layer=\(layer) \(wh)")
    }
    return s
}

var prev = voiceWindows()
fputs("READY\n", stderr)
while true {
    Thread.sleep(forTimeInterval: 0.2)
    let cur = voiceWindows()
    if cur != prev {
        let on = !cur.subtracting(prev).isEmpty
        let off = cur.isEmpty && !prev.isEmpty
        if on { print("VOICE ON \(cur.sorted().joined(separator: ","))") }
        if off { print("VOICE OFF") }
        fflush(stdout)
        prev = cur
    }
}
