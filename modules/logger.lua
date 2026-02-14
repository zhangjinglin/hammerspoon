local config = require("modules.config")

local logger = {}
local filePath = nil

function logger.init()
    local fileName = os.date(config.date_format) .. ".md"
    filePath = config.obsidian_daily_path .. fileName

    local file = io.open(filePath, "r")
    if not file then
        -- 打开 template.md 模板文件，复制内容到新文件
        local templateFile = io.open(config.teplate_path, "r")
        if templateFile then
            local content = templateFile:read("*all")
            templateFile:close()

            -- 替换标题日期为当日日期
            local todayDate = os.date(config.date_format)
            content = content:gsub("# 📅 %d%d%d%d%-%d%d%-%d%d 自动化日志", "# 📅 " .. todayDate .. " 自动化日志", 1)

            local newFile = io.open(filePath, "w")
            if newFile then
                newFile:write(content)
                newFile:close()
                print("已创建今日日记 📓")
            end
        end
    else
        file:close()
    end
end

-- 向日志中插入新的记录, 参数包含 type, content, duration
function logger.insert_log(type, content, duration)
    if not filePath then
        return false
    end

    local file = io.open(filePath, "r")
    if not file then
        return false
    end

    local filecontent = file:read("*all")
    file:close()

    if type == 'Note' then
        local note = "> [" .. os.date("%H:%M") .. "] " .. content .. "\n\n"
        filecontent = filecontent:gsub("INSERT_NOTE", note .. "%1")
    elseif type == 'Telegram' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_TG", line .. "%1")
    elseif type == 'Edge' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_EDGE", line .. "%1")
    elseif type == 'Other' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_OTHER", line .. "%1")
    end

    local writeFile = io.open(filePath, "w")
    if writeFile then
        writeFile:write(filecontent)
        writeFile:close()
        return true
    end
    return false
end

return logger