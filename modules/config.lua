local M = {}

M.hotkeys = {
    clipboard = {"cmd", "shift", "v"}
}

-- 鼠标长按语音（modules/mouse_voice.lua）
M.mouseVoice = {
    enabled = true,
    -- 与豆包"免按模式"里设的快捷键保持一致（合成走 HID 层，见 modules/mouse_voice.lua）
    key = "rightalt",       -- rightalt(右Option) / ctrl / fn / 也可直接写 keycode 数字
    flags = nil,          -- 只有 key 用数字时可能需要手工指定原始 flags
    holdMs = 500,         -- 左键按住多久算长按（正常单击约 0.2~0.3s，超 0.5s 即判长按）
    moveCancelPx = 25,    -- 位移超过多少像素取消（拖拽选字不受影响）
    maxHoldMs = 120000,   -- 兜底：最长按住时间
    requireEditableElement = false, -- 已关闭：Electron 等应用 AX 识别不可靠，改为长按即触发
    feedback = true,      -- 触发时显示提示
    debug = true,         -- 输出日志到 Hammerspoon 控制台
    excludedApps = {      -- 应用黑名单（bundle id 或名称）
        "com.tencent.xinWeChat",
    },
}

M.debug = true

return M
