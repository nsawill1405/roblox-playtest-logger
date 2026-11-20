-- Entries live in plugin settings (shared by the Edit, Play client and Play server copies of the
-- plugin, so logs made during a playtest survive pressing Stop). In Edit mode the store is also
-- mirrored into ServerStorage/PlaytestLogs so it is saved with the place.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local EntryModel = require(script.Parent.EntryModel)
local Markdown = require(script.Parent.Markdown)
local LongString = require(script.Parent.LongString)
local Signal = require(script.Parent.Signal)

local Store = {}

Store.ROOT_NAME = "PlaytestLogs"
Store.KEY_ATTRIBUTE = "PlaytestLoggerKey"
Store.Changed = Signal.new()

type Doc = { revision: number, entries: { EntryModel.Entry }, pending: { string } }

local plugin: Plugin? = nil
local placeKey = ""
local cache: Doc = { revision = 0, entries = {}, pending = {} }
local mirroredRevision = -1
local syncThread: thread? = nil

local function isEdit(): boolean
	return RunService:IsEdit()
end

local function settingsKey(): string
	return "PlaytestLogger/" .. placeKey
end

local function blobKey(name: string): string
	return settingsKey() .. "/blob/" .. name
end

local function resolvePlaceKey(): string
	local attribute = workspace:GetAttribute(Store.KEY_ATTRIBUTE)
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	if game.PlaceId ~= 0 then
		return "place_" .. tostring(game.PlaceId)
	end
	if isEdit() then
		-- Unsaved/local places have no PlaceId; tag the place so playtest copies resolve the same key.
		local key = HttpService:GenerateGUID(false)
		workspace:SetAttribute(Store.KEY_ATTRIBUTE, key)
		return key
	end
	return "unsaved_place"
end

local function readDoc(): Doc
	assert(plugin, "Store.init must be called first")
	local raw = plugin:GetSetting(settingsKey())
	if type(raw) ~= "string" or raw == "" then
		return { revision = 0, entries = {}, pending = {} }
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then
		warn("[PlaytestLogger] Could not read saved entries: " .. tostring(decoded))
		return { revision = 0, entries = {}, pending = {} }
	end
	local pending = {}
	if type(decoded.pending) == "table" then
		for _, name in decoded.pending do
			if type(name) == "string" then
				table.insert(pending, name)
			end
		end
	end
	return {
		revision = if type(decoded.revision) == "number" then decoded.revision else 0,
		entries = EntryModel.sanitizeCollection(decoded.entries),
		pending = pending,
	}
end

local function writeDoc(doc: Doc)
	assert(plugin, "Store.init must be called first")
	plugin:SetSetting(
		settingsKey(),
		HttpService:JSONEncode({ version = 1, revision = doc.revision, entries = doc.entries, pending = doc.pending })
	)
end

local function setSource(container: LuaSourceContainer, source: string)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(container, function()
			return source
		end)
	end)
	if not ok then
		(container :: any).Source = source
	end
end

local function ensureChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function splitName(name: string): (string, string)
	local folder, leaf = string.match(name, "^([^/]+)/(.+)$")
	return folder or "Misc", leaf or name
end

local function readPlaceBlob(name: string): string?
	local ok, result = pcall(function()
		local root = ServerStorage:FindFirstChild(Store.ROOT_NAME)
		local folderName, leaf = splitName(name)
		local folder = root and root:FindFirstChild(folderName)
		local item = folder and folder:FindFirstChild(leaf)
		if not item then
			return nil
		end
		if item:IsA("StringValue") then
			return item.Value
		elseif item:IsA("LuaSourceContainer") then
			return LongString.extract((item :: any).Source)
		end
		return nil
	end)
	return if ok then result else nil
end

-- Reads the revision and entries saved with the place (entries.json), if any.
local function readPlaceDoc(): (number?, { EntryModel.Entry })
	local ok, revision, entries = pcall(function()
		local root = ServerStorage:FindFirstChild(Store.ROOT_NAME)
		local item = root and root:FindFirstChild("entries.json")
		if not item or not item:IsA("LuaSourceContainer") then
			return nil, {}
		end
		local text = LongString.extract((item :: any).Source)
		local decoded = text and HttpService:JSONDecode(text)
		if type(decoded) ~= "table" then
			return nil, {}
		end
		return if type(decoded.revision) == "number" then decoded.revision else 0,
			EntryModel.sanitizeCollection(decoded.entries)
	end)
	if not ok then
		return nil, {}
	end
	return revision, entries
