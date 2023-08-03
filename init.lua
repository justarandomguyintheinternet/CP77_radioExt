-------------------------------------------------------------------------------------------------------------------------------
-- This mod was created by keanuWheeze from CP2077 Modding Tools Discord.
--
-- You are free to use this mod as long as you follow the following license guidelines:
--    * It may not be uploaded to any other site without my express permission.
--    * Using any code contained herein in another mod requires credits / asking me.
--    * You may not fork this code and make your own competing version of this mod available for download without my permission.
-------------------------------------------------------------------------------------------------------------------------------

local minR4Version = 0

radio = {
    runtimeData = {
        inMenu = false,
        inGame = false,
        time = nil,
        ts = nil
    },
    GameUI = require("modules/GameUI"),
    config = require("modules/config"),
    Cron = require("modules/Cron"),
    observers = require("modules/observers")
}

function radio:new()
    registerForEvent("onInit", function()
        math.randomseed(os.clock()) -- Prevent predictable random() behavior

        if not RadioExt then
            print("[RadioExt] Error: Red4Ext part of the mod is missing")
            return
        end
        if RadioExt.GetVersion() < minR4Version then
            print("[RadioExt] Red4Ext Part is not up to date: Version is " .. RadioExt.GetVersion() .. " Expected: " .. minR4Version .. " or newer")
            return
        end

        self.radioManager = require("modules/radioManager"):new(self)
        local result = self.radioManager:loadRadios()

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu) -- Setup observer and GameUI to detect inGame / inMenu
            self.runtimeData.inMenu = isInMenu
        end)

        self.GameUI.OnSessionStart(function()
            self.runtimeData.inGame = true
        end)

        self.GameUI.OnSessionEnd(function()
            self.runtimeData.inGame = false
            self.radioManager:disableCustomRadio()
        end)

        self.observers.init(self)
        self.runtimeData.ts = GetMod("trainSystem")

        self.runtimeData.inGame = not self.GameUI.IsDetached() -- Required to check if ingame after reloading all mods
    end)

    registerForEvent("onShutdown", function()
        self.radioManager:disableCustomRadio()
    end)

    registerForEvent("onUpdate", function(delta)
        if (not self.runtimeData.inMenu) and self.runtimeData.inGame then
            self.Cron.Update(delta)
            self.radioManager:update()
            self.radioManager:handleTS()
        else
            self.radioManager:handleMenu()
        end
    end)

    return self
end

return radio:new()

-- Pause while in loading screen