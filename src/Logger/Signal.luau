local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	local handlers = self.handlers
	handlers[handler] = true
	return {
		Disconnect = function()
			handlers[handler] = nil
		end,
	}
end

function Signal:Fire(...)
	for handler in table.clone(self.handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
