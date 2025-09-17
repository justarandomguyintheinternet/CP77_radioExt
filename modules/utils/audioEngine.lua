local GameSettings = require("modules/utils/GameSettings")

local maxRequestInterval = 1.0

local audio = {
    timeSinceLastPlayed = maxRequestInterval + 1
}

local function getAdjustedVolume(channel, volume)
    local mult = GameSettings.Get("/audio/volume/RadioportVolume")
    if GetPlayer():GetMountedVehicle() then
        mult = GameSettings.Get("/audio/volume/CarRadioVolume")
    end
    if channel == -1 then
        volume = volume * (mult / 100)
    else
        volume = volume * 0.7
    end
    return volume * 0.4
end

function audio.update(deltaTime)
    audio.timeSinceLastPlayed = audio.timeSinceLastPlayed + deltaTime
end

function audio.playFile(id, path, time, volume, fade)
    if audio.timeSinceLastPlayed < maxRequestInterval then
        return
    end

    audio.timeSinceLastPlayed = 0
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