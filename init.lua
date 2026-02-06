-- hs.pasteboard.watcher.new(function()
--     local clipboardContent = hs.pasteboard.getContents()
--     -- 只检测 http 开头，.m3u8 结尾的 URL
--     if clipboardContent and clipboardContent:match("^https?://[^%s]+%.m3u8.*$") then
--         local command  = 'open -a IINA "' .. clipboardContent .. '" --args --mpv-options="--speed=2"'
--         hs.execute(command)
--     end
-- end):start()

-- init.lua

-- 1. 加载工具模块
local utils = require("modules.utils")
local gestures = require("modules.mouse_gestures")
local finder = require("modules.finder_plus")
local clipboard = require("modules.clipboard_manager")
local announcer = require("modules.announcer")
local winLogger = require("modules.window_logger")
local shortcuts = require("modules.shortcuts")

-- 1. 初始化快捷键模块
shortcuts.init()

-- 2. 启动自动重载功能
utils.autoReload()

-- 3. 初始化专注记录模块
winLogger.init()

-- 3. 初始化鼠标手势模块
-- gestures.init()

-- 4. 初始化 Finder Plus 模块
-- finder.init()

-- 5. 初始化剪贴板管理模块
clipboard.init()

-- 6. 初始化整点报时模块
announcer.init()

-- 5. 打印一行日志到 Console，方便确认
print("Hammerspoon 入口已成功加载!!")