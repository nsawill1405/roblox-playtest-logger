-- Screenshot preview with numbered callout pins: click to add, drag to move, right-click to remove.
local RunService = game:GetService("RunService")

local Build = require(script.Parent.Build)
local Theme = require(script.Parent.Theme)
local Capture = require(script.Parent.Parent.Logger.Capture)
local ViewMath = require(script.Parent.Parent.Logger.ViewMath)
local EntryModel = require(script.Parent.Parent.Logger.EntryModel)

local ShotView = {}
ShotView.__index = ShotView

local IMAGE_CACHE_SIZE = 8
local SCENE_CACHE_SIZE = 3

local imageCache: { { key: string, image: EditableImage } } = {}
local sceneCache: { { key: string, model: Model } } = {}

local function cachedImage(key: string, blob: string): EditableImage?
	for i, item in imageCache do
		if item.key == key then
			table.remove(imageCache, i)
			table.insert(imageCache, item)
			return item.image
		end
	end
	local image = Capture.decode(blob)
	if not image then
		return nil
	end
	table.insert(imageCache, { key = key, image = image })
	while #imageCache > IMAGE_CACHE_SIZE do
		local old = table.remove(imageCache, 1)
		if old then
			old.image:Destroy()
		end
	end
	return image
end

local function viewKey(view: EntryModel.CameraView): string
	local parts = {}
	for i, value in view.cframe do
		parts[i] = string.format("%.3f", value)
	end
	return table.concat(parts, ",") .. "|" .. tostring(view.fov)
end

local function cachedScene(view: EntryModel.CameraView): Model
	local key = viewKey(view)
	for i, item in sceneCache do
		if item.key == key then
			table.remove(sceneCache, i)
			table.insert(sceneCache, item)
			return item.model
		end
	end
	local model = Capture.buildScene(view)
	table.insert(sceneCache, { key = key, model = model })
	while #sceneCache > SCENE_CACHE_SIZE do
		local old = table.remove(sceneCache, 1)
		if old then
			old.model:Destroy()
		end
	end
	return model
end

function ShotView.clearCaches()
	for _, item in imageCache do
		item.image:Destroy()
	end
	for _, item in sceneCache do
		item.model:Destroy()
	end
	table.clear(imageCache)
	table.clear(sceneCache)
end

function ShotView.forgetScene(view: EntryModel.CameraView)
	local key = viewKey(view)
	for i, item in sceneCache do
		if item.key == key then
			item.model:Destroy()
			table.remove(sceneCache, i)
			return
		end
	end
end

export type Props = {
	parent: Instance,
	layoutOrder: number?,
	widget: PluginGui,
	root: GuiObject,
	view: EntryModel.CameraView?,
	blobName: string?,
	blob: string?,
	tempId: string?,
	markers: { EntryModel.Marker },
	detect: (number, number) -> string,
	onChanged: ({ EntryModel.Marker }) -> (),
}

local function isAutoLabel(label: string): boolean
	return label == ""
		or string.match(label, "^Pin %d+$") ~= nil
		or string.sub(label, 1, 4) == "UI: "
		or string.sub(label, 1, 4) == "3D: "
end

function ShotView.new(props: Props)
	local self = setmetatable({}, ShotView)
	self.props = props
	self.markers = props.markers
	self.aspect = Capture.aspect(props.view)
	self.connections = {}
	self.scene = nil :: Model?

	local palette = Theme.palette()
	self.container = Build.make("Frame", {
		Name = "Shot",
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = palette.shotBackground,
		Size = UDim2.new(1, 0, 0, 200),
		ClipsDescendants = true,
		Parent = props.parent,
	}, { Build.corner(4) })

	self.shot = Build.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = self.container,
	}, {
		Build.make("UIAspectRatioConstraint", {
			AspectRatio = self.aspect,
			AspectType = Enum.AspectType.FitWithinMaxSize,
		}),
	})

	self:buildContent()

	self.overlay = Build.make("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = self.shot,
	})
	table.insert(
		self.connections,
		self.overlay.MouseButton1Down:Connect(function()
			if self.dragIndex then
				return
			end
			local nx, ny = self:mouseNormalized()
			local label = props.detect(nx, ny)
			if label == "" then
				label = `Pin {#self.markers + 1}`
			end
			table.insert(self.markers, { x = nx, y = ny, label = label })
			props.onChanged(self.markers)
		end)
	)
	table.insert(
		self.connections,
		self.overlay.MouseButton1Up:Connect(function()
			self:endDrag()
		end)
	)
	table.insert(
		self.connections,
		props.root.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:endDrag()
			end
		end)
	)

	self.pins = {}
	self:buildPins()
	return self
