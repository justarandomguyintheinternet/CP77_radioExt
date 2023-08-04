local GameSettings = require("modules/GameSettings")

audio = {}

function audio.playFile(path, time, volume, fade)
    fade = fade or 750
    local carVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
    RadioExt.PlayV(path, time * 1000, volume * 0.75 * (carVolume / 100))
end

function audio.stopAudio()
    RadioExt.StopV()
end

return audio