local Cron = require("modules/Cron")
local utils = require("modules/utils")
local audio = require("modules/audioEngine")

radio = {}

function radio:new(radioMod)
	local o = {}

    o.rm = radioMod

    o.metadata = nil
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

	self.__index = self
   	return setmetatable(o, self)
end

function radio:load(metadata, lengthData, path) -- metadata is the data provided by the user, lengthData is the length of all songs
    for k, v in pairs(lengthData) do
        table.insert(self.songs, {path = k, length = v})
    end

    self.name = metadata.displayName
    self.fm = metadata.fm
    self.volume = metadata.volume
    self.metadata = metadata

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
    end

    if not self.metadata.streamInfo.isStream then
        self:startRadioSimulation()
    else
        self.currentSong = {path = self.name, length = 0}
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

            self.currentSong = self.shuffelBag[1]
            table.remove(self.shuffelBag, 1)
            if #self.shuffelBag == 0 then self:generateShuffelBag() end

            self:startNewSong()

            self.tick = 0
        else
            self.tick = self.tick + 1
        end
    end)
end

function radio:activate()
    if self.active then return end

    self.active = true
    if not self.metadata.streamInfo.isStream then
        audio.playFile("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. self.currentSong.path, self.tick, self.volume)
    else
        audio.playFile(self.metadata.streamInfo.streamURL, 0, self.volume)
    end
end

function radio:deactivate()
    if not self.active then return end

    self.active = false
    audio.stopAudio()
end

function radio:currentSongDone()
    if self.active then
        audio.stopAudio()
    end
end

function radio:startNewSong()
    if self.active then
        Cron.After(0.05, function ()
            audio.playFile("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. self.currentSong.path, self.tick, self.volume)
        end)
    end
end

function radio:generateShuffelBag()
    self.shuffelBag = {}
    local bag

    if not self.currentSong then
        bag = utils.deepcopy(self.songs)
    else
        bag = utils.deepcopy(self.songs)
        utils.removeItem(bag, self.currentSong)
    end

    while #bag > 0 do
        local i = bag[math.random(#bag)]
        table.insert(self.shuffelBag, i)
        utils.removeItem(bag, i)
    end

    if self.currentSong then
        table.insert(self.shuffelBag, self.currentSong)
    end
end

return radio