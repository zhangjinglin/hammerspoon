-- init.lua

-- 1. 加载工具模块
local utils = require("modules.utils")

local logger = require("modules.logger")
local clipboard = require("modules.clipboard_manager")
local announcer = require("modules.announcer")
local winLogger = require("modules.window_logger")
local shortcuts = require("modules.shortcuts")
local audioRouter = require("modules.audio_router")

-- 自动重载配置
utils.autoReload()

-- ß初始化模块

logger.init()
clipboard.init()

announcer.init()
winLogger.init()
shortcuts.init()
audioRouter.init()


