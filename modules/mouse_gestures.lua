-- modules/mouse_gestures.lua
local mouseGestures = {}

local GESTURE_THRESHOLD = 50
local mouseStartPos = nil
local menuDismissed = false
local suppressCount = 0

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
                    -- 向上：Backspace
                    hs.eventtap.event.newKeyEvent({}, "delete", true):post()
                    hs.eventtap.event.newKeyEvent({}, "delete", false):post()
                    hs.alert.show("⌫ Backspace", 0.5)
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
