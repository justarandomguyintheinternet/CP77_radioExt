--[[
GameUI.lua
Reactive Game UI State Observer

Copyright (c) 2021 psiberx

How to use:
```
local GameUI = require('GameUI')

registerForEvent('onInit', function()
	GameUI.Listen(function(state)
		GameUI.PrintState(state)
	end)
end)
```
]]

local GameUI = { version = '1.1.7' }

GameUI.Event = {
	Braindance = 'Braindance',
	BraindancePlay = 'BraindancePlay',
	BraindanceEdit = 'BraindanceEdit',
	BraindanceExit = 'BraindanceExit',
	Camera = 'Camera',
	Context = 'Context',
	Cyberspace = 'Cyberspace',
	CyberspaceEnter = 'CyberspaceEnter',
	CyberspaceExit = 'CyberspaceExit',
	Device = 'Device',
	DeviceEnter = 'DeviceEnter',
	DeviceExit = 'DeviceExit',
	FastTravel = 'FastTravel',
	FastTravelFinish = 'FastTravelFinish',
	FastTravelStart = 'FastTravelStart',
	Flashback = 'Flashback',
	FlashbackEnd = 'FlashbackEnd',
	FlashbackStart = 'FlashbackStart',
	Johnny = 'Johnny',
	Loading = 'Loading',
	LoadingFinish = 'LoadingFinish',
	LoadingStart = 'LoadingStart',
	Menu = 'Menu',
	MenuClose = 'MenuClose',
	MenuNav = 'MenuNav',
	MenuOpen = 'MenuOpen',
	PhotoMode = 'PhotoMode',
	PhotoModeClose = 'PhotoModeClose',
	PhotoModeOpen = 'PhotoModeOpen',
	Popup = 'Popup',
	PopupClose = 'PopupClose',
	PopupOpen = 'PopupOpen',
	Possession = 'Possession',
	PossessionEnd = 'PossessionEnd',
	PossessionStart = 'PossessionStart',
	QuickHack = 'QuickHack',
	QuickHackClose = 'QuickHackClose',
	QuickHackOpen = 'QuickHackOpen',
	Scanner = 'Scanner',
	ScannerClose = 'ScannerClose',
	ScannerOpen = 'ScannerOpen',
	Scene = 'Scene',
	SceneEnter = 'SceneEnter',
	SceneExit = 'SceneExit',
	Session = 'Session',
	SessionEnd = 'SessionEnd',
	SessionStart = 'SessionStart',
	Shard = 'Shard',
	ShardClose = 'ShardClose',
	ShardOpen = 'ShardOpen',
	Tutorial = 'Tutorial',
	TutorialClose = 'TutorialClose',
	TutorialOpen = 'TutorialOpen',
	Update = 'Update',
	Vehicle = 'Vehicle',
	VehicleEnter = 'VehicleEnter',
	VehicleExit = 'VehicleExit',
	Wheel = 'Wheel',
	WheelClose = 'WheelClose',
	WheelOpen = 'WheelOpen',
}

GameUI.StateEvent = {
	[GameUI.Event.Braindance] = GameUI.Event.Braindance,
	[GameUI.Event.Context] = GameUI.Event.Context,
	[GameUI.Event.Cyberspace] = GameUI.Event.Cyberspace,
	[GameUI.Event.Device] = GameUI.Event.Device,
	[GameUI.Event.FastTravel] = GameUI.Event.FastTravel,
	[GameUI.Event.Flashback] = GameUI.Event.Flashback,
	[GameUI.Event.Johnny] = GameUI.Event.Johnny,
	[GameUI.Event.Loading] = GameUI.Event.Loading,
	[GameUI.Event.Menu] = GameUI.Event.Menu,
	[GameUI.Event.PhotoMode] = GameUI.Event.PhotoMode,
	[GameUI.Event.Popup] = GameUI.Event.Popup,
	[GameUI.Event.Possession] = GameUI.Event.Possession,
	[GameUI.Event.QuickHack] = GameUI.Event.QuickHack,
	[GameUI.Event.Scanner] = GameUI.Event.Scanner,
	[GameUI.Event.Scene] = GameUI.Event.Scene,
	[GameUI.Event.Session] = GameUI.Event.Session,
	[GameUI.Event.Shard] = GameUI.Event.Shard,
	[GameUI.Event.Tutorial] = GameUI.Event.Tutorial,
	[GameUI.Event.Update] = GameUI.Event.Update,
	[GameUI.Event.Vehicle] = GameUI.Event.Vehicle,
	[GameUI.Event.Wheel] = GameUI.Event.Wheel,
}

GameUI.Camera = {
	FirstPerson = 'FirstPerson',
	ThirdPerson = 'ThirdPerson',
}

local initialized = {}
local listeners = {}
local updateQueue = {}
local previousState = {
	isDetached = true,
	isMenu = false,
	menu = false,
}

local isDetached = true
local isLoaded = false
local isLoading = false
local isMenu = true
local isVehicle = false
local isBraindance = false
local isFastTravel = false
local isPhotoMode = false
local isShard = false
local isTutorial = false
local sceneTier = 4
local isPossessed = false
local isFlashback = false
local isCyberspace = false
local currentMenu = false
local currentSubmenu = false
local currentCamera = GameUI.Camera.FirstPerson
local contextStack = {}

