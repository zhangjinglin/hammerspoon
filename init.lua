-- init.lua

-- 1. 加载工具模块
local utils = require("modules.utils")

-- local clipboard = require("modules.clipboard_manager") -- 停用：双击Command发TG
local announcer = require("modules.announcer")
-- local winLogger = require("modules.window_logger") -- 停用：窗口日志
local shortcuts = require("modules.shortcuts")
-- local audioRouter = require("modules.audio_router") -- 停用：旧版音频路由，已被 audio_switcher 取代
local audioSwitcher = require("modules.audio_switcher")
-- local input = require("modules.app_input") -- 停用：语音结束已切 ABC，应用切换切英文冗余
local doubaoVoice = require("modules.doubao_voice")
local mouseGestures = require("modules.mouse_gestures")
local mouseVoice = require("modules.mouse_voice")


audioSwitcher:start()

-- 自动重载配置
utils.autoReload()

-- 初始化模块
-- clipboard.init()
announcer.init()
-- winLogger.init()
shortcuts.init()
-- audioRouter.init()
-- input.start() -- 停用：见上
doubaoVoice.start()

-- 鼠标手势
mouseGestures.init()

-- 鼠标长按语音（左键长按 → 豆包语音输入）
mouseVoice.init()
