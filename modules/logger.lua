local config = require("modules.config")

local logger = {}
local filePath = nil


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



            -- 替换标题日期为当日日期
            local todayDate = os.date(config.date_format)
            content = content:gsub("# 📅 %d%d%d%d%-%d%d%-%d%d 自动化日志", "# 📅 " .. todayDate .. " 自动化日志", 1)

            local newFile = io.open(filePath, "wb")
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
function logger.insert_log(type, content, duration)
    -- 确保 content 是 UTF-8 编码
    content = logger.sanitize_utf8(content)

    if not filePath then
        return false
    end

    local file = io.open(filePath, "rb")
    if not file then
        return false
    end

    local filecontent = file:read("*all")
    file:close()



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

        writeFile:write(filecontent)
        writeFile:close()
        return true
    end
    return false
end

return logger