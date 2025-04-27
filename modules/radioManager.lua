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

    for _, file in pairs(RadioExt.GetFiles("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. radioName)) do
        local extension = file:match("^.+(%..+)$")
        if isValidExtension(extension) then
            local length = RadioExt.GetSongLength("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. radioName .. "\\" .. file)
            if length ~= 0 then
                songs[radioName .. "\\" .. file] = length / 1000
            end
        end
    end

    return songs
end

function radioManager:backwardsCompatibility(metadata)
    local updated = false
    if metadata.customIcon == nil then
        metadata.customIcon = {
            ["useCustom"] = false,
            ["inkAtlasPath"] = "",
            ["inkAtlasPart"] = ""
        }
        updated = true
    end

    if metadata.streamInfo == nil then
        metadata.streamInfo = {
            isStream = false,
            streamURL = ""
        }
        updated = true
    end

    if metadata.order == nil then
        metadata.order = {}
        updated = true
    end

    if updated then
        return metadata
    else
        return nil
    end
end

function radioManager:init()
    self:loadRadios()
    -- Initialize physical radio manager when enabled in world, or create a safe dummy to absorb method calls when disabled
    if SETTINGS.enableCustomStationsInWorldRadios then
        self.managerP = require("modules/physical/radioManagerP"):new(self)
    else
        self.managerP = {}
        setmetatable(self.managerP, {
            __index = function() 
                return function() end
            end
        })
    end
    self.managerP:init()
    self.managerV = require("modules/vehicle/radioManagerV"):new(self, self.rm)
end

function radioManager:loadRadios() -- Loads radios
    local radios = RadioExt.GetFolders("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios")
    if not radios then return end
    local config = require("modules/utils/config")

    for index, path in pairs(radios) do
        local exist
        local successE = pcall(function()
            exist = config.fileExists("radios\\" .. path .. "\\metadata.json")
        end)
        if not successE or not exist then
            print("[RadioExt] Could not find metadata.json file in \"radios\\" .. path .. "\"")
        else
            local songs = self:getSongLengths(path)
            local metadata
            local success = pcall(function ()
                metadata = config.loadFile("radios\\" .. path .. "\\metadata.json")
            end)

            if success then
                local newMetadata = self:backwardsCompatibility(metadata)
                if newMetadata ~= nil then
                    local successS = pcall(function()
                        config.saveFile("radios\\" .. path .. "\\metadata.json", newMetadata)
                    end)
                    if not successS then
                        print("[RadioExt] Could not write radios\\" .. path .. "\\metadata.json")
                    end
                end
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