local stateProps = {
	{ current = 'isLoaded', previous = nil, event = { change = GameUI.Event.Session, on = GameUI.Event.SessionStart } },
	{ current = 'isDetached', previous = nil, event = { change = GameUI.Event.Session, on = GameUI.Event.SessionEnd } },
	{ current = 'isLoading', previous = 'wasLoading', event = { change = GameUI.Event.Loading, on = GameUI.Event.LoadingStart, off = GameUI.Event.LoadingFinish } },
	{ current = 'isMenu', previous = 'wasMenu', event = { change = GameUI.Event.Menu, on = GameUI.Event.MenuOpen, off = GameUI.Event.MenuClose } },
	{ current = 'isScene', previous = 'wasScene', event = { change = GameUI.Event.Scene, on = GameUI.Event.SceneEnter, off = GameUI.Event.SceneExit, reqs = { isMenu = false } } },
	{ current = 'isVehicle', previous = 'wasVehicle', event = { change = GameUI.Event.Vehicle, on = GameUI.Event.VehicleEnter, off = GameUI.Event.VehicleExit } },
	{ current = 'isBraindance', previous = 'wasBraindance', event = { change = GameUI.Event.Braindance, on = GameUI.Event.BraindancePlay, off = GameUI.Event.BraindanceExit } },
	{ current = 'isEditor', previous = 'wasEditor', event = { change = GameUI.Event.Braindance, on = GameUI.Event.BraindanceEdit, off = GameUI.Event.BraindancePlay } },
	{ current = 'isFastTravel', previous = 'wasFastTravel', event = { change = GameUI.Event.FastTravel, on = GameUI.Event.FastTravelStart, off = GameUI.Event.FastTravelFinish } },
	{ current = 'isJohnny', previous = 'wasJohnny', event = { change = GameUI.Event.Johnny } },
	{ current = 'isPossessed', previous = 'wasPossessed', event = { change = GameUI.Event.Possession, on = GameUI.Event.PossessionStart, off = GameUI.Event.PossessionEnd, scope = GameUI.Event.Johnny } },
	{ current = 'isFlashback', previous = 'wasFlashback', event = { change = GameUI.Event.Flashback, on = GameUI.Event.FlashbackStart, off = GameUI.Event.FlashbackEnd, scope = GameUI.Event.Johnny } },
	{ current = 'isCyberspace', previous = 'wasCyberspace', event = { change = GameUI.Event.Cyberspace, on = GameUI.Event.CyberspaceEnter, off = GameUI.Event.CyberspaceExit } },
	{ current = 'isDefault', previous = 'wasDefault' },
	{ current = 'isScanner', previous = 'wasScanner', event = { change = GameUI.Event.Scanner, on = GameUI.Event.ScannerOpen, off = GameUI.Event.ScannerClose, scope = GameUI.Event.Context } },
	{ current = 'isQuickHack', previous = 'wasQuickHack', event = { change = GameUI.Event.QuickHack, on = GameUI.Event.QuickHackOpen, off = GameUI.Event.QuickHackClose, scope = GameUI.Event.Context } },
	{ current = 'isPopup', previous = 'wasPopup', event = { change = GameUI.Event.Popup, on = GameUI.Event.PopupOpen, off = GameUI.Event.PopupClose, scope = GameUI.Event.Context } },
	{ current = 'isWheel', previous = 'wasWheel', event = { change = GameUI.Event.Wheel, on = GameUI.Event.WheelOpen, off = GameUI.Event.WheelClose, scope = GameUI.Event.Context } },
	{ current = 'isDevice', previous = 'wasDevice', event = { change = GameUI.Event.Device, on = GameUI.Event.DeviceEnter, off = GameUI.Event.DeviceExit, scope = GameUI.Event.Context } },
	{ current = 'isPhoto', previous = 'wasPhoto', event = { change = GameUI.Event.PhotoMode, on = GameUI.Event.PhotoModeOpen, off = GameUI.Event.PhotoModeClose } },
	{ current = 'isShard', previous = 'wasShard', event = { change = GameUI.Event.Shard, on = GameUI.Event.ShardOpen, off = GameUI.Event.ShardClose } },
	{ current = 'isTutorial', previous = 'wasTutorial', event = { change = GameUI.Event.Tutorial, on = GameUI.Event.TutorialOpen, off = GameUI.Event.TutorialClose } },
	{ current = 'menu', previous = 'lastMenu', event = { change = GameUI.Event.MenuNav, reqs = { isMenu = true, wasMenu = true }, scope = GameUI.Event.Menu } },
	{ current = 'submenu', previous = 'lastSubmenu', event = { change = GameUI.Event.MenuNav, reqs = { isMenu = true, wasMenu = true }, scope = GameUI.Event.Menu } },
	{ current = 'camera', previous = 'lastCamera', event = { change = GameUI.Event.Camera, scope = GameUI.Event.Vehicle }, parent = 'isVehicle' },
	{ current = 'context', previous = 'lastContext', event = { change = GameUI.Event.Context } },
}

