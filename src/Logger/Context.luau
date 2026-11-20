local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local EntryModel = require(script.Parent.EntryModel)
local ViewMath = require(script.Parent.ViewMath)
local Capture = require(script.Parent.Capture)

local Context = {}

function Context.mode(): string
	if RunService:IsEdit() then
		return "EditMode"
	elseif RunService:IsRunMode() then
		return "RunMode"
	elseif RunService:IsClient() then
		return "PlayMode (Client)"
	end
	return "PlayMode (Server)"
end

function Context.placeName(): string
	if game.PlaceId ~= 0 then
		return `{game.Name} ({game.PlaceId})`
	end
	return game.Name
end

local function fmt(v: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function playerRoot(): BasePart?
	local player = Players.LocalPlayer or Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function Context.describe(): string
	local mode = Context.mode()
	local root = playerRoot()
	if root then
		return `{mode} | PlayerPos={fmt(root.Position)} | Speed={string.format(
			"%.1f",
			root.AssemblyLinearVelocity.Magnitude
		)}`
	end
	local camera = workspace.CurrentCamera
	if camera then
		return `{mode} | CamPos={fmt(camera.CFrame.Position)}`
	end
	return mode
end

local function guiRoot(): BasePlayerGui?
	if not RunService:IsEdit() then
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		return playerGui
	end
	return if StarterGui.ShowDevelopmentGui then StarterGui else nil
end

local function guiPath(object: Instance, root: Instance): string
	local parts = {}
	local current: Instance? = object
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

local function isShown(object: GuiObject, root: Instance): boolean
	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

function Context.uiAt(view: EntryModel.CameraView, nx: number, ny: number): string?
	local root = guiRoot()
	if not root then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	local x = math.floor(nx * view.width)
	local y = math.floor(ny * view.height - inset.Y)
	local ok, objects = pcall(root.GetGuiObjectsAtPosition, root, x, y)
	if not ok then
		return nil
	end
	for _, object in objects do
		if isShown(object, root) then
			return "UI: " .. guiPath(object, root)
		end
	end
	return nil
end

function Context.worldAt(view: EntryModel.CameraView, nx: number, ny: number): string?
	local cf = Capture.toCFrame(view)
	local r, u, f = ViewMath.rayCoefficients(view.fov, view.width / view.height, nx, ny)
	local direction = (cf.RightVector * r + cf.UpVector * u + cf.LookVector * f).Unit * 5000
	local params = RaycastParams.new()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = workspace:Raycast(cf.Position, direction, params)
	if not result then
		return nil
	end
	if result.Instance:IsA("Terrain") then
		return "3D: Terrain (" .. result.Material.Name .. ")"
	end
	return "3D: " .. result.Instance:GetFullName()
end

-- Describes what sits under a pin: on-screen UI first, then the 3D object hit by a camera ray.
function Context.targetAt(view: EntryModel.CameraView?, nx: number, ny: number): string
	local resolved = view or Capture.cameraView()
	return Context.uiAt(resolved, nx, ny) or Context.worldAt(resolved, nx, ny) or ""
end

return Context
