local utils = require("modules/utils/utils")

local managerP = {}

function managerP:new(manager)
	local o = {}

    o.manager = manager
    o.radioObjects = {}

	self.__index = self
   	return setmetatable(o, self)
end

function managerP:init()

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
			print("create", i)
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
		print("remove", object.channelID)
	end
end

function managerP:update()
	for _, object in pairs(self.radioObjects) do
		object.radio:activate(object.channelID)
		object:update()
	end
	RadioExt.SetListener(GetPlayer():GetWorldPosition(), GetPlayer():GetWorldForward(), GetPlayer():GetWorldUp())
end

function managerP:handleMenu()
	for _, object in pairs(self.radioObjects) do
		object.radio:deactivate(object.channelID)
	end
end

return managerP