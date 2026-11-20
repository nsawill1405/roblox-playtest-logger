local EntryModel = require("../src/Logger/EntryModel")

local date = { year = 2026, month = 3, day = 4, hour = 5, min = 6, sec = 7 }

return {
	["builds sortable ids and timestamps"] = function()
		assert(EntryModel.newId(date, 1234567) == "20260304_050607_567")
		assert(EntryModel.newId(date, 5, 2) == "20260304_050607_005_2")
		assert(EntryModel.formatTimestamp(date) == "2026-03-04 05:06:07")
	end,
	["sanitizes decoded entries"] = function()
		local entries = EntryModel.sanitizeCollection({
			entries = {
				{ id = "a", category = "UI", markers = { { x = 2, y = -1, label = "Pin 1" }, "bad" }, resolved = true },
				{ id = "a" },
				{ description = "missing id" },
				{ id = "b", camera = { cframe = { 1, 2, 3 } } },
			},
		})
		assert(#entries == 2)
		local a = entries[1]
		assert(a.category == "UI & HUD" and a.resolved == true and a.description == "")
		assert(#a.markers == 1 and a.markers[1].x == 1 and a.markers[1].y == 0)
		assert(entries[2].camera == nil)
	end,
	["keeps valid camera views"] = function()
		local entry = EntryModel.sanitize({
			id = "c",
			camera = { cframe = { 0, 5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, fov = 70, width = 1920, height = 1080 },
		})
		assert(entry and entry.camera and entry.camera.width == 1920 and #entry.camera.cframe == 12)
	end,
	["counts and filters resolved entries"] = function()
		local entries = EntryModel.sanitizeCollection({ { id = "1", resolved = true }, { id = "2" }, { id = "3" } })
		local open, total = EntryModel.counts(entries)
		assert(open == 2 and total == 3)
		assert(#EntryModel.visible(entries, true) == 2 and #EntryModel.visible(entries, false) == 3)
		local found, index = EntryModel.find(entries, "3")
		assert(found and index == 3)
	end,
	["summarizes descriptions"] = function()
		assert(EntryModel.summary("") == "(no description)")
		assert(EntryModel.summary("  line one\nline two ") == "line one line two")
		local long = EntryModel.summary(string.rep("x", 100), 10)
		assert(#long == 10 and string.sub(long, -3) == "...")
		assert(EntryModel.shortTime("2026-03-04 05:06:07") == "05:06")
	end,
}
