local Cron = require("modules/utils/Cron")
local utils = require("modules/utils/utils")
local audio = require("modules/utils/audioEngine")

local radio = {}

function radio:new(radioMod)
        local o = {}

    o.rm = radioMod

    o.metadata = nil
    o.path = ""
    o.songs = {}
    o.name = nil
    o.fm = nil
    o.icon = nil
    o.volume = nil
    o.tdbName = nil
    o.path = nil

    o.simCron = nil
    o.tick = 0
    o.active = false
    o.shuffelBag = nil
    o.currentSong = nil
    o.orderedSongs = {}

    o.channels = {}

        self.__index = self
        return setmetatable(o, self)
end

function radio:getSongByPath(tab, path)
    for _, song in pairs(tab) do
        if song.path == path then return song end
    end
end

function radio:verifyOrder() -- Verify all the songs for the order exist
    local ordered = {}

    for _, song in pairs(self.metadata.order) do
        local songTable = self:getSongByPath(self.songs, self.path .. "\\" .. song)
        if songTable == nil then
            print("[RadioExt] Warning: The file \"" .. song .. "\" requested for the ordering of station \"" .. self.name .. "\" was not found.")
        else
            table.insert(ordered, songTable)
        end
    end

    self.orderedSongs = ordered
end

function radio:setupRecord(metadata, path)
    if metadata.icon == "default" then
        self.icon = "UIIcon.RadioHipHop"
    else
        self.icon = metadata.icon
    end

    path = tostring(path .. "_custom") -- In case someone names the station the same as a vanilla one

    self.tdbName = "RadioStation." .. path

    TweakDB:CloneRecord("RadioStation." .. path, "RadioStation.Pop")
    TweakDB:SetFlat("RadioStation." .. path .. ".displayName", self.name)
    TweakDB:SetFlat("RadioStation." .. path .. ".icon", self.icon)
    TweakDB:SetFlat("RadioStation." .. path .. ".index", self.index)
    CName.add(self.name)

    if metadata.customIcon.useCustom then
        TweakDB:CloneRecord("UIIcon." .. path, "UIIcon.ICEMinor")
        TweakDB:SetFlat("UIIcon." .. path .. ".atlasResourcePath", metadata.customIcon.inkAtlasPath)
        TweakDB:SetFlat("UIIcon." .. path .. ".atlasPartName", metadata.customIcon.inkAtlasPart)
        TweakDB:SetFlat("RadioStation." .. path .. ".icon", "UIIcon." .. path)
        self.icon = "UIIcon." .. path
    end
end

function radio:load(metadata, lengthData, path, index) -- metadata is the data provided by the user, lengthData is the length of all songs
    for k, v in pairs(lengthData) do
        table.insert(self.songs, { path = k, length = v })
    end

    self.name = metadata.displayName
    self.fm = metadata.fm
    self.volume = metadata.volume
    self.metadata = metadata
    self.path = path
    self.index = index + 13 -- Hardcoded 13 vanilla stations

    self:setupRecord(metadata, path)
    self:verifyOrder()

    local isStream = self.metadata.streamInfo.isStream

    if #self.songs == 0 and not isStream then
        print(("[RadioExt] Error: Station \"%s\" is not a stream, but also has no song files. The station will appear in the list but will not play anything."):format(tostring(self.name)))
    end

    if not isStream then
        if #self.songs > 0 then
            self:startRadioSimulation()
        else
            -- No songs and not a stream: don't crash startRadioSimulation,
            -- just leave the simulation dormant. The station will still appear
            -- in the radio list but won't play anything.
            print(("[RadioExt] Warning: Station \"%s\" has no songs to simulate. Skipping radio simulation."):format(tostring(self.name)))
            self.currentSong = { path = "silent", length = 999999 }
            self.tick = 0
        end
    else
        self.currentSong = { path = self.name, length = 0 } -- Used for the "playing now" HUD element
        print(("[RadioExt] Station \"%s\" configured as web stream (URL: %s)"):format(tostring(self.name), tostring(self.metadata.streamInfo.streamURL)))
    end

    -- Initialize every logical channel slot to "not playing".
    -- -1 is the vehicle-radio sentinel (mapped to slot 0 on the C++ side);
    -- 1..N are the physical-radio channels.
    -- We deliberately skip index 0 on the Lua side because it is the internal
    -- slot the C++ side reserves for the vehicle radio.
    self.channels[-1] = false
    for i = 1, RadioExt.GetNumChannels() do
        self.channels[i] = false
    end
end

