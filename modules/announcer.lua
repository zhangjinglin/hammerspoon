-- modules/announcer.lua

local announcer = {}

local overlayCanvases = {}
local countdownTimer = nil
local escEventTap = nil
local lastTriggeredKey = nil

-- 判断当前是否有活跃的显示设备（显示器或投影仪）
local function isScreenActive()
    local ok, audioSwitcher = pcall(require, "modules.audio_switcher")
    if ok and audioSwitcher and type(audioSwitcher.isDisplayActive) == "function" then
        return audioSwitcher.isDisplayActive()
    end

    for _, screen in ipairs(hs.screen.allScreens()) do
        local name = screen:name() or ""
        if name == "27M3U" or name == "JMGO" or string.find(name, "27M3U", 1, true) or string.find(name, "JMGO", 1, true) then
            return true
        end
    end
    return false
end

-- 判断当前音频是否处于静音状态
local function isAudioMuted()
    local dev = hs.audiodevice.defaultOutputDevice()
    if dev and dev:muted() == true then
        return true
    end
    return false
end


-- 中文时间格式
local function format_cn_time(hour, min)
    local period

    if hour < 12 then
        period = "上午"
    elseif hour < 18 then
        period = "下午"
    else
        period = "晚上"
    end

    local h12 = hour % 12
    if h12 == 0 then
        h12 = 12
    end

    if min == 0 then
        return string.format("现在%s%d点整", period, h12)
    end

    return string.format("现在时间%s%d点%d分", period, h12, min)
end


-- 播报用异步 hs.task 调 say，不能用 hs.execute：
-- hs.execute 会同步阻塞 Hammerspoon 主线程直到 say 退出。macOS 27 上 say 偶尔会
-- 卡在 run loop 里不退出（实测 2026-11 有一次挂了 25 分钟），主线程就一直在读管道，
-- 表现为整个 Hammerspoon 转风火轮、菜单栏图标点不动。
local sayTask = nil
local sayWatchdog = nil

local function stopSay()
    if sayWatchdog then
        sayWatchdog:stop()
        sayWatchdog = nil
    end

    if sayTask then
        local t = sayTask
        sayTask = nil
        pcall(function() t:terminate() end)
    end
end

local function speak(text)
    stopSay()

    local t

    -- 注意：Hammerspoon 1.1.x 的 hs.task.new 第 3 个参数必须是 table 或 function，
    -- 显式传 nil 会报 "incorrect type 'nil' for argument 3"，这里传一个空回调
    t = hs.task.new("/usr/bin/say", function()
        -- 只有仍是当前任务时才清理，避免覆盖新一次播报的看门狗
        if sayTask == t then
            sayTask = nil
        end

        if sayWatchdog then
            sayWatchdog:stop()
            sayWatchdog = nil
        end
    end, function()
        return true
    end, { "-v", "Tingting", text })

    if not t then
        print("[announcer] say 启动失败")
        return
    end

    sayTask = t
    t:start()

    -- 看门狗：一句话正常几秒就结束，30 秒还没退出说明 say 挂了，直接掐掉
    sayWatchdog = hs.timer.doAfter(30, function()
        if sayTask == t then
            print("[announcer] say 超过 30s 未退出，强制结束")
            stopSay()
        end
    end)
end

local function clear_overlay()
    if countdownTimer then
        countdownTimer:stop()
        countdownTimer = nil
    end

    if escEventTap then
        escEventTap:stop()
        escEventTap = nil
    end

    for _, canvas in ipairs(overlayCanvases) do
        canvas:delete()
    end

    overlayCanvases = {}
end



local function build_overlay_for_screen(screen)
    local canvas = hs.canvas.new(screen:fullFrame())

    canvas
        :behavior({
            "canJoinAllSpaces",
            "stationary",
            "ignoresCycle"
        })
        :level(hs.canvas.windowLevels.overlay)


    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {
            red = 0,
            green = 0,
            blue = 0,
            alpha = 0.82
        }
    }


    canvas[2] = {
        id = "timeText",
        type = "text",
        text = "",
        textSize = 72,
        textColor = {
            white = 1,
            alpha = 1
        },
        textAlignment = "center",
        frame = {
            x = "10%",
            y = "22%",
            w = "80%",
            h = "20%"
        }
    }


    canvas[3] = {
        type = "text",
        text = "起身活动一下,放松一下你的眼睛",
        textSize = 34,
        textColor = {
            white = 1,
            alpha = 0.92
        },
        textAlignment = "center",
        frame = {
            x = "20%",
            y = "44%",
            w = "60%",
            h = "10%"
        }
    }


    canvas[4] = {
        id = "countdownText",
        type = "text",
        text = "",
        textSize = 160,
        textColor = {
            red = 1,
            green = 0.85,
            blue = 0.2,
            alpha = 1
        },
        textAlignment = "center",
        frame = {
            x = "10%",
            y = "52%",
            w = "80%",
            h = "24%"
        }
    }


    canvas[5] = {
        type = "text",
        text = "倒计时结束再坐下",
        textSize = 26,
        textColor = {
            white = 1,
            alpha = 0.75
        },
        textAlignment = "center",
        frame = {
            x = "20%",
            y = "80%",
            w = "60%",
            h = "8%"
        }
    }


    return canvas
end



local function update_overlay(seconds, hour, min)
    local timeText = string.format(
        "%02d:%02d",
        hour,
        min
    )

    for _, canvas in ipairs(overlayCanvases) do
        canvas[2].text = timeText
        canvas[4].text = string.format("%02d", seconds)
    end
end



local function show_overlay(hour, min)
    clear_overlay()


    for _, screen in ipairs(hs.screen.allScreens()) do
        local canvas = build_overlay_for_screen(screen)

        canvas:show()

        table.insert(
            overlayCanvases,
            canvas
        )
    end


    local remainingSeconds = 10

    update_overlay(
        remainingSeconds,
        hour,
        min
    )


    escEventTap = hs.eventtap.new(
        {
            hs.eventtap.event.types.keyDown
        },
        function(event)
            if event:getKeyCode() == hs.keycodes.map.escape then
                clear_overlay()
                return true
            end

            return false
        end
    )

    escEventTap:start()



    countdownTimer = hs.timer.doEvery(
        1,
        function()
            remainingSeconds = remainingSeconds - 1

            if remainingSeconds <= 0 then
                clear_overlay()
                return
            end


            update_overlay(
                remainingSeconds,
                hour,
                min
            )
        end
    )
end



-- 手动测试
function announcer.preview()
    local now = os.date("*t")

    show_overlay(
        now.hour,
        now.min
    )
end

function announcer.init()
    clear_overlay()
    stopSay() -- 重载时清掉上一次残留的 say


    if announcer.timer then
        announcer.timer:stop()
    end


    announcer.timer = hs.timer.doEvery(
        60,
        function()
            local now = os.date("*t")


            if now.hour >= 8 and now.hour < 21 then
                local triggerKey = string.format(
                    "%04d-%02d-%02d-%02d-%02d",
                    now.year,
                    now.month,
                    now.day,
                    now.hour,
                    now.min
                )


                if now.min % 30 == 0
                    and lastTriggeredKey ~= triggerKey then
                    lastTriggeredKey = triggerKey

                    -- 当显示器和投影机都关闭，或当前已静音时，跳过播报与倒计时弹窗
                    if not isScreenActive() or isAudioMuted() then
                        return
                    end

                    local text = format_cn_time(
                        now.hour,
                        now.min
                    )

                    speak(text)
                    show_overlay(
                        now.hour,
                        now.min
                    )
                end
            end
        end
    )



    announcer.timer:start()
end

return announcer
