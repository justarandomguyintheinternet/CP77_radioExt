local config = require("modules/config")
local Cron = require("modules/Cron")
local GameSettings = require("modules/GameSettings")

audio = {}

function audio.playFile(path, time, volume, fade)
    fade = fade or 750

    local full = false

    for _, file in pairs(dir("io/out")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            full = true
        end
    end

    local carVolume = GameSettings.Get("/audio/volume/CarRadioVolume")

    if not full then
        config.tryCreateConfig("io/out/play.json", {type = "play", path = path, time = time, volume = volume * 0.75 * (carVolume / 100), fade = fade})
    else
        Cron.After(0.1, function ()
            audio.playFile(path, time, volume)
        end)
    end
end

function audio.stopAudio()
    local full = false

    for _, file in pairs(dir("io/out")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            full = true
        end
    end

    if not full then
        config.tryCreateConfig("io/out/stop.json", {type = "stop"})
    else
        Cron.After(0.1, function ()
            audio.stopAudio()
        end)
    end
end

function audio.resetEngine()
    local full = false

    for _, file in pairs(dir("io/out")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            full = true
        end
    end

    if not full then
        config.tryCreateConfig("io/out/reset.json", {type = "reset"})
    else
        Cron.After(0.1, function ()
            audio.stopAudio()
        end)
    end
end

return audio