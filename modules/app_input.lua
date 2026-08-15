local M = {}

-- 1. 定义应用与输入法的映射关系（根据需要自行替换 Input Source ID）
local config = {
    -- 强制切英文的应用列表
    englishApps = {
        ["iTerm2"] = true,
        ["Terminal"] = true,
        ["Code"] = true,
        ["Zed"] = true,
        ["Alacritty"] = true,
    },
    -- 强制切中文的应用列表
    chineseApps = {
    },
    -- 输入法 ID
    sources = {
        english = "com.apple.keylayout.ABC",
    }
}

local appWatcher = nil

-- 2. 事件回调处理
local function handleAppEvent(appName, eventType, appObject)
    if eventType == hs.application.watcher.activated then
        if config.englishApps[appName] then
            hs.keycodes.currentSourceID(config.sources.english)
        end
    end
end

-- 3. 模块启动函数
function M.start()
    if not appWatcher then
        appWatcher = hs.application.watcher.new(handleAppEvent)
    end
    appWatcher:start()
end

-- 4. 模块停止函数
function M.stop()
    if appWatcher then
        appWatcher:stop()
    end
end

return M
