-- modules/shortcuts.lua
local shortcuts = {}

-- 屏幕截图:矩形截屏并存入剪贴板
-- (keypad 面板里的截屏按钮复用这个动作)
function shortcuts.capture()
    -- 执行系统截屏命令
    -- -c: 存入剪贴板 (Copy to clipboard)
    -- -i: 交互式选择区域 (Interactive mode)
    hs.task.new("/usr/sbin/screencapture", nil, { "-c", "-i" }):start()
    -- 给一个轻量级的视觉反馈
    hs.alert.show("✂️ 区域截图", 0.5)
end

function shortcuts.init()
    -- 绑定 F1 键：屏幕截图
    -- 参数1: {} 代表不按任何修饰键（Command/Option等）
    -- 参数2: "f1" 触发按键
    hs.hotkey.bind({}, "f1", shortcuts.capture)

    -- 你以后可以在这里继续增加其他快捷键绑定
    -- hs.hotkey.bind({"option"}, "X", function() ... end)
end

return shortcuts
