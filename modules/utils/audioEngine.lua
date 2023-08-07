local GameSettings = require("modules/utils/GameSettings")

local audio = {}

function audio.playFile(id, path, time, volume, fade)
    fade = fade or 0.75
    local carVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
    RadioExt.Play(id, path, time * 1000, volume * 0.4 * (carVolume / 100), fade)
end

function audio.stopAudio(id)
    RadioExt.Stop(id)
end

return audio