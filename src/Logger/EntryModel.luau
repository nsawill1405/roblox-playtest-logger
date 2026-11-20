local Categories = if script then require(script.Parent.Categories) else require("./Categories")

local EntryModel = {}

export type Marker = { x: number, y: number, label: string }

export type CameraView = {
	cframe: { number },
	fov: number,
	width: number,
	height: number,
}

export type Entry = {
	id: string,
	timestamp: string,
	category: string,
	description: string,
	place: string,
	context: string,
	target: string,
	camera: CameraView?,
	screenshot: string,
	consoleLog: string,
	resolved: boolean,
	markers: { Marker },
}

local function str(value: any, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function num(value: any, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

function EntryModel.clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function EntryModel.newId(date: { [string]: number }, millis: number, salt: number?): string
	local base = string.format(
		"%04d%02d%02d_%02d%02d%02d_%03d",
		date.year,
		date.month,
		date.day,
		date.hour,
		date.min,
		date.sec,
		math.floor(millis) % 1000
	)
	if salt and salt > 0 then
		base ..= string.format("_%d", salt)
	end
	return base
end

function EntryModel.formatTimestamp(date: { [string]: number }): string
	return string.format(
		"%04d-%02d-%02d %02d:%02d:%02d",
		date.year,
		date.month,
		date.day,
		date.hour,
		date.min,
		date.sec
	)
end

function EntryModel.sanitizeMarker(raw: any): Marker?
	if type(raw) ~= "table" then
		return nil
	end
	return {
		x = EntryModel.clamp01(num(raw.x, 0.5)),
		y = EntryModel.clamp01(num(raw.y, 0.5)),
		label = str(raw.label, ""),
	}
end

function EntryModel.sanitizeCamera(raw: any): CameraView?
	if type(raw) ~= "table" or type(raw.cframe) ~= "table" or #raw.cframe ~= 12 then
		return nil
	end
	local components = {}
	for i = 1, 12 do
		components[i] = num(raw.cframe[i], 0)
	end
	return {
		cframe = components,
		fov = math.clamp(num(raw.fov, 70), 1, 120),
		width = math.max(1, num(raw.width, 1280)),
		height = math.max(1, num(raw.height, 720)),
	}
end

function EntryModel.sanitize(raw: any): Entry?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then
		return nil
	end
	local markers = {}
	if type(raw.markers) == "table" then
		for _, m in raw.markers do
			local marker = EntryModel.sanitizeMarker(m)
			if marker then
				table.insert(markers, marker)
			end
		end
	end
	return {
		id = raw.id,
		timestamp = str(raw.timestamp, ""),
		category = Categories.normalize(raw.category),
		description = str(raw.description, ""),
		place = str(raw.place, ""),
		context = str(raw.context, ""),
		target = str(raw.target, ""),
		camera = EntryModel.sanitizeCamera(raw.camera),
		screenshot = str(raw.screenshot, ""),
		consoleLog = str(raw.consoleLog, ""),
		resolved = raw.resolved == true,
		markers = markers,
	}
end

function EntryModel.sanitizeCollection(raw: any): { Entry }
	local entries = {}
	local seen = {}
	local list = if type(raw) == "table" then (raw.entries or raw) else nil
	if type(list) ~= "table" then
		return entries
	end
	for _, item in list do
		local entry = EntryModel.sanitize(item)
		if entry and not seen[entry.id] then
			seen[entry.id] = true
			table.insert(entries, entry)
		end
	end
	return entries
end

function EntryModel.counts(entries: { Entry }): (number, number)
	local open = 0
	for _, entry in entries do
		if not entry.resolved then
			open += 1
		end
	end
	return open, #entries
end

function EntryModel.visible(entries: { Entry }, hideResolved: boolean): { Entry }
	local out = {}
	for _, entry in entries do
		if not (hideResolved and entry.resolved) then
			table.insert(out, entry)
		end
	end
	return out
end

function EntryModel.find(entries: { Entry }, id: string): (Entry?, number?)
	for i, entry in entries do
		if entry.id == id then
			return entry, i
		end
	end
	return nil, nil
end

function EntryModel.summary(text: string?, maxLength: number?): string
	local limit = maxLength or 42
	local line = string.gsub(string.gsub(text or "", "[\r\n]+", " "), "^%s+", "")
	line = string.gsub(line, "%s+$", "")
	if line == "" then
		return "(no description)"
	end
	if utf8.len(line) and (utf8.len(line) :: number) > limit then
		local cut = utf8.offset(line, limit - 2) or (limit - 2)
		return string.sub(line, 1, cut - 1) .. "..."
	end
	return line
end

function EntryModel.shortTime(timestamp: string): string
	if #timestamp >= 16 then
		return string.sub(timestamp, 12, 16)
	end
	return timestamp
end

return EntryModel
