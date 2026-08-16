-------------------------------------------------------------------------------------------------------------------------------
-- This mod was created by keanuWheeze from CP2077 Modding Tools Discord.
--
-- You are free to use this mod as long as you follow the following license guidelines:
--    * It may not be uploaded to any other site without my express permission.
--    * Using any code contained herein in another mod requires credits / asking me.
--    * You may not fork this code and make your own competing version of this mod available for download without my permission.
-------------------------------------------------------------------------------------------------------------------------------

local minR4Version = "0.9.0"
local initializationError = true
local audio = require("modules/utils/audioEngine")

-- Compares two dotted version strings (e.g. "0.9.0" vs "0.10.2").
-- Returns true if `actual` is greater than or equal to `required`.
-- Replaces the previous lexicographic compare which considered
-- "0.10.0" < "0.9.0" (because '1' < '9' byte-by-byte) and blocked
-- valid newer builds.
local function versionGte(actual, required)
    if actual == nil then return false end
    actual = tostring(actual)
    local function parse(v)
        local parts = {}
        for n in v:gmatch("(%d+)") do
            table.insert(parts, tonumber(n) or 0)
        end
        return parts
    end
    local a = parse(actual)
    local r = parse(required)
    local len = math.max(#a, #r)
    for i = 1, len do
        local av = a[i] or 0
        local rv = r[i] or 0
        if av > rv then return true end
        if av < rv then return false end
    end
    return true -- equal
end

local radio = {
    runtimeData = {
        inMenu = false,
        inGame = false,
        time = nil,
        ts = nil
    },
    GameUI = require("modules/utils/GameUI"),
    config = require("modules/utils/config"),
    Cron = require("modules/utils/Cron"),
    observersV = require("modules/vehicle/observersV"),
    observersP = require("modules/physical/observersP"),
    logger = require("modules/utils/logger")
}

function radio:new()
    registerForEvent("onInit", function()
        math.randomseed(os.clock()) -- Prevent predictable random() behavior

        if not RadioExt then
            print("[RadioExt] Error: Red4Ext part of the mod is missing")
            return
        end
        if not versionGte(RadioExt.GetVersion(), minR4Version) then
            print("[RadioExt] Red4Ext Part version mismatch: Version is " .. tostring(RadioExt.GetVersion()) .. " Expected: " .. minR4Version .. " or newer")
            return
        end

        self.radioManager = require("modules/radioManager"):new(self)
        self.radioManager:init()

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu) -- Setup observer and GameUI to detect inGame / inMenu
            self.runtimeData.inMenu = isInMenu
        end)

        self.GameUI.OnSessionStart(function()
            self.runtimeData.inGame = true
        end)

        self.GameUI.OnSessionEnd(function()
            self.runtimeData.inGame = false
            self.radioManager:disableCustomRadios()
        end)

        self.observersV.init(self)
        self.observersP.init(self)
        self.runtimeData.ts = GetMod("trainSystem")

        self.runtimeData.inGame = not self.GameUI.IsDetached() -- Required to check if ingame after reloading all mods

        initializationError = false
    end)

    registerForEvent("onShutdown", function()
        -- radioManager may be nil if onInit aborted early (missing Red4Ext part,
        -- version mismatch, exception during init). Guard against nil so the
        -- shutdown handler itself does not throw.
        if self.radioManager and self.radioManager.disableCustomRadios then
            self.radioManager:disableCustomRadios()
        end
    end)

    registerForEvent("onUpdate", function(delta)
        if initializationError then return end
        if not self.radioManager then return end

        if (not self.runtimeData.inMenu) and self.runtimeData.inGame then
            self.Cron.Update(delta)
            self.radioManager:update()
            if self.radioManager.managerV then
                self.radioManager.managerV:handleTS()
            end
            self.logger.update()
            audio.update(delta)
        else
            self.radioManager:handleMenu()
        end
    end)

    return self
end

return radio:new()

-- NoSync:
-- Car off, pocket on => Car turns on when entering
-- Car on, pocket off => Exiting car pocket stays off

-- Entering car with pocket on => Overrides car state
-- Changing in car, then exiting => Pocket is independent

-- Sync:
-- Entering car with pocket on => Overrides car state | Same as NoSync
-- Changing in car, then exiting => Overrides pocket | Only difference