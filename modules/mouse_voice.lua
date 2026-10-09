-- modules/mouse_voice.lua
-- 鼠标左键长按 → HID 点按一次右 Option 启动 → 松开左键再点按一次结束
--
-- 原理：豆包"免按模式"设为右 Option（按一次开始、按任意键结束）。
-- 实测会话层合成（hs.eventtap / System Events）豆包直接无视，必须走 HID 层，
-- 所以经 bin/hidtap（CGEventPost kCGHIDEventTap）发修饰键点按，已验证可开关语音窗。
--   按下左键 → 0.5s 内没移动且光标下是可编辑文本 → HID 点按一次启动语音
--   松开左键 → 再 HID 点按一次（免按模式下任意键都可结束）→ 豆包结束识别、文字上屏
-- 注意：本模块不吞鼠标事件（回调一律返回 false），普通点击/双击/拖拽选字不受影响。

local M = {}

local config = require("modules.config").mouseVoice or {}
local doubaoVoice = require("modules.doubao_voice")

local ENABLED          = config.enabled ~= false
local KEY_NAME         = config.key or "rightalt"
local EXTRA_FLAGS      = config.flags
local HOLD_MS          = config.holdMs or 1200
local MOVE_CANCEL_PX   = config.moveCancelPx or 25
local MAX_HOLD_MS      = config.maxHoldMs or 120000
local EXCLUDED_APPS    = config.excludedApps or { "com.tencent.xinWeChat" }
local REQUIRE_EDITABLE = config.requireEditableElement ~= false
local FEEDBACK         = config.feedback ~= false
local DEBUG            = config.debug ~= false

-- 判定"光标下是可编辑文本"的 role 白名单
local EDITABLE_ROLES = {
    AXTextField = true,
    AXTextArea = true,
    AXSearchField = true,
    AXComboBox = true,
    AXSecureTextField = true,
}

-- 可选的语音快捷键（默认右 Option；与豆包设置里的快捷键保持一致）
local KEY_TABLE
do
    local rf = hs.eventtap.event.rawFlagMasks

    -- nil 与 0 都安全地忽略，避免某个原始 flag 在这个版本里不存在时整份配置加载失败
    local function mask(...)
        local v = 0
        for _, f in ipairs({ ... }) do
            if type(f) == "number" then v = v | f end
        end
        return v
    end

    local function entry(keyname, flags)
        local code = hs.keycodes.map[keyname]
        if not code then return nil end
        return { code = code, flags = flags or 0 }
    end

    local fnFlags = mask(rf.secondaryFn)
    local altFlags = mask(rf.alternate)
    local rightAltFlags = mask(rf.alternate, rf.deviceRightAlternate)
    local cmdFlags = mask(rf.command)
    local rightCmdFlags = mask(rf.command, rf.deviceRightCommand)
    local ctrlFlags = mask(rf.control)
    local rightCtrlFlags = mask(rf.control, rf.deviceRightControl)
    local shiftFlags = mask(rf.shift)
    local rightShiftFlags = mask(rf.shift, rf.deviceRightShift)

    KEY_TABLE = {
        rightalt = entry("rightalt", rightAltFlags),
        rightoption = entry("rightalt", rightAltFlags),
        alt = entry("alt", altFlags),
        leftalt = entry("alt", altFlags),
        rightcmd = entry("rightcmd", rightCmdFlags),
        rightcommand = entry("rightcmd", rightCmdFlags),
        cmd = entry("cmd", cmdFlags),
        rightctrl = entry("rightctrl", rightCtrlFlags),
        rightcontrol = entry("rightctrl", rightCtrlFlags),
        ctrl = entry("ctrl", ctrlFlags),
        rightshift = entry("rightshift", rightShiftFlags),
        shift = entry("shift", shiftFlags),
        fn = entry("fn", fnFlags),
    }
end

local VOICE_KEY = KEY_TABLE[KEY_NAME]
if not VOICE_KEY and type(KEY_NAME) == "number" then
    VOICE_KEY = { code = KEY_NAME, flags = EXTRA_FLAGS or 0 }
end

-- 运行状态
local state = "idle" -- idle | armed | active
local pressPoint = nil
local armTimer = nil
local guardTimer = nil
local keyDown = false
local tap = nil

local function log(fmt, ...)
    if DEBUG then
        print("[mouse-voice] " .. string.format(fmt, ...))
    end