local menuScenarios = {
	['MenuScenario_BodyTypeSelection'] = { menu = 'NewGame', submenu = 'BodyType' },
	['MenuScenario_BoothMode'] = { menu = 'BoothMode', submenu = false },
	['MenuScenario_CharacterCustomization'] = { menu = 'NewGame', submenu = 'Customization' },
	['MenuScenario_ClippedMenu'] = { menu = 'ClippedMenu', submenu = false },
	['MenuScenario_Credits'] = { menu = 'MainMenu', submenu = 'Credits' },
	['MenuScenario_DeathMenu'] = { menu = 'DeathMenu', submenu = false },
	['MenuScenario_Difficulty'] = { menu = 'NewGame', submenu = 'Difficulty' },
	['MenuScenario_E3EndMenu'] = { menu = 'E3EndMenu', submenu = false },
	['MenuScenario_FastTravel'] = { menu = 'FastTravel', submenu = 'Map' },
	['MenuScenario_FinalBoards'] = { menu = 'FinalBoards', submenu = false },
	['MenuScenario_FindServers'] = { menu = 'FindServers', submenu = false },
	['MenuScenario_HubMenu'] = { menu = 'Hub', submenu = false },
	['MenuScenario_Idle'] = { menu = false, submenu = false },
	['MenuScenario_LifePathSelection'] = { menu = 'NewGame', submenu = 'LifePath' },
	['MenuScenario_LoadGame'] = { menu = 'MainMenu', submenu = 'LoadGame' },
	['MenuScenario_MultiplayerMenu'] = { menu = 'Multiplayer', submenu = false },
	['MenuScenario_NetworkBreach'] = { menu = 'NetworkBreach', submenu = false },
	['MenuScenario_NewGame'] = { menu = 'NewGame', submenu = false },
	['MenuScenario_PauseMenu'] = { menu = 'PauseMenu', submenu = false },
	['MenuScenario_PlayRecordedSession'] = { menu = 'PlayRecordedSession', submenu = false },
	['MenuScenario_Settings'] = { menu = 'MainMenu', submenu = 'Settings' },
	['MenuScenario_SingleplayerMenu'] = { menu = 'MainMenu', submenu = false },
	['MenuScenario_StatsAdjustment'] = { menu = 'NewGame', submenu = 'Attributes' },
	['MenuScenario_Storage'] = { menu = 'Stash', submenu = false },
	['MenuScenario_Summary'] = { menu = 'NewGame', submenu = 'Summary' },
	['MenuScenario_Vendor'] = { menu = 'Vendor', submenu = false },
}

local eventScopes = {
	[GameUI.Event.Update] = {},
	[GameUI.Event.Menu] = { [GameUI.Event.Loading] = true },
}

local function toStudlyCase(s)
	return (s:lower():gsub('_*(%l)(%w*)', function(first, rest)
		return string.upper(first) .. rest
	end))
end

local function updateDetached(detached)
	isDetached = detached
	isLoaded = false
end

local function updateLoaded(loaded)
	isDetached = not loaded
	isLoaded = loaded
end

local function updateLoading(loading)
	isLoading = loading
end

local function updateMenu(menuActive)
	isMenu = menuActive or GameUI.IsMainMenu()
end

local function updateMenuScenario(scenarioName)
	local scenario = menuScenarios[scenarioName] or menuScenarios['MenuScenario_Idle']

	isMenu = scenario.menu ~= false
	currentMenu = scenario.menu
	currentSubmenu = scenario.submenu
end

local function updateMenuItem(itemName)
	currentSubmenu = itemName or false
end

local function updateVehicle(vehicleActive, cameraMode)
	isVehicle = vehicleActive
	currentCamera = cameraMode and GameUI.Camera.ThirdPerson or GameUI.Camera.FirstPerson
end

local function updateBraindance(braindanceActive)
	isBraindance = braindanceActive
end

local function updateFastTravel(fastTravelActive)
	isFastTravel = fastTravelActive
end

local function updatePhotoMode(photoModeActive)
	isPhotoMode = photoModeActive
end

local function updateShard(shardActive)
	isShard = shardActive
end

local function updateTutorial(tutorialActive)
	isTutorial = tutorialActive
end

local function updateSceneTier(sceneTierValue)
	sceneTier = sceneTierValue
end

local function updatePossessed(possessionActive)
	isPossessed = possessionActive
end

local function updateFlashback(flashbacklActive)
	isFlashback = flashbacklActive
end

local function updateCyberspace(isCyberspacePresence)
	isCyberspace = isCyberspacePresence
end

local function updateContext(oldContext, newContext)
	if oldContext == nil and newContext == nil then
		contextStack = {}
	elseif oldContext ~= nil then
		for i = #contextStack, 1, -1 do
			if contextStack[i].value == oldContext.value then
				table.remove(contextStack, i)
				break
			end
		end
	elseif newContext ~= nil then
		table.insert(contextStack, newContext)
	else
		if #contextStack > 0 and contextStack[#contextStack].value == oldContext.value then
			contextStack[#contextStack] = newContext
		end
	end
end

local function refreshCurrentState()
	local player = Game.GetPlayer()
	local blackboardDefs = Game.GetAllBlackboardDefs()
	local blackboardUI = Game.GetBlackboardSystem():Get(blackboardDefs.UI_System)
	local blackboardVH = Game.GetBlackboardSystem():Get(blackboardDefs.UI_ActiveVehicleData)
	local blackboardBD = Game.GetBlackboardSystem():Get(blackboardDefs.Braindance)
	local blackboardPM = Game.GetBlackboardSystem():Get(blackboardDefs.PhotoMode)
	local blackboardPSM = Game.GetBlackboardSystem():GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)

	if not isLoaded then
		updateDetached(not player:IsAttached() or GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame())

		if isDetached then
			currentMenu = 'MainMenu'
		end
	end

	updateMenu(blackboardUI:GetBool(blackboardDefs.UI_System.IsInMenu))
	updateTutorial(Game.GetTimeSystem():IsTimeDilationActive('UI_TutorialPopup'))

	updateSceneTier(blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.SceneTier))
	updateVehicle(
		blackboardVH:GetBool(blackboardDefs.UI_ActiveVehicleData.IsPlayerMounted),
		blackboardVH:GetBool(blackboardDefs.UI_ActiveVehicleData.IsTPPCameraOn)
	)

	updateBraindance(blackboardBD:GetBool(blackboardDefs.Braindance.IsActive))

	updatePossessed(Game.GetQuestsSystem():GetFactStr(Game.GetPlayerSystem():GetPossessedByJohnnyFactName()) == 1)
	updateFlashback(player:IsJohnnyReplacer())

	updatePhotoMode(blackboardPM:GetBool(blackboardDefs.PhotoMode.IsActive))

	if #contextStack == 0 then
		if isBraindance then
			updateContext(nil, GameUI.Context.BraindancePlayback)
		elseif Game.GetTimeSystem():IsTimeDilationActive('radial') then
			updateContext(nil, GameUI.Context.ModalPopup)
		end
	end
