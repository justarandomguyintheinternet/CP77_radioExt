local GameSettings = require("modules/utils/GameSettings")

local maxRequestInterval = 1.0

local audio = {
    timeSinceLastPlayedByChannel = {}
}

local function getAdjustedVolume(channel, volume)
    local mult = GameSettings.Get("/audio/volume/RadioportVolume") or 100
    if GetPlayer():GetMountedVehicle() then
        mult = GameSettings.Get("/audio/volume/CarRadioVolume") or 100
    end
    if channel == -1 then
        volume = volume * (mult / 100)
    else
        volume = volume * 0.7
    end
    return volume * 0.4
end

function audio.update(deltaTime)
    for channel, timeSinceLastPlayed in pairs(audio.timeSinceLastPlayedByChannel) do
        audio.timeSinceLastPlayedByChannel[channel] = timeSinceLastPlayed + deltaTime
    end
end

function audio.playFile(id, path, time, volume, fade)
    local timeSinceLastPlayed = audio.timeSinceLastPlayedByChannel[id] or maxRequestInterval + 1
    if timeSinceLastPlayed < maxRequestInterval then
        return
    end

    audio.timeSinceLastPlayedByChannel[id] = 0
    fade = fade or 0.75
    RadioExt.Play(id, path, time, getAdjustedVolume(id, volume), fade)
end

function audio.stopAudio(id)
    RadioExt.Stop(id)
end

function audio.setVolume(channel, volume)
    RadioExt.SetVolume(channel, getAdjustedVolume(channel, volume))
end

return audio
