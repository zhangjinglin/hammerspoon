local HEADPHONE_NAME     = "External Headphones" -- 例如: "External Headphones" 或 "AirPods Pro"
local MONITOR_NAME       = "27M3U"
local PROJECTOR_NAME     = "JMGO"
-- 定义屏幕监视器
local lastProjectorState = nil
local m3uDisplay         = nil

local audioSwitcher      = hs.screen.watcher.new(function()
    local screens = hs.screen.allScreens()
    local isProjectorOnline = false
    local isMonitorOnline = false

    -- 检查 JMGO 是否在线
    for _, screen in ipairs(screens) do
        if screen:name() == PROJECTOR_NAME then
            isProjectorOnline = true
            hs.print("jmgo on")
        end
        if screen:name() == MONITOR_NAME then
            isMonitorOnline = true
            hs.print("27m3u on")
        end
    end

    if isMonitorOnline then
        local monitorAudio = hs.audiodevice.findOutputByName(MONITOR_NAME)
        if monitorAudio then
            monitorAudio:setDefaultOutputDevice()
            hs.printf("音频已切换回: " .. MONITOR_NAME)
            monitorAudio:setVolume(100)
        end
    end

    -- -- 状态未发生变化时直接返回，避免屏幕刷新时反复执行声音切换
    -- if isProjectorOnline == lastProjectorState then
    --     return
    -- end
    -- lastProjectorState = isProjectorOnline

    -- 执行状态切换逻辑
    if isProjectorOnline then
        -- 切换到外置耳机
        local headphone = hs.audiodevice.findOutputByName(HEADPHONE_NAME)
        if headphone then
            headphone:setDefaultOutputDevice()
            headphone:setVolume(100)
            hs.alert.show("音频已切换至: " .. HEADPHONE_NAME)
        else
            hs.alert.show("未找到耳机设备: " .. HEADPHONE_NAME, 3)
        end
    else
        -- 切换回 27M3U 显示器自带扬声器
        local monitorAudio = hs.audiodevice.findOutputByName(MONITOR_NAME)
        if monitorAudio then
            monitorAudio:setDefaultOutputDevice()
            hs.alert.show("音频已切换回: " .. MONITOR_NAME)
        else
            local currentDevice = hs.audiodevice.defaultOutputDevice()
            if currentDevice then
                currentDevice:setVolume(0)
            end
        end
    end
end)

return audioSwitcher
