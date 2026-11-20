local EntryModel = if script then require(script.Parent.EntryModel) else require("./EntryModel")

local Markdown = {}

local function code(text: string): string
	return "`" .. string.gsub(text, "`", "'") .. "`"
end

function Markdown.build(entries: { EntryModel.Entry }, rootPath: string?): string
	local root = rootPath or "ServerStorage/PlaytestLogs"
	local lines = { "# Playtest Change Log", "" }
	for _, e in entries do
		local check = if e.resolved then "x" else " "
		local description = string.gsub(e.description, "\r?\n", " ")
		table.insert(lines, `- [{check}] **[{e.category}]** {description}`)
		local meta = `  - Time: {code(e.timestamp)} | Place: {code(e.place)}`
		if e.context ~= "" then
			meta ..= " | " .. code(e.context)
		end
		table.insert(lines, meta)
		if e.target ~= "" then
			table.insert(lines, "  - Target: " .. code(e.target))
		end
		for i, marker in e.markers do
			table.insert(lines, `  - Marker #{i}: {code(marker.label)}`)
		end
		if e.screenshot ~= "" then
			table.insert(lines, "  - Screenshot: " .. code(root .. "/" .. e.screenshot))
		end
		if e.consoleLog ~= "" then
			table.insert(lines, "  - Console Log: " .. code(root .. "/" .. e.consoleLog))
		end
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

return Markdown
