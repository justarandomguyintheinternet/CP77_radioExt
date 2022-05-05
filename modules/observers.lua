local utils = require("modules/utils")
local Cron = require("modules/Cron")
local audioEnine = require("modules/audioEngine")

observers = {
    radioUI = nil,
    input = false,
    customNotif = nil
}

function observers.getStations() -- Return sorted list of all stations {fm, radioRecord}
    local stations = VehiclesManagerDataHelper.GetRadioStations(GetPlayer())
    stations[1] = nil -- Get rid of the NoStation

    local sorted = {}

    for _, v in pairs(stations) do -- Store in temp table for sorting by fm number
        local fm = GetLocalizedText(v.record:DisplayName())
        sorted[#sorted + 1] = {data = v, fm = tonumber(utils.split(fm, " ")[1])}
    end

    for _, radio in pairs(observers.radioMod.radioManager.radios) do -- Add custom radios
        sorted[#sorted + 1] = {data = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord(radio.tdbName)}), fm = tonumber(radio.fm)}
    end

    table.sort(sorted, function (a, b) -- Sort
        return a.fm < b.fm
    end)

    return sorted
end

function observers.init(radioMod)
    observers.radioMod = radioMod

    Observe('PlayerPuppet', 'OnAction', function()
        if radioMod.runtimeData.hibernate and not observers.input then -- Restart when PC was sleeping
            observers.input = true
            audioEnine.resetEngine()

            Cron.After(0.1, function ()
                radioMod.radioManager:handleMenu()
                radioMod.runtimeData.hibernate = false
                observers.input = false
            end)
        end
    end)

    Override("VehicleRadioPopupGameController", "SetupData", function (this) -- Add stations to station list
        local sorted = observers.getStations()
        local stations = {}

        stations[1] = RadioListItemData.new({record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation")}) -- Add NoStation

        for _, v in pairs(sorted) do -- Get rid of nested table structure
            table.insert(stations, v.data)
        end

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

        this.dataSource:Reset(stations)
    end)

    ObserveAfter("VehicleRadioPopupGameController", "Activate", function (this) -- Select radio station
        local name = this.selectedItem:GetStationData().record:DisplayName()
        local radio = radioMod.radioManager:getRadioByName(name)

        if name == "LocKey#705" then -- No station
            GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetLocalizedText(name))
        end

        if radio then
            radioMod.radioManager:switchToRadio(radio)
            this.quickSlotsManager:SendRadioEvent(false, false, -1)
        else
            radioMod.radioManager:disableCustomRadio()
        end
    end)

    Observe("ExitingEvents", "OnEnter", function () -- Normal car exiting
        Cron.After(0.5, function ()
            radioMod.radioManager:disableCustomRadio()
        end)
    end)

    Override("VehicleSummonWidgetGameController", "OnVehicleRadioEvent", function (this, evt) -- Radio info popup
        this:PlayAnim("OnSongChanged", "OnTimeOut")
        if IsDefined(this.playerVehicle) then
            this.rootWidget:SetVisible(true)
            inkWidgetRef.SetVisible(this.subText, true)
            inkWidgetRef.SetVisible(this.radioStationName, true)

            if observers.customNotif then
                inkTextRef.SetText(this.radioStationName, observers.customNotif.name)

                local path = observers.customNotif.path
                path = utils.split(path, "\\")[2]
                path = path:match("(.+)%..+$")

                inkTextRef.SetText(this.subText, path)
            else
                inkTextRef.SetText(this.radioStationName, GetLocalizedTextByKey(this.playerVehicle:GetRadioReceiverStationName()))
                inkTextRef.SetText(this.subText, GetLocalizedTextByKey(this.playerVehicle:GetRadioReceiverTrackName()))
            end
        end

        observers.customNotif = nil
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
                local sorted = observers.getStations()
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
                        radioMod.radioManager:switchToRadio(nextCustom)
                    else
                        radioMod.radioManager:switchToRadio(nextCustom)
                        GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
                    end
                    observers.customNotif = {name = nextCustom.name, path = nextCustom.currentSong.path}
                else
                    radioMod.radioManager:disableCustomRadio()
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

return observers