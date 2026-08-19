-- init.lua

-- 1. 加载工具模块
local utils = require("modules.utils")

local clipboard = require("modules.clipboard_manager")
local announcer = require("modules.announcer")
local winLogger = require("modules.window_logger")
local shortcuts = require("modules.shortcuts")
-- local audioRouter = require("modules.audio_router")
local audioSwitcher = require("modules.audio_switcher")
local input = require("modules.app_input")


audioSwitcher:start()

-- 自动重载配置
utils.autoReload()

-- 初始化模块
-- clipboard.init()
announcer.init()
-- winLogger.init()
shortcuts.init()
-- audioRouter.init()
input.start()
