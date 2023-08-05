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

function observersV.initRadioP(radioMod) -- Physical radio observersV
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

function observersV.init(radioMod)
    observersV.radioMod = radioMod

    observersV.initRadioP(radioMod)

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
                        radioMod.radioManager:switchToRadio(nextCustom)
                    else
                        radioMod.radioManager:switchToRadio(nextCustom)
                        GetPlayer():GetQuickSlotsManager():SendRadioEvent(false, false, -1)
                    end
                    observersV.customNotif = {name = nextCustom.name, path = nextCustom.currentSong.path, isStream = nextCustom.metadata.streamInfo.isStream}
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

return observersV