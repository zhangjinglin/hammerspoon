# Hammerspoon 配置

个人 macOS 效率工具配置，基于 [Hammerspoon](https://www.hammerspoon.org/)。

## 环境要求

- macOS + [Hammerspoon](https://www.hammerspoon.org/download/)
- 系统设置 → 隐私与安全性 → 辅助功能：勾选 Hammerspoon（事件监听 / 模拟按键必需）

## 安装

```bash
git clone git@github.com:zhangjinglin/hammerspoon.git ~/.hammerspoon
```

启动 Hammerspoon 即可，修改任意 `.lua` 文件会自动重载配置（`modules/utils.lua` 中的 pathwatcher）。

## 目录结构

```
~/.hammerspoon
├── init.lua            # 入口，控制各模块的启用/禁用
├── modules/            # 功能模块
├── bin/                # Swift 辅助进程源码与二进制
└── template.md         # Obsidian 日志模板
```

## 模块说明

| 模块 | 状态 | 功能 |
| --- | --- | --- |
| `mouse_gestures.lua` | 启用 | 右键鼠标手势：按住右键**上滑** = Backspace，**下滑** = Return；普通右键点击仍正常弹出菜单 |
| `mouse_voice.lua` | 启用 | 左键长按语音：任意位置按住左键 0.5s → HID 点按豆包语音快捷键（右 Option）开始语音，松开左键再点按一次结束、文字上屏；拖拽/微信内不触发 |
| `announcer.lua` | 启用 | 整点/半点语音报时（8:00–21:00，Tingting 中文语音），带全屏倒计时遮罩提醒起身 |
| `shortcuts.lua` | 启用 | `F1` 区域截屏并复制到剪贴板 |
| `app_input.lua` | 注释 | 按应用自动切换输入法（已被语音结束切 ABC 覆盖，停用） |
| `doubao_voice.lua` | 启用 | 豆包语音开始自动静音、结束恢复声音并切 ABC（依赖 `bin/doubao_voice_watch` 监控语音悬浮窗） |
| `audio_switcher.lua` | 启用 | 监听投影仪（JMGO）连接状态，自动切换音频输出到外置功放 / 显示器 |
| `clipboard_manager.lua` | 注释 | 双击 Command 将剪贴板内容（文本/图片）发送到 Telegram，支持长文本自动分块 |
| `window_logger.lua` | 注释 | 记录当前应用与窗口标题停留时长，写入 Obsidian 每日笔记 |
| `logger.lua` | 依赖 | 日志写入 Obsidian 每日笔记的底层工具（供 window_logger / test 使用） |
| `audio_router.lua` | 注释 | 按屏幕/电源状态路由音频输出（旧版，被 audio_switcher 取代） |
| `finder_plus.lua` | 未启用 | Finder 增强：回车打开文件，Shift+回车重命名 |
| `utils.lua` | 启用 | 配置自动重载 |
| `config.lua` | 配置 | 快捷键、Telegram bot token、Obsidian 路径等（含敏感信息时注意不要提交） |
| `test.lua` | 调试 | 开发调试用，勿启用 |

启用/禁用模块：编辑 `init.lua`，取消对应行的注释即可。

## 豆包语音监控编译

`bin/` 下只提交 Swift 源码，二进制需本地编译一次：

```bash
swiftc -O -o bin/doubao_voice_watch bin/doubao_voice_watch.swift
```

## 鼠标长按语音（mouse_voice）

在任意位置按住左键 0.5 秒（不用动键盘）即可开始豆包语音输入，松开左键结束。

- 不吞鼠标事件：普通点击、双击选词、拖拽选字完全不受影响；
- 长按即触发（文本框 AX 识别已关闭，Electron 等应用不可靠）；
- 触发后位移超过 25px 视为拖拽，自动取消/结束；
- 豆包须设为"免按模式"（按一次开始、按任意键结束），快捷键与 `config.mouseVoice.key` 一致；
- 合成走 HID 层（`bin/hidtap`，`CGEventPost kCGHIDEventTap`），会话层合成（eventtap / System Events）豆包不识别；
- 默认在微信里不触发（避免和微信自带的按住说话打架），可在 `config.mouseVoice.excludedApps` 调整。

`modules/config.lua` 里的可调项：

```lua
M.mouseVoice = {
    enabled = true,
    key = "rightalt",     -- 必须和豆包输入法设置里的语音快捷键一致（rightalt/ctrl/fn）
    holdMs = 500,
    moveCancelPx = 25,
    requireEditableElement = false, -- true 则只在可编辑文本框里触发
    feedback = true,
    debug = true,
    excludedApps = { "com.tencent.xinWeChat" },
}
```

构建 HID 压键小工具（已提交二进制，改源码后重编）：

```bash
swiftc -O -o bin/hidtap bin/hidtap.swift
```

调试（Hammerspoon 控制台里执行）：

```lua
local mv = require("modules.mouse_voice")
mv.test(2)     -- 不碰鼠标，HID 点按两次（隔 2 秒），验证豆包会不会出语音悬浮条
mv.inspect()   -- 把鼠标放到输入框上执行，看 AX 文本框识别状态（仅供参考，不再做触发门槛）
mv.status()    -- 当前状态 / 监控进程 / 豆包语音是否开启
```

## 鼠标手势实现要点

macOS 的右键菜单在 **mouseDown 时弹出**，因此手势模块在按下时即拦截事件阻止菜单，抬手后判断纵向位移：

- 位移 > 50px：执行手势（合成 Backspace / Return 按键）
- 位移不足：合成一对右键事件，正常弹出上下文菜单
