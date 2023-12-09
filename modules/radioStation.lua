local Cron = require("modules/utils/Cron")
local utils = require("modules/utils/utils")
local audio = require("modules/utils/audioEngine")

radio = {}

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
    CName.add(self.name)

    if metadata.customIcon.useCustom then
        TweakDB:CloneRecord("UIIcon." .. path, "UIIcon.ICEMinor")
        TweakDB:SetFlat("UIIcon." .. path .. ".atlasResourcePath", metadata.customIcon.inkAtlasPath)
        TweakDB:SetFlat("UIIcon." .. path .. ".atlasPartName", metadata.customIcon.inkAtlasPart)
        TweakDB:SetFlat("RadioStation." .. path .. ".icon", "UIIcon." .. path)
        self.icon = "UIIcon." .. path
    end
end

function radio:load(metadata, lengthData, path) -- metadata is the data provided by the user, lengthData is the length of all songs
    for k, v in pairs(lengthData) do
        table.insert(self.songs, {path = k, length = v})
    end

    self.name = metadata.displayName
    self.fm = metadata.fm
    self.volume = metadata.volume
    self.metadata = metadata
    self.path = path

    self:setupRecord(metadata, path)
    self:verifyOrder()

    if #self.songs == 0 and not self.metadata.streamInfo.isStream then -- Fallback for regular stations w/o any songs
        print("[RadioExt] Error: Station \"" .. self.name .. "\" is not a stream, but also has no song files. Using fallback webstream instead.")
        self.metadata.streamInfo.isStream = true
        self.metadata.streamInfo.streamURL = "https://radio.garden/api/ara/content/listen/TP8NDBv7/channel.mp3"
    end

    if not self.metadata.streamInfo.isStream then
        self:startRadioSimulation()
    else
        self.currentSong = {path = self.name, length = 0} -- Used for the "playing now" HUD element
    end

    for i = -1, RadioExt.GetNumChannels() do -- -1 is vehicle radio, 1 - CHANNELS is physical channels
        self.channels[i] = false
    end
end

function radio:startRadioSimulation()
    self:generateShuffelBag()
    self.currentSong = self.shuffelBag[1]
    self.tick = math.random(self.currentSong.length - 15)
    table.remove(self.shuffelBag, 1)

    self.simCron = Cron.Every(1, function ()
        if self.tick >= self.currentSong.length then
            self:currentSongDone()
            if #self.shuffelBag == 0 then self:generateShuffelBag() end

            self.currentSong = self.shuffelBag[1]
            table.remove(self.shuffelBag, 1)

            self:startNewSong()

            self.tick = 0
        else
            self.tick = self.tick + 1
        end
    end)
end

function radio:activate(channel)
    if self.channels[channel] then return end

    self.channels[channel] = true
    if not self.metadata.streamInfo.isStream then
        audio.playFile(channel, "plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. self.currentSong.path, self.tick * 1000, self.volume)
    else
        audio.playFile(channel, self.metadata.streamInfo.streamURL, -1, self.volume) -- -1 indicates to open path as stream
    end

    self:tryUpdateUI()
end

function radio:deactivate(channel)
    if not self.channels[channel] then return end

    self.channels[channel] = false
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