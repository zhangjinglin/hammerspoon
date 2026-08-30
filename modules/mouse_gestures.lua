-- modules/mouse_gestures.lua
local mouseGestures = {}

local GESTURE_THRESHOLD = 50
local mouseStartPos = nil
local suppressNext = false

-- 普通右键点击：合成一对事件，把菜单正常弹出来
local function simulateRightClick()
    suppressNext = true
    local pos = hs.mouse.absolutePosition()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseDown, pos):post()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.rightMouseUp, pos):post()
end

function mouseGestures.init()
    mouseGestures.watcher = hs.eventtap.new({
        hs.eventtap.event.types.rightMouseDown,
        hs.eventtap.event.types.rightMouseUp
    }, function(event)
        if suppressNext then
            suppressNext = false
            return false
        end

        local eventType = event:getType()

        if eventType == hs.eventtap.event.types.rightMouseDown then
            -- 菜单在按下时就会弹出，必须在这里拦截
            mouseStartPos = event:location()
            return true

        elseif eventType == hs.eventtap.event.types.rightMouseUp then
            if not mouseStartPos then return false end

            local mouseEndPos = event:location()
            local dy = mouseEndPos.y - mouseStartPos.y
            mouseStartPos = nil

            -- 只看纵向位移
            local absY = math.abs(dy)

            if absY > GESTURE_THRESHOLD then
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
                simulateRightClick()
            end
            return true
        end
    end):start()
end

function mouseGestures.destroy()
    if mouseGestures.watcher then
        mouseGestures.watcher:stop()
        mouseGestures.watcher = nil
    end
end

return mouseGestures
