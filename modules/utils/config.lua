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
    local data = json.decode(file:read("*a"))
    file:close()
    return data
end

function config.saveFile(path, data)
    local encoded, jconfig = pcall(json.encode, data)
    if not encoded then
        return false, jconfig
    end

    local file, openError = io.open(path, "w")
    if not file then
        return false, openError
    end

    local wrote, writeResult, writeError = pcall(file.write, file, jconfig)
    local closed, closeResult, closeError = pcall(file.close, file)

    if not wrote then
        return false, writeResult
    elseif not writeResult then
        return false, writeError
    elseif not closed then
        return false, closeResult
    elseif not closeResult then
        return false, closeError
    end

    return true
end

return config
