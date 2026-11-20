local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Build = require(script.Parent.Build)
local Theme = require(script.Parent.Theme)
local ShotView = require(script.Parent.ShotView)
local Logger = script.Parent.Parent.Logger
local Categories = require(Logger.Categories)
local EntryModel = require(Logger.EntryModel)
local ConsoleBuffer = require(Logger.ConsoleBuffer)
local Capture = require(Logger.Capture)
local Context = require(Logger.Context)
local Store = require(Logger.Store)

local App = {}
App.__index = App

local HINT = "Click to add pin  •  Drag pin to adjust  •  Right-click pin to remove"

type Draft = {
	view: EntryModel.CameraView?,
	blob: string?,
	blobName: string,
	tempId: string?,
	markers: { EntryModel.Marker },
	description: string,
	category: string,
	capturing: boolean,
}

local function now(): ({ [string]: number }, number)
	local date = os.date("*t") :: any
	return date, DateTime.now().UnixTimestampMillis
end

local idSalt = 0
local function newId(): string
	local date, millis = now()
	idSalt += 1
	return EntryModel.newId(date, millis, idSalt % 100)
end

function App.new(plugin: Plugin, widget: DockWidgetPluginGui, console: ConsoleBuffer.ConsoleBuffer)
	local self = setmetatable({}, App)
	self.plugin = plugin
	self.widget = widget
	self.console = console
	self.tab = "new"
	self.expandedId = ""
	self.confirmDeleteId = ""
	self.hideResolved = plugin:GetSetting("PlaytestLogger/hideResolved") == true
	self.includeScreenshot = plugin:GetSetting("PlaytestLogger/includeScreenshot") ~= false
	self.includeLogs = plugin:GetSetting("PlaytestLogger/includeLogs") ~= false
	self.pauseOnQuickCapture = plugin:GetSetting("PlaytestLogger/pauseOnQuickCapture") == true
	self.tempIds = {} :: { [string]: string }
	self.shotViews = {}
	self.focusedBoxes = 0
	self.renderQueued = false
	self.draft = self:emptyDraft()
	self.connections = {}

	self.categoryMenu = plugin:CreatePluginMenu("PlaytestLoggerCategories", "Category")
	self.categoryActions = {}
	for index, category in Categories.list do
		local action = self.categoryMenu:AddNewAction("PlaytestLoggerCategory" .. index, category)
		self.categoryActions[action.ActionId] = category
	end

	self.moreMenu = plugin:CreatePluginMenu("PlaytestLoggerMore", "Playtest Logger")
	self.moreActions = {
		quick = self.moreMenu:AddNewAction("PlaytestLoggerQuickShot", "Quick Screenshot Now"),
	}
	self.moreMenu:AddSeparator()
	self.moreActions.folder = self.moreMenu:AddNewAction("PlaytestLoggerShowFolder", "Show PlaytestLogs in Explorer")
	self.moreActions.changes = self.moreMenu:AddNewAction("PlaytestLoggerOpenChanges", "Open changes.md")
	self.moreActions.json = self.moreMenu:AddNewAction("PlaytestLoggerOpenJson", "Open entries.json")
	self.moreActions.copy = self.moreMenu:AddNewAction("PlaytestLoggerCopyMarkdown", "Copy Markdown...")

	self:buildShell()
	table.insert(
		self.connections,
		Store.Changed:Connect(function()
			self:requestRender()
		end)
	)
	local themeConnection = Theme.onChanged(function()
		self:buildShell()
		self:render()
	end)
	if themeConnection then
		table.insert(self.connections, themeConnection)
	end
	self:render()
	return self
end

function App:emptyDraft(): Draft
	return {
		view = nil,
		blob = nil,
		blobName = "",
		tempId = nil,
		markers = {},
		description = "",
		category = if self.draft then self.draft.category else Categories.list[1],
		capturing = false,
	}
end

-- Shell ----------------------------------------------------------------------------------------

