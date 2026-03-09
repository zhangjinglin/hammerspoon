-- modules/announcer.lua
local announcer = {}
local config = require("modules.config")

local function format_cn_time(hour, min)
    local period = hour < 12 and "上午" or "下午"
    local h12 = hour % 12
    if h12 == 0 then
        h12 = 12
    end

    if min == 0 then
        return string.format("现在%s%d点整", period, h12)
    end

    return string.format("现在时间%s%d点%d分", period, h12, min)
end

function announcer.init()
    announcer.timer = hs.timer.doEvery(60, function()
        local now = os.date("*t")
        -- 仅在设定的时间段内且到达频率时执行
        if now.hour >= config.announcer.start_hour and now.hour < config.announcer.end_hour then
            if now.min % config.announcer.interval == 0 then
                local speakText = format_cn_time(now.hour, now.min)

                -- 直接利用你已经验证成功的系统命令
                hs.execute(string.format("say -v Binbin '%s'", speakText))
                -- hs.alert.show(string.format("⏰ %02d:%02d", now.hour, now.min), 2)
            end
        end
    end):start()
end

return announcer
