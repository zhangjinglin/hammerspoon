-- modules/finder_plus.lua
local finderPlus = {}

function finderPlus.init()
    -- 1. 把回车变成打开
    finderPlus.enterBind = hs.hotkey.new({}, "return", function()
        hs.eventtap.keyStroke({"cmd"}, "o")
    end)

    -- 2. 把 Shift + 回车 变成原来的重命名功能（发送单纯的回车）
    finderPlus.shiftEnterBind = hs.hotkey.new({"shift"}, "return", function()
        -- 暂时禁用监听器，发送一个原生的回车，再启动
        finderPlus.enterBind:disable()
        hs.eventtap.keyStroke({}, "return")
        finderPlus.enterBind:enable()
    end)

    -- 3. 只在 Finder 窗口聚焦时启用这两个绑定
    finderPlus.filter = hs.window.filter.new("Finder")
    finderPlus.filter:subscribe(hs.window.filter.windowFocused, function()
        finderPlus.enterBind:enable()
        finderPlus.shiftEnterBind:enable()
    end)
    finderPlus.filter:subscribe(hs.window.filter.windowUnfocused, function()
        finderPlus.enterBind:disable()
        finderPlus.shiftEnterBind:disable()
    end)
end

return finderPlus