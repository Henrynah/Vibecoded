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
local TOPBAR_HEIGHT = 50
local TOUCH_HEIGHT = 38 -- minimum touch target

local OrionLib = {
	Flags = {},
	Connections = {},
	NotificationSettings = { Enabled = true, Printing = false },
}

local T = {
	Main = Color3.fromRGB(20, 20, 20),
	Stroke = Color3.fromRGB(100, 100, 100),
	Divider = Color3.fromRGB(100, 100, 100),
	Text = Color3.fromRGB(255, 255, 255),
	TextDark = Color3.fromRGB(200, 200, 200),
	Element = Color3.fromRGB(80, 80, 80),
	ElementHover = Color3.fromRGB(88, 88, 88),
	OptionSel = Color3.fromRGB(40, 40, 40),
	Default = Color3.fromRGB(50, 50, 50),
}

-- Lucide icons (same source as the original BetterOrion)
local LucideIcons = {}
pcall(function()
	LucideIcons = loadstring(game:HttpGet("https://raw.githubusercontent.com/m1kp0/BetterOrion/refs/heads/main/Icons.lua"))().assets
end)
local function GetIcon(name)
	if name == nil or name == "" then return nil end
	name = tostring(name)
	if name:find("://") then return name end
	return LucideIcons["lucide-" .. name]
end

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