function radio:startRadioSimulation()
    self:generateShuffelBag()

    -- Guard against empty shuffle bag. This can happen if a station has no
    -- songs (e.g. a file-based station whose folder is empty). Previously
    -- this crashed with "attempt to index nil (local 'currentSong')",
    -- which aborted the entire loadRadios loop and made all subsequent
    -- stations vanish from the radio list.
    if #self.shuffelBag == 0 then
        print(("[RadioExt] Error: Station \"%s\" has no songs in shuffle bag. Cannot start radio simulation."):format(tostring(self.name)))
        self.currentSong = { path = "silent", length = 999999 }
        self.tick = 0
        return
    end

    self.currentSong = self.shuffelBag[1]
    -- math.random(n) requires n >= 1. Short jingles or very short clips
    -- (length <= 15s, including the 15s safety margin) previously crashed
    -- the simulation on startup with "bad argument #1 to 'random'".
    local maxStart = self.currentSong.length - 15
    if maxStart < 1 then
        maxStart = 1
    end
    self.tick = math.random(maxStart) - 1
    table.remove(self.shuffelBag, 1)

    -- TODO: Make this less stupid and more accurate, currently up to a second off, causing error on cpp side due to channel being invalid / ended
    self.simCron = Cron.Every(1, function ()
        if self.tick >= self.currentSong.length then
            self:currentSongDone()
            if #self.shuffelBag == 0 then self:generateShuffelBag() end

            -- Guard again: if generateShuffelBag somehow produced an empty bag,
            -- don't crash trying to access shuffelBag[1].
            if #self.shuffelBag == 0 then
                print(("[RadioExt] Warning: Station \"%s\" shuffle bag is empty during tick. Skipping song change."):format(tostring(self.name)))
                return
            end

            self.currentSong = self.shuffelBag[1]
            table.remove(self.shuffelBag, 1)
            self.tick = 0

            self:startNewSong()
        else
            self.tick = self.tick + 1
        end
    end)
end

function radio:activate(channel, updateUI)
    if self.channels[channel] then return end

    self.channels[channel] = true
    if not self.metadata.streamInfo.isStream then
        local songPath = "plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. self.currentSong.path
        print(("[RadioExt] Activating file-based station \"%s\" on channel %d (song: %s, pos: %.1fs)"):format(
            tostring(self.name), channel, tostring(self.currentSong.path), self.tick))
        audio.playFile(channel, songPath, self.tick * 1000, self.volume)
    else
        print(("[RadioExt] Activating stream station \"%s\" on channel %d (URL: %s)"):format(
            tostring(self.name), channel, tostring(self.metadata.streamInfo.streamURL)))
        audio.playFile(channel, self.metadata.streamInfo.streamURL, -1, self.volume) -- -1 indicates to open path as stream
    end

    if updateUI == true or updateUI == nil then
        self:tryUpdateUI()
    end
end

function radio:deactivate(channel)
    if not self.channels[channel] then return end

    self.channels[channel] = false
    print(("[RadioExt] Deactivating station \"%s\" on channel %d"):format(tostring(self.name), channel))
    audio.stopAudio(channel)
end

function radio:currentSongDone()
    for id, state in pairs(self.channels) do
        if state then
            audio.stopAudio(id)
        end
    end
end

function radio:startNewSong()
    for id, state in pairs(self.channels) do
        if state then
            Cron.After(0.05, function ()
                audio.playFile(id, "plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. self.currentSong.path, self.tick * 1000, self.volume)
            end)
        end
    end

    self:tryUpdateUI()
end

function radio:tryUpdateUI()
    if self.channels[-1] then
        Game.GetUISystem():QueueEvent(UIVehicleRadioEvent.new())

        Cron.After(0.1, function ()
            Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
        end)
    end
end

function radio:generateShuffelBag()
    self.shuffelBag = {}
    local bag = utils.deepcopy(self.songs)

    for _, song in pairs(self.orderedSongs) do
        utils.removeItem(bag, self:getSongByPath(bag, song.path))
    end

    while #bag > 0 do
        local i = bag[math.random(#bag)]
        table.insert(self.shuffelBag, i)
        utils.removeItem(bag, i)
    end

    local insertionIndex = math.random(#self.shuffelBag + 1) -- Insert ordered part somewhere
    for i = #self.orderedSongs, 1, -1 do
        table.insert(self.shuffelBag, insertionIndex, self.orderedSongs[i])
    end
end

function radio:updateVolume(channel)
    audio.setVolume(channel, self.volume)
end

return radio