-- Observers for vehicle radio

local utils = require("modules/utils/utils")
local Cron = require("modules/utils/Cron")

local observersV = {
    input = false
}

local function getNextStationIndex(currentStation)
    -- Convert vanilla station to UI index (Same as what is stored in station record)
    if currentStation < 14 and currentStation ~= -1 then
        currentStation = RadioStationDataProvider.GetRadioStationUIIndex(currentStation)
    end

    -- Figure out index of station in list of stations
    local cIndex = 0
    for index, station in pairs(VehiclesManagerDataHelper.GetRadioStations(GetPlayer())) do
        if station.record:Index() == currentStation then
            cIndex = index
        end
    end

    local nextStation = cIndex + 1
    if nextStation > #VehiclesManagerDataHelper.GetRadioStations(GetPlayer()) then
        nextStation = 2
    end

    nextStation = VehiclesManagerDataHelper.GetRadioStations(GetPlayer())[nextStation].record:Index()

    if nextStation < 14 then
        nextStation = EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(nextStation))
    end

    return nextStation
end

function observersV.init(radioMod)
    observersV.radioMod = radioMod

    Override("VehiclesManagerDataHelper", "GetRadioStations;GameObject", function (player, wrapped)
        radioMod.logger.log("VehiclesManagerDataHelper::GetRadioStations")
        local stations = wrapped(player)
        stations[1] = nil -- Get rid of the NoStation

        local sorted = {}

        for _, v in pairs(stations) do -- Store in temp table for sorting by fm number
            local fm = string.gsub(GetLocalizedText(v.record:DisplayName()), ",", ".")

            local split = utils.split(fm, " ")
            if tonumber(split[1]) then
                fm = tonumber(split[1])
            else
                fm = tonumber(split[#split])
            end

            if GetLocalizedText(v.record:DisplayName()) == "Enable Aux Radio" then fm = 0 end

            sorted[#sorted + 1] = { data = v, fm = fm }
        end

        for _, radio in pairs(observersV.radioMod.radioManager.radios) do -- Add custom radios
            sorted[#sorted + 1] = { data = RadioListItemData.new({ record = TweakDBInterface.GetRadioStationRecord(radio.tdbName) }), fm = tonumber(radio.fm)}
        end

        table.sort(sorted, function (a, b) -- Sort
            return a.fm < b.fm
        end)

        local stations = {}
        stations[1] = RadioListItemData.new({ record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation") }) -- Add NoStation

        for _, v in pairs(sorted) do -- Get rid of nested table structure
            table.insert(stations, v.data)
        end

        return stations
    end)

    -- For custom: Turns of vehicle radio, sets station for pocket radio
    Override("QuickSlotsManager", "SendRadioEvent", function (this, toggle, setStation, station, wrapped)
        radioMod.logger.log("QuickSlotsManager::SendRadioEvent")
        if station > 13 then
            if GetMountedVehicle(GetPlayer()) then
                this.Player:QueueEventForEntityID(this.PlayerVehicleID, VehicleRadioEvent.new({ toggle = false, setStation = false, station = -1 })) -- Goes to the vehicle radio if there is any, disabling it
            end
            if not GetMountedVehicle(GetPlayer()) or GetPlayer():GetPocketRadio().settings:GetSyncToCarRadio() then
                this.Player:QueueEvent(VehicleRadioEvent.new({ toggle = toggle, setStation = setStation, station = station })) -- Goes to PocketRadio::HandleVehicleRadioEvent
            end

            Cron.After(0.1, function ()
                if GetMountedVehicle(GetPlayer()) then
                    GetMountedVehicle(GetPlayer()):GetVehicleComponent().radioState = true
                    GetMountedVehicle(GetPlayer()):GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
                end
            end)
        else
            wrapped(toggle, setStation, station)
        end
    end)

    -- Used by PocketRadio when exiting a car, to transfer playback
    Override("VehicleObject", "WasRadioReceiverPlaying", function (_, wrapped)
        radioMod.logger.log("VehicleObject::WasRadioReceiverPlaying")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if not activeVRadio then
            return wrapped()
        else
            return true
        end
    end)

    -- Used by PocketRadio when exiting a car, to transfer playback
    Override("VehicleObject", "GetCurrentRadioIndex", function (_, wrapped)
        radioMod.logger.log("VehicleObject::GetCurrentRadioIndex")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if not activeVRadio then
            return wrapped()
        else
            return activeVRadio.index
        end
    end)

    -- Selecting a radio from the radiolist
    Override("VehicleRadioPopupGameController", "Activate", function (this, wrapped)
        radioMod.logger.log("VehicleRadioPopupGameController::Activate")
        local name = this.selectedItem:GetStationData().record:DisplayName()
        local radio = radioMod.radioManager:getRadioByName(name)

        if radio then
            radioMod.radioManager.managerV:switchToRadio(radio)
            GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, radio.index)

            Cron.After(0.1, function ()
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
            end)
        else
            if name == "LocKey#705" and GetMountedVehicle(GetPlayer()) then -- No station
                GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetLocalizedText(name))
            end

            radioMod.radioManager.managerV:disableCustomRadio()
            wrapped()
        end
    end)

    -- Toggle shortcut for when in a vehicle
    Override("VehicleComponent", "OnRadioToggleEvent", function (this, evt, wrapped)
        radioMod.logger.log("VehicleComponent::OnRadioToggleEvent")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if activeVRadio then -- Toggle off
            radioMod.radioManager.managerV:disableCustomRadio()
            this.vehicleBlackboard:SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
            this:GetVehicle():ToggleRadioReceiver(false)
            return
        else
            local name = GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName) -- Get current radio name

            if GetLocalizedTextByKey(name) ~= "" then
                name = GetLocalizedTextByKey(name)
            else
                name = name.value
            end
            local cRadio = radioMod.radioManager:getRadioByName(name)

            if cRadio then -- Toggle on, last radio was a custom one
                radioMod.radioManager.managerV:switchToRadio(cRadio)
                Cron.After(0.1, function ()
                    Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                end)
            else
                wrapped(evt)
            end
        end
    end)

    -- The event for this seems to come from engine side, always wants to set the last native station that it had, so this is needed to avoid the station getting set to some native one everytime a vehicle is entered
    Override("PocketRadio", "HandleVehicleRadioStationChanged", function (this, evt, wrapped)
        if this.settings:GetSyncToCarRadio() then
            local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
            evt.radioIndex = activeVRadio.index
        end
        radioMod.logger.log("PocketRadio::HandleVehicleRadioStationChanged" .. tostring(evt.radioIndex))
        wrapped(evt)
    end)

    -- For the RadioHotkey
    Override("PocketRadio", "IsActive", function (_, wrapped)
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        radioMod.logger.log("PocketRadio::IsActive " .. tostring(activeVRadio ~= nil))

        if activeVRadio then return true end
        return wrapped()
    end)

    -- Fix list start/selected index
    ObserveAfter("VehicleRadioPopupGameController", "SetupData", function (this)
        radioMod.logger.log("VehicleRadioPopupGameController::SetupData")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if not activeVRadio then return end

        for i = 0, this.dataSource:GetArraySize() - 1 do
            local stationRecord = this.dataSource:GetItem(i).record
            if IsDefined(stationRecord) then
                if stationRecord:Index() == activeVRadio.index then
                    this.startupIndex = i
                    this.currentRadioId = activeVRadio.index
                end
            end
        end
    end)

    -- Fix equalizer icon in radio list
    ObserveAfter("RadioStationListItemController", "UpdateEquializer", function (this)
        radioMod.logger.log("RadioStationListItemController::UpdateEquializer")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        if not activeVRadio then return end

        if this.stationData.record:DisplayName() == activeVRadio.station then
            this.equilizerIcon:SetVisible(true)
            this.codeTLicon:SetVisible(false)
        else
            this.equilizerIcon:SetVisible(false)
            this.codeTLicon:SetVisible(true)
        end
    end)

    -- Radio popup track name
    ObserveAfter("VehicleRadioPopupGameController", "SetTrackName", function (this)
        radioMod.logger.log("VehicleRadioPopupGameController::SetTrackName")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        if not activeVRadio then return end

        local path = activeVRadio.track
        if not activeVRadio.isStream then
            path = utils.split(path, "\\")[2]
            path = path:match("(.+)%..+$")
        end

        this.trackName:SetText(path)
        this.trackName:SetVisible(true)
    end)

    -- TODO: Make this properly change the station, also for custom ones
    Observe("VehicleObject", "NextRadioReceiverStation", function (this, wrapped)
        radioMod.logger.log("VehicleObject::NextRadioReceiverStation")
        radioMod.radioManager.managerV:disableCustomRadio()
    end)

    -- Handle radio station cycle hotkey, while on foot
    Override("PocketRadio", "HandleRadioToggleEvent", function (this, evt, wrapped)
        radioMod.logger.log("PocketRadio::HandleRadioToggleEvent")
        if not this.settings:GetCycleButtonPress() then return wrapped(evt) end

        local nextStation = getNextStationIndex(this.station)

        this.selectedStation = nextStation
        this.station = this.selectedStation
        if this.isOn then
            local cycleEvent = UIVehicleRadioCycleEvent.new()
            Game.GetUISystem():QueueEvent(cycleEvent)
        end

        this:TurnOn(true)
    end)

    Observe("PocketRadio", "TurnOn", function (this)
        radioMod.logger.log("PocketRadio::TurnOn")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        local radio = radioMod.radioManager:getRadioByIndex(this.station)

        if not GetMountedVehicle(GetPlayer()) and radio then --and (not activeVRadio)
            radioMod.radioManager.managerV:switchToRadio(radio)
        elseif not radio then
            radioMod.radioManager.managerV:disableCustomRadio()
        end
    end)

    ObserveAfter("PocketRadio", "TurnOff", function ()
        radioMod.logger.log("PocketRadio::TurnOff")

        if GetMountedVehicle(GetPlayer()) then return end

        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        if not activeVRadio then return end
        radioMod.radioManager.managerV:disableCustomRadio()
    end)

    Observe("EnteringEvents", "OnEnter", function ()
        radioMod.logger.log("EnteringEvents::OnEnter")
        local cRadio = radioMod.radioManager.managerV:getActiveStationData()

        if cRadio then
            local radio = radioMod.radioManager:getRadioByIndex(cRadio.index)
            Cron.After(0.1, function ()
                GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, cRadio.index)
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                radioMod.radioManager.managerV:switchToRadio(radio)
            end)
            Cron.After(0.5, function ()
                GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, cRadio.station)
                GetMountedVehicle(GetPlayer()):GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
            end)
            radioMod.radioManager:updateVRadioVolume()
        else
            Cron.After(0.5, function ()
                if GetPlayer():GetPocketRadio().isOn then
                    GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetPlayer():GetPocketRadio():GetStationName())
                end
            end)
        end
    end)

    -- Needed to turn radio off
    ObserveAfter("PocketRadio", "HandleVehicleUnmounted", function (this)
        radioMod.logger.log("PocketRadio::HandleVehicleUnmounted")

        -- Needs to wait for one frame, otherwise player would still be mounted
        Cron.NextTick(function ()
            radioMod.radioManager:updateVRadioVolume()
        end)

        if (not this.settings:GetSyncToCarRadio()) and (not GetPlayer():GetPocketRadio().isOn) then
            this:TurnOff(true)
        end
    end)

    ObserveAfter("VehicleSummonWidgetGameController", "TryShowVehicleRadioNotification", function (this) -- Radio info popup
        radioMod.logger.log("VehicleSummonWidgetGameController::TryShowVehicleRadioNotification")
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        if not activeVRadio then return end

        this:PlayAnimation("OnSongChanged", inkAnimOptions.new(), "OnTimeOut")
        local dpadAction = DPADActionPerformed.new()
        dpadAction.action = EHotkey.DPAD_RIGHT
        dpadAction.state = EUIActionState.COMPLETED
        this:QueueEvent(dpadAction)

        this.rootWidget:SetVisible(true)
        inkWidgetRef.SetVisible(this.subText, true)
        inkWidgetRef.SetVisible(this.radioStationName, true)

        inkTextRef.SetText(this.radioStationName, activeVRadio.station)

        local path = activeVRadio.track
        if not activeVRadio.isStream then
            path = utils.split(path, "\\")[2]
            path = path:match("(.+)%..+$")
        end

        inkTextRef.SetText(this.subText, path)
    end)

    Observe("RadioVolumeSettingsController", "ChangeValue", function ()
        radioMod.logger.log("RadioVolumeSettingsController::ChangeValue")
        radioMod.radioManager:updateVRadioVolume()
    end)
end

return observersV