// Display-audio probe and repair for Apple Silicon HDMI/DisplayPort outputs.
//
// Usage:
//   hdmi_audio_kick <device name>           probe, then repair only if stuck (default)
//   hdmi_audio_kick --probe <device name>   probe only
//
// Exit codes: 0 healthy or repaired, 1 still stuck, 2 could not check.
//
// Build: swiftc -O hdmi_audio_kick.swift -o hdmi_audio_kick

import CoreAudio
import Foundation
import IOKit
import Darwin

private let probeWindowSeconds = 2.0
private let notRunningStatus: OSStatus = 1_937_010_544 // kAudioHardwareNotRunningError ('stop')

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

private func scalarProperty<T: FixedWidthInteger>(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    fallback: T
) -> T {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    var value = fallback
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : fallback
}

private func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var ref: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ref) == noErr, let ref else { return nil }
    return ref.takeRetainedValue() as String
}

private func audioDevices() -> [AudioObjectID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

private func outputStreamCount(_ device: AudioObjectID) -> Int {
    var addr = address(kAudioDevicePropertyStreams)
    addr.mScope = kAudioObjectPropertyScopeOutput
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return 0 }
    return Int(size) / MemoryLayout<AudioStreamID>.size
}

private func name(of device: AudioObjectID) -> String {
    stringProperty(device, kAudioObjectPropertyName) ?? "?"
}

private func uid(of device: AudioObjectID) -> String? {
    stringProperty(device, kAudioDevicePropertyDeviceUID)
}

private func findDevice(_ query: String) -> AudioDeviceID? {
    let outputs = audioDevices().filter { outputStreamCount($0) > 0 }
    if query.hasPrefix("uid:") {
        let wanted = String(query.dropFirst(4))
        return outputs.first { uid(of: $0) == wanted }
    }
    if let exact = outputs.first(where: { name(of: $0) == query }) {
        return exact
    }
    let lower = query.lowercased()
    let matches = outputs.filter { name(of: $0).lowercased().contains(lower) }
    return matches.count == 1 ? matches[0] : nil
}

private func nominalSampleRate(_ device: AudioObjectID) -> Float64 {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var size = UInt32(MemoryLayout<Float64>.size)
    var rate: Float64 = 0
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr, rate > 0 else { return 48_000 }
    return rate
}

private func setNominalSampleRate(_ device: AudioObjectID, _ rate: Float64) -> OSStatus {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var target = rate
    return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &target)
}

private func availableSampleRates(_ device: AudioObjectID) -> [Float64] {
    var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
    var rates: [Float64] = []
    for range in ranges {
        rates.append(range.mMinimum)
        if range.mMaximum != range.mMinimum { rates.append(range.mMaximum) }
    }
    return Array(Set(rates)).sorted()
}

private func hogOwner(_ device: AudioObjectID) -> pid_t {
    scalarProperty(device, kAudioDevicePropertyHogMode, fallback: pid_t(-1))
}

// MARK: Kernel display-audio engine

private struct EngineSample {
    let entryID: UInt64
    let running: Bool
    let transfers: Int
    let bufferSeconds: Double
}

private func engineSample(forUID wanted: String) -> EngineSample? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVAudioDriver"), &iterator) == KERN_SUCCESS else {
        return nil
    }
    defer { IOObjectRelease(iterator) }
    var found: [EngineSample?] = []
    while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }
        let property = { (key: String) in
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard property("device UID") as? String == wanted else { continue }
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
              let running = property("is running") as? Bool,
              let transfers = (property("TransferCount") as? NSNumber)?.intValue,
              let frames = (property("io buffer frame size") as? NSNumber)?.doubleValue,
              let fixedRate = (property("sample rate") as? NSNumber)?.doubleValue else {
            found.append(nil)
            continue
        }
        let rate = fixedRate / 4_294_967_296
        found.append(EngineSample(
            entryID: entryID,
            running: running,
            transfers: transfers,
            bufferSeconds: frames > 0 && rate > 0 ? frames / rate : 0
        ))
    }
    return found.count == 1 ? found[0] : nil
}