function App:buildShell()
	if self.root then
		self:destroyShots()
		self.root:Destroy()
	end
	local palette = Theme.palette()
	self.root = Build.make("Frame", {
		Name = "PlaytestLogger",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = palette.background,
		Parent = self.widget,
	})

	local header = Build.make("Frame", {
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = palette.header,
		Parent = self.root,
	}, { Build.padding(8, 10, 8, 10) })
	Build.label("Playtest Logger", {
		FontFace = Theme.FONT_BOLD,
		TextSize = 16,
		Size = UDim2.new(1, -40, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		Parent = header,
	})
	Build.button("•••", "ghost", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(34, 24),
		Parent = header,
	}, function()
		self:showMoreMenu()
	end)

	local tabs = Build.make("Frame", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = header,
	}, { Build.list(6, true) })
	self.newTab = Build.button("+ New Entry", "subtle", {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(0.38, -3, 1, 0),
		LayoutOrder = 1,
		Parent = tabs,
	}, function()
		self.tab = "new"
		self:render()
	end)
	self.savedTab = Build.button("Saved Entries", "subtle", {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(0.62, -3, 1, 0),
		LayoutOrder = 2,
		Parent = tabs,
	}, function()
		self.tab = "saved"
		self:render()
	end)

	self.banner = Build.label("", {
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.None,
		BackgroundColor3 = Theme.ACCENT,
		BackgroundTransparency = 0.15,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		Visible = false,
		ZIndex = 10,
		Parent = self.root,
	})

	self.body = Build.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 1, -74),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = self.root,
	}, { Build.list(8), Build.padding(8, 10, 12, 10) })
	self.body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:resizeShots()
	end)

	self.overlay = nil
end

function App:showBanner(text: string)
	self.banner.Text = text
	self.banner.Visible = true
	local token = {}
	self.bannerToken = token
	task.delay(2.8, function()
		if self.bannerToken == token and self.banner then
			self.banner.Visible = false
		end
	end)
end

function App:destroyShots()
	for _, view in self.shotViews do
		view:destroy()
	end
	table.clear(self.shotViews)
end

function App:resizeShots()
	local width = self.body.AbsoluteSize.X - 20 - 26
	for _, view in self.shotViews do
		view:resize(width)
	end
end

function App:requestRender()
	if self.focusedBoxes > 0 then
		self.renderQueued = true
		return
	end
	self:render()
end

function App:trackFocus(box: TextBox, onCommit: (string) -> ())
	box.Focused:Connect(function()
		self.focusedBoxes += 1
	end)
	box.FocusLost:Connect(function()
		self.focusedBoxes = math.max(0, self.focusedBoxes - 1)
		onCommit(box.Text)
		if self.renderQueued and self.focusedBoxes == 0 then
			self.renderQueued = false
			task.defer(function()
				self:render()
			end)
		end
	end)
end

function App:render()
	local palette = Theme.palette()
	local open, total = EntryModel.counts(Store.entries())
	self.savedTab.Text = `Saved Entries ({open} open • {total} total)`
	for tab, button in { new = self.newTab, saved = self.savedTab } do
		local active = self.tab == tab
		button.BackgroundColor3 = if active then palette.tabActive else palette.button
		button.FontFace = if active then Theme.FONT_BOLD else Theme.FONT
	end

	local scroll = self.body.CanvasPosition
	self:destroyShots()
	for _, child in self.body:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	self.focusedBoxes = 0

	if self.tab == "new" then
		self:renderNewEntry()
	else
		self:renderSaved()
	end
	self:resizeShots()
	task.defer(function()
		self.body.CanvasPosition = scroll
	end)
end

-- Shared pieces --------------------------------------------------------------------------------

function App:categoryButton(current: string, parent: Instance, layoutOrder: number, onPick: (string) -> ())
	local rgb = Categories.rgb(current)
	local button = Build.make("TextButton", {
		Text = current .. "  ▾",
		BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = Theme.FONT_BOLD,
		TextSize = 13,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = layoutOrder,
		Parent = parent,
	}, { Build.corner(13), Build.padding(0, 12, 0, 12) })
	button.Activated:Connect(function()
		local action = self.categoryMenu:ShowAsync()
		local picked = action and self.categoryActions[action.ActionId]
		if picked and picked ~= current then
			onPick(picked)
		end
	end)
	return button
end