end

local function pushCurrentState()
	previousState = GameUI.GetState()
end

local function applyQueuedChanges()
	if #updateQueue > 0 then
		for _, updateCallback in ipairs(updateQueue) do
			updateCallback()
		end

		updateQueue = {}
	end
end

local function determineEvents(currentState)
	local events = { GameUI.Event.Update }
	local firing = {}

	for _, stateProp in ipairs(stateProps) do
		local currentValue = currentState[stateProp.current]
		local previousValue = previousState[stateProp.current]

		if stateProp.event and (not stateProp.parent or currentState[stateProp.parent]) then
			local reqSatisfied = true

			if stateProp.event.reqs then
				for reqProp, reqValue in pairs(stateProp.event.reqs) do
					if tostring(currentState[reqProp]) ~= tostring(reqValue) then
						reqSatisfied = false
						break
					end
				end
			end

			if reqSatisfied then
				if stateProp.event.change and previousValue ~= nil then
					if tostring(currentValue) ~= tostring(previousValue) then
						if not firing[stateProp.event.change] then
							table.insert(events, stateProp.event.change)
							firing[stateProp.event.change] = true
						end
					end
				end

				if stateProp.event.on and currentValue and not previousValue then
					if not firing[stateProp.event.on] then
						table.insert(events, stateProp.event.on)
						firing[stateProp.event.on] = true
					end
				elseif stateProp.event.off and not currentValue and previousValue then
					if not firing[stateProp.event.off] then
						table.insert(events, 1, stateProp.event.off)
						firing[stateProp.event.off] = true
					end
				end
			end
		end
	end

	return events
end

local function notifyObservers()
	if not isDetached then
		applyQueuedChanges()
	end

	local currentState = GameUI.GetState()
	local stateChanged = false

	for _, stateProp in ipairs(stateProps) do
		local currentValue = currentState[stateProp.current]
		local previousValue = previousState[stateProp.current]

		if tostring(currentValue) ~= tostring(previousValue) then
			stateChanged = true
			break
		end
	end

	if stateChanged then
		local events =  determineEvents(currentState)

		for _, event in ipairs(events) do
			if listeners[event] then
				if event ~= GameUI.Event.Update then
					currentState.event = event
				end

				for _, callback in ipairs(listeners[event]) do
					callback(currentState)
				end

				currentState.event = nil
			end
		end

		if isLoaded then
			isLoaded = false
		end

		previousState = currentState
	end
end

local function notifyAfterStart(updateCallback)
	if not isDetached then
		updateCallback()
		notifyObservers()
	else
		table.insert(updateQueue, updateCallback)
	end
end

