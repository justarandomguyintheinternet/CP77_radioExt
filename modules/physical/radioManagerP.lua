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
	-- for all radio objects: get radio station and disable with object's id
	-- release all object
end

return managerP