end

local function alert(msg, seconds)
    if FEEDBACK then
        hs.alert.show(msg, seconds or 1)
    end
end

local function stopTimer(t)
    if t then
        t:stop()
    end
    return nil
end

-- 合成 flagsChanged 事件
local function postFlags(flags)
    local e = hs.eventtap.event.newEvent()
    e:setType(hs.eventtap.event.types.flagsChanged)
    e:setKeyCode(VOICE_KEY.code)
    e:rawFlags(flags)
    e:post()
end

-- 会话层合成豆包不认，必须走 HID 层（bin/hidtap），已实测可开关语音窗
local HID_BIN = os.getenv("HOME") .. "/.hammerspoon/bin/hidtap"

-- 豆包"免按模式"：点按一次启动（任意键结束），这里每次调都发一次 HID 点按
local function tapVoiceKey(reason)
    hs.task.new(HID_BIN, function() end, function() end, { tostring(VOICE_KEY.code) }):start()
    log("HID 点按快捷键 %s (code=%s) 一次 (%s)", tostring(KEY_NAME), tostring(VOICE_KEY.code),
        tostring(reason or ""))
end

function M.press()
    if keyDown then return end
    postFlags(VOICE_KEY.flags)
    keyDown = true
    log("按住快捷键 %s (keycode=%s flags=%s)", tostring(KEY_NAME), tostring(VOICE_KEY.code),
        tostring(VOICE_KEY.flags))
end

function M.release(reason)
    if not keyDown then return end
    postFlags(0)
    keyDown = false
    log("释放快捷键 (%s)", tostring(reason or ""))
end

local function axAttr(el, name)
    if not el then return nil end
    local ok, v = pcall(function() return el:attributeValue(name) end)
    if ok then return v end
    return nil
end

-- 光标下（或向上 4 层）是否是可编辑文本元素
local function editableElementUnder(point)
    local el = hs.axuielement.systemElementAtPosition(point)
    for _ = 1, 4 do
        if not el then return nil end
        local role = axAttr(el, "AXRole")
        if role and EDITABLE_ROLES[role] then
            return el
        end
        local parent = axAttr(el, "AXParent")
        if not parent then return nil end
        el = parent
    end
    return nil
end

-- 当前焦点元素是否可编辑文本
local function focusedEditable()
    local sys = hs.axuielement.systemWideElement()
    local el = axAttr(sys, "AXFocusedUIElement")
    for _ = 1, 4 do
        if not el then return nil end
        local role = axAttr(el, "AXRole")
        if role and EDITABLE_ROLES[role] then
            return el
        end
        el = axAttr(el, "AXParent")
    end
    return nil
end

local function inEditableText(point)
    local ok, result = pcall(function()
        return (editableElementUnder(point) ~= nil) or (focusedEditable() ~= nil)
    end)
    if not ok then
        log("AX 查询异常: %s", tostring(result))
        return false
    end
    return result
end

local function frontApp()
    return hs.application.frontmostApplication()
        or (hs.window.focusedWindow() and hs.window.focusedWindow():application())
end

local function isExcludedApp()
    local app = frontApp()
    if not app then return false end
    local id, name = app:bundleID(), app:name()
    for _, ex in ipairs(EXCLUDED_APPS) do
        if ex == id or ex == name then
            log("应用在排除列表: %s", tostring(name))
            return true
        end
    end
    return false
end

local function movedTooFar(point)
    if not pressPoint then return false end
    return math.abs(point.x - pressPoint.x) > MOVE_CANCEL_PX
        or math.abs(point.y - pressPoint.y) > MOVE_CANCEL_PX
end

local function reset()
    armTimer = stopTimer(armTimer)
    guardTimer = stopTimer(guardTimer)
    state = "idle"
    pressPoint = nil
end

-- 长按达到阈值：真正开始语音
local function onHoldReached()
    armTimer = nil
    if state ~= "armed" then return end

    local point = hs.mouse.absolutePosition()
    if movedTooFar(point) then
        log("长按期间移动超过 %dpx，取消", MOVE_CANCEL_PX)
        reset()
        return
    end
    if isExcludedApp() then
        reset()
        return
    end
    if REQUIRE_EDITABLE and not inEditableText(point) then
        log("光标下不是可编辑文本，忽略")
        reset()
        return
    end

    state = "active"
    keyDown = true
    tapVoiceKey("start")
    alert("🎤 说话中，松开结束", 0.8)

    -- 兜底：鼠标抬起事件丢失时不至于让豆包一直停在语音状态
    guardTimer = hs.timer.doAfter(MAX_HOLD_MS / 1000, function()
        log("超过最长时间，强制结束语音")
        M.finish("timeout")
    end)