local function initialize(event)
	if not initialized.data then
		GameUI.Context = {
			Default = Enum.new('UIGameContext', 0),
			QuickHack = Enum.new('UIGameContext', 1),
			Scanning = Enum.new('UIGameContext', 2),
			DeviceZoom = Enum.new('UIGameContext', 3),
			BraindanceEditor = Enum.new('UIGameContext', 4),
			BraindancePlayback = Enum.new('UIGameContext', 5),
			VehicleMounted = Enum.new('UIGameContext', 6),
			ModalPopup = Enum.new('UIGameContext', 7),
			RadialWheel = Enum.new('UIGameContext', 8),
			VehicleRace = Enum.new('UIGameContext', 9),
		}

		for _, stateProp in ipairs(stateProps) do
			if stateProp.event then
				local eventScope = stateProp.event.scope or stateProp.event.change

				if eventScope then
					for _, eventKey in ipairs({ 'change', 'on', 'off' }) do
						local eventName = stateProp.event[eventKey]

						if eventName then
							if not eventScopes[eventName] then
								eventScopes[eventName] = {}
								eventScopes[eventName][GameUI.Event.Session] = true
							end

							eventScopes[eventName][eventScope] = true
						end
					end

					eventScopes[GameUI.Event.Update][eventScope] = true
				end
			end
		end

		initialized.data = true
	end

	local required = eventScopes[event] or eventScopes[GameUI.Event.Update]

	-- Game Session Listeners

	if required[GameUI.Event.Session] and not initialized[GameUI.Event.Session] then
		Observe('QuestTrackerGameController', 'OnInitialize', function()
			--spdlog.error(('QuestTrackerGameController::OnInitialize()'))

			if isDetached then
				updateLoading(false)
				updateLoaded(true)
				updateMenuScenario()
				applyQueuedChanges()
				refreshCurrentState()
				notifyObservers()
			end
		end)

		Observe('QuestTrackerGameController', 'OnUninitialize', function()
			--spdlog.error(('QuestTrackerGameController::OnUninitialize()'))

			if Game.GetPlayer() == nil then
				updateDetached(true)
				updateSceneTier(1)
				updateContext()
				updateVehicle(false, false)
				updateBraindance(false)
				updateCyberspace(false)
				updatePossessed(false)
				updateFlashback(false)
				updatePhotoMode(false)

				if currentMenu ~= 'MainMenu' then
					notifyObservers()
				else
					pushCurrentState()
				end
			end
		end)

		initialized[GameUI.Event.Session] = true
	end

	-- Loading State Listeners

	if required[GameUI.Event.Loading] and not initialized[GameUI.Event.Loading] then
		Observe('LoadingScreenProgressBarController', 'SetProgress', function(_, progress)
			--spdlog.info(('LoadingScreenProgressBarController::SetProgress(%.3f)'):format(progress))

			if not isLoading then
				updateMenuScenario()
				updateLoading(true)
				notifyObservers()

			elseif progress == 1.0 then
				if currentMenu ~= 'MainMenu' then
					updateMenuScenario()
				end

				updateLoading(false)
				notifyObservers()
			end
		end)

		initialized[GameUI.Event.Loading] = true
	end

	-- Menu State Listeners

	if required[GameUI.Event.Menu] and not initialized[GameUI.Event.Menu] then
		local menuOpenListeners = {
			'MenuScenario_Idle',
			'MenuScenario_BaseMenu',
			'MenuScenario_PreGameSubMenu',
			'MenuScenario_SingleplayerMenu',
		}

		for _, menuScenario  in pairs(menuOpenListeners) do
			Observe(menuScenario, 'OnLeaveScenario', function(_, menuName)
				if type(menuName) ~= 'userdata' then
					menuName = _
				end

				--spdlog.error(('%s::OnLeaveScenario()'):format(menuScenario))

				updateMenuScenario(Game.NameToString(menuName))

				if not isLoading then
					notifyObservers()
				end
			end)
		end

		Observe('MenuScenario_HubMenu', 'OnSelectMenuItem', function(_, menuItemData)
			if type(menuItemData) ~= 'userdata' then
				menuItemData = _
			end

			--spdlog.error(('MenuScenario_HubMenu::OnSelectMenuItem(%q)'):format(menuItemData.menuData.label))

			updateMenuItem(EnumValueToName('HubMenuItems', menuItemData.menuData.identifier).value)
			--updateMenuItem(toStudlyCase(menuItemData.menuData.label))
			notifyObservers()
		end)

		Observe('MenuScenario_HubMenu', 'OnCloseHubMenu', function()
			--spdlog.error(('MenuScenario_HubMenu::OnCloseHubMenu()'))

			updateMenuItem(false)
			notifyObservers()
		end)

		local menuItemListeners = {
			['MenuScenario_SingleplayerMenu'] = {
				['OnLoadGame'] = 'LoadGame',
				['OnMainMenuBack'] = false,
			},
			['MenuScenario_Settings'] = {
				['OnSwitchToControllerPanel'] = 'Controller',
				['OnSwitchToBrightnessSettings'] = 'Brightness',
				['OnSwitchToHDRSettings'] = 'HDR',
				['OnSettingsBack'] = 'Settings',
			},
			['MenuScenario_PauseMenu'] = {
				['OnSwitchToBrightnessSettings'] = 'Brightness',
				['OnSwitchToControllerPanel'] = 'Controller',
				['OnSwitchToCredits'] = 'Credits',
				['OnSwitchToHDRSettings'] = 'HDR',
				['OnSwitchToLoadGame'] = 'LoadGame',
				['OnSwitchToSaveGame'] = 'SaveGame',
				['OnSwitchToSettings'] = 'Settings',
			},
			['MenuScenario_DeathMenu'] = {
				['OnSwitchToBrightnessSettings'] = 'Brightness',
				['OnSwitchToControllerPanel'] = 'Controller',
				['OnSwitchToHDRSettings'] = 'HDR',
				['OnSwitchToLoadGame'] = 'LoadGame',
				['OnSwitchToSettings'] = 'Settings',
			},
			['MenuScenario_Vendor'] = {
				['OnSwitchToVendor'] = 'Trade',
				['OnSwitchToRipperDoc'] = 'RipperDoc',
				['OnSwitchToCrafting'] = 'Crafting',
			},
		}

		for menuScenario, menuItemEvents in pairs(menuItemListeners) do
			for menuEvent, menuItem in pairs(menuItemEvents) do
				Observe(menuScenario, menuEvent, function()
					--spdlog.error(('%s::%s()'):format(menuScenario, menuEvent))

					updateMenuScenario(menuScenario)
					updateMenuItem(menuItem)
					notifyObservers()
				end)
			end
		end

		local menuBackListeners = {
			['MenuScenario_PauseMenu'] = 'GoBack',
			['MenuScenario_DeathMenu'] = 'GoBack',
		}

		for menuScenario, menuBackEvent in pairs(menuBackListeners) do
			Observe(menuScenario, menuBackEvent, function(self)
				--spdlog.error(('%s::%s()'):format(menuScenario, menuBackEvent))

				if Game.NameToString(self.prevMenuName) == 'settings_main' then
					updateMenuItem('Settings')
				else
					updateMenuItem(false)
				end

				notifyObservers()
			end)
		end

		Observe('SingleplayerMenuGameController', 'OnSavesReady', function()
			--spdlog.error(('SingleplayerMenuGameController::OnSavesReady()'))

			updateMenuScenario('MenuScenario_SingleplayerMenu')

			if not isLoading then
				notifyObservers()
			end
		end)

		initialized[GameUI.Event.Menu] = true
	end

	-- Vehicle State Listeners

	if required[GameUI.Event.Vehicle] and not initialized[GameUI.Event.Vehicle] then
		Observe('hudCarController', 'OnCameraModeChanged', function(_, mode)
			if type(mode) ~= 'boolean' then
				mode = _
			end

			--spdlog.error(('hudCarController::OnCameraModeChanged(%s)'):format(tostring(mode)))

			updateVehicle(true, mode)
			notifyObservers()
		end)

		Observe('hudCarController', 'OnUnmountingEvent', function()
			--spdlog.error(('hudCarController::OnUnmountingEvent()'))

			updateVehicle(false, false)
			notifyObservers()
		end)

		Observe('gameuiPanzerHUDGameController', 'OnUninitialize', function()
			--spdlog.error(('gameuiPanzerHUDGameController::OnUninitialize()'))

			updateVehicle(false, false)
			notifyObservers()
		end)

		Observe('PlayerVisionModeController', 'OnRestrictedSceneChanged', function(_, sceneTierValue)
			if type(sceneTierValue) ~= 'number' then
				sceneTierValue = _
			end

			--spdlog.error(('PlayerVisionModeController::OnRestrictedSceneChanged(%d)'):format(sceneTierValue))

			if isVehicle then
				updateVehicle(true, sceneTierValue < 3)
				notifyObservers()
			end
		end)

		initialized[GameUI.Event.Vehicle] = true
	end

	-- Braindance State Listeners

	if required[GameUI.Event.Braindance] and not initialized[GameUI.Event.Braindance] then
		Observe('BraindanceGameController', 'OnIsActiveUpdated', function(_, braindanceActive)
			if type(braindanceActive) ~= 'boolean' then
				braindanceActive = _
			end

			--spdlog.error(('BraindanceGameController::OnIsActiveUpdated(%s)'):format(tostring(braindanceActive)))

			updateBraindance(braindanceActive)
			notifyObservers()
		end)

		initialized[GameUI.Event.Braindance] = true
	end

	-- Scene State Listeners

	if required[GameUI.Event.Scene] and not initialized[GameUI.Event.Scene] then
		Observe('PlayerVisionModeController', 'OnRestrictedSceneChanged', function(_, sceneTierValue)
			if type(sceneTierValue) ~= 'number' then
				sceneTierValue = _
			end

			--spdlog.error(('PlayerVisionModeController::OnRestrictedSceneChanged(%d)'):format(sceneTierValue))

			notifyAfterStart(function()
				updateSceneTier(sceneTierValue)
			end)
		end)

		initialized[GameUI.Event.Scene] = true
	end

	-- Photo Mode Listeners

	if required[GameUI.Event.PhotoMode] and not initialized[GameUI.Event.PhotoMode] then
		Observe('gameuiPhotoModeMenuController', 'OnShow', function()
			--spdlog.error(('PhotoModeMenuController::OnShow()'))

			updatePhotoMode(true)
			notifyObservers()
		end)

		Observe('gameuiPhotoModeMenuController', 'OnHide', function()
			--spdlog.error(('PhotoModeMenuController::OnHide()'))

			updatePhotoMode(false)
			notifyObservers()
		end)

		initialized[GameUI.Event.PhotoMode] = true
	end

	-- Fast Travel Listeners

	if required[GameUI.Event.FastTravel] and not initialized[GameUI.Event.FastTravel] then
		local fastTravelStart

		Observe('FastTravelSystem', 'OnToggleFastTravelAvailabilityOnMapRequest', function(_, request)
			if type(request) ~= 'userdata' then
				request = _
			end

			--spdlog.error(('FastTravelSystem::OnToggleFastTravelAvailabilityOnMapRequest()'))

			if request.isEnabled then
				fastTravelStart = request.pointRecord
			end
		end)

		Observe('FastTravelSystem', 'OnPerformFastTravelRequest', function(_, request)
			if type(request) ~= 'userdata' then
				request = _
			end

			--spdlog.error(('FastTravelSystem::OnPerformFastTravelRequest()'))

			local fastTravelDestination = request.pointData.pointRecord

			if tostring(fastTravelStart) ~= tostring(fastTravelDestination) then
				updateLoading(true)
				updateFastTravel(true)
				notifyObservers()
			end
		end)

		Observe('FastTravelSystem', 'OnLoadingScreenFinished', function(_, finished)
			if type(finished) ~= 'boolean' then
				finished = _
			end

			--spdlog.error(('FastTravelSystem::OnLoadingScreenFinished(%s)'):format(tostring(finished)))

			if isFastTravel and finished then
				updateLoading(false)
				updateFastTravel(false)
				refreshCurrentState()
				notifyObservers()
			end
		end)

		initialized[GameUI.Event.FastTravel] = true
	end

	-- Shard Listeners

	if required[GameUI.Event.Shard] and not initialized[GameUI.Event.Shard] then
		Observe('ShardNotificationController', 'SetButtonHints', function()
			--spdlog.error(('ShardNotificationController::SetButtonHints()'))
			updateShard(true)
			notifyObservers()
		end)

		Observe('ShardNotificationController', 'Close', function()
			--spdlog.error(('ShardNotificationController::Close()'))
			updateShard(false)
			notifyObservers()
		end)

		initialized[GameUI.Event.Shard] = true
	end

	-- Tutorial Listeners

	if required[GameUI.Event.Tutorial] and not initialized[GameUI.Event.Tutorial] then
		Observe('gameuiTutorialPopupGameController', 'PauseGame', function(_, tutorialActive)
			--spdlog.error(('gameuiTutorialPopupGameController::PauseGame(%s)'):format(tostring(tutorialActive)))

			updateTutorial(tutorialActive)
			notifyObservers()
		end)

		initialized[GameUI.Event.Tutorial] = true
	end

	-- UI Context Listeners

	if required[GameUI.Event.Context] and not initialized[GameUI.Event.Context] then
		Observe('gameuiGameSystemUI', 'PushGameContext', function(_, newContext)
			--spdlog.error(('GameSystemUI::PushGameContext(%s)'):format(tostring(newContext)))

			if isBraindance and newContext.value == GameUI.Context.Scanning.value then
				return
			end

			updateContext(nil, newContext)
			notifyObservers()
		end)

		Observe('gameuiGameSystemUI', 'PopGameContext', function(_, oldContext)
			--spdlog.error(('GameSystemUI::PopGameContext(%s)'):format(tostring(oldContext)))

			if isBraindance and oldContext.value == GameUI.Context.Scanning.value then
				return
			end

			if oldContext.value == GameUI.Context.QuickHack.value then
				oldContext = GameUI.Context.Scanning
			end

			updateContext(oldContext, nil)
			notifyObservers()
		end)

		Observe('HUDManager', 'OnQuickHackUIVisibleChanged', function(_, quickhacking)
			if type(quickhacking) ~= 'boolean' then
				quickhacking = _
			end

			--spdlog.error(('HUDManager::OnQuickHackUIVisibleChanged(%s)'):format(tostring(quickhacking)))

			if quickhacking then
				updateContext(GameUI.Context.Scanning, GameUI.Context.QuickHack)
			else
				updateContext(GameUI.Context.QuickHack, GameUI.Context.Scanning)
			end

			notifyObservers()
		end)

		Observe('gameuiGameSystemUI', 'ResetGameContext', function()
			--spdlog.error(('GameSystemUI::ResetGameContext()'))

			updateContext()
			notifyObservers()
		end)

		initialized[GameUI.Event.Context] = true
	end

	-- Johnny

	if required[GameUI.Event.Johnny] and not initialized[GameUI.Event.Johnny] then
		Observe('cpPlayerSystem', 'OnLocalPlayerPossesionChanged', function(_, possession)
			if type(possession) ~= 'userdata' then
				possession = _
			end

			--spdlog.error(('cpPlayerSystem::OnLocalPlayerPossesionChanged(%s)'):format(tostring(possession)))

			notifyAfterStart(function()
				updatePossessed(possession.value == 'Johnny')
			end)
		end)

		Observe('cpPlayerSystem', 'OnLocalPlayerChanged', function(_, player)
			if type(player) ~= 'userdata' then
				player = _
			end

			--spdlog.error(('cpPlayerSystem::OnLocalPlayerChanged(%s)'):format(tostring(player:IsJohnnyReplacer())))

			notifyAfterStart(function()
				updateFlashback(player:IsJohnnyReplacer())
			end)
		end)

		initialized[GameUI.Event.Johnny] = true
	end

	-- Cyberspace

	if required[GameUI.Event.Cyberspace] and not initialized[GameUI.Event.Cyberspace] then
		Observe('PlayerPuppet', 'OnStatusEffectApplied', function(_, evt)
			--spdlog.error(('PlayerPuppet::OnStatusEffectApplied()'))

			if evt.staticData then
				local applyCyberspacePresence = evt.staticData:GameplayTagsContains('CyberspacePresence')

				if applyCyberspacePresence then
					notifyAfterStart(function()
						updateCyberspace(true)
					end)
				end
			end
		end)

		Observe('PlayerPuppet', 'OnStatusEffectRemoved', function(_, evt)
			--spdlog.error(('PlayerPuppet::OnStatusEffectRemoved()'))

			if evt.staticData then
				local removeCyberspacePresence = evt.staticData:GameplayTagsContains('CyberspacePresence')

				if removeCyberspacePresence then
					notifyAfterStart(function()
						updateCyberspace(false)
					end)
				end
			end
		end)

		initialized[GameUI.Event.Cyberspace] = true
	end

	-- Initial state

	if not initialized.state then
		refreshCurrentState()
		pushCurrentState()

		initialized.state = true
	end
