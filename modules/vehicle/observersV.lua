-- Observers for vehicle radio

local utils = require("modules/utils/utils")
local Cron = require("modules/utils/Cron")

local observersV = {
    input = false
}

function observersV.getStations() -- Return sorted list of all stations {fm, radioRecord}
    local stations = VehiclesManagerDataHelper.GetRadioStations(GetPlayer())
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

    return sorted
end

function observersV.init(radioMod)
    observersV.radioMod = radioMod

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

    Override("VehicleRadioPopupGameController", "SetupData", function (this) -- Add stations to station list
        local sorted = observersV.getStations()
        local stations = {}

        stations[1] = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation")}) -- Add NoStation

        for _, v in pairs(sorted) do -- Get rid of nested table structure
            table.insert(stations, v.data)
        end

        this.dataSource:Reset(stations)
        this.startupIndex = 0
        this.currentRadioId = -1 -- Fallback if no match is found

        if GetMountedVehicle(GetPlayer()) then
            local name = GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
            if GetLocalizedTextByKey(name) ~= "" then
                name = GetLocalizedTextByKey(name)
            else
                name = name.value
            end

            for k, v in pairs(stations) do
                if GetLocalizedText(v.record:DisplayName()) == name then
                    this.startupIndex = k - 1
                    this.currentRadioId = k - 1
                end
            end
        end
    end)

    ObserveAfter("VehicleRadioPopupGameController", "Activate", function (this) -- Select radio station
        local name = this.selectedItem:GetStationData().record:DisplayName()
        local radio = radioMod.radioManager:getRadioByName(name)

        if name == "LocKey#705" then -- No station
            GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetLocalizedText(name))
        end

        if radio then
            radioMod.radioManager.managerV:switchToRadio(radio)
            this.quickSlotsManager:SendRadioEvent(false, false, -1)

            Cron.After(0.1, function ()
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
            end)
        else
            radioMod.radioManager.managerV:disableCustomRadio()
        end
    end)

    Observe("ExitingEvents", "OnEnter", function () -- Normal car exiting
        Cron.After(0.5, function ()
            radioMod.radioManager.managerV:disableCustomRadio()
        end)
    end)

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

    Override("VehicleComponent", "OnVehicleRadioEvent", function (this, evt, wrapped) -- Handle radio shortcut press
        if evt.toggle and not evt.setStation then
            local uiRadioEvent = UIVehicleRadioEvent.new()

            local name = GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName) -- Get current radio name
            if GetLocalizedTextByKey(name) ~= "" then
                name = GetLocalizedTextByKey(name)
            else
                name = name.value
            end

            local cRadio = radioMod.radioManager:getRadioByName(name)

            if not this.radioState and not cRadio then -- Gets turned on, vanila behavior
                this:GetVehicle():ToggleRadioReceiver(true)
                this.radioState = true
                this.vehicleBlackboard:SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
                this.vehicleBlackboard:SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, this:GetVehicle():GetRadioReceiverStationName())
                Game.GetUISystem():QueueEvent(uiRadioEvent)
            else
                local sorted = observersV.getStations()
                local stations = {}
                for _, v in pairs(sorted) do -- Get rid of nested table structure
                    table.insert(stations, v.data)
                end

                local next
                for k, v in pairs(stations) do
                    if GetLocalizedText(v.record:DisplayName()) == name then
                        next = k + 1
                        if next > #stations then next = 1 end -- Get next station index
                    end
                end

                local nextCustom = radioMod.radioManager:getRadioByName(GetLocalizedText(stations[next].record:DisplayName()))
                if nextCustom then -- Next station is custom
                    if cRadio then -- Previous was also custom
                        radioMod.radioManager.managerV:switchToRadio(nextCustom)
                    else
                        radioMod.radioManager.managerV:switchToRadio(nextCustom)
                        GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
                    end
                else
                    radioMod.radioManager.managerV:disableCustomRadio()
                    this:GetVehicle():SetRadioReceiverStation(stations[next].record:Index())
                end

                this.vehicleBlackboard:SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, this:GetVehicle():GetRadioReceiverStationName())
                Game.GetUISystem():QueueEvent(uiRadioEvent)

                -- Delayed as it wont register otherwise?
                Cron.After(0.1, function ()
                    Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                end)
            end
        else
            wrapped(evt)
        end
    end)
end

return observersV