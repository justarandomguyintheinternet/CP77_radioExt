local config = require("modules/utils/config")

local radioManager = {}

local extensions = {
    "mp3",
    "mp2",
    "flac",
    "ogg",
    "wav",
    "wax",
    "wma",
    "opus",
    "aiff",
    "aif",
    "aifc"
}

function radioManager:new(radioMod)
	local o = {}

    o.rm = radioMod
    o.radios = {}

    o.managerV = nil
    o.managerP = nil

	self.__index = self
   	return setmetatable(o, self)
end

local function isValidExtension(extension)
    for _, ext in pairs(extensions) do
        if extension == ("." .. ext) then
            return true
        end
    end
    return false
end

function radioManager:getSongLengths(radioName)
    local songs = {}

    for _, file in pairs(dir("radios/" .. radioName .. "/")) do
        local extension = file.name:match("^.+(%..+)$")
        if isValidExtension(extension) then
            local length = RadioExt.GetSongLength("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. radioName .. "\\" .. file.name)
            if length ~= 0 then
                songs[radioName .. "\\" .. file.name] = length / 1000
            end
        end
    end

    return songs
end

function radioManager:backwardsCompatibility(metadata, path)
    if metadata.customIcon == nil then
        metadata.customIcon = {
            ["useCustom"] = false,
            ["inkAtlasPath"] = "",
            ["inkAtlasPart"] = ""
        }

        config.saveFile("radios/" .. path .. "/metadata.json", metadata)
    end

    if metadata.streamInfo == nil then
        metadata.streamInfo = {
            isStream = false,
            streamURL = ""
        }

        config.saveFile("radios/" .. path .. "/metadata.json", metadata)
    end

    if metadata.order == nil then
        metadata.order = {}

        config.saveFile("radios/" .. path .. "/metadata.json", metadata)
    end
end

function radioManager:init()
    self:loadRadios()
    self.managerP = require("modules/physical/radioManagerP"):new(self)
    self.managerP:init()
    self.managerV = require("modules/vehicle/radioManagerV"):new(self, self.rm)
end

function radioManager:loadRadios() -- Loads radios
    local radios = RadioExt.GetFolders("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios")
    if not radios then return end

    for index, path in pairs(radios) do
        if not config.fileExists("radios/" .. path .. "/metadata.json") then
            print("[RadioExt] Could not find metadata.json file in \"radios/" .. path .. "\"")
        else
            local songs = self:getSongLengths(path)
            local metadata
            local success = pcall(function ()
                metadata = config.loadFile("radios/" .. path .. "/metadata.json")
            end)

            if success then
                self:backwardsCompatibility(metadata, path)

                local r = require("modules/radioStation"):new(self.rm)
                r:load(metadata, songs, path, index)
                self.radios[#self.radios + 1] = r
            else
                print("[RadioExt] Error: Failed to load the metadata.json file for \"" .. path .. "\". Make sure the file is valid.")
            end
        end
    end

    return true
end

function radioManager:getRadioByName(name)
    for _, radio in pairs(self.radios) do
        if name == radio.name then
            return radio
        end
    end

    return nil
end

function radioManager:getRadioByIndex(index)
    for _, radio in pairs(self.radios) do
        if index == radio.index then
            return radio
        end
    end

    return nil
end

function radioManager:disableCustomRadios() -- Disables all custom radios, vehicle and physical
    for _, radio in pairs(self.radios) do
        radio:deactivate(-1)
    end
    self.managerP:uninit()
end

function radioManager:update()
    self.managerV:update()
    self.managerP:update()
end

function radioManager:handleMenu()
    self.managerV:handleMenu()
    self.managerP:handleMenu()
end

function radioManager:updateVRadioVolume()
    self.rm.logger.log("updateVRadioVolume()")
    for _, radio in pairs(self.radios) do
        if radio.channels[-1] then
            radio:updateVolume(-1)
        end
    end
end

return radioManager