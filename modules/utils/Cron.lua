--[[
Cron.lua
Timed Tasks Manager

Copyright (c) 2021 psiberx
]]

local Cron = { version = '1.0.3' }

local timers = {}
local counter = 0
local prune = false

---@param timeout number
---@param recurring boolean
---@param ticks number
---@param callback function
---@param args
---@return any
local function addTimer(timeout, recurring, ticks, callback, args)
    if type(timeout) ~= 'number' then
        return
    end

    if timeout < 0 then
        return
    end

    if type(recurring) ~= 'boolean' then
        return
    end

    if type(callback) ~= 'function' then
        if type(args) == 'function' then
            callback, args = args, callback
        else
            return
        end
    end

    if type(args) ~= 'table' then
        args = { arg = args }
    end

    counter = counter + 1

    local timer = {
        id = counter,
        callback = callback,
        recurring = recurring,
        timeout = timeout,
        active = true,
        halted = false,
        delay = timeout,
        ticks = ticks,
        args = args,
    }

    if args.id == nil then
        args.id = timer.id
    end

    if args.interval == nil then
        args.interval = timer.timeout
    end

    if args.Halt == nil then
        args.Halt = Cron.Halt
    end

    if args.Pause == nil then
        args.Pause = Cron.Pause
    end

    if args.Resume == nil then
        args.Resume = Cron.Resume
    end

    table.insert(timers, timer)

    return timer.id
end

---@param timeout number
---@param callback function
---@param data
---@return any
function Cron.After(timeout, callback, data)
    return addTimer(timeout, false, -1, callback, data)
end

---@param timeout number
---@param callback function
---@param data
---@return any
function Cron.Every(timeout, callback, data)
    return addTimer(timeout, true, -1, callback, data)
end

---@param callback function
---@param data
---@return any
function Cron.NextTick(callback, data)
    return addTimer(0, false, -1, callback, data)
end

---@param callback function
---@param data
---@return any
function Cron.AfterTicks(ticks, callback, data)
	return addTimer(1, false, ticks, callback, data)
end

---@param timerId any
---@return void
function Cron.Halt(timerId)
    if type(timerId) == 'table' then
        timerId = timerId.id
    end

    for _, timer in ipairs(timers) do
        if timer.id == timerId then
            timer.active = false
            timer.halted = true
            prune = true
            break
        end
    end
end

function Cron.HaltAll()
	timers = {}
end

---@param timerId any
---@return void
function Cron.Pause(timerId)
    if type(timerId) == 'table' then
        timerId = timerId.id
    end

    for _, timer in ipairs(timers) do
        if timer.id == timerId then
            if not timer.halted then
                timer.active = false
            end
            break
        end
    end
end

---@param timerId any
---@return void
function Cron.Resume(timerId)
    if type(timerId) == 'table' then
        timerId = timerId.id
    end

    for _, timer in ipairs(timers) do
        if timer.id == timerId then
            if not timer.halted then
                timer.active = true
            end
            break
        end
    end
end

---@param delta number
---@return void
function Cron.Update(delta)
    if #timers == 0 then
        return
    end

    for _, timer in ipairs(timers) do
        if timer.active then
            if timer.ticks == -1 then
                timer.delay = timer.delay - delta
            else
                timer.ticks = timer.ticks - 1
            end

            if timer.delay <= 0 or timer.ticks == 0 then
                if timer.recurring then
                    timer.delay = timer.delay + timer.timeout
                else
                    timer.active = false
                    timer.halted = true
                    prune = true
                end

                timer.callback(timer.args)
            end
        end
    end

    if prune then
        prune = false
        for i = #timers, 1, -1 do
            if timers[i].halted then
                table.remove(timers, i)
            end
        end
    end
end

return Cron