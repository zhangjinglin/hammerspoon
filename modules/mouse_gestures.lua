-- modules/mouse_gestures.lua
local mouseGestures = {}

local GESTURE_THRESHOLD = 50
local mouseStartPos = nil

function mouseGestures.init()
    mouseGestures.watcher = hs.eventtap.new({
        hs.eventtap.event.types.rightMouseDown,
        hs.eventtap.event.types.rightMouseUp
    }, function(event)
        local eventType = event:getType()

        if eventType == hs.eventtap.event.types.rightMouseDown then
            mouseStartPos = hs.mouse.absolutePosition()
            return false

        elseif eventType == hs.eventtap.event.types.rightMouseUp then
            if not mouseStartPos then return false end

            local mouseEndPos = hs.mouse.absolutePosition()
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
                return true -- 拦截右键菜单
            end
            return false
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
