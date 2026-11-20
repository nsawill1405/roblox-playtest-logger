local Categories = require("../src/Logger/Categories")

return {
	["keeps the Unity category list"] = function()
		assert(#Categories.list == 7 and Categories.list[1] == "UI & HUD" and Categories.list[7] == "Level & Map")
	end,
	["normalizes legacy and unknown categories"] = function()
		assert(Categories.normalize(nil) == "UI & HUD")
		assert(Categories.normalize("Bug") == "Bug")
		assert(Categories.normalize("UI/HUD") == "UI & HUD")
		assert(Categories.normalize("Map Design") == "Level & Map")
		assert(Categories.normalize("Something else") == "Todo")
	end,
	["gives every category a color"] = function()
		for _, category in Categories.list do
			assert(#Categories.rgb(category) == 3)
		end
		assert(Categories.indexOf("Camera") == 5)
	end,
}
