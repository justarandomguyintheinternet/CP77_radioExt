local GameSettings = require("modules/utils/GameSettings")

-- Per-channel rate limit window (seconds).
-- The previous implementation used a single global window: any playFile call
-- within 1s of the previous one was silently dropped, which broke legitimate
-- use cases such as switching stations in quick succession or activating
-- multiple physical radios at once. We now track the last-played timestamp
-- per channel id, so each channel has its own cooldown.
local maxRequestInterval = 1.0

local audio = {
    lastPlayedByChannel = {}
}

local function getAdjustedVolume(channel, volume)
    if volume == nil then volume = 0 end

    local player = GetPlayer()
    local mult = nil
    if player then
        local ok, mounted = pcall(function()
            return player:GetMountedVehicle()
        end)
        if ok and mounted then
            mult = GameSettings.Get("/audio/volume/CarRadioVolume")
        end
    end
    if mult == nil then
        mult = GameSettings.Get("/audio/volume/RadioportVolume")
    end
    if mult == nil then mult = 100 end

    if channel == -1 then
        volume = volume * (mult / 100)
    else
        volume = volume * 0.7
    end
    return volume * 0.4
end

function audio.update(deltaTime)
    -- No global state to advance per-frame now that we use per-channel timestamps.
    -- Kept for API compatibility: init.lua calls audio.update(delta) every frame.
end

function audio.playFile(id, path, time, volume, fade)
    -- Per-channel rate limit. This prevents spamming the C++ backend with
    -- createStream requests for the same channel while it is still loading,
    -- but no longer blocks independent channels from starting simultaneously.
    local now = os.clock()
    local last = audio.lastPlayedByChannel[id] or 0
    if now - last < maxRequestInterval then
        return
    end
    audio.lastPlayedByChannel[id] = now

    fade = fade or 0.75
    RadioExt.Play(id, path, time, getAdjustedVolume(id, volume), fade)
end

function audio.stopAudio(id)
    -- Clear the per-channel cooldown on stop so that a subsequent playFile
    -- on the same channel is not artificially delayed.
    audio.lastPlayedByChannel[id] = 0
    RadioExt.Stop(id)
end

function audio.setVolume(channel, volume)
    RadioExt.SetVolume(channel, getAdjustedVolume(channel, volume))
end

return audio
