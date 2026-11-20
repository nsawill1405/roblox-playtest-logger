local Theme = {}

Theme.ACCENT = Color3.fromRGB(51, 122, 219)
Theme.ACCENT_HOVER = Color3.fromRGB(66, 143, 242)
Theme.DANGER = Color3.fromRGB(204, 66, 71)
Theme.PIN = Color3.fromRGB(230, 57, 70)
Theme.FONT = Font.fromEnum(Enum.Font.BuilderSans)
Theme.FONT_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local function studioTheme()
	local ok, theme = pcall(function()
		return settings().Studio.Theme
	end)
	return if ok then theme else nil
end

function Theme.color(guide: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	local theme = studioTheme()
	if theme then
		return (theme :: any):GetColor(guide, modifier or Enum.StudioStyleGuideModifier.Default)
	end
	return Color3.fromRGB(46, 46, 46)
end

function Theme.isDark(): boolean
	local bg = Theme.color(Enum.StudioStyleGuideColor.MainBackground)
	return (bg.R + bg.G + bg.B) / 3 < 0.5
end

function Theme.palette()
	local C = Enum.StudioStyleGuideColor
	return {
		background = Theme.color(C.MainBackground),
		header = Theme.color(C.Titlebar),
		card = Theme.color(C.ViewPortBackground):Lerp(Theme.color(C.MainBackground), 0.65),
		border = Theme.color(C.Border),
		input = Theme.color(C.InputFieldBackground),
		inputBorder = Theme.color(C.InputFieldBorder),
		text = Theme.color(C.MainText),
		dimText = Theme.color(C.DimmedText),
		subText = Theme.color(C.SubText),
		button = Theme.color(C.Button),
		buttonText = Theme.color(C.ButtonText),
		tabActive = Theme.color(C.Item, Enum.StudioStyleGuideModifier.Selected),
		shotBackground = Theme.color(C.ScriptBackground),
	}
end

function Theme.onChanged(callback: () -> ()): RBXScriptConnection?
	local ok, connection = pcall(function()
		return settings().Studio.ThemeChanged:Connect(callback)
	end)
	return if ok then connection else nil
end

return Theme
