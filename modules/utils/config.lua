local config = {}

function config.fileExists(filename)
    local f=io.open(filename,"r")
    if (f~=nil) then io.close(f) return true else return false end
end

function config.tryCreateConfig(path, data)
        if not config.fileExists(path) then
        local file = io.open(path, "w")
        local jconfig = json.encode(data)
        file:write(jconfig)
        file:close()
    end
end

function config.loadFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return nil
    end
    local ok, decoded = pcall(json.decode, content)
    if not ok or decoded == nil then
        return nil
    end
    return decoded
end

function config.saveFile(path, data)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    local ok, jconfig = pcall(json.encode, data)
    if not ok then
        file:close()
        return false
    end
    file:write(jconfig)
    file:close()
    return true
end

function config.backwardComp(path, data)
    local f = config.loadFile(path)

    for k, e in pairs(data) do
        if f[k] == nil then
            f[k] = e
        end
    end

    config.saveFile(path, f)
end

return config