end

function ShotView:buildContent()
	local props = self.props
	local image: EditableImage? = nil
	if props.blob and props.blobName then
		image = cachedImage(props.blobName, props.blob)
	end

	if image then
		Build.make("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageContent = Content.fromObject(image),
			ScaleType = Enum.ScaleType.Stretch,
			Parent = self.shot,
		})
	elseif props.tempId then
		Build.make("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = props.tempId,
			ScaleType = Enum.ScaleType.Stretch,
			Parent = self.shot,
		})
	elseif props.view then
		local viewport = Build.make("ViewportFrame", {
			Size = UDim2.fromScale(1, 1),
			Parent = self.shot,
		})
		Capture.styleViewport(viewport, props.view)
		local ok, model = pcall(cachedScene, props.view)
		if ok then
			model.Parent = viewport
			self.scene = model
		end
		local tag = Build.label("3D scene snapshot", {
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(6, 6),
			TextSize = 11,
			TextWrapped = false,
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Color3.new(0, 0, 0),
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = self.shot,
		})
		Build.padding(2, 6).Parent = tag
		Build.corner(3).Parent = tag
	else
		Build.label("No screenshot - press Retake to capture one.", {
			Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.palette().dimText,
			Parent = self.shot,
		})
	end
end

function ShotView:mouseNormalized(): (number, number)
	local mouse = self.props.widget:GetRelativeMousePosition()
	local pos, size = self.shot.AbsolutePosition, self.shot.AbsoluteSize
	return ViewMath.toNormalized(mouse.X, mouse.Y, pos.X, pos.Y, size.X, size.Y)
end

function ShotView:buildPins()
	for _, pin in self.pins do
		pin:Destroy()
	end
	table.clear(self.pins)
	for index, marker in self.markers do
		local pin = Build.make("TextButton", {
			Name = "Pin" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(marker.x, marker.y),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Theme.PIN,
			Text = tostring(index),
			TextColor3 = Color3.new(1, 1, 1),
			FontFace = Theme.FONT_BOLD,
			TextSize = 12,
			AutoButtonColor = false,
			ZIndex = 6,
			Parent = self.shot,
		}, { Build.corner(11), Build.stroke(Color3.new(1, 1, 1), 2) })
		pin.MouseButton1Down:Connect(function()
			self:beginDrag(index, pin)
		end)
		pin.MouseButton1Up:Connect(function()
			self:endDrag()
		end)
		pin.MouseButton2Click:Connect(function()
			table.remove(self.markers, index)
			self.props.onChanged(self.markers)
		end)
		table.insert(self.pins, pin)
	end
end

function ShotView:beginDrag(index: number, pin: GuiObject)
	self.dragIndex = index
	self.dragMoved = false
	if self.dragConnection then
		self.dragConnection:Disconnect()
	end
	self.dragConnection = RunService.Heartbeat:Connect(function()
		local nx, ny = self:mouseNormalized()
		local marker = self.markers[index]
		if marker and (math.abs(marker.x - nx) > 0.001 or math.abs(marker.y - ny) > 0.001) then
			marker.x, marker.y = nx, ny
			pin.Position = UDim2.fromScale(nx, ny)
			self.dragMoved = true
		end
	end)
end

function ShotView:endDrag()
	local index = self.dragIndex
	if not index then
		return
	end
	self.dragIndex = nil
	if self.dragConnection then
		self.dragConnection:Disconnect()
		self.dragConnection = nil
	end
	if self.dragMoved then
		local marker = self.markers[index]
		if marker and isAutoLabel(marker.label) then
			local detected = self.props.detect(marker.x, marker.y)
			marker.label = if detected ~= "" then detected else `Pin {index}`
		end
		self.props.onChanged(self.markers)
	end
end

function ShotView:resize(width: number)
	local height = math.clamp(math.floor(width / self.aspect), 120, 460)
	self.container.Size = UDim2.new(1, 0, 0, height)
end

function ShotView:destroy()
	if self.dragConnection then
		self.dragConnection:Disconnect()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.scene then
		self.scene.Parent = nil
	end
	self.container:Destroy()
end

return ShotView
