local miscUtils = {}

function miscUtils.isSameInstance(a, b)
        return Game['OperatorEqual;IScriptableIScriptable;Bool'](a, b)
end

function miscUtils.deepcopy(origin)
        local orig_type = type(origin)
    local copy
    if orig_type == 'table' then
        copy = {}
        for origin_key, origin_value in next, origin, nil do
            copy[miscUtils.deepcopy(origin_key)] = miscUtils.deepcopy(origin_value)
        end
        setmetatable(copy, miscUtils.deepcopy(getmetatable(origin)))
    else
        copy = origin
    end
    return copy
end

function miscUtils.indexValue(table, value)
    local index={}
    for k,v in pairs(table) do
        index[v]=k
    end
    return index[value]
end

function miscUtils.has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function miscUtils.getIndex(tab, val)
    local index = nil
    for i, v in ipairs(tab) do
                if v == val then
                        index = i
                        break
                end
    end
    return index
end

function miscUtils.removeItem(tab, val)
    -- If the value isn't present, do nothing.
    -- Previously this called table.remove(tab, nil) which silently removes
    -- the LAST element of the table, corrupting station playlists.
    local index = miscUtils.getIndex(tab, val)
    if index == nil then return end
    table.remove(tab, index)
end

function miscUtils.split(s, delimiter) --https://www.codegrepper.com/code-examples/lua/lua+split+string+by+space
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

return miscUtils