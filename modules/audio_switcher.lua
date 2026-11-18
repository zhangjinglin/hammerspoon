local M = {}

local AMP_NAME           = "External Headphones" -- 外置功放
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"
local KICK_BIN           = os.getenv("HOME") .. "/.hammerspoon/bin/hdmi_audio_kick"

local lastDisplayState   = nil -- "projector" | "monitor" | "all_off"
local lastDisplayAudioSig = ""
local settleTimer        = nil
local retryTimer         = nil
local repairTimer        = nil
local repairTask         = nil
local repairInFlight     = false
local pendingRepair      = nil -- { name = string, callback = function|nil }
local stopped            = false
local screensAsleep      = false
local wakeGracePeriod    = false  -- 唤醒保护期：防止 screen/audiodevice 事件覆盖 wake 定时器
local mutedDeviceUIDs    = {}     -- UID -> true，仅记录本模块静音的设备

local MAX_RETRIES        = 5
local RETRY_INTERVAL     = 2      -- 秒
local WAKE_SETTLE_DELAY  = 3.5    -- HDMI ARC 握手通常需要 3-5 秒
local REPAIR_DELAY       = 0.8    -- 默认输出切换后等待硬件稳定的时间

local function isDisplayAudioName(name)
    return name == MONITOR_NAME or name == PROJECTOR_NAME
end

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

-- 显示音频设备当前存在情况（用于过滤无关的 USB/蓝牙设备增删事件）
local function displayAudioSignature()
    local names = {}
    for _, dev in ipairs(hs.audiodevice.allOutputDevices() or {}) do
        local devName = dev:name()
        if isDisplayAudioName(devName) then
            names[#names + 1] = devName
        end
    end
    table.sort(names)
    return table.concat(names, "|")
end

-- 当前默认输出，仅当它是显示音频设备时返回名字
local function currentDisplayAudioDefaultName()
    local dev = hs.audiodevice.defaultOutputDevice()
    if not dev then
        return nil
    end
    local devName = dev:name()
    if isDisplayAudioName(devName) then
        return devName
    end
    return nil
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

local function muteDevice(dev)
    if not dev then
        return
    end
    if dev:muted() == false then
        dev:setMuted(true)
        if dev:muted() == true then
            mutedDeviceUIDs[dev:uid()] = true
        end
    end
end

-- 当显示器和投影机都关闭时，执行静音保护。
-- 注意：不清空已有记录，否则息屏期间重复触发会丢失之前静音的设备，唤醒后无法恢复。
local function muteAllAudio()
    muteDevice(hs.audiodevice.findOutputByName(AMP_NAME))

    local cur = hs.audiodevice.defaultOutputDevice()
    if cur and not isDisplayAudioName(cur:name()) then
        muteDevice(cur)
    end

    print("[audio_switcher] 显示器与投影机均已关闭，已静音音频输出")
end

-- 解除本模块之前静音的设备（按 UID 定向解除）
local function unmutePreviouslyMuted()
    if next(mutedDeviceUIDs) == nil then
        return
    end

    for _, dev in ipairs(hs.audiodevice.allOutputDevices() or {}) do
        local uid = dev:uid()
        if uid and mutedDeviceUIDs[uid] then
            if dev:muted() == true then
                dev:setMuted(false)
                print("[audio_switcher] 解除之前静音的设备: " .. (dev:name() or uid))
            end
            mutedDeviceUIDs[uid] = nil
        end
    end
end

local function logToolOutput(prefix, text)
    if not text or text == "" then
        return
    end
    for line in tostring(text):gmatch("[^\r\n]+") do
        print(prefix .. line)
    end
end

-- 调用探测/修复工具：健康则直接返回，卡死才瞬切采样率并复测。
-- 工具不修改默认输出，路由仍由本模块决定。
local function runRepair(name, callback)
    if stopped then
        return
    end
    if repairInFlight then
        pendingRepair = { name = name, callback = callback }
        return
    end
    if not hs.fs.attributes(KICK_BIN) then
        print("[audio_switcher] 警告: 未找到显示音频工具: " .. KICK_BIN)
        if callback then
            callback(false, "missing")
        end
        return
    end

    repairInFlight = true
    repairTask = hs.task.new(KICK_BIN, function(exitCode, stdOut, stdErr)
        repairTask = nil
        repairInFlight = false
        if stopped then
            return
        end

        if exitCode == 0 then
            if stdOut and stdOut:find("repaired", 1, true) then
                print("[audio_switcher] 已修复显示音频: " .. tostring(name))
            end
        else
            logToolOutput("[audio_switcher] ", stdOut)
            logToolOutput("[audio_switcher] ", stdErr)
            print(string.format("[audio_switcher] %s 的显示音频检测/修复返回 %s",
                tostring(name), tostring(exitCode)))
        end

        if callback then
            callback(exitCode == 0, exitCode)
        end

        local queued = pendingRepair
        pendingRepair = nil
        if queued then
            runRepair(queued.name, queued.callback)
        end
    end, { name }):start()
end

-- 默认输出就绪后，只修复“当前默认”的显示音频设备。
-- 投影仪模式下默认输出是功放，因此不会碰 JMGO；手动选 JMGO 时由 dOut 事件触发。
local function scheduleDefaultRepair(delay)
    if stopped then
        return
    end
    if repairTimer then
        repairTimer:stop()
    end
    repairTimer = hs.timer.doAfter(delay or REPAIR_DELAY, function()
        repairTimer = nil
        if stopped or screensAsleep then
            return
        end
        local name = currentDisplayAudioDefaultName()
        if name then
            runRepair(name)
        end
    end)
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

    if not alreadyDefault then
        dev:setDefaultOutputDevice()
    end

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

    -- 解除休眠期间对其他设备记录的静音保护
    unmutePreviouslyMuted()

    if showAlert and not alreadyDefault then
        hs.alert.show("音频输出: " .. name)
    end

    -- 找到设备（含重试成功）后再决定是否修复
    if name == MONITOR_NAME then
        scheduleDefaultRepair(REPAIR_DELAY)
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

        -- 只在状态变化、唤醒或启动时强制路由；普通设备事件不覆盖手动选择
        local shouldRoute = stateChanged or source == "wake" or source == "init"

        if state == "all_off" then
            muteAllAudio()
        else
            if shouldRoute then
                if state == "projector" then
                    applyDefault(AMP_NAME, showAlert or stateChanged)
                else
                    applyDefault(MONITOR_NAME, showAlert or stateChanged)
                end
            end

            -- 当前默认若是显示音频，就探测一次；健康时不改任何设置
            scheduleDefaultRepair(REPAIR_DELAY)
        end
    end)
