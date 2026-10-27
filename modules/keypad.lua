-- modules/keypad.lua
-- 菜单栏虚拟按键面板:点菜单栏图标展开/收起,面板常驻屏幕,含 豆包语音 / Backspace / Return 按键。
-- 按住顶部拖动条可拖动面板。Backspace / Return 点击即向当前应用合成按键;
-- 豆包语音键点一下开始、再点一下结束(免按模式:各点按一次 voice 键)。
-- 豆包走 HID 层(bin/hidtap),会话层合成豆包不认。(需要 Hammerspoon 辅助功能权限。)

local keypad = {}

local config = require("modules.config")

-- 面板尺寸(点):扁条状,只留图标不要文字
local PANEL_W, PANEL_H = 210, 56
-- 顶部拖动条高度(点):按住这条区域可拖动面板
local DRAG_HANDLE_H = 12
-- 菜单栏高度兜底值(实际高度在 init 里按屏幕动态取)
local MENUBAR_H_FALLBACK = 26
-- JS 消息通道名:HTML 里用 window.webkit.messageHandlers.<name>.postMessage(...) 发消息
local MESSAGE_NAME = "keypad"

-- HID 层合成(会话层合成豆包不认,项目已有 hidtap 走 CGEventPost kCGHIDEventTap)
local HIDTAP_BIN = os.getenv("HOME") .. "/.hammerspoon/bin/hidtap"
-- 豆包语音键:与 config.mouseVoice.key 保持一致(默认右 Option)
local VOICE_KEY_NAME = (config.mouseVoice and config.mouseVoice.key) or "rightalt"
local VOICE_KEYCODE = (type(VOICE_KEY_NAME) == "number" and VOICE_KEY_NAME)
    or hs.keycodes.map[VOICE_KEY_NAME] or 61

-- 按键:key 是 Hammerspoon 键名(toggle=true 表示"点击切换",每次点按一次);
-- glyph 是图标;label 只用作鼠标悬停提示,不再渲染成按钮里的文字(面板更扁)
local KEYS = {
    { key = "doubao", glyph = "🎤", label = "豆包", toggle = true },
    { key = "delete", glyph = "⌫", label = "Backspace" },
    { key = "return", glyph = "↩", label = "Return" },
}

-- 生成面板的 HTML
local function buildHtml()
    local cells = {}
    for _, k in ipairs(KEYS) do
        local attr = k.toggle and ('data-toggle="' .. k.key .. '"') or ('data-key="' .. k.key .. '"')
        cells[#cells + 1] = string.format(
            '<button %s title="%s"><b>%s</b></button>',
            attr, k.label, k.glyph
        )
    end

    return table.concat({
        '<!doctype html><html><head><meta charset="utf-8"><style>',
        'html,body{margin:0;height:100%;}',
        'body{box-sizing:border-box;display:flex;flex-direction:column;',
        'background:rgba(28,28,32,0.96);color:#fff;',
        'font:13px -apple-system,"Helvetica Neue",sans-serif;-webkit-user-select:none;}',
        '.bar{flex:0 0 ' .. DRAG_HANDLE_H .. 'px;display:flex;align-items:center;justify-content:center;',
        'cursor:move;color:rgba(255,255,255,.4);font-size:9px;letter-spacing:3px;line-height:1;}',
        '.keys{flex:1;display:flex;gap:8px;padding:0 8px 8px;align-items:stretch;}',
        'button{flex:1;border:0;border-radius:8px;background:#3a3a40;color:#fff;',
        'display:flex;align-items:center;justify-content:center;',
        'cursor:pointer;padding:0;}',
        'button b{font-size:20px;font-weight:500;line-height:1;}',
        'button:active{background:#0a84ff;}',
        '</style></head><body>',
        '<div class="bar">⋯⋯</div>',
        '<div class="keys">',
        table.concat(cells),
        '</div>',
        '<script>',
        'function send(o){try{window.webkit.messageHandlers.' .. MESSAGE_NAME .. '.postMessage(o);}catch(e){}}',
        -- 普通键:点击即触发
        'document.querySelectorAll("button[data-key]").forEach(function(b){',
        '  b.addEventListener("click", function(){ send({key:b.dataset.key}); });',
        '});',
        -- 切换键(豆包语音):点一下开、再点一下关
        'document.querySelectorAll("button[data-toggle]").forEach(function(b){',
        '  b.addEventListener("click", function(){ send({toggle:b.dataset.toggle}); });',
        '});',
        '</script></body></html>',
    })
end

-- 合成一次按键:优先只发给 target 应用(避免面板抢焦点后发错对象)
local function sendKey(target, key)
    local down = hs.eventtap.event.newKeyEvent({}, key, true)
    local up = hs.eventtap.event.newKeyEvent({}, key, false)
    if target then
        down:post(target)
        up:post(target)
    else
        down:post()
        up:post()
    end
end

-- 调 bin/hidtap 点按一次某个键码
local function hidtap(code)
    hs.task.new(HIDTAP_BIN, function() end, function() end, { tostring(code) }):start()
end

