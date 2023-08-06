local config = require("modules/utils/config")
local Cron = require("modules/utils/Cron")

local radioManager = {}

function radioManager:new(radioMod)
	local o = {}

    o.rm = radioMod
    o.radios = {}

    o.managerV = nil
    o.managerP = nil

	self.__index = self
   	return setmetatable(o, self)
end

function radioManager:getSongLengths(radioName)
    local songs = {}

    for _, file in pairs(dir("radios/" .. radioName .. "/")) do
        local extension = file.name:match("^.+(%..+)$")
        if extension == ".flac" or extension == ".mp2" or extension == ".mp3" or extension == ".ogg" or extension == ".wav" or extension == ".wax" or extension == ".wma" then
            local length = RadioExt.GetSongLength("plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios\\" .. radioName .. "\\" .. file.name)
            if length ~= 0 then
                songs[radioName .. "\\" .. file.name] = length / 1000
            end
        end
    end

    return songs
end

function radioManager:backwardsCompatibility(metadata)
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

    for _, path in pairs(radios) do
        if not config.fileExists("radios/" .. path .. "/metadata.json") then
            print("[RadioMod] Could not find metadata.json file in \"radios/" .. path .. "\"")
        else
            local songs = self:getSongLengths(path)
            local metadata
            local success = pcall(function ()
                metadata = config.loadFile("radios/" .. path .. "/metadata.json")
            end)

            if success then
                self:backwardsCompatibility(metadata)

                local r = require("modules/radioStation"):new(self.rm)
                r:load(metadata, songs, path)
                self.radios[#self.radios + 1] = r
            else
                print("[RadioMod] Error: Failed to load the metadata.json file for \"" .. path .. "\". Make sure the file is valid.")
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

return radioManager