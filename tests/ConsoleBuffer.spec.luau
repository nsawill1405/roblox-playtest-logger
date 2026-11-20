local ConsoleBuffer = require("../src/Logger/ConsoleBuffer")

return {
	["keeps only the newest lines"] = function()
		local buffer = ConsoleBuffer.new(3)
		for i = 1, 5 do
			buffer:push(tostring(i))
		end
		local lines = buffer:snapshot()
		assert(#lines == 3 and lines[1] == "3" and lines[3] == "5")
	end,
	["defaults to 80 lines like the Unity logger"] = function()
		assert(ConsoleBuffer.new().max == 80)
	end,
	["formats lines and snapshots"] = function()
		assert(ConsoleBuffer.format("12:00:01", "Error", "boom") == "[12:00:01] [Error] boom")
		local text = ConsoleBuffer.buildSnapshot({
			timestamp = "2026-01-01 12:00:00",
			place = "Place1",
			context = "EditMode",
			markers = { { label = "UI: HUD/Health" } },
		}, { "[12:00:01] [Output] hi" })
		assert(string.find(text, "=== Playtest Console Snapshot ===", 1, true))
		assert(string.find(text, "Marker #1: UI: HUD/Health", 1, true))
		assert(string.find(text, "[12:00:01] [Output] hi\n", 1, true))
	end,
}