-- 豆包语音(免按模式):点一下开始,再点一下结束 —— 每次点按一次语音键
function keypad.doubaoToggle()
    hidtap(VOICE_KEYCODE)
end

-- 记录当前"目标应用/窗口"(用户正在用的那个),供按键投递与回焦使用。
-- 若此刻前台已经是 Hammerspoon(面板自己),则不覆盖,保留上一次的目标。
function keypad.captureTarget()
    local app = hs.application.frontmostApplication()
    if app and app:bundleID() ~= hs.processInfo.bundleID then
        keypad.target = app
        keypad.targetWindow = hs.window.focusedWindow()
    end
end

-- 点是否落在面板里
function keypad.isPointInside(point)
    if not keypad.visible or not keypad.webview then return false end
    local f = keypad.webview:frame()
    return point.x >= f.x and point.x <= f.x + f.w
        and point.y >= f.y and point.y <= f.y + f.h
end

-- 点是否落在顶部拖动条上
function keypad.isOnHandle(point)
    if not keypad.visible or not keypad.webview then return false end
    local f = keypad.webview:frame()
    return point.x >= f.x and point.x <= f.x + f.w
        and point.y >= f.y and point.y <= f.y + DRAG_HANDLE_H
end

function keypad.show()
    keypad.captureTarget()
    keypad.target = keypad.target or keypad.lastApp
    keypad.webview:show()
    keypad.visible = true
end

-- 点面板会激活 Hammerspoon、让目标应用失焦。每个按键动作后把焦点还给原窗口/原应用,
-- 否则豆包语音的文字不知道往哪儿上屏。
function keypad.refocus()
    local w = keypad.targetWindow
    if not (w and pcall(function() w:focus() end)) then
        if keypad.target then pcall(function() keypad.target:activate() end) end
    end
end

function keypad.hide()
    keypad.webview:hide()
    keypad.visible = false
end

function keypad.toggle()
    if keypad.visible then keypad.hide() else keypad.show() end
end

function keypad.init()
    if keypad.menu then return end

    -- 记录最近一次被激活的非 Hammerspoon 应用,作为按键的投递目标
    keypad.appWatcher = hs.application.watcher.new(function(_, event, app)
        if event == hs.application.watcher.activated and app and app:bundleID() ~= hs.processInfo.bundleID then
            keypad.lastApp = app
        end
    end):start()

    local ucc = hs.webview.usercontent.new(MESSAGE_NAME)
    ucc:setCallback(function(message)
        local body = message and message.body
        if type(body) ~= "table" then return end
        if body.toggle then
            keypad.doubaoToggle()
            keypad.refocus()
        elseif body.key then
            sendKey(keypad.target, body.key)
            keypad.refocus()
        end
    end)

    local screen = hs.screen.mainScreen():fullFrame()
    -- 菜单栏高度 = 可见区域顶部 - 屏幕顶部(刘海屏更高,写死会点不到图标)
    local menubarH = hs.screen.mainScreen():frame().y - screen.y
    if menubarH <= 0 then menubarH = MENUBAR_H_FALLBACK end

    local frame = {
        x = screen.x + screen.w - PANEL_W - 10,
        y = screen.y + menubarH + 6,
        w = PANEL_W,
        h = PANEL_H,
    }

    local wv = hs.webview.new(frame, {}, ucc)
    wv:windowStyle({ "borderless" })
    wv:level(hs.drawing.windowLevels.floating)
    wv:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    -- 不接受键盘输入,窗口就不能成为 key window,点面板不会抢走目标应用的焦点
    wv:allowTextEntry(false)
    wv:html(buildHtml())
    keypad.webview = wv
    keypad.visible = false

    local menu = hs.menubar.new()
    menu:setTitle("⌨")
    menu:setTooltip("虚拟按键面板")
    menu:setClickCallback(function() keypad.toggle() end)
    keypad.menu = menu

    -- 面板常驻:
    --  * 按下时(此刻前台仍是用户的应用)记录目标应用/窗口,供按键投递与回焦;
    --  * 按住顶部拖动条即可拖动面板(不挡着底下的内容)。
    keypad.clickWatcher = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.leftMouseDragged,
        hs.eventtap.event.types.leftMouseUp,
    }, function(e)
        local t = e:getType()
        if t == hs.eventtap.event.types.leftMouseDown then
            local p = e:location()
            if keypad.isPointInside(p) then
                keypad.captureTarget()
                if keypad.isOnHandle(p) then
                    local f = keypad.webview:frame()
                    keypad.drag = { mouse = { x = p.x, y = p.y }, origin = { x = f.x, y = f.y } }
                end
            end
        elseif t == hs.eventtap.event.types.leftMouseDragged then
            if keypad.drag then
                local p = e:location()
                keypad.webview:topLeft({
                    x = keypad.drag.origin.x + (p.x - keypad.drag.mouse.x),
                    y = keypad.drag.origin.y + (p.y - keypad.drag.mouse.y),
                })
            end
        else -- leftMouseUp
            keypad.drag = nil
        end
        return false
    end):start()
end

return keypad
