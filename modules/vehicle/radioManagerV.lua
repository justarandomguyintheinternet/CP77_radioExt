local managerV = {}

function managerV:new(manager, radioMod)
	local o = {}

    o.manager = manager
    o.isMounted = false
    o.rm = radioMod

	self.__index = self
   	return setmetatable(o, self)
end

function managerV:getRadioByName(name)
    return self.manager:getRadioByName(name)
end

function managerV:switchToRadio(radio) -- Set avtiveRadio var to the radio object
    self.rm.logger.log("switchToRadio()", radio.channels[-1])
    if radio.channels[-1] then return end
    self:disableCustomRadio()
    if GetMountedVehicle(GetPlayer()) then
        GetMountedVehicle(GetPlayer()):GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
        GetMountedVehicle(GetPlayer()):GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, radio.name)
    end
    radio:activate(-1)
end

function managerV:disableCustomRadio() -- Just stop playback
    self.rm.logger.log("disableCustomRadio()")
    for _, radio in pairs(self.manager.radios) do
        radio:deactivate(-1)
    end

    if GetMountedVehicle(GetPlayer()) then
        GetMountedVehicle(GetPlayer()):GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
    end
end

function managerV:update()
    local veh = GetMountedVehicle(GetPlayer())
    if veh then
        if veh:IsEngineTurnedOn() then
            local name = veh:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
            local radio = self:getRadioByName(name.value)

            if radio and not radio.channels[-1] and GetMountedVehicle(GetPlayer()):GetBlackboard():GetBool(GetAllBlackboardDefs().Vehicle.VehRadioState) == true then
                radio:activate(-1, false)
                GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, radio.index)
                self.rm.logger.log("Turned back on, because mounted, active, but was not playing")
            elseif radio then -- Make sure the car radio _really_ stays off
                -- GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, radio.index)
            end
        end
    elseif GetPlayer():GetPocketRadio().isOn then
        local radio = self.manager:getRadioByIndex(GetPlayer():GetPocketRadio().station)
        if radio and not radio.channels[-1] then
            GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, radio.index) -- Will call PocketRadio::TurnOn
            self.rm.logger.log("Turned pocket radio back on, should be playing but wasnt")
        end
    end
end

function managerV:handleMenu()
    if not GetPlayer() then return end
    local radio = self.manager:getRadioByIndex(GetPlayer():GetPocketRadio().station)

    if GetMountedVehicle(GetPlayer()) then
        radio = self:getRadioByName(GetMountedVehicle(GetPlayer()):GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName).value)
    end

    if radio then
        radio.channels[-1] = true -- hacky asf, no clue why it doesnt work otherwise
        radio:deactivate(-1)
    end
end

-- Returns data of radio station, if there is any active radio station being used for vehicle radio
function managerV:getActiveStationData()
    for _, radio in pairs(self.manager.radios) do
        if radio.channels[-1] then
            return { station = radio.name, track = radio.currentSong.path, isStream = radio.metadata.streamInfo.isStream, index = radio.index }
        end
    end

    return nil
end

function managerV:handleTS() -- trainSystem comp
    if self.rm.runtimeData.ts then
        if not self.rm.runtimeData.ts.stationSys then return end
        local train = self.rm.runtimeData.ts.stationSys.activeTrain
        if train and train.playerMounted then
            for _, radio in pairs(self.manager.radios) do
                if radio.channels[-1] then
                    GetMountedVehicle(GetPlayer()):ToggleRadioReceiver(false)
                end
            end
        end
    end
end

return managerV