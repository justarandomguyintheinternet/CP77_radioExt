local GameSettings = require("modules/GameSettings")

local audio = {}

function audio.playFile(path, time, volume, fade)
    fade = fade or 0.75
    local carVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
    RadioExt.PlayV(path, time * 1000, volume * 0.3 * (carVolume / 100), fade)
end

function audio.stopAudio()
    RadioExt.StopV()
end

return audio