end

function GameUI.Observe(event, callback)
	if type(event) == 'string' then
		initialize(event)
	elseif type(event) == 'function' then
		callback, event = event, GameUI.Event.Update
		initialize(event)
	else
		if not event then
			initialize(GameUI.Event.Update)
		elseif type(event) == 'table' then
			for _, evt in ipairs(event) do
				GameUI.Observe(evt, callback)
			end
		end
		return
	end

	if type(callback) == 'function' then
		if not listeners[event] then
			listeners[event] = {}
		end

		table.insert(listeners[event], callback)
	end
end

function GameUI.Listen(event, callback)
	if type(event) == 'function' then
		callback = event
		for _, evt in pairs(GameUI.Event) do
			if not GameUI.StateEvent[evt] then
				GameUI.Observe(evt, callback)
			end
		end
	else
		GameUI.Observe(event, callback)
	end
end

function GameUI.IsDetached()
	return isDetached
end

function GameUI.IsLoading()
	return isLoading
end

function GameUI.IsMenu()
	return isMenu
end

function GameUI.IsMainMenu()
	return isMenu and currentMenu == 'MainMenu'
end

function GameUI.IsShard()
	return isShard
end

function GameUI.IsTutorial()
	return isTutorial
end

function GameUI.IsScene()
	return sceneTier >= 3 and not GameUI.IsMainMenu()
