local AssetService = game:GetService("AssetService")
local CaptureService = game:GetService("CaptureService")
local EncodingService = game:GetService("EncodingService")
local Lighting = game:GetService("Lighting")

local EntryModel = require(script.Parent.EntryModel)
local ViewMath = require(script.Parent.ViewMath)

local Capture = {}

Capture.MAX_WIDTH = 640
Capture.MAX_HEIGHT = 360
Capture.SCENE_PART_LIMIT = 2500
Capture.SCENE_DISTANCE = 1500

local BLOB_PREFIX = "RGBA1"

function Capture.cameraView(): EntryModel.CameraView
	local camera = workspace.CurrentCamera
	local size = camera.ViewportSize
	return {
		cframe = { camera.CFrame:GetComponents() },
		fov = camera.FieldOfView,
		width = math.max(1, size.X),
		height = math.max(1, size.Y),
	}
end

function Capture.toCFrame(view: EntryModel.CameraView): CFrame
	return CFrame.new(table.unpack(view.cframe))
end

function Capture.aspect(view: EntryModel.CameraView?): number
	if not view then
		return 16 / 9
	end
	return view.width / view.height
end

function Capture.encode(image: EditableImage): string
	local size = image.Size
	local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
	local compressed = EncodingService:CompressBuffer(pixels, Enum.CompressionAlgorithm.Zstd, 6)
	local base64 = buffer.tostring(EncodingService:Base64Encode(compressed))
	return `{BLOB_PREFIX}:{size.X}x{size.Y}:{base64}`
end

function Capture.decode(blob: string): EditableImage?
	local w, h, base64 = string.match(blob, "^" .. BLOB_PREFIX .. ":(%d+)x(%d+):(.+)$")
	if not w then
		return nil
	end
	local ok, image = pcall(function()
		local size = Vector2.new(tonumber(w) :: number, tonumber(h) :: number)
		local compressed = EncodingService:Base64Decode(buffer.fromstring(base64 :: string))
		local pixels = EncodingService:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
		local editable = AssetService:CreateEditableImage({ Size = size })
		editable:WritePixelsBuffer(Vector2.zero, size, pixels)
		return editable
	end)
	return if ok then image else nil
end

-- Takes a real screenshot through CaptureService and downsamples it into a storable blob.
-- Returns (blob?, temporaryContentId?). Either may be nil when Studio does not allow captures
-- in the current context (e.g. Edit mode); callers fall back to a 3D scene snapshot.
function Capture.screenshotAsync(): (string?, string?)
	local contentId: string? = nil
	local finished = false
	local ok = pcall(function()
		CaptureService:CaptureScreenshot(function(id)
			contentId = id
			finished = true
		end)
	end)
	if not ok then
		return nil, nil
	end
	local started = os.clock()
	while not finished and os.clock() - started < 5 do
		task.wait()
	end
	if not contentId then
		return nil, nil
	end

	local blob: string? = nil
	pcall(function()
		local source = AssetService:CreateEditableImageAsync(Content.fromUri(contentId :: string))
		local srcSize = source.Size
		local w, h = ViewMath.scaledSize(srcSize.X, srcSize.Y, Capture.MAX_WIDTH, Capture.MAX_HEIGHT)
		local target = source
		if w ~= srcSize.X or h ~= srcSize.Y then
			target = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
			target:DrawImageTransformed(
				Vector2.new(w / 2, h / 2),
				Vector2.new(w / srcSize.X, h / srcSize.Y),
				0,
				source,
				{ CombineType = Enum.ImageCombineType.Overwrite }
			)
		end
		blob = Capture.encode(target)
		if target ~= source then
			target:Destroy()
		end
		source:Destroy()
	end)
	return blob, contentId
end

local SKIP_IN_SNAPSHOT = { "BasePart", "LuaSourceContainer", "JointInstance", "Constraint", "Sound", "ParticleEmitter" }

local function stripClone(clone: Instance)
	for _, descendant in clone:GetDescendants() do
		for _, className in SKIP_IN_SNAPSHOT do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
end

-- Builds a static model of the parts visible from `view`, for rendering in a ViewportFrame
-- when a real screenshot is not available.
function Capture.buildScene(view: EntryModel.CameraView): Model
	local cf = Capture.toCFrame(view)
	local origin, look = cf.Position, cf.LookVector
	local candidates = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:IsA("Terrain") and descendant.Archivable then
			local offset = descendant.Position - origin
			local distance = offset.Magnitude
			local radius = descendant.Size.Magnitude / 2
			if distance - radius < Capture.SCENE_DISTANCE and (offset:Dot(look) > -radius) then
				table.insert(candidates, { part = descendant, distance = distance - radius })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local model = Instance.new("Model")
	model.Name = "PlaytestLoggerScene"
	for i = 1, math.min(#candidates, Capture.SCENE_PART_LIMIT) do
		local ok, clone = pcall(function()
			return candidates[i].part:Clone()
		end)
		if ok and clone then
			stripClone(clone)
			clone.Anchored = true
			clone.Parent = model
		end
	end
	return model
end

function Capture.styleViewport(frame: ViewportFrame, view: EntryModel.CameraView): Camera
	local camera = Instance.new("Camera")
	camera.CFrame = Capture.toCFrame(view)
	camera.FieldOfView = view.fov
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Ambient = Lighting.Ambient:Lerp(Color3.new(1, 1, 1), 0.45)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = -Lighting:GetSunDirection()
	frame.BackgroundColor3 = Color3.fromRGB(142, 186, 222)
	frame.BackgroundTransparency = 0
	return camera
end

return Capture
