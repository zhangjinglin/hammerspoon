local winLogger = {}
local config = require("modules.config") 

-- [状态追踪变量]
local currentApp = ""           -- 当前正在追踪的 App 名
local startTime = hs.timer.absoluteTime()
local totalAppDuration = 0      -- 整个 App 会话的总时长
local subEntries = {}           -- 存放 App 内部切换的标题及对应时长
local currentTitle = ""         -- 当前正在计时的子标题
local titleStartTime = 0        -- 子标题开始的时间

local THRESHOLD = 60            -- 总时长超过 30 秒才记录

function winLogger.init()
    -- 初始化第一个窗口的状态
    local firstWin = hs.window.focusedWindow()
    if firstWin then
        currentApp = firstWin:application():title()
        currentTitle = firstWin:title()
        titleStartTime = hs.timer.absoluteTime()
        startTime = titleStartTime
    end

    hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(win)
        if not win then return end
        
        local now = hs.timer.absoluteTime()
        local segmentDuration = math.floor((now - titleStartTime) / 1e9)
        
        local newApp = win:application():title()
        local newTitle = win:title()

        -- 1. 结算当前的子标题时长
        if segmentDuration > 0 then
            -- 如果该标题已存在，则累加时长；否则新增
            subEntries[currentTitle] = (subEntries[currentTitle] or 0) + segmentDuration
            totalAppDuration = totalAppDuration + segmentDuration
        end

        -- 2. 判断是否彻底换了 App
        if newApp ~= currentApp then
            -- 如果总时长达标，执行写入
            if totalAppDuration >= THRESHOLD then
                winLogger.writeGroupedLog()
            end

            -- 重置所有数据，进入新 App
            currentApp = newApp
            totalAppDuration = 0
            subEntries = {}
        end

        -- 3. 更新子标题状态
        currentTitle = newTitle
        titleStartTime = now
    end)
end

function winLogger.writeGroupedLog()
    local fileName = os.date(config.date_format) .. ".md"
    local filePath = config.obsidian_daily_path .. fileName
    
    -- 构造写入内容
    local content = string.format("\n\n---\n> [!tip] [专注记录] %s (总计 %d 秒)", currentApp, totalAppDuration)
    
    -- 将子条目按时长排序（可选）并转为无序列表
    for title, duration in pairs(subEntries) do
        if duration > 2 then -- 过滤掉极其短暂的闪过（比如切换时路过的标题）
            content = content .. string.format("\n> - `%d秒` | %s", duration, title)
        end
    end

    local file = io.open(filePath, "a")
    if file then
        file:write(content .. "\n")
        file:close()
        hs.alert.show("已汇总 App 活动记录 📊", 0.8)
    end
end

return winLogger