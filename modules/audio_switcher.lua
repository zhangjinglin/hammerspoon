local M = {}

local AMP_NAME           = "External Headphones" -- 外置功放
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"

local lastDisplayState   = nil -- "projector" | "monitor" | "all_off"
local settleTimer        = nil
local screensAsleep      = false

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

-- 当显示器和投影机都关闭时，执行静音保护
local function muteAllAudio()
    -- 静音外置功放
    local amp = hs.audiodevice.findOutputByName(AMP_NAME)
    if amp and amp:muted() == false then
        amp:setMuted(true)
    end

    -- 静音当前默认设备（若支持）
    local cur = hs.audiodevice.defaultOutputDevice()
    if cur and cur:muted() == false then
        cur:setMuted(true)
    end

    print("[audio_switcher] 显示器与投影机均已关闭，已静音音频输出")
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

-- 统一防抖收敛：合并短时间内的所有屏幕/设备/唤醒事件，等硬件握手稳定后再做切换
local function scheduleSwitch(delay, showAlert)
    if settleTimer then
        settleTimer:stop()
    end

    settleTimer = hs.timer.doAfter(delay or 1.5, function()
        settleTimer = nil

        local state = currentDisplayState()
        local stateChanged = (state ~= lastDisplayState)
        lastDisplayState = state

        if state == "all_off" then
            muteAllAudio()
        elseif state == "projector" then
            applyDefault(AMP_NAME, showAlert or stateChanged)
        elseif state == "monitor" then
            local success = applyDefault(MONITOR_NAME, showAlert or stateChanged)
            if not success then
                -- 27M3U 尚未就绪，不强行动音量，保持现状
                print("[audio_switcher] 未找到期望设备: " .. MONITOR_NAME)
            end
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

-- 3. 系统/屏幕休眠与唤醒监听
local caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
    if eventType == hs.caffeinate.watcher.screensDidSleep
        or eventType == hs.caffeinate.watcher.systemWillSleep then
        screensAsleep = true
        scheduleSwitch(0.5, false)
    elseif eventType == hs.caffeinate.watcher.screensDidWake
        or eventType == hs.caffeinate.watcher.systemDidWake then
        screensAsleep = false
        scheduleSwitch(2.0, false)
    end
end)

function M:start()
    screensAsleep = false
    lastDisplayState = currentDisplayState()
    screenWatcher:start()
    hs.audiodevice.watcher.start()
    caffeinateWatcher:start()

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
    caffeinateWatcher:stop()
end

return M