function App:markerList(markers: { EntryModel.Marker }, parent: Instance, layoutOrder: number, onChanged: () -> ())
	if #markers == 0 then
		return
	end
	local list = Build.make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder,
		Parent = parent,
	}, { Build.list(4) })
	for index, marker in markers do
		local row = Build.make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = index,
			Parent = list,
		})
		Build.make("TextLabel", {
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(0, 2),
			BackgroundColor3 = Theme.PIN,
			Text = tostring(index),
			TextColor3 = Color3.new(1, 1, 1),
			FontFace = Theme.FONT_BOLD,
			TextSize = 12,
			Parent = row,
		}, { Build.corner(11) })
		local box = Build.textBox(marker.label, {
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -64, 0, 26),
			TextWrapped = false,
			TextYAlignment = Enum.TextYAlignment.Center,
			ClipsDescendants = true,
			TextSize = 13,
			PlaceholderText = "Marker label",
			Parent = row,
		})
		self:trackFocus(box, function(text)
			if text ~= marker.label then
				marker.label = text
				onChanged()
			end
		end)
		Build.button("✕", "subtle", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(28, 26),
			Parent = row,
		}, function()
			table.remove(markers, index)
			onChanged()
		end)
	end
end

function App:addShot(props: { [string]: any })
	props.widget = self.widget
	props.root = self.root
	local view = ShotView.new(props :: any)
	table.insert(self.shotViews, view)
	return view
end

-- Capture --------------------------------------------------------------------------------------

function App:captureDraft()
	local draft = self.draft
	draft.view = Capture.cameraView()
	draft.blob, draft.tempId, draft.blobName = nil, nil, ""
	draft.capturing = true
	ShotView.forgetScene(draft.view :: EntryModel.CameraView)
	if self.tab == "new" then
		self:render()
	end
	local blob, tempId = Capture.screenshotAsync()
	if self.draft ~= draft then
		return
	end
	draft.blob, draft.tempId = blob, tempId
	draft.blobName = if blob then "Screenshots/" .. newId() else ""
	draft.capturing = false
	if self.tab == "new" then
		self:requestRender()
	end
end

function App:quickCapture()
	if self.pauseOnQuickCapture and RunService:IsRunning() then
		pcall(function()
			RunService:Pause()
		end)
	end
	self.tab = "new"
	self.widget.Enabled = true
	self:captureDraft()
	self:showBanner("Captured fresh screenshot (" .. Context.mode() .. ")")
end

function App:ensureDraft()
	if not self.draft.view and not self.draft.capturing then
		self.draft.capturing = true
		task.defer(function()
			self:captureDraft()
		end)
	end
end

function App:saveDraft(quickScreenshotOnly: boolean)
	local draft = self.draft
	if not draft.view then
		draft.view = Capture.cameraView()
	end
	local date = now()
	local id = newId()
	local timestamp = EntryModel.formatTimestamp(date)
	local place = Context.placeName()
	local context = Context.describe()
	local markers = table.clone(draft.markers)

	local screenshot = ""
	if (self.includeScreenshot or quickScreenshotOnly) and draft.blob then
		screenshot = draft.blobName
		Store.putBlob(screenshot, draft.blob)
	end
	local consoleLog = ""
	if self.includeLogs then
		consoleLog = "ConsoleLogs/" .. id
		Store.putBlob(
			consoleLog,
			ConsoleBuffer.buildSnapshot({
				timestamp = timestamp,
				place = place,
				context = context,
				markers = markers,
			}, self.console:snapshot())
		)
	end

	local description = draft.description
	if quickScreenshotOnly and description == "" then
		description = "Quick screenshot"
	end
	local entry: EntryModel.Entry = {
		id = id,
		timestamp = timestamp,
		category = draft.category,
		description = description,
		place = place,
		context = context,
		target = if markers[1] then markers[1].label else "",
		camera = if self.includeScreenshot or quickScreenshotOnly then draft.view else nil,
		screenshot = screenshot,
		consoleLog = consoleLog,
		resolved = false,
		markers = markers,
	}
	if draft.tempId and screenshot == "" then
		self.tempIds[id] = draft.tempId
	end
	self.draft = self:emptyDraft()
	Store.add(entry)
	self:showBanner(if quickScreenshotOnly then "Saved quick screenshot" else "Saved entry")
	self:render()
end

