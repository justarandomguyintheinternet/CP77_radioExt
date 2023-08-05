local object = {}

function object:new(radioMod)
	local o = {}

    o.rm = radioMod
    o.handle = nil
    o.channelID = 0

	self.__index = self
   	return setmetatable(o, self)
end

function object:init()

end

return object