// nil means no evidence either way; only a running engine that did not finish a single
// buffer pass in at least three passes' time is evidence of a stall.
private func engineStalled(before: EngineSample?, after: EngineSample?, elapsed: Double) -> Bool? {
    guard let before, let after, before.entryID == after.entryID, before.running, after.running,
          before.bufferSeconds > 0, after.transfers >= before.transfers else { return nil }
    if after.transfers > before.transfers { return false }
    return elapsed >= 3 * before.bufferSeconds ? true : nil
}

// MARK: Probe

private final class CallbackTally: @unchecked Sendable {
    private struct State {
        var count = 0
        var lastSample: Float64 = -1
        var advancedFrames: Float64 = 0
    }

    private let lock = NSLock()
    private var state = State()

    func record(_ sample: Float64) {
        lock.lock()
        if state.lastSample >= 0, sample > state.lastSample {
            state.advancedFrames += sample - state.lastSample
        }
        state.lastSample = sample
        state.count += 1
        lock.unlock()
    }

    func snapshot() -> (count: Int, advanced: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (state.count, state.advancedFrames)
    }
}

private final class StartState: @unchecked Sendable {
    private let lock = NSLock()
    private var status: OSStatus?
    private var abandoned = false

    // Called by the thread blocked in AudioDeviceStart; true means the probe has given up.
    func finished(_ value: OSStatus) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        status = value
        return abandoned
    }

    func currentStatus() -> OSStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    // nil means the start has not returned; the start thread now owns cleanup.
    func abandonUnlessFinished() -> OSStatus? {
        lock.lock()
        defer { lock.unlock() }
        if status == nil { abandoned = true }
        return status
    }
}

// Returns true when the device's audio clock really moves, false when it is stuck,
// nil when the check could not run (busy, unplugged) or failed for another reason.
private func probe(_ device: AudioDeviceID, chillSeconds: Double = probeWindowSeconds) -> Bool? {
    let deviceName = name(of: device)
    let owner = hogOwner(device)
    if owner != -1 {
        print("[hdmi_audio_kick] could not check '\(deviceName)': another process has exclusive use of it")
        return nil
    }
    guard let deviceUID = uid(of: device) else {
        print("[hdmi_audio_kick] could not check '\(deviceName)': no device UID")
        return nil
    }

    print("[hdmi_audio_kick] probing '\(deviceName)' with \(chillSeconds)s of silence...")
    let tally = CallbackTally()
    var procID: AudioDeviceIOProcID?
    let created = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil) { _, _, _, outData, outTime in
        for buffer in UnsafeMutableAudioBufferListPointer(outData) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        tally.record(outTime.pointee.mSampleTime)
    }
    guard created == noErr, let procID else {
        print("[hdmi_audio_kick] could not create an IOProc on '\(deviceName)' (OSStatus \(created))")
        return nil
    }

    let startState = StartState()
    let starter = Thread {
        let status = AudioDeviceStart(device, procID)
        if startState.finished(status) {
            AudioDeviceStop(device, procID)
            AudioDeviceDestroyIOProcID(device, procID)
            print("[hdmi_audio_kick] a late start on '\(deviceName)' returned; its IOProc is cleaned up")
        }
    }
    starter.name = "hdmi_audio_kick probe"
    starter.start()

    // A stuck start blocks for about 10 seconds. Start measuring after it returns, or
    // after 2 seconds for a healthy device, whichever comes first.
    let firstDeadline = Date().addingTimeInterval(2.0)
    while startState.currentStatus() == nil, Date() < firstDeadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let engineBefore = engineSample(forUID: deviceUID)
    let windowStart = Date()
    Thread.sleep(forTimeInterval: chillSeconds)
    let tallySnapshot = tally.snapshot()
    let engineAfter = engineSample(forUID: deviceUID)
    let elapsed = Date().timeIntervalSince(windowStart)
    let stalled = engineStalled(before: engineBefore, after: engineAfter, elapsed: elapsed)

    // Wait for a blocked start to return so its IOProc can be torn down.
    let finalDeadline = Date().addingTimeInterval(13.0)
    while startState.currentStatus() == nil, Date() < finalDeadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let startStatus = startState.abandonUnlessFinished() else {
        print("[hdmi_audio_kick] AudioDeviceStart on '\(deviceName)' has not returned after 15s")
        return false
    }
    AudioDeviceStop(device, procID)
    AudioDeviceDestroyIOProcID(device, procID)

    if startStatus != noErr && startStatus != notRunningStatus {
        print("[hdmi_audio_kick] could not check '\(deviceName)': AudioDeviceStart returned OSStatus \(startStatus)")
        return nil
    }
    let rate = nominalSampleRate(device)
    let expected = rate * chillSeconds * 0.3
    let clockMoved = tallySnapshot.count >= 3 && tallySnapshot.advanced >= expected
    let healthy = clockMoved && stalled != true

    if clockMoved && !healthy {
        print("[hdmi_audio_kick] '\(deviceName)' looks open but its engine has not moved; an app may hold a dead device open")
    }
    if let before = engineBefore, let after = engineAfter {
        print(String(format: "[hdmi_audio_kick] callbacks=%d advanced=%.0f/%.0f frames, engine transfers %d -> %d",
                     tallySnapshot.count, tallySnapshot.advanced, expected, before.transfers, after.transfers))
    } else {
        print(String(format: "[hdmi_audio_kick] callbacks=%d advanced=%.0f/%.0f frames, engine counters unavailable",
                     tallySnapshot.count, tallySnapshot.advanced, expected))
    }
    print("[hdmi_audio_kick] VERDICT: \(healthy ? "HEALTHY" : "STUCK")")
    return healthy
}

