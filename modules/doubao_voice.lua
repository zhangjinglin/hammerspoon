local M = {}

-- 豆包语音开始/结束监控：
-- 常驻 swift 进程（bin/doubao_voice_watch）盯 CGWindowList 里"豆包输入法"浮窗的出现/消失，
-- VOICE ON  -> 系统静音（记住之前状态）
-- VOICE OFF -> 恢复静音状态 + 延迟切 ABC

local ENGLISH_SOURCE_ID = "com.apple.keylayout.ABC"
local SETTLE_DELAY = 0.3
local WATCH_BIN = os.getenv("HOME") .. "/.hammerspoon/bin/doubao_voice_watch"

local task = nil
local taskBuf = ""
local prevMuted = false

local function setMuted(m)
    local dev = hs.audiodevice.defaultOutputDevice()
    if dev then
        dev:setMuted(m)
    end
end

local function onVoiceStart(info)
    print("[doubao-voice] VOICE ON " .. tostring(info or ""))
    local dev = hs.audiodevice.defaultOutputDevice()
    prevMuted = dev and dev:muted() or false
    setMuted(true)
    print("[doubao-voice] muted, prevMuted=" .. tostring(prevMuted))
end

local function onVoiceEnd()
    print("[doubao-voice] VOICE OFF")
    setMuted(prevMuted)
    print("[doubao-voice] unmuted, restored=" .. tostring(prevMuted))
    hs.timer.doAfter(SETTLE_DELAY, function()
        local cur = hs.keycodes.currentSourceID()
        if cur ~= ENGLISH_SOURCE_ID then
            hs.keycodes.currentSourceID(ENGLISH_SOURCE_ID)
            print("[doubao-voice] switched to ABC, now=" .. tostring(hs.keycodes.currentSourceID()))
        else
            print("[doubao-voice] already ABC, skip")
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
    print("[doubao-voice] watcher started")
end

function M.start()
    print("[doubao-voice] start")
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

return M
