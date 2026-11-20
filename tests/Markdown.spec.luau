local EntryModel = require("../src/Logger/EntryModel")
local Markdown = require("../src/Logger/Markdown")

return {
	["writes a checklist like the Unity changes.md"] = function()
		local entries = EntryModel.sanitizeCollection({
			{
				id = "1",
				timestamp = "2026-03-04 05:06:07",
				category = "Bug",
				description = "Health bar\noverlaps",
				place = "Obby",
				context = "PlayMode (Client) | PlayerPos=(0.0, 3.0, 0.0)",
				target = "UI: HUD/Health",
				markers = { { x = 0.1, y = 0.2, label = "UI: HUD/Health" } },
				screenshot = "Screenshots/1",
				consoleLog = "ConsoleLogs/1",
			},
			{ id = "2", category = "Todo", description = "done thing", resolved = true },
		})
		local md = Markdown.build(entries)
		assert(string.sub(md, 1, 21) == "# Playtest Change Log")
		assert(string.find(md, "- [ ] **[Bug]** Health bar overlaps", 1, true))
		assert(string.find(md, "  - Time: `2026-03-04 05:06:07` | Place: `Obby` | `PlayMode (Client)", 1, true))
		assert(string.find(md, "  - Marker #1: `UI: HUD/Health`", 1, true))
		assert(string.find(md, "  - Screenshot: `ServerStorage/PlaytestLogs/Screenshots/1`", 1, true))
		assert(string.find(md, "  - Console Log: `ServerStorage/PlaytestLogs/ConsoleLogs/1`", 1, true))
		assert(string.find(md, "- [x] **[Todo]** done thing", 1, true))
	end,
}
