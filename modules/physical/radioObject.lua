local object = {}

function object:new()
	local o = {}

    o.handle = nil
    o.channelID = 0
    o.radio = nil

	self.__index = self
   	return setmetatable(o, self)
end

function object:init(radio, id, handle)
    self.channelID = id
    self.radio = radio
    self.handle = handle
    self.radio:activate(self.channelID)
end

function object:uninit()
    self.handle = nil
    self.radio:deactivate(self.channelID)
end

function object:switchToRadio(radio)
    if self.radio then
        self.radio:deactivate(self.channelID)
    end
    self.radio = radio
    self.radio:activate(self.channelID)
end

function object:update()
    RadioExt.SetChannelPos(self.channelID, self.handle:GetWorldPosition())
end

return object