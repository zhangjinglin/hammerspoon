-- modules/keypad.lua
-- 菜单栏虚拟按键面板:点菜单栏图标弹出一个悬浮小面板,内含 Backspace / Return / Space 三个按键,
-- 鼠标点击即向"打开面板时最前面的应用"合成对应按键(需要 Hammerspoon 辅助功能权限)。

local keypad = {}

-- 面板尺寸(点)
local PANEL_W, PANEL_H = 210, 96
-- 菜单栏高度兜底值(实际高度在 init 里按屏幕动态取)
local MENUBAR_H_FALLBACK = 26
-- JS 消息通道名:HTML 里用 window.webkit.messageHandlers.<name>.postMessage(...) 发消息
local MESSAGE_NAME = "keypad"

-- 三个按键:key 是 Hammerspoon 键名,glyph 是显示的大图标,label 是下面的小字
local KEYS = {
    { key = "delete", glyph = "⌫", label = "Backspace" },
    { key = "return", glyph = "↩", label = "Return" },
    { key = "space",  glyph = "␣", label = "Space" },
}

-- 生成面板的 HTML
local function buildHtml()
    local cells = {}
    for _, k in ipairs(KEYS) do
        cells[#cells + 1] = string.format(
            '<button data-key="%s"><b>%s</b><span>%s</span></button>',
            k.key, k.glyph, k.label
        )
    end

    return table.concat({
        '<!doctype html><html><head><meta charset="utf-8"><style>',
        'html,body{margin:0;height:100%;}',
        'body{box-sizing:border-box;padding:8px;display:flex;gap:8px;align-items:stretch;',
        'background:rgba(28,28,32,0.96);color:#fff;',
        'font:13px -apple-system,"Helvetica Neue",sans-serif;-webkit-user-select:none;}',
        'button{flex:1;border:0;border-radius:10px;background:#3a3a40;color:#fff;',
        'display:flex;flex-direction:column;align-items:center;justify-content:center;',
        'gap:3px;cursor:pointer;padding:0;}',
        'button b{font-size:24px;font-weight:500;line-height:1;}',
        'button span{font-size:11px;opacity:.6;}',
        'button:active{background:#0a84ff;}',
        '</style></head><body>',
        table.concat(cells),
        '<script>',
        'document.querySelectorAll("button").forEach(function(b){',
        '  b.addEventListener("click", function(){',
        '    window.webkit.messageHandlers.' .. MESSAGE_NAME ..
        '.postMessage({key: b.dataset.key});',
        '  });',
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

function keypad.show()
    -- 目标 = 最近一次激活的非 Hammerspoon 应用;兜底用当前最前面的应用
    keypad.target = keypad.lastApp or hs.application.frontmostApplication()
    keypad.webview:show()
    keypad.visible = true
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
        local key = type(body) == "table" and body.key or nil
        if key then sendKey(keypad.target, key) end
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

    -- 面板打开时,点面板以外的地方自动收起(菜单栏区域除外,交给图标自己 toggle)
    keypad.clickWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(e)
        if not keypad.visible then return false end
        local p = e:location()
        if p.y <= screen.y + menubarH then return false end
        local f = keypad.webview:frame()
        local inside = p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h
        if not inside then keypad.hide() end
        return false
    end):start()
end

return keypad
