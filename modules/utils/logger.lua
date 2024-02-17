local active = true

local logger = {
    lines = {}
}

function logger.log(line)
    if not active then return end

    if logger.lines[line] then
        logger.lines[line] = logger.lines[line] + 1
    else
        logger.lines[line] = 1
    end
end

function logger.update()
    if not active then return end

    for line, num in pairs(logger.lines) do
        if num > 1 then
            print(("%s | %d"):format(line, num))
        else
            print(line)
        end
    end

    logger.lines = {}
end

return logger