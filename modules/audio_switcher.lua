local M = {}

local AMP_NAME           = "External Headphones" -- 外置功放
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"

local lastDisplayState   = nil -- "projector" | "monitor" | "all_off"
local settleTimer        = nil
local retryTimer         = nil
local screensAsleep      = false
local wakeGracePeriod    = false  -- 唤醒保护期：防止 screen/audiodevice 事件覆盖 wake 定时器
local mutedDeviceUIDs    = {}     -- 记录被 muteAllAudio 静音的设备 UID，唤醒时定向解除

local MAX_RETRIES        = 5
local RETRY_INTERVAL     = 2      -- 秒
local WAKE_SETTLE_DELAY  = 3.5    -- HDMI ARC 握手通常需要 3-5 秒

local function screenOnline(name)
    for _, screen in ipairs(hs.screen.allScreens()) do
        local sname = screen:name() or ""
        if sname == name or string.find(sname, name, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function projectorOnline()
    return screenOnline(PROJECTOR_NAME)
end

local function monitorOnline()
    return screenOnline(MONITOR_NAME)
end

-- 供外部模块（如 announcer.lua）查询当前屏幕是否处于活跃可用状态
function M.isDisplayActive()
    if screensAsleep then
        return false
    end
    return projectorOnline() or monitorOnline()
end

-- 获取当前显示设备状态
local function currentDisplayState()
    if screensAsleep then
        return "all_off"
    end
    if projectorOnline() then
        return "projector"
    elseif monitorOnline() then
        return "monitor"
    else
        return "all_off"
    end
end

-- 当显示器和投影机都关闭时，执行静音保护（记录被静音的设备 UID）
local function muteAllAudio()
    mutedDeviceUIDs = {}

    -- 静音外置功放
    local amp = hs.audiodevice.findOutputByName(AMP_NAME)
    if amp and amp:muted() == false then
        amp:setMuted(true)
        table.insert(mutedDeviceUIDs, amp:uid())
    end

    -- 静音当前默认设备（若支持）
    local cur = hs.audiodevice.defaultOutputDevice()
    if cur and cur:muted() == false then
        cur:setMuted(true)
        table.insert(mutedDeviceUIDs, cur:uid())
    end

    print("[audio_switcher] 显示器与投影机均已关闭，已静音音频输出")
end

-- 唤醒时，解除所有之前被 muteAllAudio 静音的设备（按 UID 定向解除）
local function unmutePreviouslyMuted()
    if #mutedDeviceUIDs == 0 then
        return
    end

    local devices = hs.audiodevice.allOutputDevices() or {}
    for _, dev in ipairs(devices) do
        local uid = dev:uid()
        for _, mutedUID in ipairs(mutedDeviceUIDs) do
            if uid == mutedUID and dev:muted() == true then
                dev:setMuted(false)
                print("[audio_switcher] 解除之前静音的设备: " .. (dev:name() or uid))
            end
        end
    end

    mutedDeviceUIDs = {}
end

-- 安全地设置指定设备为默认输出（带重试机制）
local function applyDefault(name, showAlert, retryCount)
    local dev = hs.audiodevice.findOutputByName(name)
    if not dev then
        retryCount = retryCount or 0
        if retryCount < MAX_RETRIES then
            print(string.format("[audio_switcher] 未找到 %s，%d 秒后重试 (%d/%d)",
                name, RETRY_INTERVAL, retryCount + 1, MAX_RETRIES))
            if retryTimer then
                retryTimer:stop()
            end
            retryTimer = hs.timer.doAfter(RETRY_INTERVAL, function()
                retryTimer = nil
                applyDefault(name, showAlert, retryCount + 1)
            end)
        else
            print(string.format("[audio_switcher] 重试 %d 次后仍未找到 %s，放弃",
                MAX_RETRIES, name))
        end
        return false
    end

    local cur = hs.audiodevice.defaultOutputDevice()
    local alreadyDefault = cur and (cur:uid() == dev:uid())

    -- 避免对 HDMI 设备重复设置默认设备（重复设置会打断 HDMI ACR 时钟协商）
    if not alreadyDefault then
        dev:setDefaultOutputDevice()
    end

    -- 若设备支持静音且处于静音状态，解开静音
    if dev:muted() == true then
        dev:setMuted(false)
    end

    -- 同时解除之前 muteAllAudio 静音的其他设备（如 Mac mini Speakers）
    unmutePreviouslyMuted()

    if name == AMP_NAME then
        -- 投影仪模式：外置功放（且支持音量调节）时音量设为 100
        if dev:volume() ~= nil then
            dev:setVolume(100)
        end
    elseif name == MONITOR_NAME then
        -- 显示器模式：顺便将外置功放静音，避免闲置发声或杂音
        local amp = hs.audiodevice.findOutputByName(AMP_NAME)
        if amp and amp:muted() == false then
            amp:setMuted(true)
        end
    end

    if showAlert and not alreadyDefault then
        hs.alert.show("音频输出: " .. name)
    end

    return true
end

-- 前置声明 scheduleSwitch（因为 caffeinateWatcher 和 screenWatcher 都引用它）
local scheduleSwitch

-- 统一防抖收敛：合并短时间内的所有屏幕/设备/唤醒事件，等硬件握手稳定后再做切换
scheduleSwitch = function(delay, showAlert, source)
    -- 唤醒保护期内，screen/audiodevice 事件不覆盖 wake 的定时器
    if wakeGracePeriod and source ~= "wake" then
        print("[audio_switcher] 唤醒保护期内，忽略来自 " .. tostring(source) .. " 的事件")
        return
    end

    if settleTimer then
        settleTimer:stop()
    end

    -- 取消任何正在进行的重试
    if retryTimer then
        retryTimer:stop()
        retryTimer = nil
    end

    settleTimer = hs.timer.doAfter(delay or 1.5, function()
        settleTimer = nil
        wakeGracePeriod = false

        local state = currentDisplayState()
        local stateChanged = (state ~= lastDisplayState)
        lastDisplayState = state

        if state == "all_off" then
            muteAllAudio()
        elseif state == "projector" then
            applyDefault(AMP_NAME, showAlert or stateChanged)
        elseif state == "monitor" then
            -- applyDefault 自带重试，找不到设备会自动每 2 秒重试最多 5 次
            applyDefault(MONITOR_NAME, showAlert or stateChanged)
        end
    end)
end

-- 1. 屏幕监听：显示器打开/关闭、投影仪开关
local screenWatcher = hs.screen.watcher.new(function()
    scheduleSwitch(1.5, false, "screen")
end)

-- 2. 音频设备监听：HDMI 音频端点上线/注销
hs.audiodevice.watcher.setCallback(function(event)
    if event == "dev#" then
        scheduleSwitch(1.5, false, "audiodevice")
    end
end)

-- 3. 系统/屏幕休眠与唤醒监听
local caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
    if eventType == hs.caffeinate.watcher.screensDidSleep
        or eventType == hs.caffeinate.watcher.systemWillSleep then
        screensAsleep = true
        wakeGracePeriod = false
        scheduleSwitch(0.5, false, "sleep")
    elseif eventType == hs.caffeinate.watcher.screensDidWake
        or eventType == hs.caffeinate.watcher.systemDidWake then
        screensAsleep = false
        wakeGracePeriod = true  -- 进入唤醒保护期，阻止 screen/audiodevice 事件覆盖
        scheduleSwitch(WAKE_SETTLE_DELAY, false, "wake")
    end
end)

function M:start()
    screensAsleep = false
    wakeGracePeriod = false
    mutedDeviceUIDs = {}
    lastDisplayState = currentDisplayState()
    screenWatcher:start()
    hs.audiodevice.watcher.start()
    caffeinateWatcher:start()

    -- 启动后延迟 1 秒安全纠正一次
    scheduleSwitch(1.0, false, "init")
    return self
end

function M:stop()
    if settleTimer then
        settleTimer:stop()
        settleTimer = nil
    end
    if retryTimer then
        retryTimer:stop()
        retryTimer = nil
    end
    wakeGracePeriod = false
    mutedDeviceUIDs = {}
    screenWatcher:stop()
    hs.audiodevice.watcher.stop()
    caffeinateWatcher:stop()
end

return M
