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

    Override("VehicleRadioPopupGameController", "Activate", function (this, wrapped) -- Select radio station
        local name = this.selectedItem:GetStationData().record:DisplayName()
        local radio = radioMod.radioManager:getRadioByName(name)

        if radio then
            this.quickSlotsManager:SendRadioEvent(false, false, -1)
            radioMod.radioManager.managerV:switchToRadio(radio)
            GetPlayer():GetPocketRadio().isOn = true

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

    Override("VehicleComponent", "OnRadioToggleEvent", function (this, evt, wrapped)
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if activeVRadio then
            radioMod.radioManager.managerV:disableCustomRadio()
            this.vehicleBlackboard:SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
            this:GetVehicle():ToggleRadioReceiver(false)
            GetPlayer():GetPocketRadio().isOn = true -- This makes LITERALLY NO FUCKING SENSE

            return
        else
            local name = GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName) -- Get current radio name

            if GetLocalizedTextByKey(name) ~= "" then
                name = GetLocalizedTextByKey(name)
            else
                name = name.value
            end
            local cRadio = radioMod.radioManager:getRadioByName(name)

            if cRadio then
                radioMod.radioManager.managerV:switchToRadio(cRadio)
                GetPlayer():GetPocketRadio().isOn = false
                Cron.After(0.1, function ()
                    Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                end)
            else
                wrapped(evt)
            end
        end
    end)

    Override("PocketRadio", "IsActive", function (_, wrapped)
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()
        if activeVRadio then return true end
        return wrapped()
    end)

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

    Override("PocketRadio", "HandleRadioToggleEvent", function (this, evt, wrapped)
        local activeVRadio = radioMod.radioManager.managerV:getActiveStationData()

        if activeVRadio then
            radioMod.radioManager.managerV:disableCustomRadio()
            this.isOn = false -- This makes LITERALLY NO FUCKING SENSE
            this.station = activeVRadio.index
            return
        else
            local cRadio = radioMod.radioManager:getRadioByIndex(this.station)

            if cRadio then
                this.isOn = true

                if not GetMountedVehicle(GetPlayer()) then
                    radioMod.radioManager.managerV:switchToRadio(cRadio)
                    Cron.After(0.1, function ()
                        Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                    end)
                end
            else
                wrapped(evt)
            end
        end
    end)

    Observe("EnteringEvents", "OnEnter", function () -- Normal car exiting
        local cRadio = radioMod.radioManager.managerV:getActiveStationData()

        if cRadio then
            GetPlayer():GetPocketRadio().isOn = true

            Cron.After(0.1, function ()
                GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
            end)
            Cron.After(0.5, function ()
                GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, cRadio.station)
                GetMountedVehicle(GetPlayer()):GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
            end)
        else
            Cron.After(0.5, function ()
                if GetPlayer():GetPocketRadio().isOn then
                    GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetPlayer():GetPocketRadio():GetStationName())
                end
            end)
        end
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

    Observe("RadioVolumeSettingsController", "ChangeValue", function ()
        radioMod.radioManager:updateVRadioVolume()
    end)
end

return observersV