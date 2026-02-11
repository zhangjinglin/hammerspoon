-- modules/announcer.lua
local announcer = {}
local config = require("modules.config")

function announcer.init()
    announcer.timer = hs.timer.doEvery(60, function()
        local now = os.date("*t")
        -- 仅在设定的时间段内且到达频率时执行
        if now.hour >= config.announcer.start_hour and now.hour < config.announcer.end_hour then
            if now.min % config.announcer.interval == 0 then
                local speakText = string.format("现在时间 %d点 %d分", now.hour, now.min)
                if now.min == 0 then speakText = string.format("现在 %d点整", now.hour) end
                
                -- 直接利用你已经验证成功的系统命令
                hs.execute(string.format("say -v Binbin '%s'", speakText))
                -- hs.alert.show(string.format("⏰ %02d:%02d", now.hour, now.min), 2)
            end
        end
    end):start()
end

return announcer