local function Stroke(color, transparency, thickness)
	return New("UIStroke", {
		Color = color or T.Stroke,
		Transparency = transparency == nil and 0.5 or transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function Corner(r)
	return New("UICorner", { CornerRadius = UDim.new(0, r or 5) })
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

OrionLib.Gui = Gui
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
			BackgroundColor3 = T.Main,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			LayoutOrder = NextOrder(NotifHolder),
		}, { Corner(8), Stroke(T.Stroke, 0.5), Pad(12, 12, 10, 12) })
		local icon = GetIcon(cfg.Image or "server")
		local textX = 0
		if icon then
			New("ImageLabel", {
				Parent = frame, BackgroundTransparency = 1, Image = icon,
				Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 18, 0, 18),
			})
			textX = 28
		end
		local inner = New("Frame", {
			Parent = frame, BackgroundTransparency = 1, Position = UDim2.new(0, textX, 0, 0),
			Size = UDim2.new(1, -textX, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		}, { List(3) })
		Label({
			Parent = inner, Text = title, Font = Enum.Font.GothamBold, TextSize = 15,
			Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		if content ~= "" then
			Label({
				Parent = inner, Text = content, Font = Enum.Font.GothamSemibold, TextSize = 13,
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true, LayoutOrder = 2,
			})
		end
		local timer = New("Frame", {
			Parent = inner, Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0, LayoutOrder = 3,
		}, { Corner(8) })
		Tween(timer, { Size = UDim2.new(0, 0, 0, 2) }, math.max(duration - 0.5, 0.1))
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
		}, { Corner(5), Stroke(T.Stroke, 0.5) })
		if auto then f.AutomaticSize = Enum.AutomaticSize.Y end
		return f
	end

	local function Hover(frame, button)
		Connect(button.MouseEnter, function() Tween(frame, { BackgroundColor3 = T.ElementHover }, 0.25) end)
		Connect(button.MouseLeave, function() Tween(frame, { BackgroundColor3 = T.Element }, 0.25) end)
	end

	-------------------------------------------------- Label
	function B.Label(cfg)
		local text = type(cfg) == "table" and (cfg.Name or cfg.Text) or cfg or "Label"
		local f = Base(TOUCH_HEIGHT - 6, true)
		New("UISizeConstraint", { Parent = f, MinSize = Vector2.new(0, TOUCH_HEIGHT - 6) })
		New("UIPadding", { Parent = f, PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) })
		local l = Label({
			Parent = f, Text = tostring(text), Font = Enum.Font.GothamBold, TextWrapped = true,
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
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -44, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		New("ImageLabel", {
			Parent = f, BackgroundTransparency = 1, Image = GetIcon(cfg.Icon) or "rbxassetid://3944703587",
			ImageColor3 = T.TextDark, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 20, 0, 20),
		})
		local click = Btn({ Parent = f, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
		Hover(f, click)
		local armed = false
		Connect(click.MouseButton1Click, function()
			if cfg.DoubleTap then
				if not armed then
					armed = true
					label.Text = "Are you sure?"
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
		local color = cfg.Color or T.Default
		local obj = { Value = cfg.Default and true or false, Type = "Toggle", Name = cfg.Name or "Toggle" }

		local f = Base(TOUCH_HEIGHT)
		local nameLabel = Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -60, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local box = New("Frame", {
			Parent = f, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = T.Divider, BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		})
		Corner(4).Parent = box
		local boxStroke = Stroke(T.Stroke, 0.5)
		boxStroke.Parent = box
		local check = New("ImageLabel", {
			Parent = box, BackgroundTransparency = 1, Image = "rbxassetid://3944680095",
			ImageColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 8, 0, 8), ImageTransparency = 1,
		})
		local click = Btn({ Parent = f, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
		Hover(f, click)

		local function Paint(animate)
			local d = animate and 0.3 or 0
			local info = TweenInfo.new(d, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			TweenService:Create(box, info, { BackgroundColor3 = obj.Value and color or T.Divider }):Play()
			TweenService:Create(boxStroke, info, { Color = obj.Value and color or T.Stroke }):Play()
			TweenService:Create(check, info, {
				ImageTransparency = obj.Value and 0 or 1,
				Size = obj.Value and UDim2.new(0, 20, 0, 20) or UDim2.new(0, 8, 0, 8),
			}):Play()
		end

		function obj:Set(v)
			obj.Value = v and true or false
			Paint(true)
			task.spawn(callback, obj.Value)
		end
		function obj:SetName(t) obj.Name = t; nameLabel.Text = t end
		function obj:ChangeVisibility(b) f.Visible = b end

		Connect(click.MouseButton1Click, function() obj:Set(not obj.Value) end)

		-- compat: sliders/dropdowns created "inside" a toggle are placed in the same section
		function obj:AddSlider(c) return B.Slider(c) end
		function obj:AddDropdown(c) return B.Dropdown(c) end
		function obj:AddButton(c) return B.Button(c) end
		function obj:AddLabel(c) return B.Label(c) end
		function obj:AddBind(c) return B.Bind(c) end
		function obj:AddToggle(c) return B.Toggle(c) end
		function obj:AddColorpicker(c) return B.Colorpicker(c) end
		function obj:AddTextbox(c) return B.Textbox(c) end

		Paint(false)
		if obj.Value then task.spawn(callback, obj.Value) end
		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
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
		local color = cfg.Color or T.Default
		local callback = cfg.Callback or function() end
		local endedCb = cfg.InputEndedCallback or function() end
		local obj = { Value = cfg.Default or min, Type = "Slider", Name = cfg.Name or "Slider" }

		local f = Base(64)
		Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local track = New("Frame", {
			Parent = f, Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -24, 0, 26),
			BackgroundColor3 = color, BackgroundTransparency = 0.9, BorderSizePixel = 0,
			Active = true, ClipsDescendants = true,
		}, { Corner(5), Stroke(color, 0) })
		local fill = New("Frame", {
			Parent = track, Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color,
			BackgroundTransparency = 0.3, BorderSizePixel = 0,
		}, { Corner(5) })
		local valueLabel = Label({
			Parent = track, Text = "", Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 3,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0),
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
		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
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
		}, { Corner(5), Stroke(T.Stroke, 0.5), List(0) })

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
			Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -38, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local arrow = New("ImageLabel", {
			Parent = header, BackgroundTransparency = 1, Image = "rbxassetid://7072706796",
			ImageColor3 = T.TextDark, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 20, 0, 20),
		})
		local click = Btn({ Parent = header, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })

		local search
		if cfg.Search then
			search = New("TextBox", {
				Parent = f, Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = T.Main, BorderSizePixel = 0,
				Text = "", PlaceholderText = "Search", PlaceholderColor3 = T.TextDark,
				TextColor3 = T.Text, Font = Enum.Font.GothamMedium, TextSize = 13,
				ClearTextOnFocus = false, Visible = false, LayoutOrder = 2,
			}, { Corner(6), Stroke(T.Stroke, 0.5) })
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
				b.BackgroundColor3 = T.OptionSel
				b.TextTransparency = sel and 0 or 0.4
				b.TextColor3 = T.Text
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
					BackgroundColor3 = T.OptionSel, BackgroundTransparency = 1, BorderSizePixel = 0,
					Text = tostring(opt), Font = Enum.Font.Gotham, TextSize = 13,
					TextColor3 = T.Text, TextTransparency = 0.4, LayoutOrder = idx,
				})
				Corner(6).Parent = b
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
			local picked
			if multi then
				if type(v) == "table" then
					obj.Value = {}
					for _, o in ipairs(v) do
						if table.find(obj.Options, o) then table.insert(obj.Value, o) end
					end
				else
					picked = v
					local at = table.find(obj.Value, v)
					if at then table.remove(obj.Value, at)
					elseif table.find(obj.Options, v) then table.insert(obj.Value, v) end
				end
			else
				if table.find(obj.Options, v) then obj.Value = v else obj.Value = "" end
			end
			Paint()
			task.spawn(callback, obj.Value, picked)
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
		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
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
			Size = UDim2.new(0, 80, 0, 26), BackgroundTransparency = elemT, BackgroundColor3 = T.Default,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.Text, Text = "None",
		})
		Corner(4).Parent = box
		Stroke(T.Stroke, 0.5).Parent = box

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
		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	-------------------------------------------------- Textbox
	function B.Textbox(cfg)
		cfg = type(cfg) == "string" and { Name = cfg } or cfg or {}
		local callback = cfg.Callback or function() end
		local obj = { Value = tostring(cfg.Default or ""), Type = "Textbox", Name = cfg.Name or "Textbox" }

		local f = Base(TOUCH_HEIGHT)
		Label({
			Parent = f, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.45, -12, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local box = New("TextBox", {
			Parent = f, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.55, -16, 0, 26), BackgroundColor3 = T.Default, BackgroundTransparency = elemT,
			BorderSizePixel = 0, Text = obj.Value, PlaceholderText = cfg.Placeholder or "",
			PlaceholderColor3 = T.TextDark, TextColor3 = T.Text, Font = Enum.Font.GothamMedium,
			TextSize = 13, ClearTextOnFocus = false, ClipsDescendants = true,
		}, { Corner(4), Stroke(T.Stroke, 0.5) })

		Connect(box.FocusLost, function()
			obj.Value = box.Text
			task.spawn(callback, obj.Value)
			if cfg.TextDisappear then box.Text = "" end
		end)

		function obj:Set(t)
			t = tostring(t == nil and "" or t)
			obj.Value = t
			box.Text = t
			task.spawn(callback, t)
		end
		function obj:ChangeVisibility(b) f.Visible = b end

		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
		return obj
	end

	-------------------------------------------------- Colorpicker
	-- Callback(color, transparency): transparency 0 = opaco, 1 = invisivel (igual ao que o hub espera)
	function B.Colorpicker(cfg)
		cfg = type(cfg) == "string" and { Name = cfg } or cfg or {}
		local callback = cfg.Callback or function() end
		local obj = { Type = "Colorpicker", Name = cfg.Name or "Colorpicker", Toggled = false }
		local start = typeof(cfg.Default) == "Color3" and cfg.Default or Color3.new(1, 1, 1)
		local h, sat, val = Color3.toHSV(start)
		local alpha = math.clamp(tonumber(cfg.DefaultTransparency or cfg.Transparency) or 0, 0, 1)
		obj.Value = start
		obj.Transparency = alpha

		local f = New("Frame", {
			Parent = getHolder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.Element, BackgroundTransparency = elemT, BorderSizePixel = 0,
			ClipsDescendants = true, LayoutOrder = NextOrder(getHolder()),
		}, { Corner(5), Stroke(T.Stroke, 0.5), List(0) })
		local header = New("Frame", {
			Parent = f, Size = UDim2.new(1, 0, 0, TOUCH_HEIGHT), BackgroundTransparency = 1, LayoutOrder = 1,
		})
		Label({
			Parent = header, Text = obj.Name, Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -60, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local swatch = New("Frame", {
			Parent = header, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 26, 0, 26), BackgroundColor3 = obj.Value, BorderSizePixel = 0,
		}, { Corner(4), Stroke(T.Stroke, 0.5) })
		local click = Btn({ Parent = header, Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
		local panel = New("Frame", {
			Parent = f, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Visible = false, LayoutOrder = 2,
		}, { List(6), Pad(12, 12, 4, 10) })

		local bars = {}
		local function MakeBar(order, title, onRatio)
			local track = New("Frame", {
				Parent = panel, Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0, Active = true, LayoutOrder = order, ClipsDescendants = true,
			}, { Corner(5), Stroke(T.Stroke, 0.5) })
			local grad = New("UIGradient", { Parent = track })
			local thumb = New("Frame", {
				Parent = track, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0, ZIndex = 3,
			}, { Stroke(Color3.new(0, 0, 0), 0) })
			Label({
				Parent = track, Text = title, TextSize = 12, Font = Enum.Font.GothamBold, ZIndex = 4,
				Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(1, -16, 1, 0), TextStrokeTransparency = 0.5,
			})
			local dragging = false
			local function FromInput(i)
				local w = track.AbsoluteSize.X
				if w <= 0 then return end
				onRatio(math.clamp((i.Position.X - track.AbsolutePosition.X) / w, 0, 1))
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
				end
			end)
			return { grad = grad, thumb = thumb }
		end

		local function Render()
			local c = Color3.fromHSV(h, sat, val)
			swatch.BackgroundColor3 = c
			bars.h.thumb.Position = UDim2.new(h, 0, 0, 0)
			bars.s.thumb.Position = UDim2.new(sat, 0, 0, 0)
			bars.v.thumb.Position = UDim2.new(val, 0, 0, 0)
			bars.a.thumb.Position = UDim2.new(alpha, 0, 0, 0)
			bars.s.grad.Color = ColorSequence.new(Color3.fromHSV(h, 0, val), Color3.fromHSV(h, 1, val))
			bars.v.grad.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, sat, 1))
			bars.a.grad.Color = ColorSequence.new(c, Color3.fromRGB(35, 35, 35))
		end

		local function Emit()
			obj.Value = Color3.fromHSV(h, sat, val)
			obj.Transparency = alpha
			Render()
			task.spawn(callback, obj.Value, obj.Transparency)
		end

		bars.h = MakeBar(1, "Hue", function(r) h = r; Emit() end)
		bars.s = MakeBar(2, "Saturation", function(r) sat = r; Emit() end)
		bars.v = MakeBar(3, "Brightness", function(r) val = r; Emit() end)
		bars.a = MakeBar(4, "Transparency", function(r) alpha = r; Emit() end)
		local hueKeys = {}
		for i = 0, 6 do
			table.insert(hueKeys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
		end
		bars.h.grad.Color = ColorSequence.new(hueKeys)

		function obj:Set(color, transparency)
			if typeof(color) == "Color3" then
				h, sat, val = Color3.toHSV(color)
			end
			if type(transparency) == "number" then alpha = math.clamp(transparency, 0, 1) end
			obj.Value = typeof(color) == "Color3" and color or Color3.fromHSV(h, sat, val)
			obj.Transparency = alpha
			Render()
			task.spawn(callback, obj.Value, obj.Transparency)
		end
		function obj:ChangeVisibility(b) f.Visible = b end

		Connect(click.MouseButton1Click, function()
			obj.Toggled = not obj.Toggled
			panel.Visible = obj.Toggled
		end)

		Render()
		if cfg.Flag then obj.Save = cfg.Save ~= false; OrionLib.Flags[cfg.Flag] = obj end
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
	function target:AddColorpicker(c) return B.Colorpicker(c) end
	function target:AddTextbox(c) return B.Textbox(c) end
end

---------------------------------------------------------------- window
function OrionLib:MakeWindow(cfg)
	cfg = cfg or {}
	local reqSize = cfg.Size or UDim2.fromOffset(620, 400)
	local minSize = cfg.MinSize or UDim2.fromOffset(420, 240)
	local maxSize = cfg.MaxSize or UDim2.fromOffset(4000, 2000)
	local mainT = math.clamp(cfg.Transparency or 0.35, 0, 0.9)
	local elemT = math.clamp(cfg.ElementsTransparency or 0.8, 0, 1)
	local toggleKey = cfg.ToggleUIKey or Enum.KeyCode.RightShift

	local Window = { Tabs = {}, Hidden = false, Minimized = false, Title = tostring(cfg.Name or "Better Orion") }
	local scale = 1
	local curW, curH = reqSize.X.Offset, reqSize.Y.Offset
	local limits = { minW = 300, minH = 200, maxW = 4000, maxH = 2000 }

	-- Root: scaled space (UIScale lives here so Position offsets stay consistent)
	local Root = New("Frame", {
		Parent = Gui, Name = "MainWindow", BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.fromScale(1, 1),
	})
	local UIScaleObj = New("UIScale", { Parent = Root, Scale = 1 })

	local Main = New("Frame", {
		Parent = Root, Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(curW, curH),
		BackgroundColor3 = T.Main, BackgroundTransparency = mainT, BorderSizePixel = 0,
		ClipsDescendants = true, Active = true,
	}, { Corner(10) })

	-- top bar (transparent, like the original)
	local TopBar = New("Frame", {
		Parent = Main, Name = "TopBar", Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
	})
	local titleX = 25
	local winIcon = cfg.ShowIcon and GetIcon(cfg.Icon)
	if winIcon then
		New("ImageLabel", {
			Parent = TopBar, BackgroundTransparency = 1, Image = winIcon, ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0, 25, 0.5, -10), Size = UDim2.new(0, 20, 0, 20),
		})
		titleX = 50
	end
	local TitleLabel = Label({
		Parent = TopBar, Text = cfg.Name or "Better Orion", Font = Enum.Font.GothamBlack, TextSize = 20,
		Position = UDim2.new(0, titleX, 0, 0), Size = UDim2.new(1, -(titleX + 100), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd, RichText = true,
	})
	if cfg.SubName and cfg.SubName ~= "" then
		TitleLabel.Text = string.format(
			'%s  <font size="14" face="GothamSemibold" color="rgb(200,200,200)">%s</font>',
			cfg.Name or "Better Orion", cfg.SubName)
	end
	local ButtonsFrame = New("Frame", {
		Parent = TopBar, Name = "ButtonsFrame", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0, 84, 0, 34), BackgroundTransparency = 1,
	}, { Corner(7), Stroke(T.Stroke, 0.5) })
	New("Frame", {
		Parent = ButtonsFrame, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = T.Divider, BackgroundTransparency = 0.5, BorderSizePixel = 0,
	})
	local MinBtn = Btn({ Parent = ButtonsFrame, Size = UDim2.new(0.5, 0, 1, 0) })
	local MinIcon = New("ImageLabel", {
		Parent = MinBtn, BackgroundTransparency = 1, Image = "rbxassetid://7072719338",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 18, 0, 18),
	})
	local CloseBtn = Btn({ Parent = ButtonsFrame, Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0) })
	New("ImageLabel", {
		Parent = CloseBtn, BackgroundTransparency = 1, Image = "rbxassetid://7072725342",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 18, 0, 18),
	})

	-- body: SideBar (fixed 160) + Content (fills the rest)
	local Body = New("Frame", {
		Parent = Main, Name = "Body", Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT), BackgroundTransparency = 1, ClipsDescendants = true,
	})
	local SideBar = New("Frame", {
		Parent = Body, Name = "SideBar", Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	})
	local TabList = New("ScrollingFrame", {
		Parent = SideBar, Name = "TabList", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { List(2), Pad(8, 8, 8, 8) })
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
		BackgroundTransparency = 0.35, BackgroundColor3 = T.Main, Text = "UI", Font = Enum.Font.GothamBlack,
		TextSize = 14, TextColor3 = T.Text, Visible = false, ZIndex = 50,
	}, { Corner(10), Stroke(T.Stroke, 0.5) })

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
		MinIcon.Image = Window.Minimized and "rbxassetid://7072720870" or "rbxassetid://7072719338"
		ApplySize()
	end)

	----------------------------------------------------- tabs
	local selected
	local function SelectTab(tab)
		selected = tab
		for _, t in ipairs(Window.Tabs) do
			local on = (t == tab)
			t.Page.Visible = on
			Tween(t.Label, { TextTransparency = on and 0 or 0.4 }, 0.25)
			t.Label.Font = on and Enum.Font.GothamBlack or Enum.Font.GothamSemibold
			if t.Icon then Tween(t.Icon, { ImageTransparency = on and 0 or 0.4 }, 0.25) end
		end
	end

	function Window:MakeTab(tcfg)
		tcfg = type(tcfg) == "string" and { Name = tcfg } or tcfg or {}
		local tab = { Name = tcfg.Name or "Tab" }

		local button = Btn({
			Parent = TabList, Size = UDim2.new(1, 0, 0, TOUCH_HEIGHT - 2), BackgroundTransparency = 1,
			LayoutOrder = NextOrder(TabList),
		})
		local labelX = 12
		local tabIconId = GetIcon(tcfg.Icon)
		local iconObj
		if tabIconId then
			iconObj = New("ImageLabel", {
				Parent = button, BackgroundTransparency = 1, Image = tabIconId, ImageTransparency = 0.4,
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.new(0, 18, 0, 18),
			})
			labelX = 35
		end
		local label = Label({
			Parent = button, Text = tab.Name, Font = Enum.Font.GothamSemibold, TextTransparency = 0.4,
			Position = UDim2.new(0, labelX, 0, 0), Size = UDim2.new(1, -(labelX + 4), 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		local page = New("ScrollingFrame", {
			Parent = Content, Name = "Page_" .. tab.Name, Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			ScrollBarImageColor3 = T.Divider, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, { List(10), Pad(10, 14, 10, 14) })

		tab.Button, tab.Label, tab.Icon, tab.Page = button, label, iconObj, page

		-- two columns (Left / Right); collapses to one column on narrow screens
		local ColumnsLayout = New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Top,
		})
		local Columns = New("Frame", {
			Parent = page, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, { ColumnsLayout })
		local function MakeColumn(order)
			return New("Frame", {
				Parent = Columns, Name = order == 1 and "Left" or "Right",
				Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = order,
			}, { List(10) })
		end
		local ColLeft, ColRight = MakeColumn(1), MakeColumn(2)
		local function Responsive()
			local narrow = (Content.AbsoluteSize.X / math.max(scale, 0.01)) < 430
			ColumnsLayout.FillDirection = narrow and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
			local sz = narrow and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -5, 0, 0)
			ColLeft.Size = sz
			ColRight.Size = sz
		end
		Connect(Content:GetPropertyChangedSignal("AbsoluteSize"), Responsive)
		Responsive()
		table.insert(Window.Tabs, tab)

		Connect(button.MouseButton1Click, function() SelectTab(tab) end)
		if #Window.Tabs == 1 then SelectTab(tab) end

		local function setScrolling(on) page.ScrollingEnabled = on end

		-- elements placed directly on the tab go to a lazily created untitled section
		local defaultHolder
		local function getDefaultHolder()
			if not defaultHolder then
				local s = New("Frame", {
					Parent = ColLeft, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1, LayoutOrder = NextOrder(ColLeft),
				}, { List(6) })
				defaultHolder = s
			end
			return defaultHolder
		end
		Attach(tab, MakeBuilder(getDefaultHolder, setScrolling, elemT))

		function tab:AddSection(scfg)
			scfg = type(scfg) == "string" and { Name = scfg } or scfg or {}
			local section = { Name = scfg.Name or "Section" }

			local sideCol = (tostring(scfg.Side or "Left"):lower() == "right") and ColRight or ColLeft
			local sframe = New("Frame", {
				Parent = sideCol, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = NextOrder(sideCol),
			}, { List(6) })
			Label({
				Parent = sframe, Text = section.Name, Font = Enum.Font.GothamSemibold,
				TextSize = 14, Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 0, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			local holder = New("Frame", {
				Parent = sframe, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = 1,
			}, { List(6) })

			Attach(section, MakeBuilder(function() return holder end, setScrolling, elemT))
			function section:SetName(n)
				for _, c in ipairs(sframe:GetChildren()) do
					if c:IsA("TextLabel") then c.Text = n break end
				end
			end
			return section
		end

		return tab
	end

	----------------------------------------------------- misc window api
	function Window:SetTransparency(t)
		t = math.clamp(t or 0, 0, 0.9)
		Main.BackgroundTransparency = t
	end
	function Window:SetSize(s)
		curW, curH = s.X.Offset, s.Y.Offset
		Layout()
	end
	function Window:SetToggleKey(k)
		if typeof(k) == "EnumItem" then
			toggleKey = k
		elseif type(k) == "string" and k ~= "" then
			local ok, kc = pcall(function() return Enum.KeyCode[k] end)
			if ok and kc then toggleKey = kc end
		end
	end
	function Window:SetVisible(v) SetHidden(not v) end
	function Window:Destroy() OrionLib:Destroy() end
	function Window:DestroyElement(flag)
		local e = OrionLib.Flags[flag]
		if e and e.Destroy then e:Destroy() end
		OrionLib.Flags[flag] = nil
	end

	function Window:GetSize() return curW, curH end

	local Watermark
	function Window:SetWatermarkVisibility(on)
		on = on and true or false
		if on and not Watermark then
			Watermark = New("Frame", {
				Parent = Gui, Name = "Watermark", Position = UDim2.new(0, 12, 0, 12),
				AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 26),
				BackgroundColor3 = T.Main, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 40,
			}, { Corner(6), Stroke(T.Stroke, 0.5), Pad(10, 10, 0, 0) })
			local text = Label({
				Parent = Watermark, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
				Text = Window.Title, TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 41,
			})
			local frames, last = 0, os.clock()
			Connect(RunService.RenderStepped, function()
				frames = frames + 1
				local now = os.clock()
				if now - last >= 0.5 then
					text.Text = string.format("%s | %d fps", Window.Title, math.floor(frames / (now - last) + 0.5))
					frames, last = 0, now
				end
			end)
		end
		if Watermark then Watermark.Visible = on end
	end

	OrionLib.Window = Window
	return Window
end

---------------------------------------------------------------- configs
local HttpService = game:GetService("HttpService")
local FS = {
	ok = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function" and type(listfiles) == "function",
}

local function Safe(name) return (tostring(name):gsub("[^%w_%-]", "_")) end

local function RootFolder()
	local title = OrionLib.Window and OrionLib.Window.Title or "BetterOrion"
	local root = "BetterOrion"
	if not isfolder(root) then makefolder(root) end
	root = root .. "/" .. Safe(title)
	if not isfolder(root) then makefolder(root) end
	local cfgs = root .. "/configs"
	if not isfolder(cfgs) then makefolder(cfgs) end
	return root, cfgs
end

local function Serialize()
	local data = {}
	for flag, o in pairs(OrionLib.Flags) do
		if o.Save ~= false then
			if o.Type == "Colorpicker" then
				data[flag] = { t = o.Type, r = o.Value.R, g = o.Value.G, b = o.Value.B, a = o.Transparency }
			elseif o.Type == "Toggle" or o.Type == "Slider" or o.Type == "Dropdown"
				or o.Type == "Bind" or o.Type == "Textbox" then
				data[flag] = { t = o.Type, v = o.Value }
			end
		end
	end
	return data
end

function OrionLib:ListConfigs()
	if not FS.ok then return {} end
	local ok, names = pcall(function()
		local _, cfgs = RootFolder()
		local out = {}
		for _, p in ipairs(listfiles(cfgs)) do
			local n = tostring(p):match("([^/\\]+)%.json$")
			if n then table.insert(out, n) end
		end
		table.sort(out)
		return out
	end)
	return ok and names or {}
end

function OrionLib:SaveConfig(name)
	if not FS.ok then return false, "no file functions" end
	name = Safe(name or "")
	if name == "" then return false, "empty name" end
	local ok, err = pcall(function()
		local _, cfgs = RootFolder()
		writefile(cfgs .. "/" .. name .. ".json", HttpService:JSONEncode(Serialize()))
	end)
	return ok, err
end

function OrionLib:LoadConfig(name)
	if not FS.ok then return false, "no file functions" end
	name = Safe(name or "")
	if name == "" then return false, "empty name" end
	local okRead, raw = pcall(function()
		local _, cfgs = RootFolder()
		local path = cfgs .. "/" .. name .. ".json"
		if not isfile(path) then return nil end
		return readfile(path)
	end)
	if not okRead or not raw then return false, "config not found" end
	local okJson, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not okJson or type(data) ~= "table" then return false, "invalid config file" end

	local n = 0
	for flag, e in pairs(data) do
		local o = OrionLib.Flags[flag]
		if o and type(e) == "table" and o.Type == e.t then
			pcall(function()
				if e.t == "Colorpicker" then
					o:Set(Color3.new(e.r, e.g, e.b), e.a)
				elseif e.t == "Dropdown" and type(e.v) == "table" then
					o:Set(e.v)
				elseif o.Value ~= e.v then
					o:Set(e.v)
				end
			end)
			n = n + 1
			if n % 8 == 0 then task.wait() end
		end
	end
	return true
end

function OrionLib:SetConfigTab(tabName)
	local win = OrionLib.Window
	if not win then return end
	local tab
	for _, t in ipairs(win.Tabs) do
		if t.Name == tabName then tab = t break end
	end
	if not tab then
		warn("[BetterOrion] SetConfigTab: tab not found: " .. tostring(tabName))
		return
	end
	local sec = tab:AddSection({ Name = "Configs", Side = "Right" })
	if not FS.ok then
		sec:AddLabel("This executor has no file functions, so configs are disabled.")
		return
	end

	local typed, selected = "", ""
	local list
	local autoloadLabel = sec:AddLabel("Autoload: none")

	local function AutoloadPath()
		local root = RootFolder()
		return root .. "/autoload.txt"
	end
	local function ReadAutoload()
		local ok, v = pcall(function()
			local p = AutoloadPath()
			return isfile(p) and readfile(p) or ""
		end)
		return ok and v or ""
	end
	local function RefreshAutoloadLabel()
		local a = ReadAutoload()
		autoloadLabel:Set("Autoload: " .. (a ~= "" and a or "none"))
	end
	local function RefreshList()
		if list then list:Refresh(OrionLib:ListConfigs(), true) end
		selected = ""
	end
	local function Note(msg) OrionLib:MakeNotification({ Name = "Configs", Content = msg, Time = 3 }) end

	sec:AddTextbox({ Name = "Config name", Default = "", Callback = function(t) typed = t end })
	list = sec:AddDropdown({
		Name = "Config list", Options = OrionLib:ListConfigs(), Default = "", Search = true,
		Callback = function(v) selected = v end,
	})
	sec:AddButton({ Name = "Create config", Callback = function()
		local ok, err = OrionLib:SaveConfig(typed)
		Note(ok and ("Saved: " .. Safe(typed)) or ("Could not save: " .. tostring(err)))
		if ok then RefreshList() end
	end })
	sec:AddButton({ Name = "Overwrite selected", DoubleTap = true, Callback = function()
		local ok, err = OrionLib:SaveConfig(selected)
		Note(ok and ("Overwritten: " .. selected) or ("Could not save: " .. tostring(err)))
	end })
	sec:AddButton({ Name = "Load selected", Callback = function()
		local ok, err = OrionLib:LoadConfig(selected)
		Note(ok and ("Loaded: " .. selected) or ("Could not load: " .. tostring(err)))
	end })
	sec:AddButton({ Name = "Delete selected", DoubleTap = true, Callback = function()
		if selected == "" or type(delfile) ~= "function" then Note("Nothing to delete") return end
		pcall(function()
			local _, cfgs = RootFolder()
			delfile(cfgs .. "/" .. Safe(selected) .. ".json")
		end)
		RefreshList()
		Note("Deleted")
	end })
	sec:AddButton({ Name = "Set as autoload", Callback = function()
		if selected == "" then Note("Select a config first") return end
		pcall(function() writefile(AutoloadPath(), Safe(selected)) end)
		RefreshAutoloadLabel()
		Note("Autoload: " .. selected)
	end })
	sec:AddButton({ Name = "Refresh list", Callback = RefreshList })
	RefreshAutoloadLabel()
end

function OrionLib:LoadAutoloadConfigs()
	if not FS.ok then return false end
	local ok, name = pcall(function()
		local root = RootFolder()
		local p = root .. "/autoload.txt"
		return isfile(p) and readfile(p) or ""
	end)
	if not ok or name == "" then return false end
	return OrionLib:LoadConfig(name)
end

-- Carrega o tamanho salvo da janela e passa a salvar quando ele mudar.
function OrionLib:SaveAndLoadSizes()
	local win = OrionLib.Window
	if not win or not FS.ok then return false end
	local path
	local okp = pcall(function()
		local root = RootFolder()
		path = root .. "/size.json"
	end)
	if not okp or not path then return false end

	local okRead, raw = pcall(function() return isfile(path) and readfile(path) or nil end)
	if okRead and raw then
		local okJson, d = pcall(function() return HttpService:JSONDecode(raw) end)
		if okJson and type(d) == "table" and tonumber(d.w) and tonumber(d.h) then
			win:SetSize(UDim2.fromOffset(d.w, d.h))
		end
	end

	task.spawn(function()
		local lw, lh = win:GetSize()
		while OrionLib:IsRunning() do
			task.wait(2)
			local w, h = win:GetSize()
			if w ~= lw or h ~= lh then
				lw, lh = w, h
				pcall(writefile, path, HttpService:JSONEncode({ w = w, h = h }))
			end
		end
	end)
	return true
end

function OrionLib:Init()
	local main = Gui:FindFirstChild("MainWindow")
	if main then main.Visible = true end
end

return OrionLib
