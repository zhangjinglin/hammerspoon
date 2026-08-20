local AMP_NAME           = "External Headphones" -- 外置功放
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"

local lastProjectorState = nil


local function switchAudio()
    local screens = hs.screen.allScreens()

    local projectorOnline = false

    for _, screen in ipairs(screens) do
        local name = screen:name()

        hs.printf("检测屏幕: %s", name)

        if name == PROJECTOR_NAME then
            projectorOnline = true
            break
        end
    end


    -- 状态没有变化，不重复切换
    if projectorOnline == lastProjectorState then
        return
    end

    lastProjectorState = projectorOnline


    -- 等待 HDMI/DP 音频设备注册
    hs.timer.doAfter(1, function()
        if projectorOnline then
            -- JMGO 开机 -> 外置功放

            local amp = hs.audiodevice.findOutputByName(AMP_NAME)

            if amp then
                amp:setDefaultOutputDevice()
                amp:setVolume(100)

                hs.alert.show("切换到外置功放")
            else
                hs.alert.show("未找到外置功放")
            end
        else
            -- JMGO关闭 -> 27M3U

            local monitor = hs.audiodevice.findOutputByName(MONITOR_NAME)

            if monitor then
                monitor:setDefaultOutputDevice()
                monitor:setVolume(100)

                hs.alert.show("切换到27M3U")
            else
                -- 没有27M3U -> 静音

                local current = hs.audiodevice.defaultOutputDevice()

                if current then
                    current:setVolume(0)
                end

                hs.alert.show("没有可用输出设备")
            end
        end
    end)
end



-- 创建屏幕监听
local audioSwitcher = hs.screen.watcher.new(function()
    switchAudio()
end)


-- 开始监听
audioSwitcher:start()


-- Hammerspoon启动时立即检测一次
switchAudio()


return audioSwitcher