function App:retake(entry: EntryModel.Entry)
	local view = Capture.cameraView()
	ShotView.forgetScene(view)
	local blob, tempId = Capture.screenshotAsync()
	local name = ""
	if blob then
		name = "Screenshots/" .. newId()
		Store.putBlob(name, blob)
	end
	self.tempIds[entry.id] = if blob then nil else tempId
	local old = entry.screenshot
	Store.update(entry.id, function(e)
		e.camera = view
		e.screenshot = name
	end)
	if old ~= "" and old ~= name then
		Store.dropBlob(old)
	end
	self:showBanner("Retook screenshot")
end

-- New entry view -------------------------------------------------------------------------------

function App:renderNewEntry()
	local draft = self.draft
	self:ensureDraft()

	local shotCard = Build.card({ LayoutOrder = 1, Parent = self.body })
	Build.list(6).Parent = shotCard
	local top = Build.row({ LayoutOrder = 1, Parent = shotCard })
	Build.label("Screenshot", {
		FontFace = Theme.FONT_BOLD,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = top,
	})
	Build.label(if draft.capturing then "capturing..." else Context.mode(), {
		TextColor3 = Theme.palette().dimText,
		TextSize = 12,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = top,
	})
	Build.button("Retake", "subtle", { LayoutOrder = 3, Parent = top }, function()
		self:captureDraft()
	end)

	self:addShot({
		parent = shotCard,
		layoutOrder = 2,
		view = draft.view,
		blob = draft.blob,
		blobName = draft.blobName,
		tempId = draft.tempId,
		markers = draft.markers,
		detect = function(nx, ny)
			return Context.targetAt(draft.view, nx, ny)
		end,
		onChanged = function()
			self:render()
		end,
	})
	Build.label(HINT, {
		TextSize = 12,
		TextColor3 = Theme.palette().dimText,
		LayoutOrder = 3,
		Parent = shotCard,
	})
	self:markerList(draft.markers, shotCard, 4, function()
		self:render()
	end)

	local toggles = Build.row({ LayoutOrder = 5, Parent = shotCard }, 14)
	Build.checkbox("Include screenshot", self.includeScreenshot, function(value)
		self.includeScreenshot = value
		self.plugin:SetSetting("PlaytestLogger/includeScreenshot", value)
	end).Parent =
		toggles
	Build.checkbox("Include console log", self.includeLogs, function(value)
		self.includeLogs = value
		self.plugin:SetSetting("PlaytestLogger/includeLogs", value)
	end).Parent =
		toggles
	Build.checkbox("Pause on quick capture", self.pauseOnQuickCapture, function(value)
		self.pauseOnQuickCapture = value
		self.plugin:SetSetting("PlaytestLogger/pauseOnQuickCapture", value)
	end).Parent =
		toggles

	local details = Build.card({ LayoutOrder = 2, Parent = self.body })
	Build.list(8).Parent = details
	local catRow = Build.row({ LayoutOrder = 1, Parent = details }, 8)
	Build.label("Category", {
		FontFace = Theme.FONT_BOLD,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = catRow,
	})
	self:categoryButton(draft.category, catRow, 2, function(category)
		draft.category = category
		self:render()
	end)

	local description = Build.textBox(draft.description, {
		MultiLine = true,
		PlaceholderText = "What happened? What should change?",
		Size = UDim2.new(1, 0, 0, 96),
		LayoutOrder = 2,
		Parent = details,
	})
	description:GetPropertyChangedSignal("Text"):Connect(function()
		draft.description = description.Text
	end)
	self:trackFocus(description, function(text)
		draft.description = text
	end)

	local actions = Build.row({ LayoutOrder = 3, Parent = self.body }, 8)
	Build.button("Save Entry", "primary", { LayoutOrder = 1, Parent = actions }, function()
		self:saveDraft(false)
	end)
	Build.button("Quick Screenshot", "subtle", {
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 32),
		Parent = actions,
	}, function()
		self:saveDraft(true)
	end)
end

-- Saved entries view ---------------------------------------------------------------------------

function App:openScriptOrText(name: string, title: string)
	local container = Store.findScript(name)
	if container then
		task.spawn(function()
			ScriptEditorService:OpenScriptDocumentAsync(container, {})
		end)
		return
	end
	local text = if name == "changes.md" then Store.markdown() else Store.getBlob(name)
	if text then
		self:showText(title, text)
	else
		self:showBanner(title .. " is stored in ServerStorage; open it in Edit mode")
	end
