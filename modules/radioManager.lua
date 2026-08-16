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
    local dirty = false

    if metadata.customIcon == nil then
        metadata.customIcon = {
            ["useCustom"] = false,
            ["inkAtlasPath"] = "",
            ["inkAtlasPart"] = ""
        }
        dirty = true
    else
        -- Validate sub-fields of customIcon
        if metadata.customIcon.useCustom == nil then
            metadata.customIcon.useCustom = false
            dirty = true
        end
        if metadata.customIcon.inkAtlasPath == nil then
            metadata.customIcon.inkAtlasPath = ""
            dirty = true
        end
        if metadata.customIcon.inkAtlasPart == nil then
            metadata.customIcon.inkAtlasPart = ""
            dirty = true
        end
    end

    if metadata.streamInfo == nil then
        metadata.streamInfo = {
            isStream = false,
            streamURL = ""
        }
        dirty = true
    else
        -- Validate sub-fields of streamInfo.
        -- This is the root cause of the "stream station kills all other stations" bug:
        -- if streamInfo exists but isStream is nil (or not a boolean), the station
        -- was treated as file-based, which crashed startRadioSimulation on an empty
        -- shuffle bag, which aborted loadRadios, which skipped all remaining stations.
        if type(metadata.streamInfo.isStream) ~= "boolean" then
            -- Coerce common truthy/falsy values to boolean
            local raw = metadata.streamInfo.isStream
            if raw == "true" or raw == 1 then
                metadata.streamInfo.isStream = true
            elseif raw == "false" or raw == 0 then
                metadata.streamInfo.isStream = false
            else
                metadata.streamInfo.isStream = false
            end
            print(("[RadioExt] Warning: Station \"%s\" had a non-boolean streamInfo.isStream (was %s). Coerced to %s."):format(tostring(metadata.displayName), tostring(raw), tostring(metadata.streamInfo.isStream)))
            dirty = true
        end
        if type(metadata.streamInfo.streamURL) ~= "string" then
            metadata.streamInfo.streamURL = tostring(metadata.streamInfo.streamURL or "")
            dirty = true
        end
    end

    if metadata.order == nil then
        metadata.order = {}
        dirty = true
    end

    -- Validate top-level required fields
    if type(metadata.displayName) ~= "string" then
        print(("[RadioExt] Warning: Station in folder \"%s\" has invalid displayName (was %s). Using folder name as fallback."):format(tostring(path), tostring(metadata.displayName)))
        metadata.displayName = tostring(path)
        dirty = true
    end
    if type(metadata.fm) ~= "number" then
        -- Try to coerce string to number
        local coerced = tonumber(metadata.fm)
        if coerced then
            metadata.fm = coerced
        else
            print(("[RadioExt] Warning: Station \"%s\" has invalid fm (was %s). Using 0."):format(tostring(metadata.displayName), tostring(metadata.fm)))
            metadata.fm = 0
        end
        dirty = true
    end
    if type(metadata.volume) ~= "number" then
        local coerced = tonumber(metadata.volume)
        if coerced then
            metadata.volume = coerced
        else
            print(("[RadioExt] Warning: Station \"%s\" has invalid volume (was %s). Using 1.0."):format(tostring(metadata.displayName), tostring(metadata.volume)))
            metadata.volume = 1.0
        end
        dirty = true
    end
    if type(metadata.icon) ~= "string" then
        metadata.icon = "default"
        dirty = true
    end

    if dirty then
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
    if not radios then
        print("[RadioExt] No radios folder found or empty.")
        return
    end

    print(("[RadioExt] Found %d station folder(s) in radios/"):format(#radios))

    for index, path in pairs(radios) do
        if not config.fileExists("radios/" .. path .. "/metadata.json") then
            print(("[RadioExt] Could not find metadata.json file in \"radios/%s\""):format(path))
        else
            local songs = self:getSongLengths(path)
            local metadata
            local success, err = pcall(function ()
                metadata = config.loadFile("radios/" .. path .. "/metadata.json")
            end)

            if success and metadata ~= nil then
                self:backwardsCompatibility(metadata, path)

                -- Wrap the station load in pcall so ONE broken station doesn't
                -- abort the entire loadRadios loop and make all subsequent
                -- stations vanish from the radio list.
                local r = require("modules/radioStation"):new(self.rm)
                local loadOk, loadErr = pcall(function ()
                    r:load(metadata, songs, path, index)
                end)

                if loadOk then
                    self.radios[#self.radios + 1] = r
                    local stationType = metadata.streamInfo.isStream and "stream" or "file"
                    -- Use #r.songs (integer-keyed array built by radioStation:load),
                    -- NOT #songs (which is string-keyed and always returns 0 for the
                    -- length operator in Lua).
                    local songCount = #r.songs
                    print(("[RadioExt] Loaded station \"%s\" (FM %s, %d song(s), type: %s, index: %d)"):format(
                        tostring(metadata.displayName), tostring(metadata.fm), songCount, stationType, r.index))

                    -- Helpful hint: if isStream is false but a streamURL is present,
                    -- the user almost certainly forgot to flip isStream to true.
                    if not metadata.streamInfo.isStream and type(metadata.streamInfo.streamURL) == "string" and metadata.streamInfo.streamURL ~= "" then
                        print(("[RadioExt] Hint: Station \"%s\" has isStream=false but streamURL is set to \"%s\". If this station is meant to be a web stream, set isStream to true in metadata.json."):format(
                            tostring(metadata.displayName), metadata.streamInfo.streamURL))
                    end
                else
                    print(("[RadioExt] Error: Failed to load station \"%s\" (folder: \"%s\"): %s"):format(
                        tostring(metadata.displayName), tostring(path), tostring(loadErr)))
                end
            else
                print(("[RadioExt] Error: Failed to load the metadata.json file for \"%s\". Make sure the file is valid.%s"):format(
                    path, err and (" (" .. tostring(err) .. ")") or ""))
            end
        end
    end

    print(("[RadioExt] Successfully loaded %d/%d station(s)."):format(#self.radios, #radios))
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
    -- managerP may be nil if init() threw before its construction.
    if self.managerP and self.managerP.uninit then
        self.managerP:uninit()
    end
end

function radioManager:update()
    if self.managerV then self.managerV:update() end
    if self.managerP then self.managerP:update() end
end

function radioManager:handleMenu()
    if self.managerV then self.managerV:handleMenu() end
    if self.managerP then self.managerP:handleMenu() end
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