end

-- 1. 屏幕监听：显示器打开/关闭、投影仪开关
local screenWatcher = hs.screen.watcher.new(function()
    scheduleSwitch(1.5, false, "screen")
end)

-- 2. 音频设备监听：只在显示音频端点变化时重新路由；默认输出变化时只做修复，不改路由
hs.audiodevice.watcher.setCallback(function(event)
    if event == "dev#" then
        local signature = displayAudioSignature()
        if signature ~= lastDisplayAudioSig then
            lastDisplayAudioSig = signature
            scheduleSwitch(1.5, false, "audiodevice")
        end
    elseif event == "dOut" then
        -- 用户手动选中 JMGO/27M3U 时，探测并修复它，但保持用户的选择
        scheduleDefaultRepair(0.5)
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

-- 手动触发：修复当前默认的显示音频；没有则检查显示器
function M.kickAudio()
    local name = currentDisplayAudioDefaultName() or MONITOR_NAME
    runRepair(name, function(success, code)
        if success then
            hs.alert.show("显示音频正常/已修复: " .. name, 1.5)
        elseif code == 1 then
            hs.alert.show("显示音频仍卡死: " .. name, 1.5)
        else
            hs.alert.show("无法检测显示音频: " .. name, 1.5)
        end
    end)
end

function M:start()
    stopped = false
    screensAsleep = false
    wakeGracePeriod = false
    mutedDeviceUIDs = {}
    lastDisplayState = currentDisplayState()
    lastDisplayAudioSig = displayAudioSignature()
    screenWatcher:start()
    hs.audiodevice.watcher.start()
    caffeinateWatcher:start()

    -- 启动后延迟 1 秒安全纠正一次
    scheduleSwitch(1.0, false, "init")
    return self
end

function M:stop()
    stopped = true
    if settleTimer then
        settleTimer:stop()
        settleTimer = nil
    end
    if retryTimer then
        retryTimer:stop()
        retryTimer = nil
    end
    if repairTimer then
        repairTimer:stop()
        repairTimer = nil
    end
    if repairTask then
        repairTask:terminate()
        repairTask = nil
    end
    repairInFlight = false
    pendingRepair = nil
    wakeGracePeriod = false
    mutedDeviceUIDs = {}
    screenWatcher:stop()
    hs.audiodevice.watcher.stop()
    caffeinateWatcher:stop()
end

return M
