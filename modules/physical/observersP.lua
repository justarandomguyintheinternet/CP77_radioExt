-- Observers for physical radios

local observersP = {}

local function handleActionNotifier(controller, evt)
    local notifier = ActionNotifier.new()
    notifier:SetNone()
    if controller:IsDisabled() or controller:IsUnpowered() or not controller:IsON() then
        return EntityNotificationType.DoNotNotifyEntity
    end
    controller:Notify(notifier, evt)
    return EntityNotificationType.SendThisEventToEntity
end

function observersP.init(radioMod)
    -- 13 total vanilla stations, 4 is the first one
    Override("RadioControllerPS", "OnNextStation", function (this, evt, wrapped)
        if RadioStationDataProvider.GetRadioStationUIIndex(this.activeStation) > 12 or this.activeStation > 13 then
            this.previousStation = this.activeStation
            this.activeStation = math.max(RadioStationDataProvider.GetRadioStationUIIndex(this.activeStation), this.activeStation) + 1
            if this.activeStation > 13 + #radioMod.radioManager.radios then
                this.activeStation = 12
                return wrapped(evt)
            end

            return handleActionNotifier(this, evt)
        else
            return wrapped(evt)
        end
    end)

    Override("RadioControllerPS", "OnPreviousStation", function (this, evt, wrapped)
        if this.activeStation > 13 then
            this.previousStation = this.activeStation
            this.activeStation = this.activeStation - 1
            if this.activeStation < 14 then
                this.activeStation = 4
                return wrapped(evt)
            end

            return handleActionNotifier(this, evt)
        elseif this.activeStation == 4 then
            this.previousStation = this.activeStation
            this.activeStation = 13 + #radioMod.radioManager.radios
            return handleActionNotifier(this, evt)
        else
            return wrapped(evt)
        end
    end)

    Override("RadioControllerPS", "GameAttached", function (this)
        this.amountOfStations = 14 + #radioMod.radioManager.radios
        this.activeChannelName = RadioStationDataProvider.GetChannelName(this:GetActiveRadioStation())
        this:TryInitializeInteractiveState()
    end)

    Override("RadioControllerPS", "SetDefaultRadioStation", function (this)
        if not this.radioSetup.randomizeStartingStation then
            this.activeStation = this.radioSetup.startingStation
            return
        end
        this.activeStation = math.random(0, 13 + #radioMod.radioManager.radios)
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