end

function App:renderEntry(entry: EntryModel.Entry, order: number)
	local palette = Theme.palette()
	local expanded = entry.id == self.expandedId
	local card = Build.card({ LayoutOrder = order, Parent = self.body })
	Build.list(6).Parent = card

	local header = Build.make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
		Parent = card,
	})
	local done = Build.checkbox("", entry.resolved, function(value)
		Store.update(entry.id, function(e)
			e.resolved = value
		end)
	end)
	done.Position = UDim2.fromOffset(0, 1)
	done.Parent = header
	local pill = Build.pill(entry.category, Categories.rgb(entry.category), {
		Position = UDim2.fromOffset(24, 2),
		Parent = header,
	})
	local title = Build.make("TextButton", {
		BackgroundTransparency = 1,
		Text = (if expanded then "▾ " else "▸ ") .. EntryModel.summary(entry.description, 60),
		TextColor3 = if entry.resolved then palette.dimText else palette.text,
		FontFace = Theme.FONT_BOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -80, 1, 0),
		Parent = header,
	})
	local function placeTitle()
		local left = 24 + pill.AbsoluteSize.X + 8
		title.Position = UDim2.fromOffset(left, 0)
		title.Size = UDim2.new(1, -(left + 44), 1, 0)
	end
	pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTitle)
	placeTitle()
	title.Activated:Connect(function()
		self.expandedId = if expanded then "" else entry.id
		self.confirmDeleteId = ""
		self:render()
	end)
	Build.label(EntryModel.shortTime(entry.timestamp), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 3),
		Size = UDim2.fromOffset(40, 18),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = palette.dimText,
		TextSize = 12,
		Parent = header,
	})

	if not expanded then
		return
	end

	local meta = Build.row({ LayoutOrder = 2, Parent = card }, 8)
	self:categoryButton(entry.category, meta, 1, function(category)
		Store.update(entry.id, function(e)
			e.category = category
		end)
	end)
	Build.label(`{entry.timestamp}  •  {entry.place}`, {
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextWrapped = false,
		TextColor3 = palette.dimText,
		TextSize = 12,
		LayoutOrder = 2,
		Parent = meta,
	})
	if entry.context ~= "" then
		Build.label(entry.context, { TextColor3 = palette.dimText, TextSize = 12, LayoutOrder = 3, Parent = card })
	end

	Build.label("Description", { FontFace = Theme.FONT_BOLD, TextSize = 12, LayoutOrder = 4, Parent = card })
	local description = Build.textBox(entry.description, {
		MultiLine = true,
		Size = UDim2.new(1, 0, 0, 64),
		LayoutOrder = 5,
		Parent = card,
	})
	self:trackFocus(description, function(text)
		if text ~= entry.description then
			Store.update(entry.id, function(e)
				e.description = text
			end)
		end
	end)

	local markers = table.clone(entry.markers)
	local function saveMarkers()
		Store.update(entry.id, function(e)
			e.markers = markers
			e.target = if markers[1] then markers[1].label else ""
		end)
	end
	local blob = Store.getBlob(entry.screenshot)
	local tempId = self.tempIds[entry.id]
	if entry.camera or blob or tempId then
		self:addShot({
			parent = card,
			layoutOrder = 6,
			view = entry.camera,
			blob = blob,
			blobName = entry.screenshot,
			tempId = tempId,
			markers = markers,
			detect = function(nx, ny)
				return Context.targetAt(entry.camera, nx, ny)
			end,
			onChanged = saveMarkers,
		})
		Build.label(HINT, { TextSize = 12, TextColor3 = palette.dimText, LayoutOrder = 7, Parent = card })
		self:markerList(markers, card, 8, saveMarkers)
	end

	local actions = Build.row({ LayoutOrder = 9, Parent = card }, 6)
	Build.button("Retake Screenshot", "subtle", { LayoutOrder = 1, Parent = actions }, function()
		self:retake(entry)
	end)
	if entry.camera and RunService:IsEdit() then
		Build.button("Go to View", "subtle", { LayoutOrder = 2, Parent = actions }, function()
			workspace.CurrentCamera.CFrame = Capture.toCFrame(entry.camera :: EntryModel.CameraView)
		end)
	end
	if entry.consoleLog ~= "" then
		Build.button("Console Log", "subtle", { LayoutOrder = 3, Parent = actions }, function()
			self:openScriptOrText(entry.consoleLog, "Console Log")
		end)
	end
	local confirming = self.confirmDeleteId == entry.id
	Build.button(if confirming then "Confirm Delete" else "Delete", if confirming then "danger" else "subtle", {
		LayoutOrder = 4,
		Parent = actions,
	}, function()
		if confirming then
			self.confirmDeleteId = ""
			self.expandedId = ""
			Store.remove(entry.id)
		else
			self.confirmDeleteId = entry.id
			self:render()
		end
	end)