end

function GameUI.IsScanner()
	local context = GameUI.GetContext()

	return not isMenu and not isLoading and not isFastTravel and (context.value == GameUI.Context.Scanning.value)
end

function GameUI.IsQuickHack()
	local context = GameUI.GetContext()

	return not isMenu and not isLoading and not isFastTravel and (context.value == GameUI.Context.QuickHack.value)
end

function GameUI.IsPopup()
	local context = GameUI.GetContext()

	return not isMenu and (context.value == GameUI.Context.ModalPopup.value)
end

function GameUI.IsWheel()
	local context = GameUI.GetContext()

	return not isMenu and (context.value == GameUI.Context.RadialWheel.value)
end

function GameUI.IsDevice()
	local context = GameUI.GetContext()

	return not isMenu and (context.value == GameUI.Context.DeviceZoom.value)
end

function GameUI.IsVehicle()
	return isVehicle
end

function GameUI.IsFastTravel()
	return isFastTravel
end

function GameUI.IsBraindance()
	return isBraindance
end

function GameUI.IsCyberspace()
	return isCyberspace
end

function GameUI.IsJohnny()
	return isPossessed or isFlashback
end

function GameUI.IsPossessed()
	return isPossessed
end

function GameUI.IsFlashback()
	return isFlashback
end

