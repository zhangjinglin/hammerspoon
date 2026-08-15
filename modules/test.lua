local logger = require("modules.logger")
local test = {}

function test.init()
    logger.insert_log("Note", "modules.test loaded", 0)
end

-- 创建一个针对 Microsoft Edge 的窗口过滤器
local edgeFilter = hs.window.filter.new('Microsoft Edge')

-- 监听窗口焦点改变或窗口标题改变
edgeFilter:subscribe({hs.window.filter.windowFocused, hs.window.filter.windowTitleChanged}, function(win, appName, event)
    if event == hs.window.filter.windowTitleChanged then
        local title = win:title()
        logger.insert_log("Edge", title, 0)
        -- 在这里编写你的逻辑
    end
end)

local telegramFilter = hs.window.filter.new('Telegram')

-- 监听窗口焦点改变或窗口标题改变
telegramFilter:subscribe({hs.window.filter.windowFocused, hs.window.filter.windowTitleChanged}, function(win, appName, event)
    if event == hs.window.filter.windowTitleChanged then
        local title = win:title()
        logger.insert_log("Telegram", title, 0)
        -- 在这里编写你的逻辑
    end
end)



return test
