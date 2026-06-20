local audioRouter = {}
local config = require("modules.config")

local caffeinateWatcher = nil
local screenWatcher = nil
local pendingTimer = nil

local function log(msg)
    -- print("audio_router: " .. tostring(msg))
end

local function shouldNotify(isError)
    local settings = config.audio_router or {}
    local mode = settings.notify_mode or "fail_only"

    if mode == "silent" then
        return false
    end

    if mode == "fail_only" then
        return isError
    end

    return true
end

local function notify(msg, isError)
    if shouldNotify(isError) then
        hs.alert.show(msg, 1.2)
    end
end

local function normalizedContains(text, keyword)
    if not text or not keyword or keyword == "" then
        return false
    end

    return string.find(string.lower(text), string.lower(keyword), 1, true) ~= nil
end

local function normalizedStartsWith(text, prefix)
    if not text or not prefix or prefix == "" then
        return false
    end

    return string.sub(string.lower(text), 1, string.len(prefix)) == string.lower(prefix)
end

local function findOutputDeviceByKeyword(keyword)
    local matches = {}
    local devices = hs.audiodevice.allOutputDevices() or {}

    for _, device in ipairs(devices) do
        local name = device:name() or ""
        if normalizedContains(name, keyword) then
            table.insert(matches, device)
        end
    end

    if #matches > 1 then
        log(string.format("关键词 \"%s\" 匹配到多个设备，使用第一个：%s", keyword, matches[1]:name() or "unknown"))
    end

    return matches[1], #matches
end

local function findOutputDeviceByPrefix(prefix)
    local matches = {}
    local devices = hs.audiodevice.allOutputDevices() or {}

    for _, device in ipairs(devices) do
        local name = device:name() or ""
        if normalizedStartsWith(name, prefix) then
            table.insert(matches, device)
        end
    end

    if #matches > 1 then
        log(string.format("前缀 \"%s\" 匹配到多个设备，使用第一个：%s", prefix, matches[1]:name() or "unknown"))
    end

    return matches[1], #matches
end

local function outputMatchesKeywords(device, keywords)
    if not device or not keywords then
        return false
    end

    if type(keywords) == "string" then
        return normalizedContains(device:name() or "", keywords)
    end

    for _, keyword in ipairs(keywords) do
        if normalizedContains(device:name() or "", keyword) then
            return true
        end
    end

    return false
end

local function evaluateAndRouteAudio(reason)
    local settings = config.audio_router or {}
    local monitorKeyword = settings.monitor_output_keyword or ""
    local headphoneKeyword = settings.headphone_output_keyword or ""
    local bluetoothPrefix = settings.bluetooth_headphone_prefix or ""
    local projectorKeyword = settings.projector_output_keyword or "JMGO"
    local preservedOutputKeywords = settings.preserve_current_output_keywords or {}

    if monitorKeyword == "" or headphoneKeyword == "" or projectorKeyword == "" then
        log("配置缺失：monitor_output_keyword / headphone_output_keyword / projector_output_keyword")
        notify("音频路由配置缺失", true)
        return
    end

    local currentDevice = hs.audiodevice.defaultOutputDevice()
    if outputMatchesKeywords(currentDevice, preservedOutputKeywords) then
        log(string.format("当前输出受保护（%s），跳过自动切换。触发来源：%s", currentDevice:name() or "unknown", tostring(reason or "unknown")))
        return
    end

    if bluetoothPrefix ~= "" then
        local bluetoothDevice = findOutputDeviceByPrefix(bluetoothPrefix)
        if bluetoothDevice then
            if currentDevice and currentDevice:uid() == bluetoothDevice:uid() then
                log(string.format("UGREEN 蓝牙耳机已是当前输出（%s），跳过。触发来源：%s", bluetoothDevice:name() or "unknown", tostring(reason or "unknown")))
                return
            end

            local ok = bluetoothDevice:setDefaultOutputDevice()
            if ok then
                local msg = string.format("音频切换到蓝牙耳机：%s", bluetoothDevice:name() or "unknown")
                log(msg)
                notify(msg, false)
            else
                local msg = string.format("切换蓝牙耳机失败：%s", bluetoothDevice:name() or bluetoothPrefix)
                log(msg)
                notify(msg, true)
            end

            return
        end
    end

    local projectorDevice = findOutputDeviceByKeyword(projectorKeyword)
    local projectorAvailable = projectorDevice ~= nil

    local targetKeyword = projectorAvailable and headphoneKeyword or monitorKeyword
    local targetDevice = findOutputDeviceByKeyword(targetKeyword)

    if not targetDevice then
        local stateText = projectorAvailable and "耳机" or "显示器"
        local msg = string.format("未找到%s输出设备：%s", stateText, targetKeyword)
        log(msg)
        notify(msg, true)
        return
    end

    if currentDevice and currentDevice:uid() == targetDevice:uid() then
        log(string.format("目标设备已是当前输出（%s），跳过。触发来源：%s", targetDevice:name() or "unknown", tostring(reason or "unknown")))
        return
    end

    local ok = targetDevice:setDefaultOutputDevice()
    if ok then
        local routeText = projectorAvailable and "耳机(JMGO已出现)" or "显示器(JMGO已关闭)"
        local msg = string.format("音频切换到%s：%s", routeText, targetDevice:name() or "unknown")
        log(msg)
        notify(msg, false)
    else
        local msg = string.format("切换默认输出失败：%s", targetDevice:name() or targetKeyword)
        log(msg)
        notify(msg, true)
    end
end

local function scheduleEvaluation(reason)
    local settings = config.audio_router or {}
    local debounceSeconds = tonumber(settings.debounce_seconds) or 1.0

    if debounceSeconds < 0 then
        debounceSeconds = 0
    end

    if pendingTimer then
        pendingTimer:stop()
        pendingTimer = nil
    end

    pendingTimer = hs.timer.doAfter(debounceSeconds, function()
        pendingTimer = nil
        evaluateAndRouteAudio(reason)
    end)
end

function audioRouter.init()
    if pendingTimer then
        pendingTimer:stop()
        pendingTimer = nil
    end

    if caffeinateWatcher then
        caffeinateWatcher:stop()
        caffeinateWatcher = nil
    end

    if screenWatcher then
        screenWatcher:stop()
        screenWatcher = nil
    end

    hs.audiodevice.watcher.stop()
    hs.audiodevice.watcher.setCallback(nil)

    caffeinateWatcher = hs.caffeinate.watcher.new(function(eventType)
        if eventType == hs.caffeinate.watcher.screensDidSleep
            or eventType == hs.caffeinate.watcher.screensDidWake then
            scheduleEvaluation("caffeinate")
        end
    end)
    caffeinateWatcher:start()

    screenWatcher = hs.screen.watcher.new(function()
        scheduleEvaluation("screen")
    end)
    screenWatcher:start()

    hs.audiodevice.watcher.setCallback(function()
        scheduleEvaluation("audiodevice")
    end)
    hs.audiodevice.watcher.start()

    scheduleEvaluation("init")
end

return audioRouter
