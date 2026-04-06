-- modules/announcer.lua
local announcer = {}
local config = require("modules.config")

local overlayCanvases = {}
local countdownTimer = nil
local escEventTap = nil
local lastTriggeredKey = nil

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
    local frame = screen:fullFrame()
    local canvas = hs.canvas.new(frame)
        :behavior({"canJoinAllSpaces", "stationary", "ignoresCycle"})
        :level(hs.canvas.windowLevels.overlay)

    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { red = 0, green = 0, blue = 0, alpha = 0.82 },
        roundedRectRadii = { xRadius = 0, yRadius = 0 }
    }

    canvas[2] = {
        id = "timeText",
        type = "text",
        text = "",
        textSize = 72,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "22%", w = "80%", h = "20%" }
    }

    canvas[3] = {
        id = "messageText",
        type = "text",
        text = "起身活动一下",
        textSize = 34,
        textColor = { white = 1, alpha = 0.92 },
        textAlignment = "center",
        frame = { x = "20%", y = "44%", w = "60%", h = "10%" }
    }

    canvas[4] = {
        id = "countdownText",
        type = "text",
        text = "",
        textSize = 160,
        textColor = { red = 1, green = 0.85, blue = 0.2, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "52%", w = "80%", h = "24%" }
    }

    canvas[5] = {
        id = "hintText",
        type = "text",
        text = "倒计时结束再坐下",
        textSize = 26,
        textColor = { white = 1, alpha = 0.75 },
        textAlignment = "center",
        frame = { x = "20%", y = "80%", w = "60%", h = "8%" }
    }

    return canvas
end

local function update_overlay(remainingSeconds, hour, min)
    local timeText = string.format("%02d:%02d", hour, min)

    for _, canvas in ipairs(overlayCanvases) do
        canvas[2].text = timeText
        canvas[4].text = string.format("%02d", remainingSeconds)
    end
end

local function show_overlay(hour, min)
    clear_overlay()

    for _, screen in ipairs(hs.screen.allScreens()) do
        local canvas = build_overlay_for_screen(screen)
        canvas:show()
        table.insert(overlayCanvases, canvas)
    end

    local remainingSeconds = config.announcer.countdown_seconds or 30
    update_overlay(remainingSeconds, hour, min)

    escEventTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
        if event:getKeyCode() == hs.keycodes.map.escape then
            clear_overlay()
            return true
        end

        return false
    end):start()

    countdownTimer = hs.timer.doEvery(1, function()
        remainingSeconds = remainingSeconds - 1

        if remainingSeconds <= 0 then
            clear_overlay()
            return
        end

        update_overlay(remainingSeconds, hour, min)
    end)
end

function announcer.preview()
    local now = os.date("*t")
    show_overlay(now.hour, now.min)
end

function announcer.init()
    clear_overlay()

    if announcer.timer then
        announcer.timer:stop()
    end

    announcer.timer = hs.timer.doEvery(60, function()
        local now = os.date("*t")
        local triggerKey = string.format("%04d-%02d-%02d-%02d-%02d", now.year, now.month, now.day, now.hour, now.min)

        -- 仅在设定的时间段内且到达频率时执行
        if now.hour >= config.announcer.start_hour and now.hour < config.announcer.end_hour then
            if now.min % config.announcer.interval == 0 and lastTriggeredKey ~= triggerKey then
                lastTriggeredKey = triggerKey
                local speakText = format_cn_time(now.hour, now.min)

                if config.announcer.speak ~= false then
                    hs.execute(string.format("say -v Binbin '%s'", speakText))
                end

                if now.hour < (config.announcer.activity_end_hour or config.announcer.end_hour) then
                    show_overlay(now.hour, now.min)
                end
            end
        end
    end):start()
end

return announcer