end

local function writePlaceBlob(root: Instance, name: string, data: string)
	local folderName, leaf = splitName(name)
	local folder = ensureChild(root, folderName, "Folder")
	if folderName == "ConsoleLogs" then
		local module = ensureChild(folder, leaf, "ModuleScript") :: ModuleScript
		setSource(module, LongString.comment(data) .. "\nreturn nil\n")
	else
		local value = ensureChild(folder, leaf, "StringValue") :: StringValue
		value.Value = data
	end
end

function Store.root(create: boolean?): Folder?
	if not isEdit() then
		return nil
	end
	local root = ServerStorage:FindFirstChild(Store.ROOT_NAME)
	if not root and create then
		root = Instance.new("Folder")
		root.Name = Store.ROOT_NAME
		root.Parent = ServerStorage
	end
	return root :: Folder?
end

-- Writes changes.md / entries.json, flushes blobs captured during playtests and prunes orphans.
local function mirror(doc: Doc)
	if not isEdit() then
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("PlaytestLoggerSync", "Update Playtest Logs")
	local ok, err = pcall(function()
		local root = Store.root(true) :: Folder
		for _, name in doc.pending do
			local data = plugin and plugin:GetSetting(blobKey(name))
			if type(data) == "string" then
				writePlaceBlob(root, name, data)
			end
		end

		local referenced = {}
		for _, entry in doc.entries do
			if entry.screenshot ~= "" then
				referenced[entry.screenshot] = true
			end
			if entry.consoleLog ~= "" then
				referenced[entry.consoleLog] = true
			end
		end
		for _, folderName in { "Screenshots", "ConsoleLogs" } do
			local folder = root:FindFirstChild(folderName)
			if folder then
				for _, child in folder:GetChildren() do
					if not referenced[folderName .. "/" .. child.Name] then
						child:Destroy()
					end
				end
			end
		end

		local md = ensureChild(root, "changes.md", "ModuleScript") :: ModuleScript
		setSource(
			md,
			LongString.comment(Markdown.build(doc.entries, "ServerStorage/" .. Store.ROOT_NAME)) .. "\nreturn nil\n"
		)
		local json = ensureChild(root, "entries.json", "ModuleScript") :: ModuleScript
		setSource(
			json,
			"return "
				.. LongString.literal(HttpService:JSONEncode({ revision = doc.revision, entries = doc.entries }))
				.. "\n"
		)
	end)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if not ok then
		warn("[PlaytestLogger] Failed to update ServerStorage/PlaytestLogs: " .. tostring(err))
		return
	end

	if #doc.pending > 0 and plugin then
		for _, name in doc.pending do
			plugin:SetSetting(blobKey(name), nil)
		end
		local fresh = readDoc()
		fresh.pending = {}
		writeDoc(fresh)
		doc.pending = {}
	end
	mirroredRevision = doc.revision
end

