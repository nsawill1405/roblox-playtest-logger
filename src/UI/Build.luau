local Theme = require(script.Parent.Theme)

local Build = {}

function Build.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Build.corner(radius: number?): UICorner
	return Build.make("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

function Build.stroke(color: Color3, thickness: number?): UIStroke
	return Build.make("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Build.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	return Build.make("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function Build.list(
	spacing: number?,
	horizontal: boolean?,
	align: Enum.VerticalAlignment?,
	wraps: boolean?
): UIListLayout
	return Build.make("UIListLayout", {
		Padding = UDim.new(0, spacing or 6),
		Wraps = wraps == true,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = align or Enum.VerticalAlignment.Top,
	})
end

function Build.label(text: string, props: { [string]: any }?): TextLabel
	local palette = Theme.palette()
	local base = {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = palette.text,
		FontFace = Theme.FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
	}
	for key, value in props or {} do
		base[key] = value
	end
	return Build.make("TextLabel", base)
end

export type ButtonStyle = "primary" | "subtle" | "danger" | "ghost"

function Build.button(text: string, style: ButtonStyle?, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local palette = Theme.palette()
	local kind = style or "subtle"
	local bg = if kind == "primary" then Theme.ACCENT elseif kind == "danger" then Theme.DANGER else palette.button
	local base = {
		Text = text,
		AutoButtonColor = true,
		BackgroundColor3 = bg,
		BackgroundTransparency = if kind == "ghost" then 1 else 0,
		TextColor3 = if kind == "primary" or kind == "danger" then Color3.new(1, 1, 1) else palette.buttonText,
		FontFace = if kind == "primary" then Theme.FONT_BOLD else Theme.FONT,
		TextSize = if kind == "primary" then 15 else 13,
		Size = UDim2.fromOffset(0, if kind == "primary" then 32 else 26),
		AutomaticSize = Enum.AutomaticSize.X,
	}
	for key, value in props or {} do
		base[key] = value
	end
	local button = Build.make("TextButton", base, { Build.corner(4), Build.padding(0, 10, 0, 10) })
	if kind == "subtle" then
		Build.stroke(palette.border).Parent = button
	end
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

function Build.textBox(text: string, props: { [string]: any }?): TextBox
	local palette = Theme.palette()
	local base = {
		Text = text,
		PlaceholderColor3 = palette.dimText,
		BackgroundColor3 = palette.input,
		TextColor3 = palette.text,
		FontFace = Theme.FONT,
		TextSize = 14,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 28),
	}
	for key, value in props or {} do
		base[key] = value
	end
	return Build.make(
		"TextBox",
		base,
		{ Build.corner(4), Build.stroke(palette.inputBorder), Build.padding(6, 8, 6, 8) }
	)
end

function Build.checkbox(text: string, checked: boolean, onToggle: (boolean) -> ()): TextButton
	local palette = Theme.palette()
	local state = checked
	local button = Build.make("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
	}, { Build.list(6, true, Enum.VerticalAlignment.Center) })
	local box = Build.make("TextLabel", {
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = if state then Theme.ACCENT else palette.input,
		Text = if state then "✓" else "",
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = Theme.FONT_BOLD,
		TextSize = 13,
		LayoutOrder = 1,
		Parent = button,
	}, { Build.corner(3), Build.stroke(if state then Theme.ACCENT else palette.inputBorder) })
	if text ~= "" then
		Build.label(text, {
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			TextWrapped = false,
			TextSize = 13,
			LayoutOrder = 2,
			Parent = button,
		})
	end
	button.Activated:Connect(function()
		state = not state
		box.Text = if state then "✓" else ""
		box.BackgroundColor3 = if state then Theme.ACCENT else palette.input
		onToggle(state)
	end)
	return button
end

function Build.pill(text: string, rgb: { number }, props: { [string]: any }?): TextLabel
	local base = {
		Text = text,
		BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = Theme.FONT_BOLD,
		TextSize = 12,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
	}
	for key, value in props or {} do
		base[key] = value
	end
	return Build.make("TextLabel", base, { Build.corner(10), Build.padding(0, 8, 0, 8) })
end

function Build.card(props: { [string]: any }?): Frame
	local palette = Theme.palette()
	local base = {
		BackgroundColor3 = palette.card,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props or {} do
		base[key] = value
	end
	return Build.make("Frame", base, { Build.corner(6), Build.stroke(palette.border), Build.padding(10, 12, 12, 12) })
end

function Build.row(props: { [string]: any }?, spacing: number?): Frame
	local base = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props or {} do
		base[key] = value
	end
	return Build.make("Frame", base, { Build.list(spacing or 6, true, Enum.VerticalAlignment.Center, true) })
end

return Build