// MARK: Repair

private func alternateRates(current: Float64, available: [Float64]) -> [Float64] {
    var result: [Float64] = []
    let preferred: [Float64] = current == 48_000 ? [44_100, 32_000] : [48_000, 44_100, 32_000]
    for rate in preferred where abs(rate - current) > 1 && available.contains(rate) && !result.contains(rate) {
        result.append(rate)
    }
    for rate in available where abs(rate - current) > 1 && !result.contains(rate) {
        result.append(rate)
    }
    return result
}

private func repair(_ device: AudioDeviceID) -> Int32 {
    let deviceName = name(of: device)
    switch probe(device) {
    case true?:
        print("[hdmi_audio_kick] '\(deviceName)' is already healthy; nothing to do")
        return 0
    case nil:
        print("[hdmi_audio_kick] '\(deviceName)' could not be checked; not changing anything")
        return 2
    case false?:
        break
    }

    let currentRate = nominalSampleRate(device)
    let alternatives = alternateRates(current: currentRate, available: availableSampleRates(device))
    guard !alternatives.isEmpty else {
        print("[hdmi_audio_kick] '\(deviceName)' has no alternate sample rate to switch to")
        return 1
    }

    var toggled = false
    for rate in alternatives {
        let status = setNominalSampleRate(device, rate)
        let observed = nominalSampleRate(device)
        print(String(format: "[hdmi_audio_kick] set %.0f Hz -> OSStatus %d (now %.0f Hz)", rate, status, observed))
        if status == noErr, abs(observed - rate) < 1 {
            toggled = true
            break
        }
    }
    usleep(150_000)

    var restored = false
    for attempt in 1...3 {
        let status = setNominalSampleRate(device, currentRate)
        let observed = nominalSampleRate(device)
        print(String(format: "[hdmi_audio_kick] restore %.0f Hz attempt %d -> OSStatus %d (now %.0f Hz)",
                     currentRate, attempt, status, observed))
        if status == noErr, abs(observed - currentRate) < 1 {
            restored = true
            break
        }
        usleep(150_000)
    }
    guard toggled, restored else {
        print("[hdmi_audio_kick] sample-rate toggle did not complete on '\(deviceName)'")
        return 1
    }

    usleep(200_000)
    switch probe(device) {
    case true?:
        print("[hdmi_audio_kick] repaired '\(deviceName)'")
        return 0
    case false?:
        print("[hdmi_audio_kick] '\(deviceName)' is still stuck after the sample-rate toggle")
        return 1
    case nil:
        print("[hdmi_audio_kick] repaired '\(deviceName)' but could not verify it")
        return 2
    }
}

// MARK: Entry point

var arguments = Array(CommandLine.arguments.dropFirst())
var probeOnly = false
if arguments.first == "--probe" {
    probeOnly = true
    arguments.removeFirst()
}
let target = arguments.first ?? "27M3U"
guard let device = findDevice(target) else {
    print("[hdmi_audio_kick] device not found: \(target)")
    exit(2)
}
if probeOnly {
    switch probe(device) {
    case true?: exit(0)
    case false?: exit(1)
    case nil: exit(2)
    }
}
exit(repair(device))
