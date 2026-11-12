local M = {}

-- 豆包语音监控：
-- 常驻 swift 进程（bin/doubao_voice_watch）盯 CGWindowList 里"豆包输入法"浮窗的出现/消失，
-- VOICE ON  -> 记录语音状态
-- VOICE OFF -> 延迟切 ABC 英文输入法
-- （完全取消静音操作，不触碰系统音频设备，彻底消除音频打断和死锁隐患）

local ENGLISH_SOURCE_ID = "com.apple.keylayout.ABC"
local SETTLE_DELAY = 0.3
local WATCH_BIN = os.getenv("HOME") .. "/.hammerspoon/bin/doubao_voice_watch"

local task = nil
local taskBuf = ""
local voiceOn = false
local lastVoiceOnAt = 0

-- 清理旧版本可能残留的设置
hs.settings.set("doubaoFallbackState", nil)

local function onVoiceStart(info)
    if voiceOn then
        return
    end
    voiceOn = true
    lastVoiceOnAt = hs.timer.secondsSinceEpoch()
end

local function onVoiceEnd()
    voiceOn = false
    hs.timer.doAfter(SETTLE_DELAY, function()
        local cur = hs.keycodes.currentSourceID()
        if cur ~= ENGLISH_SOURCE_ID then
            hs.keycodes.currentSourceID(ENGLISH_SOURCE_ID)
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
end

function M.start()
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
