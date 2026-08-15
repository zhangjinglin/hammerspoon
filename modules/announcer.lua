-- modules/announcer.lua

local announcer = {}

local overlayCanvases = {}
local countdownTimer = nil
local escEventTap = nil
local lastTriggeredKey = nil


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


-- 午休静音时间 11:30 - 13:30
local function isQuietTime(hour, min)
    local minutes = hour * 60 + min

    return minutes >= 11 * 60 + 30
        and minutes < 13 * 60 + 35
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
        text = "起身活动一下",
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


                    -- 午休时间完全跳过
                    -- if not isQuietTime(now.hour, now.min) then
                    local text = format_cn_time(
                        now.hour,
                        now.min
                    )


                    -- hs.execute(
                    --     string.format(
                    --         "say -v Binbin '%s'",
                    --         text
                    --     )
                    -- )


                    show_overlay(
                        now.hour,
                        now.min
                    )
                    -- end
                end
            end
        end
    )



    announcer.timer:start()
end

return announcer
