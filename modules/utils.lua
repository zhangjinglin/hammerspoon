-- modules/utils.lua

local utils = {}

function utils.autoReload()
    -- 定义重载函数
    local function reloadConfig(files)
        local doReload = false
        for _, file in ipairs(files) do
            -- 只有当修改的文件是 .lua 结尾时才触发
            if file:sub(-4) == ".lua" then
                doReload = true
                break
            end
        end
        if doReload then
            hs.reload()
        end
    end

    -- 创建监听器：监视 ~/.hammerspoon/ 及其子目录
    -- 注意：os.getenv("HOME") 会自动获取你的用户目录
    local watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
    
    -- 成功加载的提示（只在重载瞬间弹出）
    hs.alert.show("Hammerspoon 配置已同步 ✅", 1.5)
end

return utils