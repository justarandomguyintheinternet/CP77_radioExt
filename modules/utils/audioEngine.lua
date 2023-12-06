local GameSettings = require("modules/utils/GameSettings")

local audio = {}

function audio.playFile(id, path, time, volume, fade)
    fade = fade or 0.75
    if id == -1 then
        volume = volume * (GameSettings.Get("/audio/volume/CarRadioVolume") / 100)
    end
    RadioExt.Play(id, path, time, 0.4 * volume, fade)
end

function audio.stopAudio(id)
    RadioExt.Stop(id)
end

return audio