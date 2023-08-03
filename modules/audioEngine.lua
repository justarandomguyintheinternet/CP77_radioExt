local config = require("modules/config")
local Cron = require("modules/Cron")
local GameSettings = require("modules/GameSettings")

audio = {}

function audio.playFile(path, time, volume, fade)
    fade = fade or 750
    local carVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
    RadioExt.PlayV("plugins\\cyber_engine_tweaks\\mods\\radioExt\\" .. path, time * 1000, volume * 0.75 * (carVolume / 100))
end

function audio.stopAudio()
    RadioExt.StopV()
end

function audio.resetEngine()

end

return audio