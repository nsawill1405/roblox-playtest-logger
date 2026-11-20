local ConsoleBuffer = {}
ConsoleBuffer.__index = ConsoleBuffer

ConsoleBuffer.MAX_LINES = 80

export type ConsoleBuffer = typeof(setmetatable({} :: { lines: { string }, max: number }, ConsoleBuffer))

function ConsoleBuffer.new(max: number?): ConsoleBuffer
	return setmetatable({ lines = {}, max = max or ConsoleBuffer.MAX_LINES }, ConsoleBuffer)
end

function ConsoleBuffer.format(clock: string, kind: string, message: string): string
	return `[{clock}] [{kind}] {message}`
end

function ConsoleBuffer.push(self: ConsoleBuffer, line: string)
	table.insert(self.lines, line)
	while #self.lines > self.max do
		table.remove(self.lines, 1)
	end
end

function ConsoleBuffer.snapshot(self: ConsoleBuffer): { string }
	return table.clone(self.lines)
end

export type SnapshotInfo = {
	timestamp: string,
	place: string,
	context: string,
	markers: { { label: string } }?,
}

function ConsoleBuffer.buildSnapshot(info: SnapshotInfo, lines: { string }): string
	local out = {
		"=== Playtest Console Snapshot ===",
		"Timestamp: " .. info.timestamp,
		"Place: " .. info.place,
		"Context: " .. info.context,
	}
	for i, marker in info.markers or {} do
		table.insert(out, `Marker #{i}: {marker.label}`)
	end
	table.insert(out, "---------------------------------")
	for _, line in lines do
		table.insert(out, line)
	end
	return table.concat(out, "\n") .. "\n"
end

return ConsoleBuffer
