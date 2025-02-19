-------------------------------------------------------------------------------------------------------------------------------
-- This mod was created by keanuWheeze from CP2077 Modding Tools Discord.
--
-- You are free to use this mod as long as you follow the following license guidelines:
--    * It may not be uploaded to any other site without my express permission.
--    * Using any code contained herein in another mod requires credits / asking me.
--    * You may not fork this code and make your own competing version of this mod available for download without my permission.
-------------------------------------------------------------------------------------------------------------------------------

local minR4Version = 0.7
local defaultSettings = {
    enableCustomStationsInWorldRadios = true,
    includeCustomStationsInRandom = false
}

SETTINGS = nil

radio = {
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
    logger = require("modules/utils/logger"),
    version = 2.7
}

function radio:new()
    registerForEvent("onInit", function()
        math.randomseed(os.clock()) -- Prevent predictable random() behavior

        if not RadioExt then
            print("[RadioExt] Error: Red4Ext part of the mod is missing")
            return
        end
        if math.abs(RadioExt.GetVersion() - minR4Version) > 0.05 then
            print("[RadioExt] Red4Ext Part is not up to date: Version is " .. RadioExt.GetVersion() .. " Expected: " .. minR4Version .. " or newer")
            return
        end

        local config = require("modules/utils/config")
        local success = pcall(function ()
            SETTINGS = config.loadFile("settings.json")
        end)

        if success and SETTINGS then
            for k, _ in pairs(defaultSettings) do
                if SETTINGS[k] == nil then
                    success = false
                    break
                end
            end
        end

        if not success or not SETTINGS then
            print("[RadioExt] Warning: Failed to load the settings.json,use default settings")
            SETTINGS = {}
            for key, value in pairs(defaultSettings) do
                SETTINGS[key] = value
            end
        end

        if SETTINGS.enableCustomStationsInWorldRadios then
            print([[
[RadioExt] Warning: Custom stations are ENABLED on WORLD RADIOS (environmental devices).
---------------------------------------------------------------
- Saving with a world radio on custom stations causes PERMANENT MALFUNCTION after mod uninstall
- Set [enableCustomStationsInWorldRadios = false] to prevent issues (won't fix existing ones)
- Affected radios require MANUAL station cycling to recover functionality
    ]])
        end

        if SETTINGS.includeCustomStationsInRandom then
            print([[
[RadioExt] Warning: Radios in the world will now randomly select custom stations.
---------------------------------------------------------------
- World radios may choose custom stations when first loaded. If randomized to custom stations:
  State WILL BE PERMANENTLY SAVED (silent after mod uninstall)
  Can affect multiple radios in save files without notice

- Recovery: You MUST manually cycle stations on ALL affected radios

- Critical Warning: 
  Growl FM Party radio becomes UNFIXABLE 
  (station switching physically blocked)

- Essential precaution: 
  Keep [includeCustomStationsInRandom = false] to avoid these risks

* (This setting requires [enableCustomStationsInWorldRadios = true] to function)
            ]])
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
        if SETTINGS.enableCustomStationsInWorldRadios then
            self.observersP.init(self)
        end
        self.runtimeData.ts = GetMod("trainSystem")

        self.runtimeData.inGame = not self.GameUI.IsDetached() -- Required to check if ingame after reloading all mods
    end)

    registerForEvent("onShutdown", function()
        self.radioManager:disableCustomRadios()
    end)

    registerForEvent("onUpdate", function(delta)
        if (not self.runtimeData.inMenu) and self.runtimeData.inGame then
            self.Cron.Update(delta)
            self.radioManager:update()
            self.radioManager.managerV:handleTS()
            self.logger.update()
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