function GameUI.IsPhoto()
	return isPhotoMode
end

function GameUI.IsDefault()
	return not isDetached
		and not isLoading
		and not isMenu
		and not GameUI.IsScene()
		and not isFastTravel
		and not isBraindance
		and not isCyberspace
		and not isPhotoMode
		and GameUI.IsContext(GameUI.Context.Default)
end

function GameUI.GetMenu()
	return currentMenu
end

function GameUI.GetSubmenu()
	return currentSubmenu
end

function GameUI.GetCamera()
	return currentCamera
end

function GameUI.GetContext()
	return #contextStack > 0 and contextStack[#contextStack] or GameUI.Context.Default
end

function GameUI.IsContext(context)
	return GameUI.GetContext().value == (type(context) == 'userdata' and context.value or context)
end

function GameUI.GetState()
	local currentState = {}

	currentState.isDetached = GameUI.IsDetached()
	currentState.isLoading = GameUI.IsLoading()
	currentState.isLoaded = isLoaded

	currentState.isMenu = GameUI.IsMenu()
	currentState.isShard = GameUI.IsShard()
	currentState.isTutorial = GameUI.IsTutorial()

	currentState.isScene = GameUI.IsScene()
	currentState.isScanner = GameUI.IsScanner()
	currentState.isQuickHack = GameUI.IsQuickHack()
	currentState.isPopup = GameUI.IsPopup()
	currentState.isWheel = GameUI.IsWheel()
	currentState.isDevice = GameUI.IsDevice()
	currentState.isVehicle = GameUI.IsVehicle()

	currentState.isFastTravel = GameUI.IsFastTravel()

	currentState.isBraindance = GameUI.IsBraindance()
	currentState.isCyberspace = GameUI.IsCyberspace()

	currentState.isJohnny = GameUI.IsJohnny()
	currentState.isPossessed = GameUI.IsPossessed()
	currentState.isFlashback = GameUI.IsFlashback()

	currentState.isPhoto = GameUI.IsPhoto()

	currentState.isEditor = GameUI.IsContext(GameUI.Context.BraindanceEditor)

	currentState.isDefault = not currentState.isDetached
		and not currentState.isLoading
		and not currentState.isMenu
		and not currentState.isScene
		and not currentState.isScanner
		and not currentState.isQuickHack
		and not currentState.isPopup
		and not currentState.isWheel
		and not currentState.isDevice
		and not currentState.isFastTravel
		and not currentState.isBraindance
		and not currentState.isCyberspace
		and not currentState.isPhoto

	currentState.menu = GameUI.GetMenu()
	currentState.submenu = GameUI.GetSubmenu()
	currentState.camera = GameUI.GetCamera()
	currentState.context = GameUI.GetContext()

	for _, stateProp in ipairs(stateProps) do
		if stateProp.previous then
			currentState[stateProp.previous] = previousState[stateProp.current]
		end
	end

	return currentState
end

function GameUI.ExportState(state)
	local export = {}

	if state.event then
		table.insert(export, 'event = ' .. string.format('%q', state.event))
	end

	for _, stateProp in ipairs(stateProps) do
		local value = state[stateProp.current]

		if value and (not stateProp.parent or state[stateProp.parent]) then
			if type(value) == 'userdata' then
				value = string.format('%q', value.value) -- 'GameUI.Context.'
			elseif type(value) == 'string' then
				value = string.format('%q', value)
			else
				value = tostring(value)
			end

			table.insert(export, stateProp.current .. ' = ' .. value)
		end
	end

	for _, stateProp in ipairs(stateProps) do
		if stateProp.previous then
			local currentValue = state[stateProp.current]
			local previousValue = state[stateProp.previous]

			if previousValue and previousValue ~= currentValue then
				if type(previousValue) == 'userdata' then
					previousValue = string.format('%q', previousValue.value) -- 'GameUI.Context.'
				elseif type(previousValue) == 'string' then
					previousValue = string.format('%q', previousValue)
				else
					previousValue = tostring(previousValue)
				end

				table.insert(export, stateProp.previous .. ' = ' .. previousValue)
			end
		end
	end

	return '{ ' .. table.concat(export, ', ') .. ' }'
end

function GameUI.PrintState(state)
	print('[GameUI] ' .. GameUI.ExportState(state))
end

GameUI.On = GameUI.Listen

setmetatable(GameUI, {
	__index = function(_, key)
		local event = string.match(key, '^On(%w+)$')

		if event and GameUI.Event[event] then
			rawset(GameUI, key, function(callback)
				GameUI.Observe(event, callback)
			end)

			return rawget(GameUI, key)
		end
	end
})

return GameUI