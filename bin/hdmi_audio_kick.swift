import Foundation
import CoreAudio

func findDevice(matching nameKeyword: String) -> AudioDeviceID? {
    var allDevAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var allDevSize: UInt32 = 0
    let err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &allDevAddr, 0, nil, &allDevSize)
    guard err == noErr, allDevSize > 0 else { return nil }
    
    let count = Int(allDevSize) / MemoryLayout<AudioDeviceID>.size
    var devIDs = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &allDevAddr, 0, nil, &allDevSize, &devIDs)
    
    let targetLower = nameKeyword.lowercased()
    for id in devIDs {
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let s = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &size, ptr)
        }
        if s == noErr {
            let name = cfName as String
            if name.lowercased().contains(targetLower) {
                return id
            }
        }
    }
    return nil
}

func getNominalSampleRate(devID: AudioDeviceID) -> Float64? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    let s = AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &rate)
    return s == noErr ? rate : nil
}

func setNominalSampleRate(devID: AudioDeviceID, rate: Float64) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var targetRate = rate
    let size = UInt32(MemoryLayout<Float64>.size)
    let s = AudioObjectSetPropertyData(devID, &addr, 0, nil, size, &targetRate)
    return s == noErr
}

func getAvailableSampleRates(devID: AudioDeviceID) -> [Float64] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let err = AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &size)
    guard err == noErr, size > 0 else { return [] }
    
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
    AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &ranges)
    
    var rates: [Float64] = []
    for r in ranges {
        rates.append(r.mMinimum)
        if r.mMaximum != r.mMinimum {
            rates.append(r.mMaximum)
        }
    }
    return Array(Set(rates)).sorted()
}

func setDefaultOutput(devID: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var id = devID
    let s = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id)
    return s == noErr
}

func kickAudio(deviceName: String) -> Bool {
    guard let devID = findDevice(matching: deviceName) else {
        print("[hdmi_audio_kick] 未找到设备: \(deviceName)")
        return false
    }
    
    guard let currentRate = getNominalSampleRate(devID: devID) else {
        print("[hdmi_audio_kick] 无法读取采样率: \(deviceName) (ID: \(devID))")
        return false
    }
    
    let availableRates = getAvailableSampleRates(devID: devID)
    
    // 优先选择 44100 与 48000 互切
    let alternateRate: Float64
    if currentRate == 48000.0 && availableRates.contains(44100.0) {
        alternateRate = 44100.0
    } else if currentRate == 44100.0 && availableRates.contains(48000.0) {
        alternateRate = 48000.0
    } else if let alt = availableRates.first(where: { abs($0 - currentRate) > 1.0 }) {
        alternateRate = alt
    } else {
        alternateRate = (currentRate == 48000.0) ? 44100.0 : 48000.0
    }
    
    // 切换至替代采样率，迫使 CoreAudio 与 HDMI 控制器完全重构 DMA 管道与 ACR 时钟
    _ = setNominalSampleRate(devID: devID, rate: alternateRate)
    
    // 等待硬件完成重协商
    usleep(150_000)
    
    // 切回原始基准采样率
    let restored = setNominalSampleRate(devID: devID, rate: currentRate)
    
    usleep(100_000)
    _ = setDefaultOutput(devID: devID)
    
    if restored {
        print("[hdmi_audio_kick] ✅ HDMI 音频时钟管线重置完成 (\(deviceName), \(currentRate) Hz)")
        return true
    } else {
        print("[hdmi_audio_kick] ⚠️ 恢复初始采样率失败")
        return false
    }
}

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "27M3U"
let success = kickAudio(deviceName: target)
exit(success ? 0 : 1)
