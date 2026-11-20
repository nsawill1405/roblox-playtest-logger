local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")

local ConsoleBuffer = require(script.Logger.ConsoleBuffer)
local Store = require(script.Logger.Store)
local App = require(script.UI.App)

local console = ConsoleBuffer.new()

local function kindOf(messageType: Enum.MessageType): string
	return (string.gsub(messageType.Name, "^Message", ""))
end

local okHistory, history = pcall(function()
	return LogService:GetLogHistory()
end)
if okHistory then
	for _, item in history do
		local clock = os.date("%H:%M:%S", math.floor(item.timestamp or os.time()))
		console:push(ConsoleBuffer.format(clock, kindOf(item.messageType), item.message))
	end
end
local logConnection = LogService.MessageOut:Connect(function(message, messageType)
	console:push(ConsoleBuffer.format(os.date("%H:%M:%S"), kindOf(messageType), message))
end)

Store.init(plugin)

local toolbar = plugin:CreateToolbar("Playtest Logger")
local toggleButton = toolbar:CreateButton(
	"PlaytestLoggerToggle",
	"Open Playtest Logger (log bugs, UI feedback and changes with screenshots)",
	"rbxasset://textures/AnimationEditor/icon_checkmark.png",
	"Playtest Logger"
)
toggleButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 440, 600, 330, 420)
local widget = plugin:CreateDockWidgetPluginGuiAsync("PlaytestLogger", widgetInfo)
widget.Title = "Playtest Logger"
widget.Name = "PlaytestLogger"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local app = App.new(plugin, widget, console)

local function openWindow()
	widget.Enabled = true
	app.tab = if app.tab == "saved" then "saved" else "new"
	app:ensureDraft()
	app:render()
end

toggleButton.Click:Connect(function()
	if widget.Enabled then
		widget.Enabled = false
	else
		openWindow()
	end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)
toggleButton:SetActive(widget.Enabled)

-- Bind these under File > Customize Shortcuts (e.g. Ctrl+Shift+L and F1).
local openAction = plugin:CreatePluginAction(
	"PlaytestLoggerOpen",
	"Open Playtest Logger",
	"Open the Playtest Logger window",
	"rbxasset://textures/AnimationEditor/icon_checkmark.png",
	true
)
openAction.Triggered:Connect(openWindow)

local quickAction = plugin:CreatePluginAction(
	"PlaytestLoggerQuickCapture",
	"Playtest Logger Quick Capture",
	"Open Playtest Logger and snap the current frame",
	"rbxasset://textures/AnimationEditor/icon_checkmark.png",
	true
)
quickAction.Triggered:Connect(function()
	app:quickCapture()
end)

-- F1 in the game viewport always triggers a quick capture, matching the Unity version.
local inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F1 then
		task.spawn(function()
			app:quickCapture()
		end)
	end
end)

plugin.Unloading:Connect(function()
	logConnection:Disconnect()
	inputConnection:Disconnect()
	Store.stop()
	app:destroy()
end)
