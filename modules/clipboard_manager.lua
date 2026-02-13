-- modules/clipboard_manager.lua
local clipboard = {}
local config = require("modules.config")
local logger = require("modules.logger")

local lastCmdTime = 0
local doubleClickThreshold = 0.4 -- 两次点击间隔小于 0.4 秒视为双击

-- [新增] 用于去重的状态变量
local lastSentContent = ""
local lastSentTime = 0

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
                clipboard.appendToObsidian()
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
        if content then
            clipboard.checkAndSendToTG(content)
        end
    end):start()
end

-- 检查是否为链接并发送至 TG
function clipboard.checkAndSendToTG(text)
    -- 极简正则判断：是否以 http:// 或 https:// 开头
    if text:match("^https?://[%w-_%.%?%.:/%+=&]+") then

        -- 确定路由目标
        local targetChatId = config.tg_chat_id_default
        local prefix = "🔗 发现新链接："
        
        -- 如果链接包含 t.me，则切换目标群组
        if text:match("t%.me/") then
            targetChatId = config.tg_chat_id_telegram
            prefix = "✈️ 发现电报链接："
        end

        local url = "https://api.telegram.org/bot" .. config.tg_bot_token .. "/sendMessage"
        local body = {
            chat_id = targetChatId,
            text = prefix .. "\n" .. text
        }

        -- 使用异步 HTTP 请求，不阻塞系统
        hs.http.asyncPost(url, hs.json.encode(body), {["Content-Type"] = "application/json"}, function(status, response)
            if status == 200 then
                -- hs.pasteboard.setContents("")
                hs.alert.show("已转发至 Telegram ✈️", 0.8)  
            else
                print("TG 发送失败，状态码：" .. status)
            end
        end)
    end
end

function clipboard.appendToObsidian()
    -- 1. 先模拟一个 Cmd + C，把当前选中的内容刷进剪贴板
    hs.eventtap.keyStroke({"cmd"}, "c")
    
    -- 给系统一点点时间（0.1秒）来完成剪贴板写入
    hs.timer.doAfter(0.1, function()
        local text = hs.pasteboard.getContents()
        if not text or text == "" then return end

        -- 替换掉文本里面的回车
        text = formatForCallout(text)
        logger.insert_log("Note", text)
        hs.alert.show("已采集至日记 📝", 0.8)
    end)
end

function formatForCallout(text)
    -- 1. 先把文本末尾多余的换行去掉
    text = text:gsub("%s+$", "")
    
    -- 2. 在每一行的开头加上 "> "
    -- 注意：要把每一个 "\n" 替换为 "\n> "
    local formatted = text:gsub("\n", "\n> ")
    
    -- 3. 处理可能出现的空行（防止变成只有 ">" 的行，Obsidian 有时对纯 ">" 渲染不稳）
    -- 我们可以把纯 ">" 替换为 "> " (带个空格)
    formatted = formatted:gsub("\n>$", "\n> ")
    
    return formatted
end


return clipboard