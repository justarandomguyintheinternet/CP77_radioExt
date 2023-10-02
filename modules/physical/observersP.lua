-- Observers for physical radios

local observersP = {}

function observersP.init(radioMod)
    Override("RadioControllerPS", "GameAttached", function (this)
        this.amountOfStations = 14 + #radioMod.radioManager.radios
        this.activeChannelName = RadioStationDataProvider.GetChannelName(this:GetActiveRadioStation())
        this:TryInitializeInteractiveState()
    end)

    Observe("Radio", "PlayGivenStation", function (this)
        local active = this:GetDevicePS():GetActiveStationIndex()

        if active > 13 then
            local radio = radioMod.radioManager.radios[active - 13]

            GameObject.AudioSwitch(this, "radio_station", "station_none", "radio")
            local object = radioMod.radioManager.managerP:getObjectByHandle(this)
            if object then
                object:switchToRadio(radio)
            else
                radioMod.radioManager.managerP:createObject(this, radio)
            end
        else
            radioMod.radioManager.managerP:removeObjectByHandle(this)
        end
    end)

    Observe("Radio", "TurnOffDevice", function (this)
        radioMod.radioManager.managerP:removeObjectByHandle(this)
    end)

    Observe("Radio", "CutPower", function (this)
        radioMod.radioManager.managerP:removeObjectByHandle(this)
    end)

    Observe("Radio", "DeactivateDevice", function (this)
        radioMod.radioManager.managerP:removeObjectByHandle(this)
    end)

    ObserveBefore("Radio", "OnDetach", function (this)
        radioMod.radioManager.managerP:removeObjectByHandle(this)
    end)

    Override("RadioInkGameController", "SetupStationLogo", function (this, wrapped)
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()

        if active > 13 then
            local radio = radioMod.radioManager.radios[active - 13]

            local iconRecord = TweakDBInterface.GetUIIconRecord(radio.icon)
            inkImageRef.SetAtlasResource(this.stationLogoWidget, iconRecord:AtlasResourcePath())
            inkImageRef.SetTexturePart(this.stationLogoWidget, iconRecord:AtlasPartName())
        else
            inkImageRef.SetAtlasResource(this.stationLogoWidget, ResRef.FromName("base\\gameplay\\gui\\common\\icons\\radiostations_icons.inkatlas"))
            wrapped()
        end
    end)

    ObserveAfter("RadioInkGameController", "TurnOn", function (this)
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()
        if active < 14 then
            return
        end

        local radio = radioMod.radioManager.radios[active - 13]
        if radio then
            inkTextRef.SetText(this.stationNameWidget, radio.name)
        end
    end)
end

return observersP