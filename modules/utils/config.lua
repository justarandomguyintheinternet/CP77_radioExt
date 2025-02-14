local config = {}

-- Check if the file exists (if the content cannot be read, the file is considered non-existent)
function config.fileExists(filename)
    local content = RadioExt.ReadFileWrapper("plugins\\cyber_engine_tweaks\\mods\\radioExt\\" .. filename)
    return content ~= nil and content ~= ""
end

function config.tryCreateConfig(path, data)
    if not config.fileExists(path) then
        local jconfig = json.encode(data)
        RadioExt.WriteFileWrapper(path, jconfig)
    end
end

function config.loadFile(path)
    local content = RadioExt.ReadFileWrapper("plugins\\cyber_engine_tweaks\\mods\\radioExt\\" .. path)
    local configData = json.decode(content)
    return configData
end

function config.saveFile(path, data)
    local jconfig = json.encode(data)
    RadioExt.WriteFileWrapper("plugins\\cyber_engine_tweaks\\mods\\radioExt\\" .. path, jconfig)
end

function config.backwardComp(path, data)
    local f = nil
    local successL = pcall(function()
        f = config.loadFile(path)
    end)
    if not successL or not f then
        print("[RadioExt] Could not read" .. path)
        return
    end
    for k, e in pairs(data) do
        if f[k] == nil then
            f[k] = e
        end
    end
    local successS = pcall(function()
        config.saveFile(path, f)
    end)
    if not successS then
        print("[RadioExt] Could not write" .. path)
    end
end

return config