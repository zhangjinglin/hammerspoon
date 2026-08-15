local config = require("modules.config")

local logger = {}
local filePath = nil

local function resolveTodayFilePath()
    local fileName = os.date(config.date_format) .. ".md"
    return config.obsidian_daily_path .. fileName
end

local function ensureDailyFileExists(targetPath)
    local file, openErr = io.open(targetPath, "rb")
    if file then
        file:close()
        return true
    end

    local templateFile, templateErr = io.open(config.teplate_path, "rb")
    if not templateFile then
        -- print(string.format("logger: 无法打开模板文件 %s: %s", config.teplate_path, tostring(templateErr)))
        -- print(string.format("logger: 原日志文件不存在 %s: %s", targetPath, tostring(openErr)))
        return false
    end

    local content = templateFile:read("*all")
    templateFile:close()
    if not content then
        -- print(string.format("logger: 模板文件读取失败 %s", config.teplate_path))
        return false
    end

    local todayDate = os.date(config.date_format)
    content = content:gsub("# 📅 %d%d%d%d%-%d%d%-%d%d 自动化日志", "# 📅 " .. todayDate .. " 自动化日志", 1)

    local newFile, createErr = io.open(targetPath, "wb")
    if not newFile then
        -- print(string.format("logger: 创建日记文件失败 %s: %s", targetPath, tostring(createErr)))
        return false
    end

    local ok, writeErr = newFile:write(content)
    newFile:close()
    if not ok then
        -- print(string.format("logger: 写入新日记文件失败 %s: %s", targetPath, tostring(writeErr)))
        return false
    end

    -- print("已创建今日日记 📓")
    return true
end

local function insertBeforeMarker(filecontent, marker, line, logType)
    local updated, count = filecontent:gsub(marker, function(m)
        return line .. m
    end, 1)

    if count == 0 then
        -- print(string.format("logger: 未找到占位符 %s，类型 %s 未写入", marker, logType))
    end

    return updated, count
end

function logger.init()
    filePath = resolveTodayFilePath()
    if not ensureDailyFileExists(filePath) then
        -- print(string.format("logger: 初始化失败，无法准备日志文件 %s", tostring(filePath)))
    end
end

-- 检查并修复非 UTF-8 字符串
function logger.sanitize_utf8(str)
    if not str then return nil end

    local res = {}
    local i = 1
    local len = #str

    while i <= len do
        -- 尝试从当前位置验证 UTF-8
        local success, pos = utf8.len(str, i)
        if success then
            -- 如果成功，说明剩余部分都是合法的
            table.insert(res, str:sub(i))
            break
        else
            -- 如果失败，pos 是第一个非法字节的位置
            if pos > i then
                table.insert(res, str:sub(i, pos - 1))
            end
            -- 替换非法字节为空格
            table.insert(res, " ")
            -- 跳过非法字节，继续检查下一个
            i = pos + 1
        end
    end

    return table.concat(res)
end

-- 向日志中插入新的记录, 参数包含 type, content, duration
function logger.insert_log(logType, content, duration)
    -- 确保 content 是 UTF-8 编码
    content = logger.sanitize_utf8(content) or ""

    local todayPath = resolveTodayFilePath()
    if filePath ~= todayPath then
        filePath = todayPath
    end

    if not filePath then
        return false
    end

    if not ensureDailyFileExists(filePath) then
        return false
    end

    local file, readErr = io.open(filePath, "rb")
    if not file then
        -- print(string.format("logger: 打开日志文件失败 %s: %s", filePath, tostring(readErr)))
        return false
    end

    local filecontent = file:read("*all")
    file:close()
    if not filecontent then
        -- print(string.format("logger: 读取日志文件失败 %s", filePath))
        return false
    end

    local writeCount = 0

    if logType == 'Note' then
        local note = "> [" .. os.date("%H:%M") .. "] " .. content .. "\n\n"
        filecontent, writeCount = insertBeforeMarker(filecontent, "INSERT_NOTE", note, logType)
    elseif logType == 'Telegram' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent, writeCount = insertBeforeMarker(filecontent, "INSERT_TG", line, logType)
    elseif logType == 'Edge' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent, writeCount = insertBeforeMarker(filecontent, "INSERT_EDGE", line, logType)
    elseif logType == 'Other' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent, writeCount = insertBeforeMarker(filecontent, "INSERT_OTHER", line, logType)
    else
        -- print(string.format("logger: 未知日志类型 %s", tostring(logType)))
        return false
    end

    if writeCount == 0 then
        return false
    end

    local writeFile, openWriteErr = io.open(filePath, "wb")
    if not writeFile then
        -- print(string.format("logger: 打开写入文件失败 %s: %s", filePath, tostring(openWriteErr)))
        return false
    end

    local ok, writeErr = writeFile:write(filecontent)
    writeFile:close()

    if not ok then
        -- print(string.format("logger: 写入日志文件失败 %s: %s", filePath, tostring(writeErr)))
        return false
    end

    return true
end

return logger
