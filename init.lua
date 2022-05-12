-------------------------------------------------------------------------------------------------------------------------------
-- This mod was created by keanuWheeze from CP2077 Modding Tools Discord.
--
-- You are free to use this mod as long as you follow the following license guidelines:
--    * It may not be uploaded to any other site without my express permission.
--    * Using any code contained herein in another mod requires credits / asking me.
--    * You may not fork this code and make your own competing version of this mod available for download without my permission.
-------------------------------------------------------------------------------------------------------------------------------

radio = {
    runtimeData = {
        inMenu = false,
        inGame = false,
        time = nil,
        hibernate = false,
        ts = nil
    },
    GameUI = require("modules/GameUI"),
    config = require("modules/config"),
    Cron = require("modules/Cron"),
    observers = require("modules/observers")
}

function radio:new()
    registerForEvent("onInit", function()
        self.radioManager = require("modules/radioManager"):new(self)
        local result = self.radioManager:loadRadios()

        if not result then
            print("[RadioMod] Could not find radiosInfo.json!")
        end

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
        if (not self.runtimeData.inMenu) and self.runtimeData.inGame and not self.runtimeData.hibernate then
            self.Cron.Update(delta)
            self.radioManager:update()
            self.radioManager:handleTS()
        elseif not self.runtimeData.hibernate then
            self.radioManager:handleMenu()
        elseif self.observers.input then -- Got wake up input
            self.Cron.Update(delta)
        end

        if self.runtimeData.time then
            if os.time() - self.runtimeData.time > 2 then -- PC came back from sleep
                self.runtimeData.hibernate = true -- Listen to any input to restart audio
            end
        end
        self.runtimeData.time = os.time()
    end)

    return self

end

return radio:new()