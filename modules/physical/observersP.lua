-- Observers for physical radios

local observersP = {}

function observersV.init(radioMod)
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
            -- Stop playback
            -- check if radioObject exists with this handle
            -- Change playpack of the one with this handle to the new station
            -- Create new object with this handle and start playback
        else
            -- Check if radio with this handle existst
            -- If yes then remove object
        end
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

return observersV