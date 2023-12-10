-- Observers for vehicle radio

local utils = require("modules/utils/utils")
local Cron = require("modules/utils/Cron")

local observersV = {
    input = false
}

function observersV.init(radioMod)
    observersV.radioMod = radioMod

    Override("VehiclesManagerDataHelper", "GetRadioStations;GameObject", function (player, wrapped)
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

            sorted[#sorted + 1] = {data = v, fm = fm}
        end

        for _, radio in pairs(observersV.radioMod.radioManager.radios) do -- Add custom radios
            sorted[#sorted + 1] = {data = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord(radio.tdbName)}), fm = tonumber(radio.fm)}
        end

        table.sort(sorted, function (a, b) -- Sort
            return a.fm < b.fm
        end)

        local stations = {}
        stations[1] = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation")}) -- Add NoStation

        for _, v in pairs(sorted) do -- Get rid of nested table structure
            table.insert(stations, v.data)
        end

        return stations
    end)

    -- Override("QuickSlotsManager", "SendRadioEvent", function (this, toggle, setStation, stationIndex, wrapped)
    --     print("send", stationIndex)
    --     local vehRadioEvent = VehicleRadioEvent.new()
    --     vehRadioEvent.toggle = toggle
    --     vehRadioEvent.setStation = setStation
    --     vehRadioEvent.station = -1
    --     if stationIndex >= 0 then
    --         if stationIndex > 13 then
    --             vehRadioEvent.station = stationIndex
    --         else
    --             vehRadioEvent.station = EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(stationIndex))
    --         end
    --     end
    --     if this.IsPlayerInCar then
    --         this.Player:QueueEventForEntityID(this.PlayerVehicleID, vehRadioEvent)
    --     end
    --     this.Player:QueueEvent(vehRadioEvent)
    -- end)

    -- Override("VehicleComponent", "OnVehicleRadioEvent", function (this, evt, wrapped)
    --     print("radioEve")
    --     if evt.station > 13 then
    --         local station = radioMod.radioManager:getRadioByIndex(evt.station)
    --         radioMod.radioManager.managerV:switchToRadio(station)
    --         GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
    --     else
    --         radioMod.radioManager.managerV:disableCustomRadio()
    --         wrapped(evt)
    --     end
    -- end)

    Override("")

    ObserveAfter("VehicleRadioPopupGameController", "SetupData", function (this)
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

    ObserveAfter("RadioStationListItemController", "UpdateEquializer", function (this)
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

    ObserveAfter("VehicleRadioPopupGameController", "SetTrackName", function (this) -- Radio popup track name
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

    -- Observe("PocketRadio", "HandleVehicleRadioEvent", function (this, evt)
    --     if evt.station > 13 then
    --         Game.GetAudioSystem():Play("dev_pocket_radio_off", this.player:GetEntityID(), "pocket_radio_emitter")
    --         local station = radioMod.radioManager:getRadioByIndex(evt.station)
    --         radioMod.radioManager.managerV:switchToRadio(station)
    --     else
    --         radioMod.radioManager.managerV:disableCustomRadio()
    --     end
    -- end)

    -- Override("PocketRadio", "HandleVehicleUnmounted", function (this, vehicle, wrapped)
    --     if this.station < 13 then
    --         wrapped(vehicle)
    --     end
    --     print(this.station, this.selectedStation)
    -- end)

    -- Observe("ExitingEvents", "OnEnter", function () -- Normal car exiting
    --     Cron.After(0.5, function ()
    --         radioMod.radioManager.managerV:disableCustomRadio()
    --     end)
    -- end)

    ObserveAfter("VehicleSummonWidgetGameController", "TryShowVehicleRadioNotification", function (this) -- Radio info popup
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

    -- Override("VehicleComponent", "OnVehicleRadioEvent", function (this, evt, wrapped) -- Handle radio shortcut press
    --     if evt.toggle and not evt.setStation then
    --         local uiRadioEvent = UIVehicleRadioEvent.new()

    --         local name = GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName) -- Get current radio name
    --         if GetLocalizedTextByKey(name) ~= "" then
    --             name = GetLocalizedTextByKey(name)
    --         else
    --             name = name.value
    --         end

    --         local cRadio = radioMod.radioManager:getRadioByName(name)

    --         if not this.radioState and not cRadio then -- Gets turned on, vanila behavior
    --             this:GetVehicle():ToggleRadioReceiver(true)
    --             this.radioState = true
    --             this.vehicleBlackboard:SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
    --             this.vehicleBlackboard:SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, this:GetVehicle():GetRadioReceiverStationName())
    --             Game.GetUISystem():QueueEvent(uiRadioEvent)
    --         else
    --             local sorted = observersV.getStations()
    --             local stations = {}
    --             for _, v in pairs(sorted) do -- Get rid of nested table structure
    --                 table.insert(stations, v.data)
    --             end

    --             local next
    --             for k, v in pairs(stations) do
    --                 if GetLocalizedText(v.record:DisplayName()) == name then
    --                     next = k + 1
    --                     if next > #stations then next = 1 end -- Get next station index
    --                 end
    --             end

    --             local nextCustom = radioMod.radioManager:getRadioByName(GetLocalizedText(stations[next].record:DisplayName()))
    --             if nextCustom then -- Next station is custom
    --                 if cRadio then -- Previous was also custom
    --                     radioMod.radioManager.managerV:switchToRadio(nextCustom)
    --                 else
    --                     radioMod.radioManager.managerV:switchToRadio(nextCustom)
    --                     GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
    --                 end
    --             else
    --                 radioMod.radioManager.managerV:disableCustomRadio()
    --                 this:GetVehicle():SetRadioReceiverStation(stations[next].record:Index())
    --             end

    --             this.vehicleBlackboard:SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, this:GetVehicle():GetRadioReceiverStationName())
    --             Game.GetUISystem():QueueEvent(uiRadioEvent)

    --             -- Delayed as it wont register otherwise?
    --             Cron.After(0.1, function ()
    --                 Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
    --             end)
    --         end
    --     else
    --         wrapped(evt)
    --     end
    -- end)

    Observe("RadioVolumeSettingsController", "ChangeValue", function ()
        radioMod.radioManager:updateVRadioVolume()
    end)
end

return observersV