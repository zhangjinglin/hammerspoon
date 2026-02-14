local winLogger = {}
local config = require("modules.config")
local logger = require("modules.logger")

-- [状态追踪变量]
local currentApp = ""           -- 当前应用名称
local currentTitle = ""         -- 当前标题
local titleStartTime = 0        -- 当前标题的开始时间

-- [应用类型判断]
local function getAppType(appName)
    if appName == "Telegram" then
        return "Telegram"
    elseif appName == "Microsoft Edge" then
        return "Edge"
    else
        return "Other"
    end
end
-- [标题清理：移除Telegram等应用的未读计数]
local function normalizeTitle(appName, title)
    if not title then return "" end
    if appName == "Telegram" then
        -- 移除特殊的 Unicode 字符
        local clean = title:gsub("[\226\128\142\226\129\168\226\129\169]", "")
        -- 替换管道符
        clean = clean:gsub("|", " ")
        -- 移除开头的计数："(33) " -> ""
        clean = clean:gsub("^%s*%(%d+%)%s*", "")
        -- 移除结尾的计数（如果有）：" – (721)" -> ""
        clean = clean:gsub("%s*[%-–]%s*%(%d+%)%s*$", "")
        return clean
    end
    return title
end


-- [格式化时长]
local function formatDuration(totalSeconds)
    local s = totalSeconds or 0
    local days = math.floor(s / 86400)
    local hrs = math.floor((s % 86400) / 3600)
    local mins = math.floor((s % 3600) / 60)
    local secs = s % 60

    local res = ""
    if days > 0 then res = res .. days .. "天" end
    if hrs > 0 or days > 0 then res = res .. string.format("%d小时", hrs) end
    if mins > 0 or hrs > 0 or days > 0 then res = res .. string.format("%02d分钟", mins) end
    res = res .. string.format("%02d秒", secs)
    
    return res
end

-- [检查当前时间是否在禁止日志的时间段内 (23:00 - 7:00 AM)]
local function isLoggingDisabled()
    local hour = tonumber(os.date("%H"))
    return hour >= 23 or hour < 7
end

-- [记录前一个标题的时长，然后切换到新标题]
local function recordPreviousTitleAndSwitch(appName, newTitle)
    local now = hs.timer.absoluteTime()
    local duration = 0
    -- local DURATION_THRESHOLD = 60  -- 只记录超过60秒的活动
    
    -- 动态阈值：Telegram/Edge 只要变化就记录(阈值=0)
    -- 其他应用需保持 30 秒以上
    local DURATION_THRESHOLD = 30
    if appName == "Telegram" or appName == "Microsoft Edge" then
        DURATION_THRESHOLD = 5
    end
    
    -- 如果有前一个标题，计算其持续时间并记录
    if currentTitle ~= "" and titleStartTime > 0 then
        duration = math.floor((now - titleStartTime) / 1e9)
        
        -- 只有当持续时间超过阈值时才记录
        if duration >= DURATION_THRESHOLD then
            local appType = getAppType(appName)
            
            -- 如果是Telegram或Edge，使用标题；如果是Other，使用应用名
            local logContent = (appType == "Other") and appName .. " - " .. currentTitle or currentTitle
            logContent = logContent:gsub("|", " ")
            
            print(string.format("记录 %s: \"%s\" 持续 %d秒", appType, logContent, duration))
            logger.insert_log(appType, logContent, formatDuration(duration))
        else
            print(string.format("跳过 %s 的短暂活动: \"%s\" 仅 %d秒", appName, currentTitle, duration))
        end
    end
    
    -- 切换到新标题
    currentTitle = newTitle
    titleStartTime = now
end

function winLogger.init()
    -- 初始化第一个窗口的状态
    local focusedWin = hs.window.focusedWindow()
    if focusedWin then
        currentApp = focusedWin:application():title()
        currentTitle = normalizeTitle(currentApp, focusedWin:title())
        titleStartTime = hs.timer.absoluteTime()
    end

    -- 监听窗口焦点变化
    hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(win)
        if not win then return end
        
        -- 在禁止时段禁用日志
        if isLoggingDisabled() then
            return
        end
        
        local newApp = win:application():title()
        if newApp == "Finder" then return end
        local newTitle = normalizeTitle(newApp, win:title())
        
        print("窗口焦点变化: " .. newApp .. " - " .. newTitle)
        
        -- 如果应用有变化，记录前一个标题，然后重置
        if newApp ~= currentApp then
            recordPreviousTitleAndSwitch(currentApp, "")
            currentApp = newApp
            currentTitle = ""
            titleStartTime = 0
        end
        
        -- 如果同一应用内标题有变化，记录前一个标题
        if newTitle ~= currentTitle and currentApp == newApp then
            recordPreviousTitleAndSwitch(currentApp, newTitle)
        end
    end)
    
    -- 监听窗口标题变化（对当前焦点窗口）
    hs.window.filter.default:subscribe(hs.window.filter.windowTitleChanged, function(win)
        if not win then return end
        
        -- 在禁止时段禁用日志
        if isLoggingDisabled() then
            return
        end
        
        local app = win:application():title()
        if app == "Finder" then return end
        local title = normalizeTitle(app, win:title())
        
        -- 只处理当前焦点窗口的标题变化
        local focusedWin = hs.window.focusedWindow()
        if not focusedWin or focusedWin:application():title() ~= app then
            return
        end
        
        print("标题变化: " .. app .. " - " .. title)
        
        -- 如果标题确实改变了，记录前一个标题
        if title ~= currentTitle then
            recordPreviousTitleAndSwitch(app, title)
        end
    end)
end

return winLogger