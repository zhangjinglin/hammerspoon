local winLogger = {}
local config = require("modules.config") 

-- [状态追踪变量]
local currentApp = ""           -- 当前正在追踪的 App 名
local startTime = hs.timer.absoluteTime()
local totalAppDuration = 0      -- 整个 App 会话的总时长
local subEntries = {}           -- 存放 App 内部切换的标题及对应时长
local currentTitle = ""         -- 当前正在计时的子标题
local titleStartTime = 0        -- 子标题开始的时间
local screenshotTimer = nil     -- 定时器对象，必须保存到变量中防止被垃圾回收
local currentWin = nil          -- 当前正在追踪的窗口对象（用于截图）

local THRESHOLD = 300            -- 总时长超过 300 秒才记录

-- 检查当前时间是否在禁止日志的时间段内 (23:00 - 7:00 AM)
local function isLoggingDisabled()
    local hour = tonumber(os.date("%H"))
    -- 23 到 23:59 或 0 到 6:59 之间不记录
    return hour >= 23 or hour < 7
end

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

function winLogger.init()
    -- [新增] 启动每 5 秒截图定时器
    -- 必须保存到变量中，否则会被垃圾回收
    -- screenshotTimer = hs.timer.doEvery(900, winLogger.captureAndLogScreenshot)

    -- 初始化第一个窗口的状态（保存为 currentWin，供后续截图使用）
    currentWin = hs.window.focusedWindow()
    if currentWin then
        currentApp = currentWin:application():title()
        currentTitle = currentWin:title()
        titleStartTime = hs.timer.absoluteTime()
        startTime = titleStartTime
    end

    hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(win)
        if not win then return end
        
        -- 在禁止时段禁用日志
        if isLoggingDisabled() then
            return
        end
        
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

        -- 更新 currentWin 为新聚焦的窗口（注意：不要在判断 app 切换并写入日志之前覆盖它，
        -- 以便 writeGroupedLog 能拿到上一个 app 的窗口用于截图）
        currentWin = win
    end)
end

function winLogger.captureAndLogScreenshot()
    -- 在禁止时段禁用日志
    if isLoggingDisabled() then
        return
    end
    
    local todayDate = os.date(config.date_format)
    local dailyFolder = config.obsidian_daily_path
    local imagesFolder = dailyFolder .. "images/"

    -- print("captureAndLogScreenshot")
    
    -- 1. 确保存放图片的文件夹存在
    -- mkdir -p 可以递归创建目录，如果已存在也不会报错
    os.execute("mkdir -p '" .. imagesFolder .. "'")
    
    -- 2. 截图
    local screen = hs.screen.mainScreen()
    if not screen then return end
    
    local image = screen:snapshot()
    if not image then return end
    
    -- 3. 保存图片
    local timeStr = os.date("%H-%M-%S")
    local imgName = "screenshot-" .. todayDate .. "-" .. timeStr .. ".jpg"
    local fullPath = imagesFolder .. imgName
    
    -- saveToFile(path, filetype) -> boolean
    -- filetype: BMP, GIF, JPEG, PDF, PNG, TIFF
    image:saveToFile(fullPath, "JPEG")
    
    -- 4. 写入日记文件
    local logFile = dailyFolder .. todayDate .. ".md"
    local file = io.open(logFile, "a")
    if file then
        -- 相对路径引用，让 Obsidian 能直接识别
        -- 格式：![screenshot-10-00-00.jpg](images/screenshot-10-00-00.jpg)
        local mdLink = string.format("\n\n---\n> [!example] 📸 屏幕快照 %s\n> ![[%s]]\n", timeStr, imgName)
        
        -- 如果你想用标准 Markdown 链接：
        local mdLink = string.format("\n\n![Snapshot %s](images/%s)\n", timeStr, imgName)
        
        file:write(mdLink)
        file:close()
    end
end

function winLogger.writeGroupedLog()
    local fileName = os.date(config.date_format) .. ".md"
    local filePath = config.obsidian_daily_path .. fileName

    -- print("Writing grouped log for app: " .. currentApp)
    
    -- 获取当前应用的截图（使用 currentWin 窗口对象）
    local appScreenshot = nil
    local screenshotName = nil
    if currentWin then
        appScreenshot = currentWin:snapshot()
    end
    if appScreenshot then
        local imagesFolder = config.obsidian_daily_path .. "images/"
        os.execute("mkdir -p '" .. imagesFolder .. "'")
        screenshotName = os.date(config.date_format) .. "-" .. os.date("%H-%M-%S") .. "-" .. currentApp .. ".jpg"
        local screenshotPath = imagesFolder .. screenshotName
        appScreenshot:saveToFile(screenshotPath, "JPEG")    
        -- print("Saved app screenshot to: " .. screenshotPath)
    end
    -- 构造写入内容
    local content = string.format("\n\n---\n> [!tip] [专注记录] %s " .. os.date("(%H:%M)") .. "(总计 %s) \n> ![[%s]]", currentApp, formatDuration(totalAppDuration), screenshotName or "")
    
    -- 将子条目按时长排序（可选）并转为无序列表
    -- 简单的遍历是无序的，如果需要排序可以先提取 keys
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