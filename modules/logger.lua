local config = require("modules.config")

local logger = {}
local filePath = nil
local bom = "\239\187\191" -- UTF-8 BOM

function logger.init()
    local fileName = os.date(config.date_format) .. ".md"
    filePath = config.obsidian_daily_path .. fileName

    local file = io.open(filePath, "rb")
    if not file then
        -- 打开 template.md 模板文件，复制内容到新文件
        local templateFile = io.open(config.teplate_path, "rb")
        if templateFile then
            local content = templateFile:read("*all")
            templateFile:close()

            -- 如果模板文件包含 BOM，先移除，避免重复
            if content:sub(1, 3) == bom then
                content = content:sub(4)
            end

            -- 替换标题日期为当日日期
            local todayDate = os.date(config.date_format)
            content = content:gsub("# 📅 %d%d%d%d%-%d%d%-%d%d 自动化日志", "# 📅 " .. todayDate .. " 自动化日志", 1)

            local newFile = io.open(filePath, "wb")
            if newFile then
                -- 确保写入 BOM
                newFile:write(bom)
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

    local file = io.open(filePath, "rb")
    if not file then
        return false
    end

    local filecontent = file:read("*all")
    file:close()

    -- 读取时如果已经有 BOM，先移除，以便统一处理
    if filecontent:sub(1, 3) == bom then
        filecontent = filecontent:sub(4)
    end

    if type == 'Note' then
        local note = "> [" .. os.date("%H:%M") .. "] " .. content .. "\n\n"
        filecontent = filecontent:gsub("INSERT_NOTE", function(m) return note .. m end)
    elseif type == 'Telegram' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_TG", function(m) return line .. m end)
    elseif type == 'Edge' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_EDGE", function(m) return line .. m end)
    elseif type == 'Other' then
        local line = "| " .. os.date("%H:%M") .. " | " .. content .. " | " .. tostring(duration or "") .. " |\n"
        filecontent = filecontent:gsub("INSERT_OTHER", function(m) return line .. m end)
    end

    local writeFile = io.open(filePath, "wb")
    if writeFile then
        -- 写入时统一加上 BOM
        writeFile:write(bom)
        writeFile:write(filecontent)
        writeFile:close()
        return true
    end
    return false
end

return logger