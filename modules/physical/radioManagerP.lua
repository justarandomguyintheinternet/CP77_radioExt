local utils = require("modules/utils/utils")

---@class radioManagerP
---@field manager radioManager
---@field radioObjects table
---@field cameraTransform userdata
local managerP = {}

function managerP:new(manager)
	local o = {}

    o.manager = manager
    o.radioObjects = {}
	o.cameraTransform = nil

	self.__index = self
   	return setmetatable(o, self)
end

function managerP:init()
	self.cameraTransform = Transform.new()
end

function managerP:uninit()
	for _, object in pairs(self.radioObjects) do
		object.radio:deactivate(object.channelID)
	end
	self.radioObjects = {}
end

function managerP:getObjectByHandle(handle)
	for _, object in pairs(self.radioObjects) do
		if utils.isSameInstance(object.handle, handle) then
			return object
		end
	end
end

function managerP:createObject(handle, station)
	local obj = require("modules/physical/radioObject"):new()

	for i = 1, RadioExt.GetNumChannels() do
		if self.radioObjects[i] == nil then
			obj:init(station, i, handle)
			self.radioObjects[i] = obj
			return
		end
	end

	print("[RadioExt] Error: All channels used (Too many radios)")
end

function managerP:removeObjectByHandle(handle)
	local object = self:getObjectByHandle(handle)

	if object then
		object:uninit()
		self.radioObjects[object.channelID] = nil
	end
end

function managerP:update()
	for channelID, object in pairs(self.radioObjects) do
		object.radio:activate(object.channelID)
		if not object:update() then
			object:uninit()
			self.radioObjects[channelID] = nil
		end
	end

	if next(self.radioObjects) == nil then return end

	Game.GetCameraSystem():GetActiveCameraWorldTransform(self.cameraTransform)
	RadioExt.SetListener(self.cameraTransform.position, GetPlayer():GetWorldForward(), GetPlayer():GetWorldUp())
end

function managerP:handleMenu()
	for _, object in pairs(self.radioObjects) do
		object.radio:deactivate(object.channelID)
	end
end

return managerP
