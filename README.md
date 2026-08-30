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
└── template.md         # Obsidian 日志模板
```

## 模块说明

| 模块 | 状态 | 功能 |
| --- | --- | --- |
| `mouse_gestures.lua` | 启用 | 右键鼠标手势：按住右键**上滑** = Backspace，**下滑** = Return；普通右键点击仍正常弹出菜单 |
| `announcer.lua` | 启用 | 整点/半点语音报时（8:00–21:00，Tingting 中文语音），带全屏倒计时遮罩提醒起身 |
| `shortcuts.lua` | 启用 | `F1` 区域截屏并复制到剪贴板 |
| `app_input.lua` | 启用 | 按应用自动切换输入法：终端 / iTerm2 / VS Code / Zed / Alacritty 强制英文（适配豆包输入法） |
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

## 鼠标手势实现要点

macOS 的右键菜单在 **mouseDown 时弹出**，因此手势模块在按下时即拦截事件阻止菜单，抬手后判断纵向位移：

- 位移 > 50px：执行手势（合成 Backspace / Return 按键）
- 位移不足：合成一对右键事件，正常弹出上下文菜单
