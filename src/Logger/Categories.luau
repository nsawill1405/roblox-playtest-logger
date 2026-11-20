local Categories = {}

Categories.list = {
	"UI & HUD",
	"Todo",
	"Bug",
	"Physics & Controls",
	"Camera",
	"Visuals & Shaders",
	"Level & Map",
}

local COLORS = {
	["UI & HUD"] = { 41, 143, 194 },
	["Todo"] = { 194, 133, 41 },
	["Bug"] = { 204, 66, 71 },
	["Physics & Controls"] = { 133, 87, 199 },
	["Camera"] = { 61, 117, 204 },
	["Visuals & Shaders"] = { 46, 158, 133 },
	["Level & Map"] = { 71, 158, 82 },
}

local PREFIXES = {
	{ "UI", "UI & HUD" },
	{ "Todo", "Todo" },
	{ "Bug", "Bug" },
	{ "Physics", "Physics & Controls" },
	{ "Camera", "Camera" },
	{ "Visuals", "Visuals & Shaders" },
	{ "Level", "Level & Map" },
	{ "Map", "Level & Map" },
}

function Categories.normalize(category: string?): string
	if type(category) ~= "string" or category == "" then
		return Categories.list[1]
	end
	if COLORS[category] then
		return category
	end
	for _, pair in PREFIXES do
		if string.sub(category, 1, #pair[1]) == pair[1] then
			return pair[2]
		end
	end
	return "Todo"
end

function Categories.indexOf(category: string): number
	return table.find(Categories.list, Categories.normalize(category)) or 1
end

function Categories.rgb(category: string?): { number }
	return COLORS[Categories.normalize(category)] or { 97, 107, 128 }
end

return Categories
