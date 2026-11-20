--[[
	BetterOrion (Mobile-safe rewrite)
	API: MakeWindow, MakeNotification
	Window : MakeTab
	Tab    : AddSection (+ AddToggle/AddSlider/... direct)
	Section: AddLabel, AddButton, AddToggle, AddSlider, AddDropdown, AddBind
	Toggle : AddSlider, AddDropdown (compat -> placed in the same Section)

	Layout (never breaks on resize / small screens):
	  Main
	   |- TopBar   (40px)
	   |- Body
	   |   |- SideBar  : fixed 160px
	   |   |- Content  : Position (0,160,0,0)  Size (1,-160,1,0)
	   |- ResizeHandle
	  Window is clamped to the viewport and UIScale is applied on small screens.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local SIDEBAR_WIDTH = 160
local TOPBAR_HEIGHT = 40
local TOUCH_HEIGHT = 40 -- minimum touch target

local OrionLib = {
	Flags = {},
	Connections = {},
	NotificationSettings = { Enabled = true, Printing = false },
}

local T = {
	Main = Color3.fromRGB(20, 20, 22),
	TopBar = Color3.fromRGB(26, 26, 29),
	Side = Color3.fromRGB(24, 24, 27),
	Element = Color3.fromRGB(34, 34, 38),
	ElementHover = Color3.fromRGB(44, 44, 49),
	Stroke = Color3.fromRGB(62, 62, 68),
	Text = Color3.fromRGB(240, 240, 240),
	TextDark = Color3.fromRGB(165, 165, 172),
	Accent = Color3.fromRGB(88, 135, 255),
}

---------------------------------------------------------------- helpers
local function GetGuiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2 = pcall(function() return game:GetService("CoreGui"):GetChildren() end)
	if ok2 then return game:GetService("CoreGui") end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function New(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function Stroke(color, thickness)
	return New("UIStroke", {
		Color = color or T.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function Pad(l, r, t, b)
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
	})
end

local function List(padding)
	return New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 0),
	})
end

local function Label(props)
	local p = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
	}
	for k, v in pairs(props) do p[k] = v end
	return New("TextLabel", p)
end

local function Btn(props)
	local p = {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}
	for k, v in pairs(props) do p[k] = v end
	return New("TextButton", p)
end

local function Tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(OrionLib.Connections, c)
	return c
end

local function Viewport()
	local cam = workspace.CurrentCamera
	return (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end

local function IsPointer(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function IsMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local function Round(n, inc)
	inc = inc or 1
	if inc <= 0 then return n end
	local r = math.floor(n / inc + 0.5) * inc
	local s = tostring(inc)
	local dot = s:find("%.")
	if dot then
		local decimals = #s - dot
		r = tonumber(string.format("%." .. decimals .. "f", r)) or r
	end
	return r
end

local orderCounters = setmetatable({}, { __mode = "k" })
local function NextOrder(holder)
	orderCounters[holder] = (orderCounters[holder] or 0) + 1
	return orderCounters[holder]
end

---------------------------------------------------------------- root gui
local GuiParent = GetGuiParent()
for _, g in ipairs(GuiParent:GetChildren()) do
	if g.Name == "BetterOrion" then g:Destroy() end
end
pcall(function()
	for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
		if g.Name == "BetterOrion" then g:Destroy() end
	end
end)

local Gui = New("ScreenGui", {
	Name = "BetterOrion",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
})
pcall(function() if syn and syn.protect_gui then syn.protect_gui(Gui) end end)
Gui.Parent = GuiParent

function OrionLib:IsRunning() return Gui.Parent ~= nil end

function OrionLib:Destroy()
	for _, c in ipairs(OrionLib.Connections) do pcall(function() c:Disconnect() end) end
	OrionLib.Connections = {}
	Gui:Destroy()
end

---------------------------------------------------------------- notifications
local NotifHolder = New("Frame", {
	Parent = Gui,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.new(0, 260, 1, -24),
}, {
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
	}),
})

function OrionLib:SetNotifyingState(cfg)
	cfg = cfg or {}
	if cfg.Enabled ~= nil then OrionLib.NotificationSettings.Enabled = cfg.Enabled end
	if cfg.Printing ~= nil then OrionLib.NotificationSettings.Printing = cfg.Printing end
end

