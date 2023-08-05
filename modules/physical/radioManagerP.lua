local managerP = {}

function managerP:new(radioMod)
	local o = {}

    o.rm = radioMod
    o.radioObjects = {}

	self.__index = self
   	return setmetatable(o, self)
end

function managerP:init()

end

return managerP