-- Wraps arbitrary text in Luau long brackets so it can live inside a script's Source.
local LongString = {}

local function level(text: string): string
	local n = 0
	while string.find(text, "]" .. string.rep("=", n) .. "]", 1, true) do
		n += 1
	end
	return string.rep("=", n)
end

function LongString.comment(text: string): string
	local eq = level(text)
	return `--[{eq}[\n{text}\n]{eq}]`
end

function LongString.literal(text: string): string
	local eq = level(text)
	return `[{eq}[\n{text}]{eq}]`
end

-- Returns the contents of the first long bracket block in `source`, or nil.
function LongString.extract(source: string): string?
	local open, openEnd, eq = string.find(source, "%[(=*)%[")
	if not open then
		return nil
	end
	local close = string.find(source, "]" .. eq .. "]", openEnd + 1, true)
	if not close then
		return nil
	end
	local body = string.sub(source, openEnd + 1, close - 1)
	if string.sub(body, 1, 1) == "\n" then
		body = string.sub(body, 2)
	end
	if string.sub(body, -1) == "\n" then
		body = string.sub(body, 1, -2)
	end
	return body
end

return LongString
