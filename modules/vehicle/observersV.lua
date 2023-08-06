-- Observers for vehicle radio

local utils = require("modules/utils/utils")
local Cron = require("modules/utils/Cron")

local observersV = {
    radioUI = nil,
    input = false,
    customNotif = nil
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

    Override("VehicleRadioPopupGameController", "SetupData", function (this) -- Add stations to station list
        local sorted = observersV.getStations()
        local stations = {}

        stations[1] = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation")}) -- Add NoStation

        for _, v in pairs(sorted) do -- Get rid of nested table structure
            table.insert(stations, v.data)
        end

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
                end
            end

        end

        this.dataSource:Reset(stations)
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
        else
            radioMod.radioManager.managerV:disableCustomRadio()
        end
    end)

    Observe("ExitingEvents", "OnEnter", function () -- Normal car exiting
        Cron.After(0.5, function ()
            radioMod.radioManager.managerV:disableCustomRadio()
        end)
    end)

    Override("VehicleSummonWidgetGameController", "OnVehicleRadioEvent", function (this, evt) -- Radio info popup
        this:PlayAnim("OnSongChanged", "OnTimeOut")
        if IsDefined(this.playerVehicle) then
            this.rootWidget:SetVisible(true)
            inkWidgetRef.SetVisible(this.subText, true)
            inkWidgetRef.SetVisible(this.radioStationName, true)

            if observersV.customNotif then
                inkTextRef.SetText(this.radioStationName, observersV.customNotif.name)

                local path = observersV.customNotif.path
                if not observersV.customNotif.isStream then
                    path = utils.split(path, "\\")[2]
                    path = path:match("(.+)%..+$")
                end

                inkTextRef.SetText(this.subText, path)
            else
                inkTextRef.SetText(this.radioStationName, GetLocalizedTextByKey(this.playerVehicle:GetRadioReceiverStationName()))
                inkTextRef.SetText(this.subText, GetLocalizedTextByKey(this.playerVehicle:GetRadioReceiverTrackName()))
            end
        end

        observersV.customNotif = nil
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
                    observersV.customNotif = {name = nextCustom.name, path = nextCustom.currentSong.path, isStream = nextCustom.metadata.streamInfo.isStream}
                else
                    radioMod.radioManager.managerV:disableCustomRadio()
                    this:GetVehicle():SetRadioReceiverStation(stations[next].record:Index())
                end

                this.vehicleBlackboard:SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, this:GetVehicle():GetRadioReceiverStationName())
                Game.GetUISystem():QueueEvent(uiRadioEvent)
            end
        else
            wrapped(evt)
        end
    end)
end

return observersV