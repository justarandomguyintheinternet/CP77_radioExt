local managerV = {}

function managerV:new(manager, radioMod)
        local o = {}

    o.manager = manager
    o.isMounted = false
    o.rm = radioMod
    o.menuDeactivated = false

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
    local veh = GetMountedVehicle(GetPlayer())
    if veh then
        veh:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
        veh:GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, radio.name)
    end
    radio:activate(-1)
end

function managerV:disableCustomRadio() -- Just stop playback
    self.rm.logger.log("disableCustomRadio()")
    for _, radio in pairs(self.manager.radios) do
        radio:deactivate(-1)
    end

    local veh = GetMountedVehicle(GetPlayer())
    if veh then
        veh:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
    end
end

function managerV:update()
    self.menuDeactivated = false
    local player = GetPlayer()
    if not player then return end

    local veh = GetMountedVehicle(player)
    if veh then
        if veh:IsEngineTurnedOn() then
            local nameResult = veh:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
            -- nameResult may be a CName wrapper without `.value` if the
            -- blackboard key was never written to. Guard against nil.
            local name = nameResult and nameResult.value
            local radio = name and self:getRadioByName(name) or nil

            if radio and not radio.channels[-1] and veh:GetBlackboard():GetBool(GetAllBlackboardDefs().Vehicle.VehRadioState) == true then
                radio:activate(-1, false)
                player:GetQuickSlotsManager():SendRadioEvent(true, true, radio.index)
                self.rm.logger.log("Turned back on, because mounted, active, but was not playing")
            elseif radio then -- Make sure the car radio _really_ stays off
                -- player:GetQuickSlotsManager():SendRadioEvent(true, true, radio.index)
            end
        end
    elseif player:GetPocketRadio().isOn then
        local radio = self.manager:getRadioByIndex(player:GetPocketRadio().station)
        if radio and not radio.channels[-1] then
            player:GetQuickSlotsManager():SendRadioEvent(true, true, radio.index) -- Will call PocketRadio::TurnOn
            self.rm.logger.log("Turned pocket radio back on, should be playing but wasnt")
        end
    end
end

function managerV:handleMenu()
    if self.menuDeactivated then return end
    local player = GetPlayer()
    if not player then return end

    local radio = self.manager:getRadioByIndex(player:GetPocketRadio().station)

    local veh = GetMountedVehicle(player)
    if veh then
        local nameResult = veh:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
        -- nameResult may not have a `.value` field if the blackboard key was
        -- never set (e.g. fresh save). Guard against that.
        if nameResult and nameResult.value then
            radio = self:getRadioByName(nameResult.value)
        end
    end

    if radio then
        radio.channels[-1] = true -- hacky asf, no clue why it doesnt work otherwise
        radio:deactivate(-1)
    end
    self.menuDeactivated = true
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
            -- Player is on a train. They may not have a "mounted vehicle" in
            -- the engine sense, so guard against nil here to avoid crashing
            -- the per-frame update loop.
            local veh = GetMountedVehicle(GetPlayer())
            if not veh then return end
            for _, radio in pairs(self.manager.radios) do
                if radio.channels[-1] then
                    veh:ToggleRadioReceiver(false)
                end
            end
        end
    end
end

return managerV