-- Observers for physical radios

local observersP = {}

function observersP.init(radioMod)
    Override("RadioControllerPS", "InitializeRadioStations", function (this, wrapped)
        if this.stationsInitialized then return end
        wrapped()

        local stations = this.stations

        for _, radio in pairs(radioMod.radioManager.radios) do
            local map = RadioStationsMap.new()
            map.channelName = radio.name -- Name
            map.stationID = ERadioStationList.NONE
            table.insert(stations, map)
        end

        this.stations = stations
    end)

    Observe("Radio", "PlayGivenStation", function (this)
        local map = this:GetDevicePS():GetStationByIndex(this:GetDevicePS():GetActiveStationIndex())
        local radio = radioMod.radioManager:getRadioByName(map.channelName)

        if radio then
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
        local PS = this:GetOwner():GetDevicePS()
        local map = PS:GetStationByIndex(PS:GetActiveStationIndex())
        local radio = radioMod.radioManager:getRadioByName(map.channelName)
        if radio then
            local iconRecord = TweakDBInterface.GetUIIconRecord(radio.icon)
            inkImageRef.SetAtlasResource(this.stationLogoWidget, iconRecord:AtlasResourcePath())
            inkImageRef.SetTexturePart(this.stationLogoWidget, iconRecord:AtlasPartName())
        else
            inkImageRef.SetAtlasResource(this.stationLogoWidget, ResRef.FromName("base\\gameplay\\gui\\common\\icons\\radiostations_icons.inkatlas"))
            wrapped()
        end
    end)

    ObserveAfter("RadioInkGameController", "TurnOn", function (this)
        local PS = this:GetOwner():GetDevicePS()
        local map = PS:GetStationByIndex(PS:GetActiveStationIndex())
        local radio = radioMod.radioManager:getRadioByName(map.channelName)
        if radio then
            inkTextRef.SetText(this.stationNameWidget, radio.name)
        end
    end)
end

return observersP