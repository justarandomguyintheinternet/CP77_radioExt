--[[
GameSettings.lua
Game Settings Manager
Copyright (c) 2021 psiberx
]]

local GameSettings = { version = '1.0.4' }

local module = {}

function module.parsePath(setting)
	return setting:match('^(/.+)/([A-Za-z0-9_]+)$')
end

function module.makePath(groupPath, varName)
	return groupPath .. '/' .. varName
end

function module.isBoolType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'Bool'
end

function module.isNameType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'Name' or target == 'NameList'
end

function module.isNumberType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'Int' or target == 'Float'
end

function module.isIntType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'Int' or target == 'IntList'
end

function module.isFloatType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'Float' or target == 'FloatList'
end

function module.isListType(target)
	if type(target) == 'userdata' then
		target = target.value
	end

	return target == 'IntList' or target == 'FloatList' or target == 'StringList' or target == 'NameList'
end

function module.exportVar(var)
	local output = {}

	output.path = module.makePath(Game.NameToString(var:GetGroupPath()), Game.NameToString(var:GetName()))
	output.value = var:GetValue()
	output.type = var:GetType().value

	if module.isNameType(output.type) then
		output.value = Game.NameToString(output.value)
	end

	if module.isNumberType(output.type)  then
		output.min = var:GetMinValue()
		output.max = var:GetMaxValue()
		output.step = var:GetStepValue()
	end

	if module.isListType(output.type)  then
		output.index = var:GetIndex() + 1
		output.options = var:GetValues()

		if module.isNameType(output.type) then
			for i, option in ipairs(output.options) do
				output.options[i] = Game.NameToString(option)
			end
		end
	end

	return output
end

function module.exportVars(isPreGame, group, output)
	if type(group) ~= 'userdata' then
		group = Game.GetSettingsSystem():GetRootGroup()
	end

	if type(isPreGame) ~= 'bool' then
		isPreGame = GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame()
	end

	if not output then
		output = {}
	end

	for _, var in ipairs(group:GetVars(isPreGame)) do
		table.insert(output, module.exportVar(var))
	end

	for _, child in ipairs(group:GetGroups(isPreGame)) do
		module.exportVars(isPreGame, child, output)
	end

	table.sort(output, function(a, b)
		return a.path < b.path
	end)

	return output
end

function GameSettings.Has(setting)
	local path, name = module.parsePath(setting)

	return Game.GetSettingsSystem():HasVar(path, name)
end

function GameSettings.Var(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var then
		return nil
	end

	return module.exportVar(var)
end

function GameSettings.Get(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var then
		return nil
	end

	return var:GetValue()
end

function GameSettings.GetIndex(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var or not module.isListType(var:GetType()) then
		return nil
	end

	return var:GetIndex() + 1
end

function GameSettings.Set(setting, value)
	local path, name = module.parsePath(setting)
	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var then
		return
	end

	if module.isListType(var:GetType()) then
		local index = var:GetIndexFor(value)

		if index then
			var:SetIndex(index)
		end
	else
		var:SetValue(value)
	end
end

function GameSettings.SetIndex(setting, index)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var or not module.isListType(var:GetType()) then
		return
	end

	var:SetIndex(index - 1)
end

function GameSettings.Toggle(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var or not module.isBoolType(var:GetType()) then
		return
	end

	var:Toggle()
end

function GameSettings.ToggleAll(settings)
	local state = not GameSettings.Get(settings[1])

	for _, setting in ipairs(settings) do
		GameSettings.Set(setting, state)
	end
end

function GameSettings.ToggleGroup(path)
	local group = Game.GetSettingsSystem():GetGroup(path)
	local vars = group:GetVars(false)
	local state = nil

	for _, var in ipairs(vars) do
		if module.isBoolType(var:GetType()) then
			-- Invert the first bool option
			if state == nil then
				state = not var:GetValue()
			end

			var:SetValue(state)
		end
	end
end

function GameSettings.Options(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var or not module.isListType(var:GetType()) then
		return nil
	end

	return var:GetValues(), var:GetIndex() + 1
end

function GameSettings.Reset(setting)
	local path, name = module.parsePath(setting)

	local var = Game.GetSettingsSystem():GetVar(path, name)

	if not var then
		return
	end

	var:RestoreDefault()
end

function GameSettings.NeedsConfirmation()
	return Game.GetSettingsSystem():NeedsConfirmation()
end

function GameSettings.NeedsReload()
	return Game.GetSettingsSystem():NeedsLoadLastCheckpoint()
end

function GameSettings.NeedsRestart()
	return Game.GetSettingsSystem():NeedsRestartToApply()
end

function GameSettings.Confirm()
	Game.GetSettingsSystem():ConfirmChanges()
end

function GameSettings.Reject()
	Game.GetSettingsSystem():RejectChanges()
end

function GameSettings.Save()
	GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():RequestSaveUserSettings()
end

function GameSettings.Export(isPreGame)
	return module.exportVars(isPreGame)
end

function GameSettings.ExportTo(exportPath, isPreGame, keyBinds)
	local output = {}
	local isPreGame = GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame()

	local vars = module.exportVars(isPreGame)

	for _, var in ipairs(vars) do
		if (not keyBinds and (var.path:match('^/key_bindings/') == nil)) or keyBinds then 
			local value = var.value
			local options

			if type(value) == 'string' then
				value = string.format('%q', value)
			end

			if var.options and #var.options > 1 then
				options = {}

				for i, option in ipairs(var.options) do
					--if type(option) == 'string' then
					--	option = string.format('%q', option)
					--end

					options[i] = option
				end

				options = ' -- ' .. table.concat(options, ' | ')
			elseif var.min then
				if module.isIntType(var.type) then
					options = (' -- %d to %d / %d'):format(var.min, var.max, var.step)
				else
					options = (' -- %.2f to %.2f / %.2f'):format(var.min, var.max, var.step)
				end
			end

			table.insert(output, ('  ["%s"] = %s,%s'):format(var.path, value, options or ''))
		end
	end

	table.insert(output, 1, '{')
	table.insert(output, '}')

	output = table.concat(output, '\n')

	if exportPath then
		if not exportPath:find('%.lua$') then
			exportPath = exportPath .. '.lua'
		end

		local exportFile = io.open(exportPath, 'w')

		if exportFile then
			exportFile:write('return ')
			exportFile:write(output)
			exportFile:close()
		end
	else
		return output
	end
end

function GameSettings.Import(settings)
	for setting, value in pairs(settings) do
		GameSettings.Set(setting, value)
		if GameSettings.NeedsConfirmation() then
        	GameSettings.Confirm()
    	end
	end
end

function GameSettings.ImportFrom(importPath)
	local importChunk = loadfile(importPath)

	if importChunk then
		GameSettings.Import(importChunk())
	end
end

function GameSettings.DumpVars(isPreGame)
	return GameSettings.ExportTo(nil, isPreGame, true)
end

function GameSettings.PrintVars(isPreGame)
	print(GameSettings.DumpVars(isPreGame))
end

return GameSettings