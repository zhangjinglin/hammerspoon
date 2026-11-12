local M = {}

local AMP_NAME           = "External Headphones" -- 外置功放
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"

local lastProjectorState = nil
local settleTimer        = nil

local function projectorOnline()
    for _, screen in ipairs(hs.screen.allScreens()) do
        if screen:name() == PROJECTOR_NAME then
            return true
        end
    end
    return false
end

-- 当前期望的默认输出设备：投影仪开着用功放，否则用显示器
local function desiredDeviceName()
    if projectorOnline() then
        return AMP_NAME
    end
    return MONITOR_NAME
end

-- 安全地设置指定设备为默认输出
local function applyDefault(name, showAlert)
    local dev = hs.audiodevice.findOutputByName(name)
    if not dev then
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

    -- 只有外置功放（且支持音量调节）时才把音量设为 100
    -- 27M3U 等 HDMI 设备不支持软件音量调节，绝不能调用 setVolume
    if name == AMP_NAME and dev:volume() ~= nil then
        dev:setVolume(100)
    end

    if showAlert and not alreadyDefault then
        hs.alert.show("音频输出: " .. name)
    end

    return true
end

-- 统一防抖收敛：合并短时间内的所有屏幕/设备/唤醒事件，等硬件握手稳定后再做切换
local function scheduleSwitch(delay, showAlert)
    if settleTimer then
        settleTimer:stop()
    end

    settleTimer = hs.timer.doAfter(delay or 1.5, function()
        settleTimer = nil

        local online = projectorOnline()
        local stateChanged = (online ~= lastProjectorState)
        lastProjectorState = online

        local target = desiredDeviceName()
        local success = applyDefault(target, showAlert or stateChanged)

        if not success and target == MONITOR_NAME then
            -- 27M3U 尚未就绪，不强行动音量，保持现状
            print("[audio_switcher] 未找到期望设备: " .. target)
        end
    end)
end

-- 1. 屏幕监听：显示器打开/关闭、投影仪开关
local screenWatcher = hs.screen.watcher.new(function()
    scheduleSwitch(1.5, false)
end)

-- 2. 音频设备监听：HDMI 音频端点上线/注销
hs.audiodevice.watcher.setCallback(function(event)
    if event == "dev#" then
        scheduleSwitch(1.5, false)
    end
end)

-- 3. 系统唤醒监听：休眠唤醒时重新校验
local wakeWatcher = hs.caffeinate.watcher.new(function(eventType)
    if eventType == hs.caffeinate.watcher.screensDidWake
        or eventType == hs.caffeinate.watcher.systemDidWake then
        scheduleSwitch(2.0, false)
    end
end)

function M:start()
    lastProjectorState = projectorOnline()
    screenWatcher:start()
    hs.audiodevice.watcher.start()
    wakeWatcher:start()

    -- 启动后延迟 1 秒安全纠正一次
    scheduleSwitch(1.0, false)
    return self
end

function M:stop()
    if settleTimer then
        settleTimer:stop()
        settleTimer = nil
    end
    screenWatcher:stop()
    hs.audiodevice.watcher.stop()
    wakeWatcher:stop()
end

return M
