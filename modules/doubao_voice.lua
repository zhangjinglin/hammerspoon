local M = {}

-- 豆包语音开始/结束监控：
-- 常驻 swift 进程（bin/doubao_voice_watch）盯 CGWindowList 里"豆包输入法"浮窗的出现/消失，
-- VOICE ON  -> 系统静音（记住之前状态）
-- VOICE OFF -> 恢复静音状态 + 延迟切 ABC

local ENGLISH_SOURCE_ID = "com.apple.keylayout.ABC"
local SETTLE_DELAY = 0.3
local WATCH_BIN = os.getenv("HOME") .. "/.hammerspoon/bin/doubao_voice_watch"
-- 当前输出设备不支持软件静音时（如 HDMI 显示器），切到这个可控设备
local FALLBACK_OUTPUT = "Mac mini Speakers"

local task = nil
local taskBuf = ""
-- 语音状态（供 mouse_voice 做触发回执）
local voiceOn = false
local lastVoiceOnAt = 0
local prevMuted = false
local origDevice = nil
local switchedToFallback = false
local fallbackPrevMuted = false
local fallbackPrevVolume = nil

local function muteCurrent()
    local dev = hs.audiodevice.defaultOutputDevice()
    if not dev then
        return false
    end
    origDevice = dev
    prevMuted = dev:muted() or false
    dev:setMuted(true)
    if dev:muted() then
        -- print("[doubao-voice] muted on " .. tostring(dev:name()))
        return true
    end
    -- 当前设备不支持软件静音（如 HDMI 显示器），切到可控设备
    local fb = hs.audiodevice.findOutputByName(FALLBACK_OUTPUT)
    if fb then
        fallbackPrevMuted = fb:muted() or false
        fallbackPrevVolume = fb:volume()
        fb:setMuted(true)
        fb:setVolume(0)
        fb:setDefaultOutputDevice()
        switchedToFallback = true
        -- print("[doubao-voice] device unmuttable, switched to " .. FALLBACK_OUTPUT)
        return true
    end
    print("[doubao-voice] mute failed, no fallback device")
    return false
end

local function unmuteCurrent()
    if switchedToFallback then
        switchedToFallback = false
        if origDevice then
            origDevice:setDefaultOutputDevice()
            -- print("[doubao-voice] switched back to " .. tostring(origDevice:name()))
            origDevice = nil
        end
        local fb = hs.audiodevice.findOutputByName(FALLBACK_OUTPUT)
        if fb then
            if fallbackPrevVolume then
                fb:setVolume(fallbackPrevVolume)
            end
            fb:setMuted(fallbackPrevMuted)
        end
    else
        local dev = hs.audiodevice.defaultOutputDevice()
        if dev then
            dev:setMuted(prevMuted)
        end
        -- print("[doubao-voice] unmuted, restored=" .. tostring(prevMuted))
    end
end

local function onVoiceStart(info)
    -- print("[doubao-voice] VOICE ON " .. tostring(info or ""))
    voiceOn = true
    lastVoiceOnAt = hs.timer.secondsSinceEpoch()
    muteCurrent()
end

local function onVoiceEnd()
    -- print("[doubao-voice] VOICE OFF")
    voiceOn = false
    unmuteCurrent()
    hs.timer.doAfter(SETTLE_DELAY, function()
        local cur = hs.keycodes.currentSourceID()
        if cur ~= ENGLISH_SOURCE_ID then
            hs.keycodes.currentSourceID(ENGLISH_SOURCE_ID)
            -- print("[doubao-voice] switched to ABC, now=" .. tostring(hs.keycodes.currentSourceID()))
        -- else
        --     print("[doubao-voice] already ABC, skip")
        end
    end)
end

local function handleLine(line)
    if line:match("^VOICE ON") then
        onVoiceStart(line:sub(10))
    elseif line:match("^VOICE OFF") then
        onVoiceEnd()
    end
end

local function startTask()
    taskBuf = ""
    task = hs.task.new(WATCH_BIN, function(exitCode, stdOut, stdErr)
        print(string.format("[doubao-voice] watcher exited(%s), restart in 1s. stderr=%s",
            tostring(exitCode), tostring(stdErr)))
        task = nil
        hs.timer.doAfter(1, function()
            if task == nil then
                startTask()
            end
        end)
        return true
    end, function(t, stdOut, stdErr)
        if stdOut and #stdOut > 0 then
            taskBuf = taskBuf .. stdOut
            while true do
                local i = taskBuf:find("\n")
                if not i then
                    break
                end
                local line = taskBuf:sub(1, i - 1)
                taskBuf = taskBuf:sub(i + 1)
                handleLine(line)
            end
        end
        if stdErr and #stdErr > 0 then
            print("[doubao-voice] watcher stderr: " .. stdErr)
        end
        return true
    end)
    task:start()
    -- print("[doubao-voice] watcher started")
end

function M.start()
    -- print("[doubao-voice] start")
    if not task then
        startTask()
    end
end

function M.stop()
    if task then
        task:terminate()
        task = nil
    end
end

-- 以下查询接口供鼠标长按语音（modules/mouse_voice.lua）判断触发是否生效
function M.isVoiceOn()
    return voiceOn
end

function M.lastVoiceOnTimestamp()
    return lastVoiceOnAt
end

function M.isWatcherRunning()
    return task ~= nil
end

return M