local function adopt(doc: Doc)
	local changed = doc.revision ~= cache.revision
	cache = doc
	if isEdit() and (doc.revision ~= mirroredRevision or #doc.pending > 0) then
		mirror(doc)
	end
	if changed then
		Store.Changed:Fire()
	end
end

function Store.init(pluginRef: Plugin)
	plugin = pluginRef
	placeKey = resolvePlaceKey()
	local doc = readDoc()
	cache = doc
	if isEdit() then
		-- The place is the source of truth when it is newer than this machine's settings
		-- (opened on another workstation, or settings were cleared).
		local placeRevision, placeEntries = readPlaceDoc()
		local settingsEmpty = doc.revision == 0 and #doc.entries == 0
		if placeRevision and (placeRevision > doc.revision or settingsEmpty) then
			-- Keep playtest entries whose captures were never flushed into the place.
			local merged = table.clone(placeEntries)
			for _, entry in doc.entries do
				local unflushed = table.find(doc.pending, entry.screenshot) or table.find(doc.pending, entry.consoleLog)
				if unflushed and not EntryModel.find(placeEntries, entry.id) then
					table.insert(merged, entry)
				end
			end
			doc.revision = if #merged > #placeEntries then placeRevision + 1 else placeRevision
			doc.entries = merged
			writeDoc(doc)
		end
		local inSync = placeRevision == doc.revision and #doc.pending == 0
		local nothingSaved = not placeRevision and #doc.entries == 0 and #doc.pending == 0
		if inSync or nothingSaved then
			mirroredRevision = doc.revision
		else
			mirror(doc)
		end
	end
	if not syncThread then
		syncThread = task.spawn(function()
			while true do
				task.wait(1)
				local ok, err = pcall(function()
					adopt(readDoc())
				end)
				if not ok then
					warn("[PlaytestLogger] Sync error: " .. tostring(err))
				end
			end
		end)
	end
end

function Store.stop()
	if syncThread then
		pcall(task.cancel, syncThread)
		syncThread = nil
	end
end

function Store.entries(): { EntryModel.Entry }
	return cache.entries
end

function Store.revision(): number
	return cache.revision
end

-- Applies `mutate` to a fresh copy of the entries and persists the result.
function Store.commit(mutate: ({ EntryModel.Entry }) -> ())
	local doc = readDoc()
	mutate(doc.entries)
	doc.revision += 1
	writeDoc(doc)
	adopt(doc)
end

function Store.add(entry: EntryModel.Entry)
	Store.commit(function(entries)
		table.insert(entries, entry)
	end)
end

function Store.update(id: string, mutate: (EntryModel.Entry) -> ())
	Store.commit(function(entries)
		local entry = EntryModel.find(entries, id)
		if entry then
			mutate(entry)
		end
	end)
end

function Store.remove(id: string)
	local removed: EntryModel.Entry? = nil
	Store.commit(function(entries)
		local entry, index = EntryModel.find(entries, id)
		if entry and index then
			removed = entry
			table.remove(entries, index)
		end
	end)
	if removed then
		Store.dropBlob(removed.screenshot)
		Store.dropBlob(removed.consoleLog)
	end
end

-- Saves a blob (screenshot pixels or console text). Must be called before the entry that
-- references it is committed, so the mirror never prunes it.
function Store.putBlob(name: string, data: string)
	assert(plugin, "Store.init must be called first")
	if isEdit() then
		local recording = ChangeHistoryService:TryBeginRecording("PlaytestLoggerBlob", "Save Playtest Log")
		local ok, err = pcall(writePlaceBlob, Store.root(true) :: Folder, name, data)
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		if ok then
			return
		end
		warn("[PlaytestLogger] Could not write " .. name .. ": " .. tostring(err))
	end
	plugin:SetSetting(blobKey(name), data)
	local doc = readDoc()
	if not table.find(doc.pending, name) then
		table.insert(doc.pending, name)
	end
	writeDoc(doc)
	cache.pending = doc.pending
end

function Store.getBlob(name: string): string?
	if name == "" then
		return nil
	end
	local pending = plugin and plugin:GetSetting(blobKey(name))
	if type(pending) == "string" then
		return pending
	end
	return readPlaceBlob(name)
end

function Store.dropBlob(name: string)
	if name == "" or not plugin then
		return
	end
	if plugin:GetSetting(blobKey(name)) ~= nil then
		plugin:SetSetting(blobKey(name), nil)
		local doc = readDoc()
		local index = table.find(doc.pending, name)
		if index then
			table.remove(doc.pending, index)
			writeDoc(doc)
		end
	end
end

function Store.findScript(name: string): LuaSourceContainer?
	local root = Store.root(false)
	if not root then
		return nil
	end
	local item: Instance? = nil
	if string.find(name, "/", 1, true) then
		local folderName, leaf = splitName(name)
		local folder = root:FindFirstChild(folderName)
		item = folder and folder:FindFirstChild(leaf)
	else
		item = root:FindFirstChild(name)
	end
	return if item and item:IsA("LuaSourceContainer") then item else nil
end

function Store.markdown(): string
	return Markdown.build(cache.entries, "ServerStorage/" .. Store.ROOT_NAME)
end

return Store
