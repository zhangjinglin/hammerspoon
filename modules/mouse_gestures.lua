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
            local dx = mouseEndPos.x - mouseStartPos.x
            local dy = mouseEndPos.y - mouseStartPos.y
            mouseStartPos = nil

            -- 获取位移的绝对值，用来判断是横向还是纵向更明显
            local absX = math.abs(dx)
            local absY = math.abs(dy)

            -- 只有当最大位移超过阈值时才触发
            if math.max(absX, absY) > GESTURE_THRESHOLD then
                
                -- 情况 A: 纵向滑动更明显 (上下)
                if absY > absX then
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
                
                -- 情况 B: 横向滑动更明显 (左右)
                else
                    if dx < 0 then
                        -- 向左：复制 (Command + C)
                        hs.eventtap.event.newKeyEvent({"cmd"}, "c", true):post()
                        hs.eventtap.event.newKeyEvent({"cmd"}, "c", false):post()
                        hs.alert.show("⌘ Copy", 0.5)
                    else
                        -- 向右：粘贴 (Command + V)
                        hs.eventtap.event.newKeyEvent({"cmd"}, "v", true):post()
                        hs.eventtap.event.newKeyEvent({"cmd"}, "v", false):post()
                        hs.alert.show("⌘ Paste", 0.5)
                    end
                end
                
                return true -- 拦截右键菜单
            end
            return false
        end
    end):start()
end

return mouseGestures