-- modules/clipboard_manager.lua
local clipboard = {}
local config = require("modules.config")

local lastCmdTime = 0
local doubleClickThreshold = 0.4 -- 两次点击间隔小于 0.4 秒视为双击
local tgMessageLimit = 4096
local tgRawChunkLimit = 1800

local function trim(text)
    local cleaned = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return cleaned
end

local function escapeHTML(text)
    text = tostring(text or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    return text
end

local function convertInlineCode(text)
    text = tostring(text or "")
    local parts = {}
    local pos = 1

    while true do
        local openStart, openEnd = text:find("`", pos, true)
        if not openStart then
            table.insert(parts, escapeHTML(text:sub(pos)))
            break
        end

        local closeStart, closeEnd = text:find("`", openEnd + 1, true)
        if not closeStart then
            table.insert(parts, escapeHTML(text:sub(pos)))
            break
        end

        table.insert(parts, escapeHTML(text:sub(pos, openStart - 1)))
        table.insert(parts, "<code>" .. escapeHTML(text:sub(openEnd + 1, closeStart - 1)) .. "</code>")
        pos = closeEnd + 1
    end

    return table.concat(parts)
end

local function convertMarkdownToTGHTML(text)
    text = tostring(text or "")
    local parts = {}
    local pos = 1

    while true do
        local openStart, openEnd = text:find("```", pos, true)
        if not openStart then
            table.insert(parts, convertInlineCode(text:sub(pos)))
            break
        end

        table.insert(parts, convertInlineCode(text:sub(pos, openStart - 1)))

        local codeStart = openEnd + 1
        local lineEnd = text:find("\n", codeStart, true)
        if not lineEnd then
            table.insert(parts, escapeHTML(text:sub(openStart)))
            break
        end

        local closeStart, closeEnd = text:find("```", lineEnd + 1, true)
        if not closeStart then
            table.insert(parts, escapeHTML(text:sub(openStart)))
            break
        end

        local code = text:sub(lineEnd + 1, closeStart - 1)
        code = code:gsub("\n$", "")
        table.insert(parts, "<pre><code>" .. escapeHTML(code) .. "</code></pre>")
        pos = closeEnd + 1
    end

    return table.concat(parts)
end

local function splitFirstParagraph(text)
    text = trim((text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
    if text == "" then
        return "", ""
    end

    local question, answer = text:match("^(.-)\n%s*\n(.*)$")
    if question then
        return trim(question), trim(answer)
    end

    return text, ""
end

local function isAnswerMarkerLine(line)
    return line:match("^%s*答：") or line:match("^%s*答:")
end

local function parseTaggedChatSegments(text)
    text = trim((text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
    local segments = {}
    local currentRole = nil
    local currentLines = {}
    local sawMarker = false

    local function flushCurrent()
        if currentRole and #currentLines > 0 then
            local content = trim(table.concat(currentLines, "\n"))
            if content ~= "" then
                table.insert(segments, {
                    role = currentRole,
                    content = content
                })
            end
        end

        currentRole = nil
        currentLines = {}
    end

    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:match("^%s*请问") then
            flushCurrent()
            sawMarker = true
            currentRole = "question"
            currentLines = { trim(line) }
        elseif isAnswerMarkerLine(line) then
            flushCurrent()
            sawMarker = true
            currentRole = "answer"
            currentLines = { trim(line) }
        elseif currentRole then
            table.insert(currentLines, line)
        elseif trim(line) ~= "" then
            currentRole = "answer"
            currentLines = { line }
        end
    end

    flushCurrent()

    if sawMarker then
        return segments
    end

    return nil
end

local function splitRawTextForTG(text)
    local chunks = {}
    text = tostring(text or "")

    while #text > tgRawChunkLimit do
        local chunk = text:sub(1, tgRawChunkLimit)
        local splitAt = chunk:match("^.*()\n\n") or chunk:match("^.*()\n") or tgRawChunkLimit
        if splitAt < 1 then
            splitAt = tgRawChunkLimit
        end

        table.insert(chunks, trim(text:sub(1, splitAt)))
        text = trim(text:sub(splitAt + 1))
    end

    if text ~= "" then
        table.insert(chunks, text)
    end

    return chunks
end

local function formatSegmentChunks(role, content)
    local chunks = {}

    for _, rawChunk in ipairs(splitRawTextForTG(content)) do
        local formatted = convertMarkdownToTGHTML(rawChunk)
        if role == "question" then
            formatted = "<b><i>Q: " .. formatted .. "</i></b>"
        end
        table.insert(chunks, formatted)
    end

    return chunks
end

local function packTGHTMLChunks(chunks)
    local packed = {}

    for _, chunk in ipairs(chunks) do
        if chunk ~= "" then
            local last = packed[#packed]
            if last and #(last .. "\n\n" .. chunk) <= tgMessageLimit then
                packed[#packed] = last .. "\n\n" .. chunk
            else
                table.insert(packed, chunk)
            end
        end
    end

    return packed
end

local function formatChatChunksForTG(text)
    local taggedSegments = parseTaggedChatSegments(text)
    if taggedSegments then
        local segmentChunks = {}
        for _, segment in ipairs(taggedSegments) do
            for _, chunk in ipairs(formatSegmentChunks(segment.role, segment.content)) do
                table.insert(segmentChunks, chunk)
            end
        end

        return packTGHTMLChunks(segmentChunks)
    end

    local question, answer = splitFirstParagraph(text)
    local segmentChunks = {}

    if question ~= "" then
        for _, chunk in ipairs(formatSegmentChunks("question", question)) do
            table.insert(segmentChunks, chunk)
        end
    end

    if answer ~= "" then
        for _, chunk in ipairs(formatSegmentChunks("answer", answer)) do
            table.insert(segmentChunks, chunk)
        end
    end

    return packTGHTMLChunks(segmentChunks)
end

function clipboard.init()
    -- 监听修饰键变化（Command 键）
    clipboard.tap = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
        local flags = event:getFlags()
        local keyCode = event:getKeyCode()

        -- 55 是左 Command 键，54 是右 Command 键的 KeyCode
        if (keyCode == 55 or keyCode == 54) and flags.cmd then
            local now = hs.timer.absoluteTime() / 1e9 -- 转为秒
            local diff = now - lastCmdTime
            
            if diff < doubleClickThreshold then
                -- 【触发动作：双击 Command】
                clipboard.sendSelectionToTG()
                lastCmdTime = 0 -- 重置，防止连击三次触发两次
            else
                lastCmdTime = now
            end
        end
        return false
    end):start()

    -- 2. [新增] 剪贴板内容变化监听 (用于 Telegram 自动转发)
    -- 每当剪贴板内容变化时，这个 watcher 就会运行
    clipboard.watcher = hs.pasteboard.watcher.new(function(content)
        -- 如果剪贴板里面是一个.m3u8结尾的链接。
        if content and content:match("^https?://[%w-_%.%?%.:/%+=&]+%.m3u8") then
            -- 获取当前 Edge 浏览器中的 URL。
            refer = getEdgeURL()
            -- 获取当前 Edge 浏览器中 tab 的标题。
            local app = hs.application.get("Microsoft Edge")
            local title = app and app:mainWindow() and app:mainWindow():title() or "unknown_title"
            -- 从标题中提取番号，假设番号是标题开头的连续非空字符序列（直到第一个空格为止）。
            local fanhao = app:mainWindow():title():match("^%s*(%S+)")
                    -- print("fanhao:", fanhao)
    
            -- 这里的格式是为了配合 hls-command-generator 工具，生成一个可以直接在命令行使用的下载命令。
            content = "N_m3u8DL-RE '" .. content .. "' -H 'Referer: " .. refer .. "' -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) hls-command-generator/0.1.0 Chrome/148.0.7778.265 Safari/537.36' -H 'Origin: https://missav.ws'  -H 'Accept: */*'  -H 'Accept-Language: en-US' --save-name " .. fanhao  
            -- 把 content 写回到剪贴板。
            hs.pasteboard.setContents(content)
        elseif content and content:match("^https?://[%w-_%.%?%.:/%+=&]+") then
            -- 如果是普通链接，则继续执行原有的 TG 转发逻辑
             clipboard.checkAndSendToTG(content)
        end
    end):start()
end

-- 获取当前 Edge 浏览器中 tab 的 URL
function getEdgeURL()
    local ok, result = hs.osascript.applescript([[
        tell application "Microsoft Edge"
            get URL of active tab of front window
        end tell
    ]])

    return ok and result or ""
end

-- 发送消息至 TG 机器人的通用辅助函数
function clipboard.postToTG(text, chatId, successAlert, parseMode)
    if not config.tg_bot_token or not chatId or chatId == "" or chatId == "-100xxxxxxxxxx" then
        -- print("TG 发送被跳过：未配置 Bot Token 或有效的 Chat ID")
        return
    end

    local url = "https://api.telegram.org/bot" .. config.tg_bot_token .. "/sendMessage"
    local body = {
        chat_id = chatId,
        text = text
    }
    if parseMode then
        body.parse_mode = parseMode
    end

    -- 使用异步 HTTP 请求，不阻塞系统
    hs.http.asyncPost(url, hs.json.encode(body), {["Content-Type"] = "application/json"}, function(status, response)
        if status == 200 then
            if successAlert then
                hs.alert.show(successAlert, 0.8)
            end
        else
            -- print("TG 发送失败，状态码：" .. status .. ", 响应：" .. tostring(response))
        end
    end)
end

-- 发送剪贴板图片至 TG 群组
function clipboard.postImageToTG(image, chatId, successAlert)
    if not config.tg_bot_token or not chatId or chatId == "" or chatId == "-100xxxxxxxxxx" then
        -- print("TG 图片发送被跳过：未配置 Bot Token 或有效的 Chat ID")
        return
    end

    if not image then
        -- print("TG 图片发送被跳过：剪贴板中没有可用图片")
        return
    end

    local imagePath = os.tmpname() .. ".png"
    local saved = image:saveToFile(imagePath, true, "PNG")
    if not saved then
        -- print("TG 图片发送失败：无法保存临时图片 " .. tostring(imagePath))
        return
    end

    local url = "https://api.telegram.org/bot" .. config.tg_bot_token .. "/sendPhoto"
    local task = hs.task.new("/usr/bin/curl", function(exitCode, stdOut, stdErr)
        os.remove(imagePath)

        if exitCode == 0 and stdOut and stdOut:match('"ok"%s*:%s*true') then
            if successAlert then
                hs.alert.show(successAlert, 0.8)
            end
        else
            -- print("TG 图片发送失败，退出码：" .. tostring(exitCode) .. ", 输出：" .. tostring(stdOut) .. ", 错误：" .. tostring(stdErr))
        end
    end, {
        "-sS",
        "-X", "POST",
        url,
        "-F", "chat_id=" .. chatId,
        "-F", "photo=@" .. imagePath
    })

    task:start()
end

-- 检查是否为链接并发送至 TG
function clipboard.checkAndSendToTG(text)
    -- 极简正则判断：是否以 http:// 或 https:// 开头
    if text:match("^https?://[%w-_%.%?%.:/%+=&]+") then

        -- 跳过夸克网盘链接，不发送到 Telegram
        if text:match("^https://pan%.quark%.cn") then
            return
        end

         -- 跳过x video，不发送到 Telegram
        if text:match("^https://video.twimg") then
            return
        end

        -- 确定路由目标
        local targetChatId = config.tg_chat_id_default
        local prefix = "🔗 发现新链接："
        
        -- 如果链接包含 t.me，则切换目标群组
        if text:match("t%.me/") then
            targetChatId = config.tg_chat_id_telegram
            prefix = "✈️ 发现电报链接："
        end

        clipboard.postToTG(prefix .. "\n" .. text, targetChatId, "已转发至 Telegram ✈️")
    end
end

function clipboard.sendSelectionToTG()
    -- 1. 先模拟一个 Cmd + C，把当前选中的内容刷进剪贴板
    hs.eventtap.keyStroke({"cmd"}, "c")
    
    -- 给系统一点点时间（0.1秒）来完成剪贴板写入
    hs.timer.doAfter(0.15, function()
        local chatId = config.tg_chat_id_mythoughs
        if not chatId then return end

        local text = hs.pasteboard.getContents()
        if text and text:match("%S") then
            local chunks = formatChatChunksForTG(text)
            for index, chunk in ipairs(chunks) do
                local alert = (index == #chunks) and "已发送至 Telegram ✈️" or nil
                clipboard.postToTG(chunk, chatId, alert, "HTML")
            end
            return
        end

        local types = hs.pasteboard.typesAvailable()
        if types and types.image then
            clipboard.postImageToTG(hs.pasteboard.readImage(), chatId, "图片已发送至 Telegram ✈️")
        else
            hs.alert.show("没有可发送的文字或图片", 0.8)
        end
    end)
end


return clipboard
