local active = false

local logger = {
    lines = {}
}

function logger.log(line)
    if not active then return end

    local found = false
    for _, data in pairs(logger.lines) do
        if data.line == line then
            data.num = data.num + 1
            found = true
        end
    end

    if not found then
        table.insert(logger.lines, {line = line, num = 1})
    end
end

function logger.update()
    if not active then return end

    for _, data in pairs(logger.lines) do
        if data.num > 1 then
            print(("%s | %d"):format(data.line, data.num))
        else
            print(data.line)
        end
    end

    logger.lines = {}
end

return logger