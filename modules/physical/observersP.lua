-- Observers for physical radios

local observersP = {}

local function canRespondToAction(controller)
    return not (controller:IsDisabled() or controller:IsUnpowered() or not controller:IsON())
end

local function handleActionNotifier(controller, evt)
    local notifier = ActionNotifier.new()
    notifier:SetNone()
    controller:Notify(notifier, evt)
    return EntityNotificationType.SendThisEventToEntity
end

function observersP.init(radioMod)
    Override("RadioControllerPS", "OnNextStation", function (this, evt, wrapped)
        if not canRespondToAction(this) then
            return EntityNotificationType.DoNotNotifyEntity
        end

        local lastVanillaStationIndex = radioMod.radioManager:getLastVanillaStationIndex()
        local firstCustomStationIndex = radioMod.radioManager:getFirstCustomStationIndex()

        if RadioStationDataProvider.GetRadioStationUIIndex(this.activeStation) >= lastVanillaStationIndex or this.activeStation >= firstCustomStationIndex then
            this.previousStation = this.activeStation
            this.activeStation = math.max(RadioStationDataProvider.GetRadioStationUIIndex(this.activeStation), this.activeStation) + 1
            if this.activeStation > radioMod.radioManager:getLastCustomStationIndex() then
                this.activeStation = EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(lastVanillaStationIndex))
                return wrapped(evt)
            end

            return handleActionNotifier(this, evt)
        else
            return wrapped(evt)
        end
    end)

    Override("RadioControllerPS", "OnPreviousStation", function (this, evt, wrapped)
        if not canRespondToAction(this) then
            return EntityNotificationType.DoNotNotifyEntity
        end

        if #radioMod.radioManager.radios == 0 then
            return wrapped(evt)
        end

        local firstCustomStationIndex = radioMod.radioManager:getFirstCustomStationIndex()

        if this.activeStation >= firstCustomStationIndex then
            this.previousStation = this.activeStation
            this.activeStation = this.activeStation - 1
            if this.activeStation < firstCustomStationIndex then
                this.activeStation = EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(0))
                return wrapped(evt)
            end

            return handleActionNotifier(this, evt)
        elseif this.activeStation == EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(0)) then
            this.previousStation = this.activeStation
            this.activeStation = radioMod.radioManager:getLastCustomStationIndex()
            return handleActionNotifier(this, evt)
        else
            return wrapped(evt)
        end
    end)

    Observe("Radio", "PlayGivenStation", function (this)
        local active = this:GetDevicePS():GetActiveStationIndex()
        local radio = radioMod.radioManager:getRadioByIndex(active)

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
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()
        local radio = radioMod.radioManager:getRadioByIndex(active)

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
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()
        local radio = radioMod.radioManager:getRadioByIndex(active)
        if radio then
            inkTextRef.SetText(this.stationNameWidget, radio.name)
        end
    end)
end

return observersP