end

function M.finish(reason)
    local wasActive = (state == "active")
    reset()
    if wasActive then
        keyDown = false
        tapVoiceKey(reason or "mouseup")
    end
end

local function onMouseDown(event)
    if state ~= "idle" then return false end
    pressPoint = event:location()
    state = "armed"
    armTimer = hs.timer.doAfter(HOLD_MS / 1000, onHoldReached)
    return false
end

local function onMouseUp()
    if state == "armed" then
        reset()
    elseif state == "active" then
        M.finish("mouseup")
    end
    return false
end

local function onMouseDragged(event)
    if state == "idle" then return false end
    if movedTooFar(event:location()) then
        if state == "armed" then
            log("拖拽，取消长按计时")
            reset()
        else
            log("拖拽中，结束语音")
            M.finish("drag")
        end
    end
    return false
end

function M.init()
    if not ENABLED then
        print("[mouse-voice] 已在 config.mouseVoice.enabled 中关闭")
        return
    end
    if not VOICE_KEY then
        print("[mouse-voice] 未知的 config.mouseVoice.key: " .. tostring(KEY_NAME))
        return
    end

    -- 上次异常退出可能留下按住状态
    postFlags(0)

    tap = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.leftMouseUp,
        hs.eventtap.event.types.leftMouseDragged,
    }, function(event)
        local t = event:getType()
        if t == hs.eventtap.event.types.leftMouseDown then
            return onMouseDown(event)
        elseif t == hs.eventtap.event.types.leftMouseUp then
            return onMouseUp()
        else
            return onMouseDragged(event)
        end
    end)
    tap:start()

    -- Hammerspoon 退出/重载前如果语音还开着，补一次点按把它关掉
    local prevShutdown = hs.shutdownCallback
    hs.shutdownCallback = function()
        if type(prevShutdown) == "function" then
            pcall(prevShutdown)
        end
        if state == "active" then
            M.finish("shutdown")
        else
            postFlags(0)
        end
    end

    -- print(string.format("[mouse-voice] 已启动：左键长按 %dms → 点按 %s 启动/结束，位移>%dpx 取消",
    --     HOLD_MS, tostring(KEY_NAME), MOVE_CANCEL_PX))
end

function M.stop()
    M.finish("stop")
    if tap then
        tap:stop()
        tap = nil
    end
end

-- ---- 手动调试接口（可在 Hammerspoon 控制台里调用）----

-- 不碰鼠标，直接点按两次语音键（中间隔 N 秒），用来验证"合成按键能否唤起豆包"
function M.test(seconds)
    seconds = seconds or 2
    print(string.format("[mouse-voice] 手动测试：点按 %s 启动，%s 秒后点按结束",
        tostring(KEY_NAME), tostring(seconds)))
    tapVoiceKey("test-start")
    hs.timer.doAfter(seconds, function()
        tapVoiceKey("test-end")
        print("[mouse-voice] 手动测试结束")
    end)
end

-- 打印当前光标下的判定结果，用来确认文本框识别是否正常
function M.inspect()
    local point = hs.mouse.absolutePosition()
    local el = editableElementUnder(point)
    local app = frontApp()
    local focused = focusedEditable()
    local msg = string.format("位置=(%d,%d) 应用=%s 光标下角色=%s 焦点可编辑=%s 判定=%s",
        math.floor(point.x), math.floor(point.y),
        tostring(app and app:name()),
        tostring(axAttr(el, "AXRole")),
        tostring(focused ~= nil),
        (el or focused) and "会触发" or "不会触发")
    print("[mouse-voice] " .. msg)
    return msg
end

function M.status()
    local msg = string.format("state=%s keyDown=%s watcher=%s voiceOn=%s",
        state, tostring(keyDown), tostring(doubaoVoice.isWatcherRunning()),
        tostring(doubaoVoice.isVoiceOn()))
    print("[mouse-voice] " .. msg)
    return msg
end

return M