function OrionLib:MakeNotification(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Name or "Notification")
	local content = tostring(cfg.Content or "")
	local duration = tonumber(cfg.Time) or 5
	if OrionLib.NotificationSettings.Printing then print(title .. ": " .. content) end
	if not OrionLib.NotificationSettings.Enabled then return end

	task.spawn(function()
		local frame = New("Frame", {
			Parent = NotifHolder,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.TopBar,
			BorderSizePixel = 0,
			LayoutOrder = NextOrder(NotifHolder),
		}, {
			Stroke(T.Stroke), Pad(12, 12, 10, 10), List(3),
		})
		New("Frame", { -- accent bar
			Parent = frame, Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(0, -12, 0, 0),
			BackgroundColor3 = T.Accent, BorderSizePixel = 0,
		})
		Label({
			Parent = frame, Text = title, Font = Enum.Font.GothamBold, TextSize = 14,
			Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		if content ~= "" then
			Label({
				Parent = frame, Text = content, TextSize = 13, TextColor3 = T.TextDark,
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true, LayoutOrder = 2,
			})
		end
		task.wait(duration)
		if frame.Parent then
			Tween(frame, { BackgroundTransparency = 1 }, 0.25)
			task.wait(0.25)
			frame:Destroy()
		end
	end)
end

---------------------------------------------------------------- element builder
local function MakeBuilder(getHolder, setScrolling, elemT)
	local B = {}

	local function Base(height, auto)
		local f = New("Frame", {
			Parent = getHolder(),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = T.Element,
			BackgroundTransparency = elemT,
			BorderSizePixel = 0,
			LayoutOrder = NextOrder(getHolder()),
		}, { Stroke(T.Stroke) })
		if auto then f.AutomaticSize = Enum.AutomaticSize.Y end
		return f
	end

	local function Hover(frame, button)
		Connect(button.MouseEnter, function() Tween(frame, { BackgroundColor3 = T.ElementHover }) end)
		Connect(button.MouseLeave, function() Tween(frame, { BackgroundColor3 = T.Element }) end)
	end

	-------------------------------------------------- Label
	function B.Label(cfg)
		local text = type(cfg) == "table" and (cfg.Name or cfg.Text) or cfg or "Label"
		local f = Base(TOUCH_HEIGHT - 6, true)
		f:FindFirstChildOfClass("UIStroke").Transparency = 0.5
		New("UISizeConstraint", { Parent = f, MinSize = Vector2.new(0, TOUCH_HEIGHT - 6) })
		New("UIPadding", { Parent = f, PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) })
		local l = Label({
			Parent = f, Text = tostring(text), TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y,
		})
		local obj = {}
		function obj:Set(t) l.Text = tostring(t) end
		function obj:SetText(t) l.Text = tostring(t) end
		return obj
	end

	-------------------------------------------------- Button
	function B.Button(cfg)
		cfg = type(cfg) == "string" and { Name = cfg } or cfg or {}
		local name = cfg.Name or "Button"
		local callback = cfg.Callback or function() end
		local f = Base(TOUCH_HEIGHT)
		local label = Label({
			Parent = f, Text = name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local click = Btn({ Parent = f, Size = UDim2.new(1, 0, 1, 0) })
		Hover(f, click)
		local armed = false
		Connect(click.MouseButton1Click, function()
			if cfg.DoubleTap then
				if not armed then
					armed = true
					label.Text = "Tap again to confirm"
					task.delay(cfg.TapDelay or 1.2, function()
						if armed then armed = false; label.Text = name end
					end)
					return
				end
				armed = false
				label.Text = name
			end
			task.spawn(callback)
		end)
		local obj = {}
		function obj:Set(t) name = tostring(t); label.Text = name end
		return obj
	end

	-------------------------------------------------- Toggle
	function B.Toggle(cfg)
		cfg = type(cfg) == "string" and { Name = cfg } or cfg or {}
		local callback = cfg.Callback or function() end
		local obj = { Value = cfg.Default and true or false, Type = "Toggle", Name = cfg.Name or "Toggle" }

		local f = Base(TOUCH_HEIGHT)
		Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -60, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local box = New("Frame", {
			Parent = f, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = T.Main, BorderSizePixel = 0,
		}, { Stroke(T.Stroke) })
		local check = Label({
			Parent = box, Text = "✓", Font = Enum.Font.GothamBlack, TextSize = 18,
			Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 1,
		})
		local click = Btn({ Parent = f, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
		Hover(f, click)

		local function Paint()
			Tween(box, { BackgroundColor3 = obj.Value and T.Accent or T.Main })
			Tween(check, { TextTransparency = obj.Value and 0 or 1 })
		end

		function obj:Set(v)
			obj.Value = v and true or false
			Paint()
			task.spawn(callback, obj.Value)
		end
		function obj:SetName(t) obj.Name = t; f:FindFirstChildOfClass("TextLabel").Text = t end
		function obj:ChangeVisibility(b) f.Visible = b end

		Connect(click.MouseButton1Click, function() obj:Set(not obj.Value) end)

		-- compat: sliders/dropdowns created "inside" a toggle are placed in the same section
		function obj:AddSlider(c) return B.Slider(c) end
		function obj:AddDropdown(c) return B.Dropdown(c) end
		function obj:AddButton(c) return B.Button(c) end
		function obj:AddLabel(c) return B.Label(c) end
		function obj:AddBind(c) return B.Bind(c) end
		function obj:AddToggle(c) return B.Toggle(c) end

		box.BackgroundColor3 = obj.Value and T.Accent or T.Main
		check.TextTransparency = obj.Value and 0 or 1
		if obj.Value then task.spawn(callback, obj.Value) end
		if cfg.Flag then OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	-------------------------------------------------- Slider
	function B.Slider(cfg)
		cfg = cfg or {}
		local min = cfg.Min or 0
		local max = cfg.Max or 100
		if max <= min then max = min + 1 end
		local inc = cfg.Increment or 1
		local valueName = cfg.ValueName and (" " .. cfg.ValueName) or ""
		local callback = cfg.Callback or function() end
		local endedCb = cfg.InputEndedCallback or function() end
		local obj = { Value = cfg.Default or min, Type = "Slider", Name = cfg.Name or "Slider" }

		local f = Base(60)
		Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -110, 0, 20),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local valueLabel = Label({
			Parent = f, Text = "", TextColor3 = T.TextDark, TextSize = 13,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6),
			Size = UDim2.new(0, 100, 0, 20), TextXAlignment = Enum.TextXAlignment.Right,
		})
		local track = New("Frame", {
			Parent = f, Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 20),
			BackgroundColor3 = T.Main, BorderSizePixel = 0, Active = true,
		}, { Stroke(T.Stroke) })
		local fill = New("Frame", {
			Parent = track, Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.Accent, BorderSizePixel = 0,
		})

		local function Render()
			local a = (obj.Value - min) / (max - min)
			fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
			valueLabel.Text = tostring(obj.Value) .. valueName
		end

		function obj:Set(v)
			v = tonumber(v) or min
			obj.Value = math.clamp(Round(v, inc), min, max)
			Render()
			task.spawn(callback, obj.Value)
		end

		local dragging = false
		local function FromInput(i)
			local w = track.AbsoluteSize.X
			if w <= 0 then return end
			local a = math.clamp((i.Position.X - track.AbsolutePosition.X) / w, 0, 1)
			obj:Set(min + (max - min) * a)
		end
		Connect(track.InputBegan, function(i)
			if IsPointer(i) then
				dragging = true
				setScrolling(false)
				FromInput(i)
			end
		end)
		Connect(UIS.InputChanged, function(i)
			if dragging and IsMove(i) then FromInput(i) end
		end)
		Connect(UIS.InputEnded, function(i)
			if dragging and IsPointer(i) then
				dragging = false
				setScrolling(true)
				task.spawn(endedCb, obj.Value)
			end
		end)

		obj.Value = math.clamp(Round(tonumber(obj.Value) or min, inc), min, max)
		Render()
		task.spawn(callback, obj.Value)
		if cfg.Flag then OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	-------------------------------------------------- Dropdown
	function B.Dropdown(cfg)
		cfg = cfg or {}
		local multi = cfg.Multi and true or false
		local maxShow = cfg.MaxSize or 5
		local callback = cfg.Callback or function() end
		local ROW = 34

		local obj = {
			Type = "Dropdown", Name = cfg.Name or "Dropdown",
			Options = {}, Buttons = {}, Toggled = false,
			Value = multi and {} or "",
		}

		local f = New("Frame", {
			Parent = getHolder(),
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.Element, BackgroundTransparency = elemT, BorderSizePixel = 0,
			ClipsDescendants = true, LayoutOrder = NextOrder(getHolder()),
		}, { Stroke(T.Stroke), List(0) })

		local header = New("Frame", {
			Parent = f, Size = UDim2.new(1, 0, 0, TOUCH_HEIGHT), BackgroundTransparency = 1, LayoutOrder = 1,
		})
		Label({
			Parent = header, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.5, -12, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local current = Label({
			Parent = header, Text = "", TextColor3 = T.TextDark, TextSize = 13,
			Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -34, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local arrow = Label({
			Parent = header, Text = "v", Font = Enum.Font.GothamBold, TextColor3 = T.TextDark,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 18, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
		})
		local click = Btn({ Parent = header, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })

		local search
		if cfg.Search then
			search = New("TextBox", {
				Parent = f, Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = T.Main, BorderSizePixel = 0,
				Text = "", PlaceholderText = "Search", PlaceholderColor3 = T.TextDark,
				TextColor3 = T.Text, Font = Enum.Font.GothamMedium, TextSize = 13,
				ClearTextOnFocus = false, Visible = false, LayoutOrder = 2,
			}, { Stroke(T.Stroke) })
		end

		local list = New("ScrollingFrame", {
			Parent = f, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, LayoutOrder = 3,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, { List(0) })

		local function IsSelected(opt)
			if multi then return table.find(obj.Value, opt) ~= nil end
			return obj.Value == opt
		end

		local function UpdateText()
			if multi then
				local names = {}
				for _, v in ipairs(obj.Value) do table.insert(names, tostring(v)) end
				current.Text = #names > 0 and table.concat(names, ", ") or "..."
			else
				current.Text = tostring(obj.Value ~= "" and obj.Value or "...")
			end
		end

		local function Paint()
			for opt, b in pairs(obj.Buttons) do
				local sel = IsSelected(opt)
				b.BackgroundTransparency = sel and 0 or 1
				b.BackgroundColor3 = T.Accent
				b.TextColor3 = sel and Color3.new(1, 1, 1) or T.TextDark
			end
			UpdateText()
		end

		local function Resize()
			local rows = math.min(#obj.Options, maxShow)
			list.Size = UDim2.new(1, 0, 0, rows > 0 and (rows * ROW + 4) or 0)
		end

		local function Open(state)
			obj.Toggled = state
			list.Visible = state
			if search then search.Visible = state end
			Tween(arrow, { Rotation = state and 180 or 0 })
		end

		local function Rebuild()
			for _, b in pairs(obj.Buttons) do b:Destroy() end
			obj.Buttons = {}
			for idx, opt in ipairs(obj.Options) do
				local b = New("TextButton", {
					Parent = list, Size = UDim2.new(1, 0, 0, ROW), AutoButtonColor = false,
					BackgroundColor3 = T.Accent, BackgroundTransparency = 1, BorderSizePixel = 0,
					Text = tostring(opt), Font = Enum.Font.GothamMedium, TextSize = 13,
					TextColor3 = T.TextDark, LayoutOrder = idx,
				})
				obj.Buttons[opt] = b
				Connect(b.MouseButton1Click, function()
					obj:Set(opt)
					if not multi then Open(false) end
				end)
			end
			Resize()
			Paint()
		end

		function obj:Set(v)
			if multi then
				if type(v) == "table" then
					obj.Value = {}
					for _, o in ipairs(v) do
						if table.find(obj.Options, o) then table.insert(obj.Value, o) end
					end
				else
					local at = table.find(obj.Value, v)
					if at then table.remove(obj.Value, at)
					elseif table.find(obj.Options, v) then table.insert(obj.Value, v) end
				end
			else
				if table.find(obj.Options, v) then obj.Value = v else obj.Value = "" end
			end
			Paint()
			task.spawn(callback, obj.Value)
		end
		obj.SetValue = obj.Set

		function obj:Refresh(options, delete)
			if delete then
				obj.Value = multi and {} or ""
			end
			obj.Options = options or {}
			-- drop selections that no longer exist
			if multi then
				for i = #obj.Value, 1, -1 do
					if not table.find(obj.Options, obj.Value[i]) then table.remove(obj.Value, i) end
				end
			elseif not table.find(obj.Options, obj.Value) then
				obj.Value = ""
			end
			Rebuild()
		end

		function obj:ChangeVisibility(b) f.Visible = b end

		Connect(click.MouseButton1Click, function() Open(not obj.Toggled) end)
		if search then
			Connect(search:GetPropertyChangedSignal("Text"), function()
				local q = string.lower(search.Text)
				for opt, b in pairs(obj.Buttons) do
					b.Visible = q == "" or string.find(string.lower(tostring(opt)), q, 1, true) ~= nil
				end
			end)
		end

		obj.Options = cfg.Options or {}
		Rebuild()
		local def = cfg.Default
		if multi then
			if type(def) == "table" and #def > 0 then obj:Set(def) end
		elseif def ~= nil and def ~= "" and table.find(obj.Options, def) then
			obj:Set(def)
		end
		if cfg.Flag then OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	-------------------------------------------------- Bind
	function B.Bind(cfg)
		cfg = cfg or {}
		local callback = cfg.Callback or function() end
		local hold = cfg.Hold and true or false
		local obj = { Value = "", Binding = false, Type = "Bind", Name = cfg.Name or "Bind" }

		local f = Base(TOUCH_HEIGHT)
		Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -110, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local box = Btn({
			Parent = f, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 80, 0, 28), BackgroundTransparency = 0, BackgroundColor3 = T.Main,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.Text, Text = "None",
		})
		Stroke(T.Stroke).Parent = box

		local function Show() box.Text = obj.Value ~= "" and obj.Value or "None" end

		function obj:Set(key)
			obj.Binding = false
			if typeof(key) == "EnumItem" then key = key.Name end
			obj.Value = key or ""
			Show()
		end

		Connect(box.MouseButton1Click, function()
			if obj.Binding then return end
			obj.Binding = true
			box.Text = "..."
		end)

		Connect(UIS.InputBegan, function(input, gp)
			if obj.Binding then
				if input.UserInputType == Enum.UserInputType.Keyboard then
					if input.KeyCode == Enum.KeyCode.Escape then
						obj.Binding = false
						Show()
					elseif input.KeyCode == Enum.KeyCode.Backspace then
						obj:Set("")
					else
						obj:Set(input.KeyCode.Name)
					end
				end
				return
			end
			if gp or obj.Value == "" then return end
			if input.KeyCode.Name == obj.Value or input.UserInputType.Name == obj.Value then
				task.spawn(callback, hold and true or nil)
			end
		end)
		if hold then
			Connect(UIS.InputEnded, function(input)
				if obj.Value ~= "" and (input.KeyCode.Name == obj.Value or input.UserInputType.Name == obj.Value) then
					task.spawn(callback, false)
				end
			end)
		end

		obj:Set(cfg.Default or "")
		if cfg.Flag then OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	return B
end

local function Attach(target, B)
	function target:AddLabel(c) return B.Label(c) end
	function target:AddParagraph(title, content)
		return B.Label((title or "") .. ((content and content ~= "") and ("\n" .. content) or ""))
	end
	function target:AddButton(c) return B.Button(c) end
	function target:AddToggle(c) return B.Toggle(c) end
	function target:AddSlider(c) return B.Slider(c) end
	function target:AddDropdown(c) return B.Dropdown(c) end
	function target:AddBind(c) return B.Bind(c) end
end

---------------------------------------------------------------- window
function OrionLib:MakeWindow(cfg)
	cfg = cfg or {}
	local reqSize = cfg.Size or UDim2.fromOffset(620, 400)
	local minSize = cfg.MinSize or UDim2.fromOffset(420, 240)
	local maxSize = cfg.MaxSize or UDim2.fromOffset(4000, 2000)
	local mainT = math.clamp(cfg.Transparency or 0, 0, 0.6)
	local elemT = math.clamp(cfg.ElementsTransparency or 0, 0, 0.4)
	local toggleKey = cfg.ToggleUIKey or Enum.KeyCode.RightShift

	local Window = { Tabs = {}, Hidden = false, Minimized = false }
	local scale = 1
	local curW, curH = reqSize.X.Offset, reqSize.Y.Offset
	local limits = { minW = 300, minH = 200, maxW = 4000, maxH = 2000 }

	-- Root: scaled space (UIScale lives here so Position offsets stay consistent)
	local Root = New("Frame", {
		Parent = Gui, Name = "Root", BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.fromScale(1, 1),
	})
	local UIScaleObj = New("UIScale", { Parent = Root, Scale = 1 })

	local Main = New("Frame", {
		Parent = Root, Name = "MainWindow",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(curW, curH),
		BackgroundColor3 = T.Main, BackgroundTransparency = mainT, BorderSizePixel = 0,
		ClipsDescendants = true, Active = true,
	}, { Stroke(T.Stroke) })

	-- top bar
	local TopBar = New("Frame", {
		Parent = Main, Name = "TopBar", Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundColor3 = T.TopBar, BackgroundTransparency = mainT * 0.5, BorderSizePixel = 0, Active = true,
	})
	New("Frame", { -- bottom line
		Parent = TopBar, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = T.Stroke, BorderSizePixel = 0,
	})
	local titleX = 12
	if cfg.ShowIcon and cfg.Icon and tostring(cfg.Icon):find("rbxasset") then
		New("ImageLabel", {
			Parent = TopBar, BackgroundTransparency = 1, Image = tostring(cfg.Icon),
			Position = UDim2.new(0, 10, 0.5, -12), Size = UDim2.new(0, 24, 0, 24),
		})
		titleX = 42
	end
	local TitleLabel = Label({
		Parent = TopBar, Text = cfg.Name or "Better Orion", Font = Enum.Font.GothamBlack, TextSize = 16,
		Position = UDim2.new(0, titleX, 0, 0), Size = UDim2.new(1, -(titleX + 100), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if cfg.SubName and cfg.SubName ~= "" then
		TitleLabel.RichText = true
		TitleLabel.Text = string.format('%s  <font size="12" color="rgb(150,150,158)">%s</font>',
			cfg.Name or "Better Orion", cfg.SubName)
	end
	local CloseBtn = Btn({
		Parent = TopBar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 44, 1, 0), Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.Text,
	})
	local MinBtn = Btn({
		Parent = TopBar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 0),
		Size = UDim2.new(0, 44, 1, 0), Text = "-", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = T.Text,
	})

	-- body: SideBar (fixed 160) + Content (fills the rest)
	local Body = New("Frame", {
		Parent = Main, Name = "Body", Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT), BackgroundTransparency = 1, ClipsDescendants = true,
	})
	local SideBar = New("Frame", {
		Parent = Body, Name = "SideBar", Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
		BackgroundColor3 = T.Side, BackgroundTransparency = mainT * 0.5, BorderSizePixel = 0,
	})
	New("Frame", {
		Parent = SideBar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = T.Stroke, BorderSizePixel = 0,
	})
	local TabList = New("ScrollingFrame", {
		Parent = SideBar, Name = "TabList", Size = UDim2.new(1, -1, 1, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { List(2), Pad(6, 6, 6, 6) })
	local Content = New("Frame", {
		Parent = Body, Name = "Content", Position = UDim2.new(0, SIDEBAR_WIDTH, 0, 0),
		Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true,
	})

	local ResizeHandle = Btn({
		Parent = Main, Name = "ResizeHandle", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 30, 0, 30), Text = "◢", TextColor3 = T.TextDark, TextSize = 16,
		Font = Enum.Font.GothamBold, ZIndex = 20, TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	})

	-- floating open button (so mobile users can reopen the UI)
	local OpenBtn = Btn({
		Parent = Gui, Name = "OpenButton", Position = UDim2.new(0, 12, 0, 70), Size = UDim2.new(0, 44, 0, 44),
		BackgroundTransparency = 0, BackgroundColor3 = T.TopBar, Text = "UI", Font = Enum.Font.GothamBold,
		TextSize = 14, TextColor3 = T.Text, Visible = false, ZIndex = 50,
	}, { Stroke(T.Stroke) })

	----------------------------------------------------- layout engine
	local function ClampPosition()
		local vp = Viewport()
		local rw, rh = vp.X / scale, vp.Y / scale
		local w = Main.Size.X.Offset
		local h = Main.Size.Y.Offset
		local lx = math.max((rw - w) / 2, 0)
		local ly = math.max((rh - h) / 2, 0)
		Main.Position = UDim2.new(
			0.5, math.clamp(Main.Position.X.Offset, -lx, lx),
			0.5, math.clamp(Main.Position.Y.Offset, -ly, ly)
		)
	end

	local function ApplySize()
		Main.Size = UDim2.fromOffset(curW, Window.Minimized and TOPBAR_HEIGHT or curH)
		ClampPosition()
	end

	local function Layout()
		local vp = Viewport()
		scale = math.clamp(math.min(vp.X / 760, vp.Y / 440), 0.55, 1)
		UIScaleObj.Scale = scale
		Root.Size = UDim2.fromScale(1 / scale, 1 / scale)

		limits.maxW = math.max(math.floor((vp.X - 40) / scale), 240)
		limits.maxH = math.max(math.floor((vp.Y - 40) / scale), 160)
		limits.maxW = math.min(limits.maxW, maxSize.X.Offset)
		limits.maxH = math.min(limits.maxH, maxSize.Y.Offset)
		limits.minW = math.min(minSize.X.Offset, limits.maxW)
		limits.minH = math.min(minSize.Y.Offset, limits.maxH)

		curW = math.clamp(curW, limits.minW, limits.maxW)
		curH = math.clamp(curH, limits.minH, limits.maxH)
		ApplySize()
	end

	if workspace.CurrentCamera then
		Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), Layout)
	end
	Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		if workspace.CurrentCamera then
			Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), Layout)
			Layout()
		end
	end)
	Layout()

	----------------------------------------------------- drag
	do
		local dragging, startPos, startOffset = false, nil, nil
		Connect(TopBar.InputBegan, function(i)
			if IsPointer(i) then
				dragging = true
				startPos = Vector2.new(i.Position.X, i.Position.Y)
				startOffset = Vector2.new(Main.Position.X.Offset, Main.Position.Y.Offset)
				local conn
				conn = i.Changed:Connect(function()
					if i.UserInputState == Enum.UserInputState.End then
						dragging = false
						conn:Disconnect()
					end
				end)
			end
		end)
		Connect(UIS.InputChanged, function(i)
			if dragging and IsMove(i) then
				local d = (Vector2.new(i.Position.X, i.Position.Y) - startPos) / scale
				Main.Position = UDim2.new(0.5, startOffset.X + d.X, 0.5, startOffset.Y + d.Y)
				ClampPosition()
			end
		end)
	end

	----------------------------------------------------- resize (clamped)
	do
		local resizing, startPos, startW, startH, startOff = false, nil, 0, 0, nil
		Connect(ResizeHandle.InputBegan, function(i)
			if IsPointer(i) and not Window.Minimized then
				resizing = true
				startPos = Vector2.new(i.Position.X, i.Position.Y)
				startW, startH = curW, curH
				startOff = Vector2.new(Main.Position.X.Offset, Main.Position.Y.Offset)
				local conn
				conn = i.Changed:Connect(function()
					if i.UserInputState == Enum.UserInputState.End then
						resizing = false
						conn:Disconnect()
					end
				end)
			end
		end)
		Connect(UIS.InputChanged, function(i)
			if resizing and IsMove(i) then
				local d = (Vector2.new(i.Position.X, i.Position.Y) - startPos) / scale
				local w = math.clamp(startW + d.X, limits.minW, limits.maxW)
				local h = math.clamp(startH + d.Y, limits.minH, limits.maxH)
				curW, curH = w, h
				-- keep the top-left corner fixed while resizing (anchor is centered)
				Main.Position = UDim2.new(0.5, startOff.X + (w - startW) / 2, 0.5, startOff.Y + (h - startH) / 2)
				ApplySize()
			end
		end)
	end

	----------------------------------------------------- show / hide / minimize
	local function SetHidden(h)
		Window.Hidden = h
		Root.Visible = not h
		OpenBtn.Visible = h
	end
	Connect(CloseBtn.MouseButton1Click, function()
		SetHidden(true)
		OrionLib:MakeNotification({ Name = "Interface hidden", Content = "Tap the UI button to reopen.", Time = 3 })
	end)
	Connect(OpenBtn.MouseButton1Click, function() SetHidden(false) end)
	Connect(UIS.InputBegan, function(i, gp)
		if not gp and i.KeyCode == toggleKey then SetHidden(not Window.Hidden) end
	end)
	Connect(MinBtn.MouseButton1Click, function()
		Window.Minimized = not Window.Minimized
		Body.Visible = not Window.Minimized
		ResizeHandle.Visible = not Window.Minimized
		MinBtn.Text = Window.Minimized and "+" or "-"
		ApplySize()
	end)

	----------------------------------------------------- tabs
	local selected
	local function SelectTab(tab)
		selected = tab
		for _, t in ipairs(Window.Tabs) do
			local on = (t == tab)
			t.Page.Visible = on
			t.Button.BackgroundTransparency = on and 0 or 1
			t.Button.BackgroundColor3 = T.Element
			t.Label.TextColor3 = on and T.Text or T.TextDark
			t.Label.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
			t.Bar.Visible = on
		end
	end

	function Window:MakeTab(tcfg)
		tcfg = type(tcfg) == "string" and { Name = tcfg } or tcfg or {}
		local tab = { Name = tcfg.Name or "Tab" }

		local button = Btn({
			Parent = TabList, Size = UDim2.new(1, 0, 0, TOUCH_HEIGHT), BackgroundColor3 = T.Element,
			BackgroundTransparency = 1, LayoutOrder = NextOrder(TabList),
		})
		local bar = New("Frame", {
			Parent = button, Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = T.Accent,
			BorderSizePixel = 0, Visible = false,
		})
		local labelX = 12
		if tcfg.Icon and tostring(tcfg.Icon):find("rbxasset") then
			New("ImageLabel", {
				Parent = button, BackgroundTransparency = 1, Image = tostring(tcfg.Icon),
				Position = UDim2.new(0, 10, 0.5, -9), Size = UDim2.new(0, 18, 0, 18),
			})
			labelX = 36
		end
		local label = Label({
			Parent = button, Text = tab.Name, TextColor3 = T.TextDark,
			Position = UDim2.new(0, labelX, 0, 0), Size = UDim2.new(1, -(labelX + 6), 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		local page = New("ScrollingFrame", {
			Parent = Content, Name = "Page_" .. tab.Name, Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			ScrollBarImageColor3 = T.Stroke, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, { List(10), Pad(10, 14, 10, 14) })

		tab.Button, tab.Label, tab.Bar, tab.Page = button, label, bar, page
		table.insert(Window.Tabs, tab)

		Connect(button.MouseButton1Click, function() SelectTab(tab) end)
		if #Window.Tabs == 1 then SelectTab(tab) end

		local function setScrolling(on) page.ScrollingEnabled = on end

		-- elements placed directly on the tab go to a lazily created untitled section
		local defaultHolder
		local function getDefaultHolder()
			if not defaultHolder then
				local s = New("Frame", {
					Parent = page, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1, LayoutOrder = NextOrder(page),
				}, { List(6) })
				defaultHolder = s
			end
			return defaultHolder
		end
		Attach(tab, MakeBuilder(getDefaultHolder, setScrolling, elemT))

		function tab:AddSection(scfg)
			scfg = type(scfg) == "string" and { Name = scfg } or scfg or {}
			local section = { Name = scfg.Name or "Section" }

			local sframe = New("Frame", {
				Parent = page, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = NextOrder(page),
			}, { List(6) })
			Label({
				Parent = sframe, Text = string.upper(section.Name), Font = Enum.Font.GothamBold,
				TextSize = 12, TextColor3 = T.TextDark, Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 0, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local holder = New("Frame", {
				Parent = sframe, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = 1,
			}, { List(6) })

			Attach(section, MakeBuilder(function() return holder end, setScrolling, elemT))
			function section:SetName(n)
				for _, c in ipairs(sframe:GetChildren()) do
					if c:IsA("TextLabel") then c.Text = string.upper(n) break end
				end
			end
			return section
		end

		return tab
	end

	----------------------------------------------------- misc window api
	function Window:SetTransparency(t)
		t = math.clamp(t or 0, 0, 0.6)
		Main.BackgroundTransparency = t
	end
	function Window:SetSize(s)
		curW, curH = s.X.Offset, s.Y.Offset
		Layout()
	end
	function Window:SetToggleKey(k)
		if typeof(k) == "EnumItem" then toggleKey = k elseif Enum.KeyCode[k] then toggleKey = Enum.KeyCode[k] end
	end
	function Window:SetVisible(v) SetHidden(not v) end
	function Window:Destroy() OrionLib:Destroy() end
	function Window:DestroyElement(flag)
		local e = OrionLib.Flags[flag]
		if e and e.Destroy then e:Destroy() end
		OrionLib.Flags[flag] = nil
	end

	OrionLib.Window = Window
	return Window
end

function OrionLib:Init()
	local main = Gui:FindFirstChild("Root", true)
	if main then main.Visible = true end
end

return OrionLib
