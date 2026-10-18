-- modules/mouse_gestures.lua
local mouseGestures = {}

local GESTURE_THRESHOLD = 50
local mouseStartPos = nil
local menuDismissed = false
local suppressCount = 0

-- 系统「键盘显示程序」（Keyboard Viewer）开关。
-- macOS 26 已经移除了 KeyboardViewer.app（open -b com.apple.KeyboardViewer 会失败），
-- 键盘显示程序现在是 TextInputMenuAgent 提供的一个窗口，只能通过输入法菜单里那个
-- 状态项（菜单栏上的 ABC / 拼音）中的 Show / Hide Keyboard Viewer 切换。
local function inputMenuBarItem()
    local app = hs.application.get("TextInputMenuAgent")
    if not app then return nil end
    local element = hs.axuielement.applicationElement(app)
    local extras = element and element:attributeValue("AXExtrasMenuBar")
    if not extras then return nil end
    return (extras:attributeValue("AXChildren") or {})[1]
end

local function keyboardViewerMenuItem(item)
    local menu = (item:attributeValue("AXChildren") or {})[1]
    if not menu then return nil end
    for _, mi in ipairs(menu:attributeValue("AXChildren") or {}) do
        local title = mi:attributeValue("AXTitle")
        if title and title:find("Keyboard Viewer") then return mi end
    end
    return nil
end

function mouseGestures.toggleKeyboardViewer()
    local item = inputMenuBarItem()
    local target = nil
    if item then
        -- AX 打开这个状态项的菜单大概要 1.5s（等菜单真正显示出来），之后菜单项才拿得到
        item:performAction("AXPress")
        hs.timer.usleep(150000)
        target = keyboardViewerMenuItem(item)
        if target then target:performAction("AXPress") end
    end
    if target then
        hs.alert.show("⌨️ Keyboard Viewer", 0.5)
    else
        hs.alert.show("⌨️ 没找到输入法菜单里的 Keyboard Viewer", 2)
    end
end

-- 关掉漏出来的右键菜单（没有菜单时发了也无害）
local function dismissMenu()
    hs.eventtap.event.newKeyEvent({}, "escape", true):post()
    hs.eventtap.event.newKeyEvent({}, "escape", false):post()
end

-- 普通右键点击：合成一对事件，把菜单正常弹出来
local function simulateRightClick()
    suppressCount = 2
    local pos = hs.mouse.absolutePosition()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseDown, pos):post()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseUp, pos):post()
end

function mouseGestures.init()
    mouseGestures.watcher = hs.eventtap.new({
        hs.eventtap.event.types.rightMouseDown,
        hs.eventtap.event.types.rightMouseDragged,
        hs.eventtap.event.types.rightMouseUp
    }, function(event)
        if suppressCount > 0 then
            suppressCount = suppressCount - 1
            return false
        end

        local eventType = event:getType()

        if eventType == hs.eventtap.event.types.rightMouseDown then
            -- 菜单在按下时就会弹出，必须在这里拦截
            mouseStartPos = event:location()
            menuDismissed = false
            return true

        elseif eventType == hs.eventtap.event.types.rightMouseDragged then
            -- 手势过程中不让菜单跟踪，全部吞掉；
            -- 一旦超过阈值就先 Escape 一次，把已漏出的菜单关掉
            if not mouseStartPos then return false end
            local p = event:location()
            if not menuDismissed and math.abs(p.y - mouseStartPos.y) > GESTURE_THRESHOLD then
                menuDismissed = true
                dismissMenu()
            end
            return true

        elseif eventType == hs.eventtap.event.types.rightMouseUp then
            if not mouseStartPos then return false end

            local mouseEndPos = event:location()
            local dy = mouseEndPos.y - mouseStartPos.y
            mouseStartPos = nil

            -- 只看纵向位移
            local absY = math.abs(dy)

            if absY > GESTURE_THRESHOLD then
                -- Dragged 里可能已经 Escape 过，这里兜底：确保菜单关了再发键
                if not menuDismissed then
                    dismissMenu()
                end
                menuDismissed = false
                if dy < 0 then
                    -- 向上：显示 / 隐藏键盘显示程序（Keyboard Viewer）
                    hs.timer.doAfter(0.05, mouseGestures.toggleKeyboardViewer)
                else
                    -- 向下：Return
                    hs.eventtap.event.newKeyEvent({}, "return", true):post()
                    hs.eventtap.event.newKeyEvent({}, "return", false):post()
                    hs.alert.show("↩ Return", 0.5)
                end
            else
                -- 普通点击，恢复右键菜单
                menuDismissed = false
                simulateRightClick()
            end
            return true
        end
    end):start()
end

return mouseGestures