end

function App:renderSaved()
	local entries = Store.entries()
	local bar = Build.card({ LayoutOrder = 0, Parent = self.body })
	local row = Build.row({ Parent = bar }, 8)
	Build.checkbox("Hide Done Entries", self.hideResolved, function(value)
		self.hideResolved = value
		self.plugin:SetSetting("PlaytestLogger/hideResolved", value)
		self:render()
	end).Parent =
		row
	Build.button("Collapse All", "subtle", { LayoutOrder = 2, Parent = row }, function()
		self.expandedId = ""
		self:render()
	end)
	Build.button("Show in Explorer", "subtle", { LayoutOrder = 3, Parent = row }, function()
		self:revealFolder()
	end)

	local visible = EntryModel.visible(entries, self.hideResolved)
	if #visible == 0 then
		Build.label("No matching saved entries. Switch to '+ New Entry' or press F1 to log an issue.", {
			TextColor3 = Theme.palette().dimText,
			LayoutOrder = 1,
			Parent = self.body,
		})
		return
	end
	for index, entry in visible do
		self:renderEntry(entry, index)
	end
end

-- Menu actions ---------------------------------------------------------------------------------

function App:revealFolder()
	local root = Store.root(false)
	if root then
		Selection:Set({ root })
	else
		self:showBanner(
			if not RunService:IsEdit()
				then "ServerStorage/PlaytestLogs is available in Edit mode"
				else "No logs saved in this place yet"
		)
	end
end

function App:showText(title: string, text: string)
	if self.overlay then
		self.overlay:Destroy()
	end
	local palette = Theme.palette()
	local overlay = Build.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = palette.background,
		ZIndex = 20,
		Parent = self.root,
	}, { Build.padding(10) })
	self.overlay = overlay
	Build.label(title .. "  (Ctrl+A, Ctrl+C to copy)", {
		FontFace = Theme.FONT_BOLD,
		Size = UDim2.new(1, -80, 0, 26),
		AutomaticSize = Enum.AutomaticSize.None,
		ZIndex = 21,
		Parent = overlay,
	})
	Build.button("Close", "subtle", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		ZIndex = 21,
		Parent = overlay,
	}, function()
		overlay:Destroy()
		self.overlay = nil
	end)
	local scroller = Build.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		ScrollBarThickness = 6,
		ZIndex = 21,
		Parent = overlay,
	})
	Build.textBox(text, {
		MultiLine = true,
		TextEditable = false,
		TextWrapped = false,
		FontFace = Font.fromEnum(Enum.Font.RobotoMono),
		TextSize = 13,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 22,
		Parent = scroller,
	})
end

function App:showMoreMenu()
	local action = self.moreMenu:ShowAsync()
	if not action then
		return
	end
	if action == self.moreActions.quick then
		task.spawn(function()
			self:captureDraft()
			self:saveDraft(true)
		end)
	elseif action == self.moreActions.folder then
		self:revealFolder()
	elseif action == self.moreActions.changes then
		self:openScriptOrText("changes.md", "changes.md")
	elseif action == self.moreActions.json then
		self:openScriptOrText("entries.json", "entries.json")
	elseif action == self.moreActions.copy then
		self:showText("changes.md", Store.markdown())
	end
end

function App:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self:destroyShots()
	ShotView.clearCaches()
	if self.root then
		self.root:Destroy()
	end
end

return App
