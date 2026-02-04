-- modules/config.lua
local config = {}

-- 【请修改这里】改成你 Obsidian 仓库日记所在的真实文件夹路径
config.obsidian_daily_path = "/Volumes/t7/my-work/obsidian/jinglin/日记/"

-- 【请修改这里】你日记的文件名格式，比如 2026-02-03.md
config.date_format = "%Y-%m-%d" 

-- [新增] Telegram 配置
config.tg_bot_token = ""      -- 从 @BotFather 获取
config.tg_chat_id = ""         -- 格式通常是 -100xxxxxxxxxx
config.tg_chat_id_default = ""   -- 原有的普通群组
config.tg_chat_id_telegram = ""  -- [新增] 专门接收 t.me 链接的群组

config.announcer = {
    start_hour = 8,  -- 早上 8 点开始报时
    end_hour = 22,   -- 晚上 10 点停止报时（22点后不再响）
    interval = 15    -- 报时频率（分钟），比如 30 代表每半小时
}

return config