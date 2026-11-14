local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local RunService = game:GetService('RunService')
local HttpService = game:GetService('HttpService')
local TextService = game:GetService('TextService')

local playerGui = RunService:IsStudio() and Players.LocalPlayer.PlayerGui or game:GetService('CoreGui')

local SWIPE_ZONE = 70
local SWIPE_DIST = 90
local SMOOTH = 24

local ACCENT = Color3.fromRGB(96, 205, 255)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(32, 32, 32)
local SURFACE = Color3.fromRGB(50, 50, 50)
local INK = Color3.fromRGB(20, 20, 20)
local MUTED = Color3.fromRGB(190, 190, 190)
local PAD_COLOR = Color3.fromRGB(108, 203, 95)
local SCALE_COLOR = Color3.fromRGB(255, 185, 60)
local OPACITY_COLOR = Color3.fromRGB(180, 140, 255)
local SNAP_COLOR = Color3.fromRGB(255, 120, 200)

local HOVER = TweenInfo.new(0.12)
local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function newGui(name, order)
	local g = Instance.new('ScreenGui')
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = playerGui
	return g
end

local function addCorner(parent, radius)
	local c = Instance.new('UICorner')
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent, color, transparency, thickness)
	local s = Instance.new('UIStroke')
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local gui = newGui('UILibFrames', 10)
local editorGui = newGui('UILibEditor', 100)
gui.Enabled = false

local uiOn = false
local setUIEnabled

do
	local realPG = Players.LocalPlayer:WaitForChild('PlayerGui')
	local wasOn = {}
	local watchers = {}

	local function isOwnGui(g)
		return g == gui or g == editorGui
	end

	local function suppressGui(g)
		if watchers[g] or isOwnGui(g) or not g.Parent then
			return
		end
		if g.Enabled then
			wasOn[g] = true
		end
		watchers[g] = g:GetPropertyChangedSignal('Enabled'):Connect(function()
			if uiOn and g.Enabled then
				wasOn[g] = true
				g.Enabled = false
			end
		end)
		g.Enabled = false
	end

	local function releaseGui(g)
		local c = watchers[g]
		if c then
			c:Disconnect()
			watchers[g] = nil
		end
		if wasOn[g] then
			wasOn[g] = nil
			if g.Parent then
				g.Enabled = true
			end
		end
	end

	function setUIEnabled(v)
		uiOn = v
		gui.Enabled = v
		if v then
			for _, g in ipairs(realPG:GetChildren()) do
				if g:IsA('ScreenGui') then
					suppressGui(g)
				end
			end
		else
			for g in pairs(watchers) do
				releaseGui(g)
			end
		end
	end

	realPG.ChildAdded:Connect(function(c)
		if uiOn and c:IsA('ScreenGui') then
			task.defer(suppressGui, c)
		end
	end)
end

local root = Instance.new('Frame')
root.Name = 'Root'
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Parent = gui

local entries = {}
local layouts = {}
local animating = {}
local editing = false
local panelOpen = false
local selected
local drag
local hold
local swipe

local FOLDER = 'CapCut SaiLub'
local FILE = FOLDER .. '/Capcut_' .. game.PlaceId .. '.json'
local canFile = type(writefile) == 'function' and type(readfile) == 'function' and type(isfile) == 'function' and type(makefolder) == 'function'

if canFile then
	pcall(function()
		if not isfolder(FOLDER) then
			makefolder(FOLDER)
		end
	end)
end

local function persist()
	if canFile then
		pcall(function()
			writefile(FILE, HttpService:JSONEncode(layouts))
		end)
	end
end

if canFile then
	local ok, data = pcall(function()
		if isfile(FILE) then
			return HttpService:JSONDecode(readfile(FILE))
		end
	end)
	if ok and type(data) == 'table' then
		layouts = data
	end
end

local applyImage

do
	local getAsset = (type(getcustomasset) == 'function' and getcustomasset) or (type(getsynasset) == 'function' and getsynasset) or nil
	local imageCache = {}

	local function hashStr(s)
		local h = 5381
		for i = 1, #s do
			h = (h * 33 + s:byte(i)) % 4294967296
		end
		return string.format('%08x', h)
	end

	local function fetchBody(url)
		local req = (type(request) == 'function' and request) or (type(http_request) == 'function' and http_request) or (syn and type(syn.request) == 'function' and syn.request) or nil
		if req then
			local ok, res = pcall(req, { Url = url, Method = 'GET' })
			if ok and type(res) == 'table' and res.Body and (res.StatusCode == nil or res.StatusCode == 200) then
				return res.Body
			end
		end
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == 'string' then
			return body
		end
		return nil
	end

	local function loadUrlImage(url)
		if imageCache[url] then
			return imageCache[url]
		end
		if not (getAsset and canFile) then
			return nil
		end
		local path = FOLDER .. '/img_' .. hashStr(url) .. '.png'
		local ok = pcall(function()
			if not isfile(path) then
				local body = fetchBody(url)
				if not body then
					error('download failed')
				end
				writefile(path, body)
			end
		end)
		if not ok then
			return nil
		end
		local okA, asset = pcall(getAsset, path)
		if okA and asset then
			imageCache[url] = asset
			return asset
		end
		return nil
	end

	local function directAsset(src)
		local s = tostring(src):gsub('%s+', '')
		if s:match('^%d+$') then
			return 'rbxassetid://' .. s
		end
		if s:match('^rbxassetid://') or s:match('^rbxasset://') or s:match('^rbxthumb://') or s:match('^https?://www%.roblox%.com/asset') then
			return s
		end
		return nil
	end

	function applyImage(e, src)
		src = tostring(src or '')
		e.imageSrc = src
		local token = {}
		e.imgToken = token
		if src == '' then
			e.frame.Image = ''
			return
		end
		local direct = directAsset(src)
		if direct then
			e.frame.Image = direct
			return
		end
		if src:match('^https?://') then
			task.spawn(function()
				local asset = loadUrlImage(src)
				if asset and e.imgToken == token and e.frame.Parent then
					e.frame.Image = asset
				end
			end)
		end
	end
end

local smartOn = true
local smartSnap = true
if layouts.__smart ~= nil then
	smartOn = layouts.__smart == true
end

local function screenSize()
	local sz = root.AbsoluteSize
	if sz.X > 0 and sz.Y > 0 then
		return sz.X, sz.Y
	end
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 then
		return cam.ViewportSize.X, cam.ViewportSize.Y
	end
	return 1280, 720
end

local overlay = Instance.new('Frame')
overlay.Name = 'EditOverlay'
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 0
overlay.Visible = false
overlay.Parent = root

local PANEL_H = 56
local PAGE_X = 149
local IDLE_W = PAGE_X + 322 + 11
local EDIT_W = PAGE_X + 328 + 11
local FAST = TweenInfo.new(0.12)

local panel = Instance.new('Frame')
panel.Name = 'EditPanel'
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, -140)
panel.Size = UDim2.fromOffset(IDLE_W, PANEL_H)
panel.BackgroundColor3 = WHITE
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = editorGui
addCorner(panel, 12)

do
	local TITLE_X = 34
	local DIVIDER_X = 140

	local panelFill = Instance.new('UIGradient')
	panelFill.Rotation = 90
	panelFill.Color = ColorSequence.new(Color3.fromRGB(48, 48, 48), Color3.fromRGB(30, 30, 30))
	panelFill.Parent = panel

	local panelStroke = addStroke(panel, WHITE, 0, 1)
	local strokeFade = Instance.new('UIGradient')
	strokeFade.Rotation = 90
	strokeFade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.94) })
	strokeFade.Parent = panelStroke

	local logo = Instance.new('Frame')
	logo.AnchorPoint = Vector2.new(0, 0.5)
	logo.Position = UDim2.new(0, 18, 0.5, 0)
	logo.Size = UDim2.fromOffset(8, 8)
	logo.BackgroundColor3 = ACCENT
	logo.BorderSizePixel = 0
	logo.ZIndex = 3
	logo.Parent = panel
	addCorner(logo, 4)

	local title = Instance.new('TextLabel')
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, TITLE_X, 0.5, 0)
	title.Size = UDim2.fromOffset(100, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 14
	title.TextColor3 = WHITE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = 'SaiLub Capcut'
	title.ZIndex = 3
	title.Parent = panel

	local divider = Instance.new('Frame')
	divider.AnchorPoint = Vector2.new(0, 0.5)
	divider.Position = UDim2.new(0, DIVIDER_X, 0.5, 0)
	divider.Size = UDim2.fromOffset(1, 22)
	divider.BackgroundColor3 = WHITE
	divider.BackgroundTransparency = 0.85
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = panel
end

local function makePage(width)
	local page = Instance.new('CanvasGroup')
	page.AnchorPoint = Vector2.new(0, 0.5)
	page.Position = UDim2.new(0, PAGE_X, 0.5, 0)
	page.Size = UDim2.fromOffset(width + 4, 44)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ZIndex = 3
	page.Parent = panel
	local list = Instance.new('UIListLayout')
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = page
	local pad = Instance.new('UIPadding')
	pad.PaddingLeft = UDim.new(0, 2)
	pad.Parent = page
	return page
end

local idlePage = makePage(322)
local editPage = makePage(328)
editPage.Visible = false
editPage.GroupTransparency = 1

local function drawBar(parent, w, h, rot, z)
	local f = Instance.new('Frame')
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.ZIndex = z or 4
	f.Parent = parent
	addCorner(f, 1)
	return f
end

local styles = {
	accent = { base = ACCENT, hover = Color3.fromRGB(128, 218, 255), press = Color3.fromRGB(78, 172, 215), text = INK, stroke = 1 },
	normal = { base = SURFACE, hover = Color3.fromRGB(66, 66, 66), press = Color3.fromRGB(42, 42, 42), text = WHITE, stroke = 0.9 },
	danger = { base = SURFACE, hover = Color3.fromRGB(72, 52, 55), press = Color3.fromRGB(52, 38, 40), text = WHITE, hoverText = Color3.fromRGB(255, 153, 164), stroke = 0.9 },
	on = { base = PAD_COLOR, hover = Color3.fromRGB(130, 220, 118), press = Color3.fromRGB(86, 170, 75), text = INK, stroke = 1 },
	subtle = { base = Color3.fromRGB(44, 44, 44), hover = Color3.fromRGB(66, 66, 66), press = Color3.fromRGB(42, 42, 42), text = MUTED, stroke = 0.92 },
}

local function makeButton(parent, text, style, order, width)
	local st = styles[style]
	local b = Instance.new('TextButton')
	b.Size = UDim2.fromOffset(width, 34)
	b.BackgroundColor3 = st.base
	b.AutoButtonColor = false
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = st.text
	b.BorderSizePixel = 0
	b.LayoutOrder = order
	b.ZIndex = 4
	b.Parent = parent
	addCorner(b, 8)
	local stroke = addStroke(b, WHITE, st.stroke, 1)
	local grad = Instance.new('UIGradient')
	grad.Rotation = 90
	grad.Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 205, 205))
	grad.Enabled = style == 'accent' or style == 'on'
	grad.Parent = b
	local sc = Instance.new('UIScale')
	sc.Parent = b
	local function tint(color, textColor, scale)
		TweenService:Create(b, HOVER, { BackgroundColor3 = color, TextColor3 = textColor }):Play()
		TweenService:Create(sc, HOVER, { Scale = scale }):Play()
	end
	b.MouseEnter:Connect(function()
		tint(st.hover, st.hoverText or st.text, 1)
	end)
	b.MouseLeave:Connect(function()
		tint(st.base, st.text, 1)
	end)
	b.MouseButton1Down:Connect(function()
		tint(st.press, st.hoverText or st.text, 0.96)
	end)
	b.MouseButton1Up:Connect(function()
		if UserInputService.MouseEnabled then
			tint(st.hover, st.hoverText or st.text, 1)
		else
			tint(st.base, st.text, 1)
		end
	end)
	local function setStyle(name)
		st = styles[name]
		grad.Enabled = name == 'accent' or name == 'on'
		stroke.Transparency = st.stroke
		tint(st.base, st.text, 1)
	end
	return b, setStyle
end

local btnEdit = makeButton(idlePage, 'Edit', 'accent', 1, 84)

local refreshCapture
local setToggleView

do
	local function makeToggleSeg(parent, order, onChange)
		local seg = Instance.new('Frame')
		seg.Size = UDim2.fromOffset(146, 34)
		seg.BackgroundColor3 = DARK
		seg.BackgroundTransparency = 0.06
		seg.BorderSizePixel = 0
		seg.LayoutOrder = order
		seg.ZIndex = 4
		seg.Parent = parent
		addCorner(seg, 8)
		addStroke(seg, WHITE, 0.88, 1)

		local thumb = Instance.new('Frame')
		thumb.Size = UDim2.fromOffset(70, 30)
		thumb.Position = UDim2.fromOffset(74, 2)
		thumb.BackgroundColor3 = ACCENT
		thumb.BorderSizePixel = 0
		thumb.ZIndex = 5
		thumb.Parent = seg
		addCorner(thumb, 6)

		local btns = {}
		for i, name in ipairs({ 'Enabled', 'Disabled' }) do
			local b = Instance.new('TextButton')
			b.Position = UDim2.fromOffset(2 + (i - 1) * 72, 2)
			b.Size = UDim2.fromOffset(70, 30)
			b.BackgroundTransparency = 1
			b.AutoButtonColor = false
			b.Font = Enum.Font.GothamMedium
			b.TextSize = 13
			b.TextColor3 = i == 2 and INK or WHITE
			b.Text = name
			b.ZIndex = 6
			b.Parent = seg
			b.MouseButton1Click:Connect(function()
				onChange(i == 1)
			end)
			btns[i] = b
		end

		return function(on)
			TweenService:Create(thumb, SLIDE, { Position = UDim2.fromOffset(on and 2 or 74, 2) }):Play()
			for i, b in ipairs(btns) do
				TweenService:Create(b, HOVER, { TextColor3 = ((i == 1) == on) and INK or WHITE }):Play()
			end
		end
	end

	local rawToggleView = makeToggleSeg(idlePage, 2, function(on)
		setUIEnabled(on)
		setToggleView(uiOn)
	end)

	function setToggleView(on)
		rawToggleView(on)
		if refreshCapture then
			refreshCapture(on)
		end
	end
end

do
	local btnCapture = makeButton(idlePage, '', 'subtle', 3, 34)
	local camParts = {}

	local function part(w, h, y, filled, round)
		local f = Instance.new('Frame')
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0.5, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = MUTED
		f.BackgroundTransparency = filled and 0 or 1
		f.BorderSizePixel = 0
		f.ZIndex = 5
		f.Parent = btnCapture
		addCorner(f, round)
		local st = not filled and addStroke(f, MUTED, 0, 1.5) or nil
		camParts[#camParts + 1] = { frame = f, stroke = st }
	end
	part(6, 3, -8, true, 1)
	part(16, 11, 1, false, 3)
	part(6, 6, 1, false, 3)

	local function paintCamera(color, alpha)
		for _, c in ipairs(camParts) do
			if c.stroke then
				TweenService:Create(c.stroke, HOVER, { Color = color, Transparency = alpha }):Play()
			else
				TweenService:Create(c.frame, HOVER, { BackgroundColor3 = color, BackgroundTransparency = alpha }):Play()
			end
		end
	end

	refreshCapture = function(on)
		paintCamera(MUTED, on and 0 or 0.65)
	end
	refreshCapture(false)

	btnCapture.MouseEnter:Connect(function()
		if uiOn then
			paintCamera(WHITE, 0)
		end
	end)
	btnCapture.MouseLeave:Connect(function()
		refreshCapture(uiOn)
	end)

	local capturing = false
	btnCapture.MouseButton1Click:Connect(function()
		if not uiOn or capturing or editing then
			return
		end
		local okSvc, CaptureService = pcall(function()
			return game:GetService('CaptureService')
		end)
		if not okSvc or not CaptureService then
			return
		end
		capturing = true
		local restored = false
		local function restore()
			if restored then
				return
			end
			restored = true
			editorGui.Enabled = true
			capturing = false
		end
		editorGui.Enabled = false
		task.delay(4, restore)
		task.spawn(function()
			for _ = 1, 3 do
				RunService.RenderStepped:Wait()
			end
			local ok = pcall(function()
				CaptureService:CaptureScreenshot(function(contentId)
					restore()
					pcall(function()
						CaptureService:PromptSaveCapturesToGallery({ contentId }, function() end)
					end)
				end)
			end)
			if not ok then
				restore()
			end
		end)
	end)
end

local btnClose = makeButton(idlePage, '', 'subtle', 4, 34)

do
	local closeBars = { drawBar(btnClose, 12, 2, 45), drawBar(btnClose, 12, 2, -45) }
	for _, bar in ipairs(closeBars) do
		bar.BackgroundColor3 = MUTED
	end
	btnClose.MouseEnter:Connect(function()
		for _, bar in ipairs(closeBars) do
			TweenService:Create(bar, HOVER, { BackgroundColor3 = WHITE }):Play()
		end
	end)
	btnClose.MouseLeave:Connect(function()
		for _, bar in ipairs(closeBars) do
			TweenService:Create(bar, HOVER, { BackgroundColor3 = MUTED }):Play()
		end
	end)
end

local btnSave = makeButton(editPage, 'Save', 'accent', 1, 76)
local btnReset = makeButton(editPage, 'Reset', 'normal', 2, 76)
local btnCancel = makeButton(editPage, 'Cancel', 'danger', 3, 76)

local setSmartView

do
	local btnSmart, setSmartStyle = makeButton(editPage, 'Smart', smartOn and 'on' or 'normal', 4, 76)

	function setSmartView()
		setSmartStyle(smartOn and 'on' or 'normal')
	end

	btnSmart.MouseButton1Click:Connect(function()
		smartOn = not smartOn
		setSmartView()
	end)
end

local activePage = idlePage

local function showPage(page, width)
	if activePage == page then
		return
	end
	local old = activePage
	activePage = page
	TweenService:Create(old, FAST, { GroupTransparency = 1 }):Play()
	task.delay(0.14, function()
		if activePage ~= old then
			old.Visible = false
		end
	end)
	page.Visible = true
	page.GroupTransparency = 1
	page.Position = UDim2.new(0, PAGE_X + 14, 0.5, 0)
	TweenService:Create(page, SLIDE, { GroupTransparency = 0, Position = UDim2.new(0, PAGE_X, 0.5, 0) }):Play()
	TweenService:Create(panel, SLIDE, { Size = UDim2.fromOffset(width, PANEL_H) }):Play()
end

local function refreshButtons()
	if editing then
		showPage(editPage, EDIT_W)
	else
		showPage(idlePage, IDLE_W)
	end
end

local hint, hintHidden, setHintHidden, setHint

do
	hint = Instance.new('TextLabel')
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -16)
	hint.Size = UDim2.new(0, -32, 0, 0)
	hint.AutomaticSize = Enum.AutomaticSize.XY
	hint.TextWrapped = true
	hint.BackgroundColor3 = DARK
	hint.BackgroundTransparency = 1
	hint.TextTransparency = 1
	hint.TextColor3 = MUTED
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.Text = 'Tap a frame to select  |  drag to move  |  corners to resize  |  double-tap a value to reset  |  tap empty space to deselect'
	hint.Visible = false
	hint.Parent = editorGui
	addCorner(hint, 10)
	local hintStroke = addStroke(hint, WHITE, 1, 1)
	local hintPad = Instance.new('UIPadding')
	hintPad.PaddingLeft = UDim.new(0, 16)
	hintPad.PaddingRight = UDim.new(0, 16)
	hintPad.PaddingTop = UDim.new(0, 9)
	hintPad.PaddingBottom = UDim.new(0, 9)
	hintPad.Parent = hint

	hintHidden = false

	function setHintHidden(h)
		if hintHidden == h then
			return
		end
		hintHidden = h
		if not hint.Visible then
			return
		end
		TweenService:Create(hint, FADE, { BackgroundTransparency = h and 1 or 0.06, TextTransparency = h and 1 or 0 }):Play()
		TweenService:Create(hintStroke, FADE, { Transparency = h and 1 or 0.88 }):Play()
	end

	function setHint(show)
		if show then
			hintHidden = false
			hint.Visible = true
			TweenService:Create(hint, FADE, { BackgroundTransparency = 0.06, TextTransparency = 0 }):Play()
			TweenService:Create(hintStroke, FADE, { Transparency = 0.88 }):Play()
		else
			hintHidden = false
			TweenService:Create(hint, FADE, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(hintStroke, FADE, { Transparency = 1 }):Play()
			task.delay(0.2, function()
				if not editing then
					hint.Visible = false
				end
			end)
		end
	end
end

local panelHidden = false
local setPanelHidden, setPanel

do
	local tab = Instance.new('TextButton')
	tab.Name = 'PullTab'
	tab.AnchorPoint = Vector2.new(0.5, 0)
	tab.Position = UDim2.new(0.5, 0, 0, 0)
	tab.Size = UDim2.fromOffset(160, 40)
	tab.BackgroundTransparency = 1
	tab.AutoButtonColor = false
	tab.Text = ''
	tab.ZIndex = 5
	tab.Parent = editorGui

	local tabGroup = Instance.new('CanvasGroup')
	tabGroup.Size = UDim2.new(1, 0, 0, 80)
	tabGroup.BackgroundTransparency = 1
	tabGroup.GroupTransparency = 1
	tabGroup.ZIndex = 5
	tabGroup.Parent = tab

	local tabBar = Instance.new('Frame')
	tabBar.AnchorPoint = Vector2.new(0.5, 0)
	tabBar.Position = UDim2.new(0.5, 0, 0, 8)
	tabBar.Size = UDim2.fromOffset(40, 4)
	tabBar.BackgroundColor3 = WHITE
	tabBar.BackgroundTransparency = 0.45
	tabBar.BorderSizePixel = 0
	tabBar.ZIndex = 6
	tabBar.Parent = tabGroup
	addCorner(tabBar, 2)

	local chev = Instance.new('Frame')
	chev.AnchorPoint = Vector2.new(0.5, 0)
	chev.Position = UDim2.new(0.5, 0, 0, 18)
	chev.Size = UDim2.fromOffset(14, 8)
	chev.BackgroundTransparency = 1
	chev.ZIndex = 6
	chev.Parent = tabGroup

	for _, spec in ipairs({ { 3.5, 38 }, { 10.5, -38 } }) do
		local f = Instance.new('Frame')
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0, spec[1], 0.5, 0)
		f.Size = UDim2.fromOffset(9, 2)
		f.Rotation = spec[2]
		f.BackgroundColor3 = WHITE
		f.BackgroundTransparency = 0.3
		f.BorderSizePixel = 0
		f.ZIndex = 6
		f.Parent = chev
		addCorner(f, 1)
	end

	local tabLabel = Instance.new('TextLabel')
	tabLabel.AnchorPoint = Vector2.new(0.5, 0)
	tabLabel.Position = UDim2.new(0.5, 0, 0, 36)
	tabLabel.Size = UDim2.fromOffset(160, 16)
	tabLabel.BackgroundTransparency = 1
	tabLabel.Font = Enum.Font.Gotham
	tabLabel.TextSize = 11
	tabLabel.TextColor3 = WHITE
	tabLabel.TextTransparency = 0.25
	tabLabel.Text = 'Swipe down to edit layout'
	tabLabel.ZIndex = 6
	tabLabel.Parent = tabGroup

	TweenService:Create(chev, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()

	task.delay(0.6, function()
		if not panelOpen then
			TweenService:Create(tabGroup, FADE, { GroupTransparency = 0.15 }):Play()
		end
	end)

	task.delay(7, function()
		TweenService:Create(tabLabel, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	end)

	function setPanelHidden(h)
		if panelHidden == h then
			return
		end
		panelHidden = h
		if panelOpen then
			local target = h and UDim2.new(0.5, 0, 0, -140) or UDim2.new(0.5, 0, 0, 16)
			TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target }):Play()
		end
	end

	function setPanel(open)
		panelOpen = open
		panelHidden = false
		local target = open and UDim2.new(0.5, 0, 0, 16) or UDim2.new(0.5, 0, 0, -140)
		local info = open and TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out) or TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		TweenService:Create(panel, info, { Position = target }):Play()
		TweenService:Create(tabGroup, FADE, { GroupTransparency = open and 1 or 0.15 }):Play()
		tab.Interactable = not open
	end

	tab.MouseButton1Click:Connect(function()
		setPanel(true)
	end)
end

local function getPad(e)
	local l = e.layout
	if l:IsA('UIGridLayout') then
		return l.CellPadding.X.Offset, l.CellPadding.Y.Offset
	end
	return l.Padding.Offset, l.Padding.Offset
end

local function setPad(e, px, py)
	local l = e.layout
	if l:IsA('UIGridLayout') then
		l.CellPadding = UDim2.new(l.CellPadding.X.Scale, px, l.CellPadding.Y.Scale, py)
	else
		l.Padding = UDim.new(l.Padding.Scale, l.FillDirection == Enum.FillDirection.Vertical and py or px)
	end
end

local function getRect(e)
	local s = root.AbsoluteSize
	local p = e.frame.AbsolutePosition - root.AbsolutePosition
	local z = e.frame.AbsoluteSize
	return p.X / s.X, p.Y / s.Y, (p.X + z.X) / s.X, (p.Y + z.Y) / s.Y
end

local function applyRect(e, l, t, r, b)
	local k = e.uiscale.Scale
	local w, h = r - l, b - t
	local a = e.frame.AnchorPoint
	e.frame.Size = UDim2.fromScale(w / k, h / k)
	e.frame.Position = UDim2.fromScale(l + w * a.X, t + h * a.Y)
end

local function targetRect(e)
	local g = e.tgt
	if g then
		return g.l, g.t, g.r, g.b
	end
	return getRect(e)
end

local function targetK(e)
	return e.tgt and e.tgt.k or e.uiscale.Scale
end

local function targetPad(e)
	local g = e.tgt
	if g then
		return g.px, g.py
	end
	return getPad(e)
end

local function stopAnim(e)
	animating[e] = nil
	e.cur = nil
	e.tgt = nil
end

local function moveTo(e, l, t, r, b, k, px, py)
	if not e.cur then
		local cl, ct, cr, cb = getRect(e)
		local cpx, cpy = getPad(e)
		e.cur = { l = cl, t = ct, r = cr, b = cb, k = e.uiscale.Scale, px = cpx, py = cpy }
	end
	local tk = targetK(e)
	local tpx, tpy = targetPad(e)
	e.tgt = { l = l, t = t, r = r, b = b, k = k or tk, px = px or tpx, py = py or tpy }
	animating[e] = true
end

local function settle()
	for e in pairs(animating) do
		local g = e.tgt
		if g then
			e.uiscale.Scale = g.k
			setPad(e, g.px, g.py)
			applyRect(e, g.l, g.t, g.r, g.b)
		end
		stopAnim(e)
	end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function tracks(ref, input)
	if input == ref then
		return true
	end
	return ref.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
end

local function sameRelease(ref, input)
	if input == ref then
		return true
	end
	return ref.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1
end

-- forward declarations (assigned inside do-blocks below)
local positionToolbar, boxStyle
local refreshReadout, endDrag, beginDrag, updateDrag
local selectEntry, makeBox, removeBox
local rebuildList, showList
local snapshot, startEdit, stopEdit, resetAll
local makeBase, smartApply, reflowAll
local New
local ops = {}
local sty = {}

-- heartbeat + overlap handling
do
	local KEYS = { 'l', 't', 'r', 'b', 'k', 'px', 'py' }

	local function nearRect(e, rx, ry, rw, rh, margin)
		local s = root.AbsoluteSize
		local l, t, r, b = targetRect(e)
		return l * s.X < rx + rw + margin and r * s.X > rx - margin and t * s.Y < ry + rh + margin and b * s.Y > ry - margin
	end

	local function updateOverlap()
		local e = selected
		local s = root.AbsoluteSize
		local nearHint, nearPanel = false, false
		if editing and e and e.kind ~= 'credit' and e.frame.Visible then
			local hw, hh = hint.AbsoluteSize.X, hint.AbsoluteSize.Y
			nearHint = nearRect(e, (s.X - hw) / 2, s.Y - 16 - hh, hw, hh, hintHidden and 40 or 24)
			if panelOpen then
				nearPanel = nearRect(e, (s.X - EDIT_W) / 2, 16, EDIT_W, PANEL_H, panelHidden and 40 or 24)
			end
		end
		setHintHidden(nearHint)
		setPanelHidden(nearPanel)
	end

	RunService.Heartbeat:Connect(function(dt)
		if editing then
			updateOverlap()
		end
		local a = 1 - math.exp(-dt * SMOOTH)
		for _, e in pairs(entries) do
			if e.box and e.tb and e.tbCur and (e.tbCur - e.tb).Magnitude > 0.3 then
				e.tbCur = e.tbCur:Lerp(e.tb, 1 - math.exp(-dt * 12))
				positionToolbar(e)
			end
		end
		for e in pairs(animating) do
			local c, g = e.cur, e.tgt
			if not (c and g) or not e.frame.Parent then
				stopAnim(e)
				continue
			end
			local done = true
			for _, key in ipairs(KEYS) do
				local diff = g[key] - c[key]
				local limit = (key == 'px' or key == 'py') and 0.05 or 0.0004
				if math.abs(diff) > limit then
					c[key] += diff * a
					done = false
				else
					c[key] = g[key]
				end
			end
			e.uiscale.Scale = c.k
			setPad(e, math.floor(c.px + 0.5), math.floor(c.py + 0.5))
			applyRect(e, c.l, c.t, c.r, c.b)
			if done then
				stopAnim(e)
			end
		end
	end)
end

-- smart (responsive) layout
do
	local function propsRect(e)
		local W, H = screenSize()
		local pos, size, a, k = e.frame.Position, e.frame.Size, e.frame.AnchorPoint, e.uiscale.Scale
		local w = (size.X.Scale + size.X.Offset / W) * k
		local h = (size.Y.Scale + size.Y.Offset / H) * k
		local l = pos.X.Scale + pos.X.Offset / W - w * a.X
		local t = pos.Y.Scale + pos.Y.Offset / H - h * a.Y
		return l, t, l + w, t + h
	end

	function makeBase(e, rw, rh)
		local l, t, r, b = propsRect(e)
		return { l = l, t = t, r = r, b = b, k = e.uiscale.Scale, rw = rw, rh = rh }
	end

	local function anchorOf(c)
		if c < 1 / 3 then
			return 0
		elseif c > 2 / 3 then
			return 1
		end
		return 0.5
	end

	local function smartRect(base, W, H)
		local f = math.min(W / base.rw, H / base.rh)
		local wpx = (base.r - base.l) * base.rw * f
		local hpx = (base.b - base.t) * base.rh * f
		local cx, cy = (base.l + base.r) / 2, (base.t + base.b) / 2
		local ax, ay = anchorOf(cx), anchorOf(cy)
		local ccx = ax * W + (cx - ax) * base.rw * f
		local ccy = ay * H + (cy - ay) * base.rh * f
		local l, t = (ccx - wpx / 2) / W, (ccy - hpx / 2) / H
		local r, b = l + wpx / W, t + hpx / H
		if l < 0 then
			r, l = r - l, 0
		end
		if r > 1 and r - l <= 1 then
			l, r = l - (r - 1), 1
		end
		if t < 0 then
			b, t = b - t, 0
		end
		if b > 1 and b - t <= 1 then
			t, b = t - (b - 1), 1
		end
		return l, t, r, b, base.k * f
	end

	function smartApply(e)
		local base = e.base
		if not base or editing or e.kind == 'credit' or not e.frame.Parent then
			return
		end
		local W, H = screenSize()
		if W <= 0 or H <= 0 then
			return
		end
		stopAnim(e)
		local l, t, r, b, k = smartRect(base, W, H)
		e.uiscale.Scale = k
		applyRect(e, l, t, r, b)
	end

	function reflowAll()
		for _, e in pairs(entries) do
			smartApply(e)
		end
	end

	root:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
		if smartOn and not editing then
			reflowAll()
		end
	end)
end


-- text / credit styling (color, font, stroke, tiled credit watermark)
do
	local FONT_NAMES = {
		'GothamMedium', 'GothamBold', 'GothamBlack', 'Gotham', 'SourceSansBold', 'SourceSans', 'Arial', 'ArialBold',
		'Bangers', 'Creepster', 'FredokaOne', 'LuckiestGuy', 'Kalam', 'PatrickHand', 'PermanentMarker', 'SpecialElite',
		'Oswald', 'Michroma', 'Fondamento', 'Arcade', 'Antique', 'Cartoon', 'Code', 'Highway', 'SciFi', 'Sarpanch',
		'Ubuntu', 'Nunito', 'Merriweather', 'Montserrat', 'Roboto', 'RobotoMono', 'JosefinSans', 'Jura', 'Garamond', 'Fantasy',
	}
	local FONTS = {}
	for _, n in ipairs(FONT_NAMES) do
		local ok, f = pcall(function()
			return Enum.Font[n]
		end)
		if ok and f then
			table.insert(FONTS, f)
		end
	end
	if #FONTS == 0 then
		FONTS[1] = Enum.Font.GothamMedium
	end
	sty.FONTS = FONTS

	sty.SWATCHES = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(255, 185, 60),
		Color3.fromRGB(255, 235, 90),
		Color3.fromRGB(108, 203, 95),
		Color3.fromRGB(96, 205, 255),
		Color3.fromRGB(180, 140, 255),
	}

	local function pct(v)
		return string.format('%d%%', math.floor(v * 100 + 0.5))
	end
	local function px(v)
		return string.format('%dpx', math.floor(v + 0.5))
	end

	local STEPS = {
		topacity = { title = 'Opacity', color = OPACITY_COLOR, field = 'tr', inv = true, min = 0, max = 1, step = 0.05, def = 0, fmt = pct },
		stroke = { title = 'Stroke', color = SNAP_COLOR, field = 'strokeT', min = 0, max = 8, step = 0.5, def = 0, fmt = function(v)
			return string.format('%.1f', v)
		end },
		cstroke = { title = 'Outline', color = SNAP_COLOR, field = 'cs', min = 0, max = 1, step = 0.1, def = 0, fmt = pct },
		tsize = { title = 'Size', color = SCALE_COLOR, field = 'size', min = 8, max = 150, step = 2, def = 22, fmt = px },
		angle = { title = 'Angle', color = PAD_COLOR, field = 'angle', min = -90, max = 90, step = 1, def = 30, fmt = function(v)
			return string.format('%d°', math.floor(v + 0.5))
		end },
		gapx = { title = 'Space X', color = PAD_COLOR, field = 'gx', min = 40, max = 800, step = 10, def = 240, fmt = px },
		gapy = { title = 'Space Y', color = ACCENT, field = 'gy', min = 30, max = 500, step = 10, def = 110, fmt = px },
	}
	for _, d in pairs(STEPS) do
		d.drag = (d.max - d.min) / 200
	end
	sty.STEPS = STEPS

	local function enumItem(enum, name)
		local ok, v = pcall(function()
			return enum[name]
		end)
		return ok and v or nil
	end

	local function tileStyle(e, lab)
		local st = e.style
		lab.Text = st.text
		lab.TextColor3 = st.color
		lab.Font = st.font
		lab.TextSize = st.size
		lab.TextTransparency = st.tr
		lab.TextStrokeTransparency = 1 - st.cs
		lab.TextStrokeColor3 = Color3.new(0, 0, 0)
	end

	function sty.apply(e)
		local st = e.style
		if not st then
			return
		end
		if e.kind == 'text' then
			local f = e.frame
			f.TextColor3 = st.color
			f.Font = st.font
			f.TextTransparency = st.tr
			if e.strokeObj then
				e.strokeObj.Thickness = st.strokeT
				e.strokeObj.Enabled = st.strokeT > 0
			end
		elseif e.kind == 'credit' then
			if e.holder then
				e.holder.Rotation = st.angle
			end
			if e.tiles then
				for _, lab in ipairs(e.tiles) do
					tileStyle(e, lab)
				end
			end
		end
	end

	function sty.rebuild(e)
		local holder = e.holder
		if not holder or not holder.Parent then
			return
		end
		holder:ClearAllChildren()
		local tiles = {}
		e.tiles = tiles
		local st = e.style
		local W, H = screenSize()
		local diag = math.ceil(math.sqrt(W * W + H * H)) + 8
		holder.Size = UDim2.fromOffset(diag, diag)
		holder.Rotation = st.angle
		local sx, sy = math.max(st.gx, 20), math.max(st.gy, 16)
		local cols, rows = math.ceil(diag / sx) + 2, math.ceil(diag / sy) + 1
		while cols * rows > 900 do
			sx, sy = sx * 1.25, sy * 1.25
			cols, rows = math.ceil(diag / sx) + 2, math.ceil(diag / sy) + 1
		end
		for r = 0, rows - 1 do
			local off = (r % 2) * sx / 2
			for c = -1, cols - 2 do
				local lab = Instance.new('TextLabel')
				lab.AnchorPoint = Vector2.new(0.5, 0.5)
				lab.AutomaticSize = Enum.AutomaticSize.XY
				lab.Size = UDim2.fromOffset(0, 0)
				lab.BackgroundTransparency = 1
				lab.BorderSizePixel = 0
				lab.TextWrapped = false
				lab.Position = UDim2.fromOffset(off + c * sx, r * sy)
				tileStyle(e, lab)
				lab.Parent = holder
				tiles[#tiles + 1] = lab
			end
		end
	end

	function sty.schedule(e)
		local token = {}
		e.rbToken = token
		task.delay(0.06, function()
			if e.rbToken == token then
				sty.rebuild(e)
			end
		end)
	end

	function sty.init(e, config)
		if e.kind == 'text' then
			local f = e.frame
			e.style = { color = f.TextColor3, font = f.Font, tr = f.TextTransparency, strokeT = 0 }
			local stroke = Instance.new('UIStroke')
			stroke.Thickness = 0
			stroke.Enabled = false
			stroke.Color = Color3.new(0, 0, 0)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			stroke.Parent = f
			e.strokeObj = stroke
		elseif e.kind == 'credit' then
			local c = config or {}
			e.style = {
				color = typeof(c.TextColor3) == 'Color3' and c.TextColor3 or Color3.new(1, 1, 1),
				font = typeof(c.Font) == 'EnumItem' and c.Font or Enum.Font.GothamBold,
				tr = type(c.TextTransparency) == 'number' and c.TextTransparency or 0.6,
				cs = 0,
				text = tostring(c.Text or 'Credit'),
				size = type(c.TextSize) == 'number' and c.TextSize or 22,
				angle = type(c.Angle) == 'number' and c.Angle or 30,
				gx = type(c.SpaceX) == 'number' and c.SpaceX or 240,
				gy = type(c.SpaceY) == 'number' and c.SpaceY or 110,
			}
			local holder = Instance.new('Frame')
			holder.Name = 'Tiles'
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromScale(0.5, 0.5)
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.Parent = e.frame
			e.holder = holder
			sty.rebuild(e)
		end
	end

	function sty.copy(e)
		local c = {}
		for k, v in pairs(e.style) do
			c[k] = v
		end
		return c
	end

	function sty.restore(e, st)
		local c = {}
		for k, v in pairs(st) do
			c[k] = v
		end
		e.style = c
		sty.apply(e)
		if e.kind == 'credit' then
			sty.rebuild(e)
		end
	end

	function sty.setField(e, field, v)
		if not e.style then
			return
		end
		e.style[field] = v
		e.touched = true
		e.reset = false
		e.styleEdited = true
		sty.apply(e)
		if e.kind == 'credit' and (field == 'gx' or field == 'gy') then
			sty.schedule(e)
		end
		refreshReadout(e)
	end

	function sty.getVal(e, kind)
		local d = STEPS[kind]
		local v = e.style[d.field]
		if d.inv then
			v = 1 - v
		end
		return v
	end

	function sty.setVal(e, kind, v)
		local d = STEPS[kind]
		v = math.clamp(math.floor(v / d.step + 0.5) * d.step, d.min, d.max)
		if d.inv then
			v = 1 - v
		end
		sty.setField(e, d.field, math.floor(v * 1000 + 0.5) / 1000)
	end

	function sty.fmt(e, kind)
		return STEPS[kind].fmt(sty.getVal(e, kind))
	end

	function sty.resetVal(e, kind)
		local d = STEPS[kind]
		local dv = e.def and e.def.style and e.def.style[d.field]
		if dv == nil then
			dv = d.def
		end
		sty.setField(e, d.field, dv)
	end

	function sty.serialize(e)
		local st = e.style
		return {
			c = st.color:ToHex(),
			f = st.font.Name,
			tr = st.tr,
			st = st.strokeT,
			cs = st.cs,
			tx = st.text,
			sz = st.size,
			an = st.angle,
			gx = st.gx,
			gy = st.gy,
		}
	end

	function sty.load(e, d)
		local st = e.style
		if not st or type(d) ~= 'table' then
			return
		end
		if type(d.c) == 'string' then
			local ok, col = pcall(Color3.fromHex, d.c)
			if ok and col then
				st.color = col
			end
		end
		local fnt = type(d.f) == 'string' and enumItem(Enum.Font, d.f)
		if fnt then
			st.font = fnt
		end
		local function num(key, field)
			if type(d[key]) == 'number' then
				st[field] = d[key]
			end
		end
		num('tr', 'tr')
		if e.kind == 'text' then
			num('st', 'strokeT')
		else
			num('cs', 'cs')
			num('sz', 'size')
			num('an', 'angle')
			num('gx', 'gx')
			num('gy', 'gy')
			if type(d.tx) == 'string' then
				st.text = d.tx
			end
		end
		e.styleEdited = true
		sty.apply(e)
		if e.kind == 'credit' then
			sty.rebuild(e)
		end
	end

	root:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
		for _, e in pairs(entries) do
			if e.kind == 'credit' then
				sty.schedule(e)
			end
		end
	end)
end

-- drag / snapping / value operations
do
	local SNAP = 10
	local MIN_SIZE = 0.03
	local MIN_PX = 20
	local MIN_SCALE = 0.4
	local MAX_SCALE = 3
	local MAX_PAD = 80
	local STEPS = sty.STEPS

	local function snapStep(n, size)
		return math.floor(n * size + 0.5) / size
	end

	local function isText(c)
		return c:IsA('TextLabel') or c:IsA('TextButton') or c:IsA('TextBox')
	end

	local function minSize(e, wPx, hPx, opx, opy)
		local k = targetK(e)
		local layout = e.layout
		local n, sw, sh, mw, mh = 0, 0, 0, 0, 0
		local pl, pr, pt, pb = 0, 0, 0, 0
		for _, c in ipairs(e.frame:GetChildren()) do
			if c:IsA('GuiObject') and c.Visible then
				n += 1
				local w, h = c.Size.X.Offset, c.Size.Y.Offset
				if isText(c) then
					local ok, ts = pcall(function()
						return TextService:GetTextSize(c.Text, c.TextSize, c.Font, Vector2.new(100000, 100000))
					end)
					if ok then
						w = math.max(w, ts.X + 12)
						h = math.max(h, ts.Y + 4)
					end
				end
				sw += w
				sh += h
				mw = math.max(mw, w)
				mh = math.max(mh, h)
			elseif c:IsA('UIPadding') then
				pl, pr, pt, pb = c.PaddingLeft.Offset, c.PaddingRight.Offset, c.PaddingTop.Offset, c.PaddingBottom.Offset
			end
		end
		local wu, hu = wPx / k, hPx / k
		local gx, gy = targetPad(e)
		if opx then
			gx, gy = opx, opy
		end
		local minW, minH
		if layout:IsA('UIGridLayout') then
			local cw, ch = layout.CellSize.X.Offset, layout.CellSize.Y.Offset
			if layout.FillDirection == Enum.FillDirection.Horizontal then
				local cols = math.max(1, math.floor((wu - pl - pr + gx) / math.max(cw + gx, 1)))
				local rows = math.ceil(math.max(n, 1) / cols)
				minW = cw + pl + pr
				minH = rows * ch + (rows - 1) * gy + pt + pb
			else
				local rows = math.max(1, math.floor((hu - pt - pb + gy) / math.max(ch + gy, 1)))
				local cols = math.ceil(math.max(n, 1) / rows)
				minH = ch + pt + pb
				minW = cols * cw + (cols - 1) * gx + pl + pr
			end
		else
			local gaps = math.max(n - 1, 0) * gx
			if layout.FillDirection == Enum.FillDirection.Vertical then
				minH = sh + gaps + pt + pb
				minW = mw + pl + pr
			else
				minW = sw + gaps + pl + pr
				minH = mh + pt + pb
			end
		end
		return math.max(minW * k, MIN_PX), math.max(minH * k, MIN_PX)
	end

	local function bestSnap(self, axis, edges)
		local best, bestCoord, bestOther
		local s = root.AbsoluteSize
		local limit = SNAP / (axis == 'x' and s.X or s.Y)
		local function consider(target, other)
			for _, m in ipairs(edges) do
				local d = target - m
				if math.abs(d) <= limit and (best == nil or math.abs(d) < math.abs(best)) then
					best, bestCoord, bestOther = d, target, other
				end
			end
		end
		consider(0, nil)
		consider(1, nil)
		for _, o in pairs(entries) do
			if o ~= self and o.kind ~= 'credit' and o.frame.Visible then
				local l, t, r, b = getRect(o)
				if axis == 'x' then
					consider(l, o)
					consider(r, o)
				else
					consider(t, o)
					consider(b, o)
				end
			end
		end
		return best, bestCoord, bestOther
	end

	local guideObjs = {}
	local linked = {}

	local function getGuide(axis)
		local g = guideObjs[axis]
		if g then
			return g
		end
		local line = Instance.new('Frame')
		line.BackgroundColor3 = SNAP_COLOR
		line.BorderSizePixel = 0
		line.ZIndex = 104
		line.Visible = false
		line.Parent = root
		local label = Instance.new('TextLabel')
		label.Size = UDim2.fromOffset(0, 0)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.BackgroundColor3 = SNAP_COLOR
		label.TextColor3 = INK
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 11
		label.ZIndex = 105
		if axis == 'x' then
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.new(1, 6, 0.5, 0)
		else
			label.AnchorPoint = Vector2.new(0.5, 1)
			label.Position = UDim2.new(0.5, 0, 0, -6)
		end
		label.Parent = line
		addCorner(label, 5)
		local lp = Instance.new('UIPadding')
		lp.PaddingLeft = UDim.new(0, 6)
		lp.PaddingRight = UDim.new(0, 6)
		lp.PaddingTop = UDim.new(0, 3)
		lp.PaddingBottom = UDim.new(0, 3)
		lp.Parent = label
		g = { line = line, label = label }
		guideObjs[axis] = g
		return g
	end

	local function setLinked(set)
		for o in pairs(linked) do
			if not set[o] then
				linked[o] = nil
				if o.box then
					boxStyle(o)
				end
			end
		end
		for o in pairs(set) do
			if not linked[o] and o.box then
				linked[o] = true
				TweenService:Create(o.boxStroke, HOVER, { Color = SNAP_COLOR, Transparency = 0, Thickness = 2 }):Play()
				TweenService:Create(o.tag, HOVER, { BackgroundColor3 = SNAP_COLOR, BackgroundTransparency = 0 }):Play()
			end
		end
	end

	local function showSnap(gx, gy, l, t, r, b)
		local s = root.AbsoluteSize
		local set = {}
		local function place(axis, info, lo, hi, a0, a1)
			local g = getGuide(axis)
			if not info or not (math.abs(lo - info.coord) < 0.003 or math.abs(hi - info.coord) < 0.003) then
				g.line.Visible = false
				return
			end
			local from, to = a0, a1
			if info.other then
				local ol, ot, orr, ob = getRect(info.other)
				if axis == 'x' then
					from, to = math.min(from, ot), math.max(to, ob)
				else
					from, to = math.min(from, ol), math.max(to, orr)
				end
				set[info.other] = true
				g.label.Text = 'Snap: ' .. info.other.key
			else
				from, to = math.max(0, from - 0.04), math.min(1, to + 0.04)
				g.label.Text = 'Snap: screen edge'
			end
			if axis == 'x' then
				g.line.Position = UDim2.fromOffset(info.coord * s.X - 1, from * s.Y)
				g.line.Size = UDim2.fromOffset(2, math.max(2, (to - from) * s.Y))
			else
				g.line.Position = UDim2.fromOffset(from * s.X, info.coord * s.Y - 1)
				g.line.Size = UDim2.fromOffset(math.max(2, (to - from) * s.X), 2)
			end
			g.line.Visible = true
		end
		place('x', gx, l, r, t, b)
		place('y', gy, t, b, l, r)
		setLinked(set)
	end

	local function clearSnap()
		for _, g in pairs(guideObjs) do
			g.line.Visible = false
		end
		setLinked({})
	end

	local function pointer(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			return input.Position.X, input.Position.Y
		end
		local m = UserInputService:GetMouseLocation()
		return m.X, m.Y
	end

	function refreshReadout(e)
		local ui = e.ui
		if not ui then
			return
		end
		local px, py = targetPad(e)
		px, py = math.floor(px + 0.5), math.floor(py + 0.5)
		local padText = px == py and tostring(px) or (px .. '/' .. py)
		local active = drag and drag.entry == e and drag.active and drag.mode
		for kind, h in pairs(ui) do
			if h.sync then
				h.sync()
			else
				local value
				if kind == 'pad' then
					value = padText
				elseif kind == 'opacity' then
					value = string.format('%d%%', math.floor((1 - e.frame.ImageTransparency) * 100 + 0.5))
				elseif STEPS[kind] then
					value = sty.fmt(e, kind)
				else
					value = string.format('%.2fx', targetK(e))
				end
				h.mid.Text = string.format("<font color='#%s'>%s</font>  <b>%s</b>", h.color:ToHex(), h.title, value)
				local on = active == kind
				TweenService:Create(h.stroke, HOVER, {
					Color = on and h.color or WHITE,
					Transparency = on and 0 or 0.88,
					Thickness = on and 1.5 or 1,
				}):Play()
			end
		end
	end

	function endDrag()
		local d = drag
		drag = nil
		clearSnap()
		if d then
			refreshReadout(d.entry)
		end
	end

	local function setPadding(e, px, py, l, t, r, b)
		local s = root.AbsoluteSize
		e.touched = true
		e.reset = false
		local mw, mh = minSize(e, (r - l) * s.X, (b - t) * s.Y, px, py)
		mw, mh = mw / s.X, mh / s.Y
		moveTo(e, l, t, math.min(1, math.max(r, l + mw)), math.min(1, math.max(b, t + mh)), nil, px, py)
		refreshReadout(e)
	end

	local function setScale(e, newK, k0, l, t, r, b)
		e.touched = true
		e.reset = false
		local w, h = r - l, b - t
		local ratio = math.min(newK / k0, 1 / w, 1 / h)
		local nw, nh = w * ratio, h * ratio
		local nl = math.max(0, math.min(l, 1 - nw))
		local nt = math.max(0, math.min(t, 1 - nh))
		moveTo(e, nl, nt, nl + nw, nt + nh, k0 * ratio)
		refreshReadout(e)
	end

	local function setOpacity(e, v)
		e.touched = true
		e.reset = false
		e.trEdited = true
		e.frame.ImageTransparency = 1 - math.clamp(math.floor(v * 100 + 0.5) / 100, 0, 1)
		refreshReadout(e)
	end

	function ops.setAlign(e, axis, name)
		e.touched = true
		e.reset = false
		if axis == 'h' then
			e.layout.HorizontalAlignment = Enum.HorizontalAlignment[name]
		else
			e.layout.VerticalAlignment = Enum.VerticalAlignment[name]
		end
		refreshReadout(e)
	end

	function ops.setDirection(e, name)
		e.touched = true
		e.reset = false
		e.layout.FillDirection = Enum.FillDirection[name]
		local s = root.AbsoluteSize
		local l, t, r, b = targetRect(e)
		local px, py = targetPad(e)
		local mw, mh = minSize(e, (r - l) * s.X, (b - t) * s.Y, px, py)
		mw, mh = mw / s.X, mh / s.Y
		moveTo(e, l, t, math.min(1, math.max(r, l + mw)), math.min(1, math.max(b, t + mh)))
		refreshReadout(e)
	end

	function ops.setCorner(e, name)
		e.touched = true
		e.reset = false
		e.layout.StartCorner = Enum.StartCorner[name]
		refreshReadout(e)
	end

	function ops.stepPadding(e, dir)
		local px, py = targetPad(e)
		local l, t, r, b = targetRect(e)
		setPadding(e, math.clamp(math.floor(px + 0.5) + dir, 0, MAX_PAD), math.clamp(math.floor(py + 0.5) + dir, 0, MAX_PAD), l, t, r, b)
	end

	function ops.stepScale(e, delta)
		local k = targetK(e)
		local l, t, r, b = targetRect(e)
		setScale(e, math.clamp(math.floor((k + delta) * 100 + 0.5) / 100, MIN_SCALE, MAX_SCALE), k, l, t, r, b)
	end

	function ops.stepOpacity(e, delta)
		setOpacity(e, (1 - e.frame.ImageTransparency) + delta)
	end

	function ops.stepGeneric(e, kind, dir)
		sty.setVal(e, kind, sty.getVal(e, kind) + dir * STEPS[kind].step)
	end

	function ops.resetControl(e, kind)
		local l, t, r, b = targetRect(e)
		if kind == 'pad' then
			setPadding(e, e.defaultPadX, e.defaultPadY, l, t, r, b)
		elseif kind == 'opacity' then
			setOpacity(e, 1 - (e.defaultImgTr or 0))
		elseif STEPS[kind] then
			sty.resetVal(e, kind)
		else
			setScale(e, e.defaultScale, targetK(e), l, t, r, b)
		end
	end

	function updateDrag()
		local d = drag
		local e = d.entry
		local s = root.AbsoluteSize
		local px, py = pointer(d.input)
		if not d.active then
			if math.abs(px - d.x) + math.abs(py - d.y) < 4 then
				return
			end
			d.active = true
			refreshReadout(e)
		end
		local dxp, dyp = px - d.x, py - d.y
		local dx, dy = dxp / s.X, dyp / s.Y
		local l, t, r, b = d.l, d.t, d.r, d.b
		local gx, gy
		e.touched = true
		e.reset = false

		local desc = STEPS[d.mode]
		if desc then
			sty.setVal(e, d.mode, d.v0 + dxp * desc.drag)
			return
		end

		if d.mode == 'scale' then
			local nk = math.clamp(d.k + dxp / 200, MIN_SCALE, MAX_SCALE)
			setScale(e, math.floor(nk * 100 + 0.5) / 100, d.k, l, t, r, b)
			return
		end

		if d.mode == 'pad' then
			local delta = math.floor(dxp * 0.3 + 0.5)
			setPadding(e, math.clamp(d.padx + delta, 0, MAX_PAD), math.clamp(d.pady + delta, 0, MAX_PAD), l, t, r, b)
			return
		end

		if d.mode == 'opacity' then
			setOpacity(e, math.clamp(d.op + dxp / 200, 0, 1))
			return
		end

		if d.mode == 'move' then
			local w, h = r - l, b - t
			local nl, nt = l + dx, t + dy
			local sx, cxv, ox = bestSnap(e, 'x', { nl, nl + w })
			nl = sx and nl + sx or snapStep(nl, s.X)
			if sx then
				gx = { coord = cxv, other = ox }
			end
			local sy, cyv, oy = bestSnap(e, 'y', { nt, nt + h })
			nt = sy and nt + sy or snapStep(nt, s.Y)
			if sy then
				gy = { coord = cyv, other = oy }
			end
			nl = math.clamp(nl, 0, math.max(0, 1 - w))
			nt = math.clamp(nt, 0, math.max(0, 1 - h))
			l, t, r, b = nl, nt, nl + w, nt + h
		else
			if d.cx == 0 then
				local v = l + dx
				local sx, cxv, ox = bestSnap(e, 'x', { v })
				v = sx and v + sx or snapStep(v, s.X)
				if sx then
					gx = { coord = cxv, other = ox }
				end
				l = math.clamp(v, 0, r - MIN_SIZE)
			else
				local v = r + dx
				local sx, cxv, ox = bestSnap(e, 'x', { v })
				v = sx and v + sx or snapStep(v, s.X)
				if sx then
					gx = { coord = cxv, other = ox }
				end
				r = math.clamp(v, l + MIN_SIZE, 1)
			end
			if d.cy == 0 then
				local v = t + dy
				local sy, cyv, oy = bestSnap(e, 'y', { v })
				v = sy and v + sy or snapStep(v, s.Y)
				if sy then
					gy = { coord = cyv, other = oy }
				end
				t = math.clamp(v, 0, b - MIN_SIZE)
			else
				local v = b + dy
				local sy, cyv, oy = bestSnap(e, 'y', { v })
				v = sy and v + sy or snapStep(v, s.Y)
				if sy then
					gy = { coord = cyv, other = oy }
				end
				b = math.clamp(v, t + MIN_SIZE, 1)
			end
			local mw, mh = minSize(e, (r - l) * s.X, (b - t) * s.Y)
			mw, mh = mw / s.X, mh / s.Y
			if d.cx == 0 then
				l = math.max(0, math.min(l, r - mw))
				r = math.max(r, l + mw)
			else
				r = math.min(1, math.max(r, l + mw))
				l = math.min(l, r - mw)
			end
			if d.cy == 0 then
				t = math.max(0, math.min(t, b - mh))
				b = math.max(b, t + mh)
			else
				b = math.min(1, math.max(b, t + mh))
				t = math.min(t, b - mh)
			end
		end
		showSnap(gx, gy, l, t, r, b)
		moveTo(e, l, t, r, b)
	end

	function beginDrag(e, mode, cx, cy, input)
		if drag then
			return
		end
		local l, t, r, b = getRect(e)
		local px, py = pointer(input)
		local padx, pady = getPad(e)
		drag = {
			entry = e,
			mode = mode,
			cx = cx,
			cy = cy,
			input = input,
			x = px,
			y = py,
			l = l,
			t = t,
			r = r,
			b = b,
			k = e.uiscale.Scale,
			padx = padx,
			pady = pady,
			op = e.kind == 'image' and (1 - e.frame.ImageTransparency) or 1,
			v0 = STEPS[mode] and sty.getVal(e, mode) or nil,
		}
	end
end

-- selection box, toolbar controls
do
	local H_OPTIONS = { 'Left', 'Center', 'Right' }
	local V_OPTIONS = { 'Top', 'Center', 'Bottom' }
	local DIR_OPTIONS = { 'Horizontal', 'Vertical' }
	local CORNER_OPTIONS = { 'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight' }
	local CORNER_POS = { TopLeft = { 0, 0 }, TopRight = { 1, 0 }, BottomLeft = { 0, 1 }, BottomRight = { 1, 1 } }
	local ROW_Y = { pad = 0, scale = 40, align = 80, dir = 120 }
	local TB_H = 156

	local stepPadding, stepScale, stepOpacity, resetControl = ops.stepPadding, ops.stepScale, ops.stepOpacity, ops.resetControl
	local setAlign, setDirection, setCorner = ops.setAlign, ops.setDirection, ops.setCorner

	function positionToolbar(e)
		local cur = e.tbCur
		if not cur or not e.handles then
			return
		end
		for _, h in ipairs(e.handles) do
			if h.kind ~= 'corner' then
				h.frame.Position = UDim2.fromOffset(cur.X + (h.col or 0) * 188 - ((e.ncols or 1) - 1) * 94, cur.Y + (h.row or ROW_Y[h.kind] or 0))
			end
		end
	end

	local function updateBox(e)
		local box = e.box
		if box then
			local p = e.frame.AbsolutePosition - root.AbsolutePosition
			local z = e.frame.AbsoluteSize
			box.Position = UDim2.fromOffset(p.X, p.Y)
			box.Size = UDim2.fromOffset(z.X, z.Y)
			local rs = root.AbsoluteSize
			local tbh = e.tbH or TB_H
			local half = (e.tbW or 188) / 2
			local cx = math.clamp(p.X + z.X / 2, half, math.max(half, rs.X - half))
			if e.kind == 'credit' then
				cx = math.max(half, rs.X - half - 16)
			end
			local py
			if p.Y + z.Y + 14 + tbh + 8 <= rs.Y then
				py = p.Y + z.Y + 14
			elseif p.Y - 36 - tbh >= 0 then
				py = p.Y - 36 - tbh
			else
				py = math.max(0, math.min(p.Y + z.Y - tbh - 8, rs.Y - tbh - 8))
			end
			if not e.handles then
				return
			end
			if e.kind == 'credit' then
				py = math.max(0, (rs.Y - tbh) / 2)
			end
			e.tb = Vector2.new(cx, py)
			if not e.tbCur then
				e.tbCur = e.tb
			end
			for _, h in ipairs(e.handles) do
				if h.kind == 'corner' then
					h.frame.Position = UDim2.fromOffset(p.X + h.cx * z.X, p.Y + h.cy * z.Y)
				end
			end
			positionToolbar(e)
		end
	end

	local function removeControls(e)
		local handles = e.handles
		e.handles, e.ui = nil, nil
		e.tb, e.tbCur, e.tbH = nil, nil, nil
		if not handles then
			return
		end
		for _, h in ipairs(handles) do
			h.frame.Interactable = false
			if h.kind == 'corner' then
				local dot = h.frame:FindFirstChildOfClass('Frame')
				if dot then
					TweenService:Create(dot, FADE, { Size = UDim2.fromOffset(0, 0) }):Play()
				end
			else
				TweenService:Create(h.frame, FADE, { GroupTransparency = 1 }):Play()
			end
		end
		task.delay(0.22, function()
			for _, h in ipairs(handles) do
				h.frame:Destroy()
			end
		end)
	end

	function removeBox(e)
		if selected == e then
			selected = nil
		end
		if e.conns then
			for _, c in ipairs(e.conns) do
				c:Disconnect()
			end
			e.conns = nil
		end
		removeControls(e)
		local box = e.box
		e.box, e.tag, e.boxStroke = nil, nil, nil
		if not box then
			return
		end
		box.Interactable = false
		TweenService:Create(box, FADE, { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(box:GetDescendants()) do
			if d:IsA('UIStroke') then
				TweenService:Create(d, FADE, { Transparency = 1 }):Play()
			elseif d:IsA('TextLabel') then
				TweenService:Create(d, FADE, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			end
		end
		task.delay(0.22, function()
			box:Destroy()
		end)
	end

	boxStyle = function(e)
		local box = e.box
		if not box then
			return
		end
		local on = selected == e
		box.ZIndex = on and 100 or (e.kind == 'credit' and 97 or 99)
		TweenService:Create(box, FADE, { BackgroundTransparency = e.kind == 'credit' and 1 or (on and 0.88 or 0.96) }):Play()
		TweenService:Create(e.boxStroke, FADE, { Color = ACCENT, Transparency = on and 0 or 0.55, Thickness = on and 2 or 1 }):Play()
		TweenService:Create(e.tag, FADE, { BackgroundColor3 = ACCENT, BackgroundTransparency = on and 0 or 0.45, TextTransparency = 0 }):Play()
	end

	local function makeWrap()
		local wrap = Instance.new('CanvasGroup')
		wrap.AnchorPoint = Vector2.new(0.5, 0)
		wrap.Size = UDim2.fromOffset(180, 36)
		wrap.BackgroundTransparency = 1
		wrap.BorderSizePixel = 0
		wrap.GroupTransparency = 1
		wrap.ZIndex = 102
		wrap.Parent = root
		TweenService:Create(wrap, FADE, { GroupTransparency = 0 }):Play()
		return wrap
	end

	local function makeStepper(e, kind, title, color)
		local wrap = makeWrap()
		local f = Instance.new('Frame')
		f.Position = UDim2.fromOffset(2, 2)
		f.Size = UDim2.fromOffset(176, 32)
		f.BackgroundColor3 = DARK
		f.BackgroundTransparency = 0.06
		f.BorderSizePixel = 0
		f.ZIndex = 102
		f.Parent = wrap
		addCorner(f, 8)
		local stroke = addStroke(f, WHITE, 0.88, 1)

		local function part(text, x, w, size)
			local b = Instance.new('TextButton')
			b.Position = UDim2.fromOffset(x, 2)
			b.Size = UDim2.fromOffset(w, 28)
			b.BackgroundColor3 = WHITE
			b.BackgroundTransparency = 1
			b.AutoButtonColor = false
			b.Font = Enum.Font.GothamMedium
			b.TextSize = size
			b.TextColor3 = WHITE
			b.Text = text
			b.ZIndex = 103
			b.Parent = f
			return b
		end

		local minus = part('', 2, 28, 18)
		local mid = part('', 32, 112, 13)
		local plus = part('', 146, 28, 18)
		mid.RichText = true
		addCorner(minus, 6)
		addCorner(plus, 6)
		drawBar(minus, 10, 2, 0, 104)
		drawBar(plus, 10, 2, 0, 104)
		drawBar(plus, 2, 10, 0, 104)

		local function hover(b)
			local function fade(v)
				TweenService:Create(b, HOVER, { BackgroundTransparency = v }):Play()
			end
			b.MouseEnter:Connect(function()
				fade(0.9)
			end)
			b.MouseLeave:Connect(function()
				fade(1)
			end)
			b.MouseButton1Down:Connect(function()
				fade(0.8)
			end)
			b.MouseButton1Up:Connect(function()
				fade(UserInputService.MouseEnabled and 0.9 or 1)
			end)
		end
		hover(minus)
		hover(plus)

		local function stepOnce(dir)
			if kind == 'pad' then
				stepPadding(e, dir)
			elseif kind == 'opacity' then
				stepOpacity(e, dir * 0.05)
			elseif sty.STEPS[kind] then
				ops.stepGeneric(e, kind, dir)
			else
				stepScale(e, dir * 0.05)
			end
		end

		local function press(dir)
			return function(input)
				if not isPress(input) or hold or drag then
					return
				end
				local token = {}
				hold = { input = input, token = token }
				stepOnce(dir)
				task.spawn(function()
					task.wait(0.4)
					while hold and hold.token == token and e.handles do
						stepOnce(dir)
						task.wait(0.06)
					end
				end)
			end
		end

		minus.InputBegan:Connect(press(-1))
		plus.InputBegan:Connect(press(1))
		mid.InputBegan:Connect(function(input)
			if not isPress(input) or drag or hold then
				return
			end
			local now = os.clock()
			if e.lastTap and e.lastTap.kind == kind and now - e.lastTap.time < 0.3 then
				e.lastTap = nil
				resetControl(e, kind)
				return
			end
			e.lastTap = { kind = kind, time = now }
			beginDrag(e, kind, 0, 0, input)
		end)

		return { frame = wrap, kind = kind, mid = mid, stroke = stroke, title = title, color = color }
	end

	local function dirIcon(b, name)
		local parts = {}
		for i = -1, 1 do
			local f = Instance.new('Frame')
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = name == 'Horizontal' and UDim2.new(0.5, i * 6, 0.5, 0) or UDim2.new(0.5, 0, 0.5, i * 6)
			f.Size = UDim2.fromOffset(4, 4)
			f.BackgroundColor3 = WHITE
			f.BorderSizePixel = 0
			f.ZIndex = 105
			f.Parent = b
			addCorner(f, 1)
			parts[#parts + 1] = f
		end
		return function(color, animate)
			for _, f in ipairs(parts) do
				if animate then
					TweenService:Create(f, HOVER, { BackgroundColor3 = color }):Play()
				else
					f.BackgroundColor3 = color
				end
			end
		end
	end

	local function cornerIcon(b, name)
		local c = CORNER_POS[name]
		local box = Instance.new('Frame')
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(14, 14)
		box.BackgroundTransparency = 1
		box.ZIndex = 105
		box.Parent = b
		addCorner(box, 3)
		local stroke = addStroke(box, WHITE, 0, 1.5)
		local dot = Instance.new('Frame')
		dot.AnchorPoint = Vector2.new(c[1], c[2])
		dot.Position = UDim2.new(c[1], c[1] == 0 and 2 or -2, c[2], c[2] == 0 and 2 or -2)
		dot.Size = UDim2.fromOffset(5, 5)
		dot.BackgroundColor3 = WHITE
		dot.BorderSizePixel = 0
		dot.ZIndex = 106
		dot.Parent = box
		addCorner(dot, 2)
		return function(color, animate)
			if animate then
				TweenService:Create(stroke, HOVER, { Color = color }):Play()
				TweenService:Create(dot, HOVER, { BackgroundColor3 = color }):Play()
			else
				stroke.Color = color
				dot.BackgroundColor3 = color
			end
		end
	end

	local ALIGN_F = { Left = 0, Top = 0, Center = 0.5, Right = 1, Bottom = 1 }

	local function alignIcon(b, e, axis, name)
		local box = Instance.new('Frame')
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(14, 14)
		box.BackgroundTransparency = 1
		box.ZIndex = 105
		box.Parent = b
		addCorner(box, 3)
		local stroke = addStroke(box, WHITE, 0, 1.5)
		local dot = Instance.new('Frame')
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(5, 5)
		dot.BackgroundColor3 = WHITE
		dot.BorderSizePixel = 0
		dot.ZIndex = 106
		dot.Parent = box
		addCorner(dot, 2)

		local function place(animate)
			local fx = ALIGN_F[axis == 'h' and name or e.layout.HorizontalAlignment.Name]
			local fy = ALIGN_F[axis == 'h' and e.layout.VerticalAlignment.Name or name]
			local pos = UDim2.fromOffset(4.5 + fx * 5, 4.5 + fy * 5)
			if animate then
				TweenService:Create(dot, SLIDE, { Position = pos }):Play()
			else
				dot.Position = pos
			end
		end
		place(false)

		local function paint(color, animate)
			if animate then
				TweenService:Create(stroke, HOVER, { Color = color }):Play()
				TweenService:Create(dot, HOVER, { BackgroundColor3 = color }):Play()
			else
				stroke.Color = color
				dot.BackgroundColor3 = color
			end
		end
		return paint, place
	end

	local function makeSegment(parent, x, options, get, set, icon)
		local seg = Instance.new('Frame')
		seg.Position = UDim2.fromOffset(x + 2, 2)
		seg.Size = UDim2.fromOffset(#options * 28 + 2, 32)
		seg.BackgroundColor3 = DARK
		seg.BackgroundTransparency = 0.06
		seg.BorderSizePixel = 0
		seg.ZIndex = 102
		seg.Parent = parent
		addCorner(seg, 8)
		addStroke(seg, WHITE, 0.88, 1)

		local thumb = Instance.new('Frame')
		thumb.Size = UDim2.fromOffset(26, 28)
		thumb.Position = UDim2.fromOffset(2, 2)
		thumb.BackgroundColor3 = ACCENT
		thumb.BorderSizePixel = 0
		thumb.ZIndex = 103
		thumb.Parent = seg
		addCorner(thumb, 6)

		local paints = {}
		local updates = {}
		for i, name in ipairs(options) do
			local b = Instance.new('TextButton')
			b.Position = UDim2.fromOffset(2 + (i - 1) * 28, 2)
			b.Size = UDim2.fromOffset(26, 28)
			b.BackgroundTransparency = 1
			b.AutoButtonColor = false
			b.Font = Enum.Font.GothamBold
			b.TextSize = 12
			b.TextColor3 = WHITE
			b.Text = icon and '' or name:sub(1, 1)
			b.ZIndex = 104
			b.Parent = seg
			b.InputBegan:Connect(function(input)
				if isPress(input) then
					set(name)
				end
			end)
			if icon then
				local pf, uf = icon(b, name)
				paints[name] = pf
				updates[name] = uf
			else
				paints[name] = function(color, animate)
					if animate then
						TweenService:Create(b, HOVER, { TextColor3 = color }):Play()
					else
						b.TextColor3 = color
					end
				end
			end
		end

		local first = true
		return function()
			local current = get()
			for i, name in ipairs(options) do
				local on = name == current
				if on then
					local pos = UDim2.fromOffset(2 + (i - 1) * 28, 2)
					if first then
						thumb.Position = pos
					else
						TweenService:Create(thumb, SLIDE, { Position = pos }):Play()
					end
				end
				paints[name](on and INK or WHITE, not first)
			end
			for _, u in pairs(updates) do
				u(not first)
			end
			first = false
		end
	end

	local function makeAlign(e)
		local wrap = makeWrap()
		local syncH = makeSegment(wrap, 0, H_OPTIONS, function()
			return e.layout.HorizontalAlignment.Name
		end, function(n)
			setAlign(e, 'h', n)
		end, function(b, name)
			return alignIcon(b, e, 'h', name)
		end)
		local syncV = makeSegment(wrap, 90, V_OPTIONS, function()
			return e.layout.VerticalAlignment.Name
		end, function(n)
			setAlign(e, 'v', n)
		end, function(b, name)
			return alignIcon(b, e, 'v', name)
		end)
		return {
			frame = wrap,
			kind = 'align',
			sync = function()
				syncH()
				syncV()
			end,
		}
	end

	local function makeDirRow(e)
		local wrap = makeWrap()
		local grid = e.layout:IsA('UIGridLayout')
		local syncD = makeSegment(wrap, grid and 0 or 61, DIR_OPTIONS, function()
			return e.layout.FillDirection.Name
		end, function(n)
			setDirection(e, n)
		end, dirIcon)
		local syncC
		if grid then
			syncC = makeSegment(wrap, 62, CORNER_OPTIONS, function()
				return e.layout.StartCorner.Name
			end, function(n)
				setCorner(e, n)
			end, cornerIcon)
		end
		return {
			frame = wrap,
			kind = 'dir',
			sync = function()
				syncD()
				if syncC then
					syncC()
				end
			end,
		}
	end

	local function makeInput(e, mode)
		local wrap = makeWrap()
		local f = Instance.new('Frame')
		f.Position = UDim2.fromOffset(2, 2)
		f.Size = UDim2.fromOffset(176, 32)
		f.BackgroundColor3 = DARK
		f.BackgroundTransparency = 0.06
		f.BorderSizePixel = 0
		f.ZIndex = 102
		f.Parent = wrap
		addCorner(f, 8)
		local stroke = addStroke(f, WHITE, 0.88, 1)

		local box = Instance.new('TextBox')
		box.Position = UDim2.fromOffset(10, 2)
		box.Size = UDim2.fromOffset(156, 28)
		box.BackgroundTransparency = 1
		box.ClearTextOnFocus = false
		box.ClipsDescendants = true
		box.Font = Enum.Font.Gotham
		box.TextSize = 12
		box.TextColor3 = WHITE
		box.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
		box.PlaceholderText = (mode == 'image' and 'Image id or .png link') or (mode == 'hex' and '#RRGGBB') or 'Type text'
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 104
		box.Parent = f

		local function current()
			if mode == 'image' then
				return e.imageSrc or ''
			end
			if mode == 'hex' then
				return '#' .. e.style.color:ToHex():upper()
			end
			if mode == 'ctext' then
				return e.style.text
			end
			return e.frame.Text
		end

		box.Text = current()

		box.Focused:Connect(function()
			TweenService:Create(stroke, HOVER, { Color = ACCENT, Transparency = 0, Thickness = 1.5 }):Play()
		end)
		box.FocusLost:Connect(function()
			TweenService:Create(stroke, HOVER, { Color = WHITE, Transparency = 0.88, Thickness = 1 }):Play()
			if mode == 'image' then
				if box.Text ~= (e.imageSrc or '') then
					e.touched = true
					e.reset = false
					e.srcEdited = true
					applyImage(e, box.Text)
				end
			end
			if mode == 'hex' then
				local hx = box.Text:gsub('[#%s]', '')
				local ok, col = pcall(Color3.fromHex, hx)
				if #hx == 6 and ok and col then
					sty.setField(e, 'color', col)
				else
					box.Text = current()
				end
			end
		end)

		if mode == 'text' then
			box:GetPropertyChangedSignal('Text'):Connect(function()
				if box:IsFocused() then
					e.touched = true
					e.reset = false
					e.textEdited = true
					e.frame.Text = box.Text
				end
			end)
		end

		if mode == 'ctext' then
			box:GetPropertyChangedSignal('Text'):Connect(function()
				if box:IsFocused() then
					sty.setField(e, 'text', box.Text)
				end
			end)
		end

		return {
			frame = wrap,
			kind = (mode == 'hex') and 'hex' or 'input',
			sync = function()
				if not box:IsFocused() then
					box.Text = current()
				end
			end,
		}
	end


	local function rowShell()
		local wrap = makeWrap()
		local f = Instance.new('Frame')
		f.Position = UDim2.fromOffset(2, 2)
		f.Size = UDim2.fromOffset(176, 32)
		f.BackgroundColor3 = DARK
		f.BackgroundTransparency = 0.06
		f.BorderSizePixel = 0
		f.ZIndex = 102
		f.Parent = wrap
		addCorner(f, 8)
		addStroke(f, WHITE, 0.88, 1)
		return wrap, f
	end

	local function makeFont(e)
		local wrap, f = rowShell()
		local function btn(text, x, w, size)
			local b = Instance.new('TextButton')
			b.Position = UDim2.fromOffset(x, 2)
			b.Size = UDim2.fromOffset(w, 28)
			b.BackgroundColor3 = WHITE
			b.BackgroundTransparency = 1
			b.AutoButtonColor = false
			b.Font = Enum.Font.GothamMedium
			b.TextSize = size
			b.TextColor3 = WHITE
			b.Text = text
			b.ZIndex = 103
			b.Parent = f
			return b
		end
		local prev = btn('‹', 2, 28, 18)
		local mid = btn('', 32, 112, 13)
		local nxt = btn('›', 146, 28, 18)
		mid.TextTruncate = Enum.TextTruncate.AtEnd
		addCorner(prev, 6)
		addCorner(nxt, 6)
		for _, b in ipairs({ prev, nxt }) do
			b.MouseEnter:Connect(function()
				TweenService:Create(b, HOVER, { BackgroundTransparency = 0.9 }):Play()
			end)
			b.MouseLeave:Connect(function()
				TweenService:Create(b, HOVER, { BackgroundTransparency = 1 }):Play()
			end)
		end
		local function shift(dir)
			local list = sty.FONTS
			local i = table.find(list, e.style.font) or 1
			i = (i - 1 + dir) % #list + 1
			sty.setField(e, 'font', list[i])
		end
		prev.MouseButton1Click:Connect(function()
			shift(-1)
		end)
		nxt.MouseButton1Click:Connect(function()
			shift(1)
		end)
		mid.MouseButton1Click:Connect(function()
			shift(1)
		end)
		return {
			frame = wrap,
			kind = 'font',
			sync = function()
				mid.Text = e.style.font.Name
				mid.Font = e.style.font
			end,
		}
	end

	local function makeSwatches(e)
		local wrap, f = rowShell()
		local items = {}
		for i, col in ipairs(sty.SWATCHES) do
			local b = Instance.new('TextButton')
			b.Position = UDim2.fromOffset(7 + (i - 1) * 21, 7)
			b.Size = UDim2.fromOffset(18, 18)
			b.BackgroundColor3 = col
			b.AutoButtonColor = false
			b.Text = ''
			b.BorderSizePixel = 0
			b.ZIndex = 103
			b.Parent = f
			addCorner(b, 5)
			local st = addStroke(b, ACCENT, 1, 2)
			b.MouseButton1Click:Connect(function()
				sty.setField(e, 'color', col)
			end)
			items[i] = { stroke = st, color = col }
		end
		return {
			frame = wrap,
			kind = 'swatch',
			sync = function()
				for _, it in ipairs(items) do
					local on = it.color == e.style.color
					TweenService:Create(it.stroke, HOVER, { Transparency = on and 0 or 1 }):Play()
				end
			end,
		}
	end

	local function gen(e, kind)
		local d = sty.STEPS[kind]
		return makeStepper(e, kind, d.title, d.color)
	end

	local function makeControls(e)
		if e.handles or not e.box then
			return
		end
		local handles = {}
		for cx = 0, (e.kind == 'credit' and -1 or 1) do for cy = 0, 1 do
				local h = Instance.new('Frame')
				h.AnchorPoint = Vector2.new(0.5, 0.5)
				h.Size = UDim2.fromOffset(28, 28)
				h.BackgroundTransparency = 1
				h.BorderSizePixel = 0
				h.Active = true
				h.ZIndex = 102
				h.Parent = root
				table.insert(handles, { frame = h, kind = 'corner', cx = cx, cy = cy })
				local dot = Instance.new('Frame')
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.fromScale(0.5, 0.5)
				dot.Size = UDim2.fromOffset(0, 0)
				dot.BackgroundColor3 = WHITE
				dot.BorderSizePixel = 0
				dot.ZIndex = 103
				dot.Parent = h
				addCorner(dot, 6)
				addStroke(dot, ACCENT, 0, 2)
				TweenService:Create(dot, POP, { Size = UDim2.fromOffset(12, 12) }):Play()
				h.InputBegan:Connect(function(input)
					if isPress(input) then
						beginDrag(e, 'resize', cx, cy, input)
					end
				end)
			end
		end

		if e.kind == 'image' then
			table.insert(handles, makeStepper(e, 'scale', 'Scale', SCALE_COLOR))
			table.insert(handles, makeStepper(e, 'opacity', 'Opacity', OPACITY_COLOR))
			table.insert(handles, makeInput(e, 'image'))
		elseif e.kind == 'text' then
			table.insert(handles, makeInput(e, 'text'))
			table.insert(handles, makeFont(e))
			table.insert(handles, makeSwatches(e))
			table.insert(handles, makeInput(e, 'hex'))
			table.insert(handles, makeStepper(e, 'scale', 'Scale', SCALE_COLOR))
			table.insert(handles, gen(e, 'topacity'))
			table.insert(handles, gen(e, 'stroke'))
		elseif e.kind == 'credit' then
			table.insert(handles, makeInput(e, 'ctext'))
			table.insert(handles, makeFont(e))
			table.insert(handles, makeSwatches(e))
			table.insert(handles, makeInput(e, 'hex'))
			table.insert(handles, gen(e, 'topacity'))
			table.insert(handles, gen(e, 'cstroke'))
			table.insert(handles, gen(e, 'tsize'))
			table.insert(handles, gen(e, 'angle'))
			table.insert(handles, gen(e, 'gapx'))
			table.insert(handles, gen(e, 'gapy'))
		else
			table.insert(handles, makeStepper(e, 'pad', 'Padding', PAD_COLOR))
			table.insert(handles, makeStepper(e, 'scale', 'Scale', SCALE_COLOR))
			table.insert(handles, makeAlign(e))
			table.insert(handles, makeDirRow(e))
		end

		local list = {}
		for _, h in ipairs(handles) do
			if h.kind ~= 'corner' then
				table.insert(list, h)
			end
		end
		local ncols = math.max(1, math.ceil(#list / 5))
		local per = math.max(1, math.ceil(#list / ncols))
		e.ui = {}
		for i, h in ipairs(list) do
			h.col = math.floor((i - 1) / per)
			h.row = ((i - 1) % per) * 40
			e.ui[h.kind] = h
		end
		e.ncols = ncols
		e.tbW = ncols * 188 - 8
		e.tbH = per * 40 - 4
		e.handles = handles
		updateBox(e)
		refreshReadout(e)
	end

	function selectEntry(e)
		if e and not e.box then
			return
		end
		if selected == e then
			return
		end
		local old = selected
		selected = e
		if old then
			removeControls(old)
			boxStyle(old)
		end
		if e then
			makeControls(e)
			boxStyle(e)
		end
	end

	function makeBox(e)
		if e.box then
			return
		end
		local box = Instance.new('Frame')
		box.Name = e.key
		box.BackgroundColor3 = ACCENT
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Active = e.kind ~= 'credit'
		box.ZIndex = 99
		box.Parent = root
		local boxStroke = addStroke(box, ACCENT, 1, 1)

		local tag = Instance.new('TextLabel')
		tag.AnchorPoint = e.kind == 'credit' and Vector2.new(0, 0) or Vector2.new(0, 1)
		tag.Position = e.kind == 'credit' and UDim2.fromOffset(12, 12) or UDim2.new(0, 0, 0, -8)
		tag.Size = UDim2.fromOffset(0, 0)
		tag.AutomaticSize = Enum.AutomaticSize.XY
		tag.BackgroundColor3 = ACCENT
		tag.BackgroundTransparency = 1
		tag.TextTransparency = 1
		tag.TextColor3 = INK
		tag.Font = Enum.Font.GothamMedium
		tag.TextSize = 12
		tag.Text = e.key
		tag.ZIndex = 101
		tag.Parent = box
		addCorner(tag, 6)
		local tagPad = Instance.new('UIPadding')
		tagPad.PaddingLeft = UDim.new(0, 8)
		tagPad.PaddingRight = UDim.new(0, 8)
		tagPad.PaddingTop = UDim.new(0, 4)
		tagPad.PaddingBottom = UDim.new(0, 4)
		tagPad.Parent = tag

		e.box = box
		e.tag = tag
		e.boxStroke = boxStroke
		boxStyle(e)

		box.InputBegan:Connect(function(input)
			if e.kind ~= 'credit' and isPress(input) and not drag then selectEntry(e)
				beginDrag(e, 'move', 0, 0, input)
			end
		end)

		e.conns = {
			e.frame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
				updateBox(e)
			end),
			e.frame:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
				updateBox(e)
			end),
		}
		updateBox(e)
	end
end

-- frame list panel
do
	local LIST_W = 240
	local LIST_SHOW = UDim2.new(0, 16, 0.5, 0)
	local LIST_HIDE = UDim2.new(0, -LIST_W - 40, 0.5, 0)

	local listPanel = Instance.new('Frame')
	listPanel.Name = 'FrameList'
	listPanel.AnchorPoint = Vector2.new(0, 0.5)
	listPanel.Position = LIST_HIDE
	listPanel.Size = UDim2.fromOffset(LIST_W, 80)
	listPanel.BackgroundColor3 = WHITE
	listPanel.BackgroundTransparency = 0.06
	listPanel.BorderSizePixel = 0
	listPanel.ZIndex = 2
	listPanel.Visible = false
	listPanel.Parent = editorGui
	addCorner(listPanel, 12)

	local listFill = Instance.new('UIGradient')
	listFill.Rotation = 90
	listFill.Color = ColorSequence.new(Color3.fromRGB(48, 48, 48), Color3.fromRGB(30, 30, 30))
	listFill.Parent = listPanel

	local listStroke = addStroke(listPanel, WHITE, 0, 1)
	local listStrokeFade = Instance.new('UIGradient')
	listStrokeFade.Rotation = 90
	listStrokeFade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.94) })
	listStrokeFade.Parent = listStroke

	local listTitle = Instance.new('TextLabel')
	listTitle.Position = UDim2.fromOffset(16, 12)
	listTitle.Size = UDim2.fromOffset(90, 20)
	listTitle.BackgroundTransparency = 1
	listTitle.Font = Enum.Font.GothamMedium
	listTitle.TextSize = 14
	listTitle.TextColor3 = WHITE
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.Text = 'Frames'
	listTitle.ZIndex = 3
	listTitle.Parent = listPanel

	local listSub = Instance.new('TextLabel')
	listSub.AnchorPoint = Vector2.new(1, 0)
	listSub.Position = UDim2.new(1, -42, 0, 14)
	listSub.Size = UDim2.fromOffset(80, 16)
	listSub.BackgroundTransparency = 1
	listSub.Font = Enum.Font.Gotham
	listSub.TextSize = 11
	listSub.TextColor3 = MUTED
	listSub.TextXAlignment = Enum.TextXAlignment.Right
	listSub.Text = 'Show / hide'
	listSub.ZIndex = 3
	listSub.Parent = listPanel

	local collapseBtn = Instance.new('TextButton')
	collapseBtn.AnchorPoint = Vector2.new(1, 0)
	collapseBtn.Position = UDim2.new(1, -10, 0, 10)
	collapseBtn.Size = UDim2.fromOffset(26, 26)
	collapseBtn.BackgroundColor3 = WHITE
	collapseBtn.BackgroundTransparency = 1
	collapseBtn.AutoButtonColor = false
	collapseBtn.Font = Enum.Font.GothamBold
	collapseBtn.TextSize = 18
	collapseBtn.TextColor3 = MUTED
	collapseBtn.Text = '‹'
	collapseBtn.ZIndex = 4
	collapseBtn.Parent = listPanel
	addCorner(collapseBtn, 6)
	collapseBtn.MouseEnter:Connect(function()
		TweenService:Create(collapseBtn, HOVER, { BackgroundTransparency = 0.9, TextColor3 = WHITE }):Play()
	end)
	collapseBtn.MouseLeave:Connect(function()
		TweenService:Create(collapseBtn, HOVER, { BackgroundTransparency = 1, TextColor3 = MUTED }):Play()
	end)

	local listTab = Instance.new('TextButton')
	listTab.Name = 'FrameListTab'
	listTab.AnchorPoint = Vector2.new(0, 0.5)
	listTab.Position = UDim2.new(0, -30, 0.5, 0)
	listTab.Size = UDim2.fromOffset(26, 64)
	listTab.BackgroundColor3 = DARK
	listTab.BackgroundTransparency = 0.06
	listTab.AutoButtonColor = false
	listTab.Font = Enum.Font.GothamBold
	listTab.TextSize = 18
	listTab.TextColor3 = WHITE
	listTab.Text = '›'
	listTab.BorderSizePixel = 0
	listTab.ZIndex = 3
	listTab.Visible = false
	listTab.Parent = editorGui
	addCorner(listTab, 8)
	addStroke(listTab, WHITE, 0.88, 1)

	local listCollapsed = false

	local listScroll = Instance.new('ScrollingFrame')
	listScroll.Position = UDim2.fromOffset(8, 44)
	listScroll.Size = UDim2.new(1, -16, 1, -52)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 3
	listScroll.ScrollBarImageColor3 = MUTED
	listScroll.CanvasSize = UDim2.new()
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.ZIndex = 3
	listScroll.Parent = listPanel

	local listLayout = Instance.new('UIListLayout')
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listScroll

	local listPad = Instance.new('UIPadding')
	listPad.PaddingRight = UDim.new(0, 6)
	listPad.Parent = listScroll

	local function setVisible(e, v)
		e.touched = true
		e.reset = false
		e.frame.Visible = v
		if editing then
			if v then
				makeBox(e)
				selectEntry(e)
			else
				removeBox(e)
			end
		end
		if e.listSync then
			e.listSync()
		end
	end

	local function makeRow(e, order)
		local row = Instance.new('TextButton')
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = WHITE
		row.BackgroundTransparency = 1
		row.AutoButtonColor = false
		row.Text = ''
		row.LayoutOrder = order
		row.ZIndex = 4
		row.Parent = listScroll
		addCorner(row, 8)

		local label = Instance.new('TextLabel')
		label.Position = UDim2.fromOffset(12, 0)
		label.Size = UDim2.new(1, -68, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextColor3 = WHITE
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = e.key
		label.ZIndex = 5
		label.Parent = row

		local track = Instance.new('Frame')
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -12, 0.5, 0)
		track.Size = UDim2.fromOffset(36, 18)
		track.BackgroundColor3 = SURFACE
		track.BorderSizePixel = 0
		track.ZIndex = 5
		track.Parent = row
		addCorner(track, 9)
		addStroke(track, WHITE, 0.85, 1)

		local knob = Instance.new('Frame')
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Position = UDim2.new(0, 3, 0.5, 0)
		knob.Size = UDim2.fromOffset(12, 12)
		knob.BackgroundColor3 = MUTED
		knob.BorderSizePixel = 0
		knob.ZIndex = 6
		knob.Parent = track
		addCorner(knob, 6)

		row.MouseEnter:Connect(function()
			TweenService:Create(row, HOVER, { BackgroundTransparency = 0.92 }):Play()
		end)
		row.MouseLeave:Connect(function()
			TweenService:Create(row, HOVER, { BackgroundTransparency = 1 }):Play()
		end)
		row.InputBegan:Connect(function(input)
			if not isPress(input) then
				return
			end
			if input.Position.X >= track.AbsolutePosition.X - 10 or not e.frame.Visible then
				setVisible(e, not e.frame.Visible)
			else
				selectEntry(e)
			end
		end)

		local first = true
		e.listSync = function()
			local on = e.frame.Visible
			local info = first and TweenInfo.new(0) or SLIDE
			TweenService:Create(track, info, { BackgroundColor3 = on and ACCENT or SURFACE }):Play()
			TweenService:Create(knob, info, {
				Position = UDim2.new(0, on and 21 or 3, 0.5, 0),
				BackgroundColor3 = on and INK or MUTED,
			}):Play()
			TweenService:Create(label, FADE, { TextTransparency = on and 0 or 0.5 }):Play()
			first = false
		end
		e.listSync()
	end

	function rebuildList()
		for _, e in pairs(entries) do
			e.listSync = nil
		end
		for _, c in ipairs(listScroll:GetChildren()) do
			if c:IsA('GuiObject') then
				c:Destroy()
			end
		end
		local keys = {}
		for k in pairs(entries) do
			table.insert(keys, k)
		end
		table.sort(keys)
		for i, k in ipairs(keys) do
			makeRow(entries[k], i)
		end
		local h = math.min(44 + #keys * 40 + 8, 340)
		TweenService:Create(listPanel, SLIDE, { Size = UDim2.fromOffset(LIST_W, h) }):Play()
	end

	local function setListCollapsed(c)
		if not editing then
			return
		end
		listCollapsed = c
		if c then
			TweenService:Create(listPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = LIST_HIDE }):Play()
			listTab.Visible = true
			TweenService:Create(listTab, SLIDE, { Position = UDim2.new(0, 0, 0.5, 0) }):Play()
		else
			listPanel.Visible = true
			TweenService:Create(listPanel, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = LIST_SHOW }):Play()
			TweenService:Create(listTab, SLIDE, { Position = UDim2.new(0, -30, 0.5, 0) }):Play()
			task.delay(0.22, function()
				if not listCollapsed then
					listTab.Visible = false
				end
			end)
		end
	end

	collapseBtn.MouseButton1Click:Connect(function()
		setListCollapsed(true)
	end)
	listTab.MouseButton1Click:Connect(function()
		setListCollapsed(false)
	end)

	function showList(show)
		if show then
			listCollapsed = true
			listPanel.Position = LIST_HIDE
			listTab.Position = UDim2.new(0, -30, 0.5, 0)
			listTab.Visible = true
			TweenService:Create(listTab, SLIDE, { Position = UDim2.new(0, 0, 0.5, 0) }):Play()
		else
			listCollapsed = false
			TweenService:Create(listPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = LIST_HIDE }):Play()
			TweenService:Create(listTab, SLIDE, { Position = UDim2.new(0, -30, 0.5, 0) }):Play()
			task.delay(0.32, function()
				if not editing then
					listPanel.Visible = false
					listTab.Visible = false
				end
			end)
		end
	end
end

-- edit lifecycle (commit / revert / start / stop)
do
	local function commit()
		settle()
		local W, H = screenSize()
		for key, e in pairs(entries) do
			if e.touched then
				local p, z = e.frame.Position, e.frame.Size
				local padx, pady = getPad(e)
				layouts[key] = {
					p.X.Scale,
					p.Y.Scale,
					z.X.Scale,
					z.Y.Scale,
					e.uiscale.Scale,
					padx,
					pady,
					e.layout.HorizontalAlignment.Name,
					e.layout.VerticalAlignment.Name,
					e.frame.Visible,
					e.layout.FillDirection.Name,
					e.layout:IsA('UIGridLayout') and e.layout.StartCorner.Name or 'TopLeft',
					W,
					H,
					e.textEdited and e.frame.Text or '',
					e.srcEdited and (e.imageSrc or '') or '',
					e.trEdited and e.frame.ImageTransparency or -1,
					e.styleEdited and sty.serialize(e) or false,
				}
				e.base = makeBase(e, W, H)
			elseif e.reset then
				layouts[key] = nil
				e.base = e.baseDefault
			end
			e.touched = false
			e.reset = false
		end
		layouts.__smart = smartOn
		persist()
	end

	local function captureState(e)
		local padx, pady = getPad(e)
		return {
			scale = e.uiscale.Scale,
			pos = e.frame.Position,
			size = e.frame.Size,
			padx = padx,
			pady = pady,
			ha = e.layout.HorizontalAlignment.Name,
			va = e.layout.VerticalAlignment.Name,
			fd = e.layout.FillDirection.Name,
			sc = e.layout:IsA('UIGridLayout') and e.layout.StartCorner.Name or nil,
			vis = e.frame.Visible,
			text = e.kind == 'text' and e.frame.Text or nil,
			img = e.kind == 'image' and (e.imageSrc or '') or nil,
			tr = e.kind == 'image' and e.frame.ImageTransparency or nil,
			te = e.textEdited,
			se = e.srcEdited,
			re = e.trEdited,
			style = e.style and sty.copy(e) or nil,
			ye = e.styleEdited,
		}
	end

	ops.captureState = captureState

	local function restore(e, st)
		stopAnim(e)
		e.uiscale.Scale = st.scale
		e.frame.Position = st.pos
		e.frame.Size = st.size
		e.layout.FillDirection = Enum.FillDirection[st.fd]
		setPad(e, st.padx, st.pady)
		e.layout.HorizontalAlignment = Enum.HorizontalAlignment[st.ha]
		e.layout.VerticalAlignment = Enum.VerticalAlignment[st.va]
		if st.sc then
			e.layout.StartCorner = Enum.StartCorner[st.sc]
		end
		if e.kind == 'text' and st.text ~= nil then
			e.frame.Text = st.text
		end
		if e.kind == 'image' then
			if st.img ~= nil and (e.imageSrc or '') ~= st.img then
				applyImage(e, st.img)
			end
			if st.tr ~= nil then
				e.frame.ImageTransparency = st.tr
			end
		end
		e.textEdited, e.srcEdited, e.trEdited = st.te, st.se, st.re
		e.styleEdited = st.ye
		if st.style and e.style then
			sty.restore(e, st.style)
		end
		if e.frame.Visible ~= st.vis then
			e.frame.Visible = st.vis
			if editing then
				if st.vis then
					makeBox(e)
				else
					removeBox(e)
				end
			end
		end
		if e.listSync then
			e.listSync()
		end
		refreshReadout(e)
	end

	local function revert()
		for _, e in pairs(entries) do
			if e.snap then
				restore(e, e.snap)
			end
			e.touched = false
			e.reset = false
		end
	end

	function snapshot(e)
		e.snap = captureState(e)
		e.def = e.def or captureState(e)
	end

	function startEdit()
		if editing then
			return
		end
		if not uiOn then
			setUIEnabled(true)
			setToggleView(true)
		end
		editing = true
		smartSnap = smartOn
		for _, e in pairs(entries) do
			snapshot(e)
			if e.frame.Visible then
				makeBox(e)
				refreshReadout(e)
			end
		end
		rebuildList()
		showList(true)
		overlay.Visible = true
		setHint(true)
		TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
		refreshButtons()
	end

	function stopEdit(save)
		if not editing then
			return
		end
		editing = false
		endDrag()
		hold = nil
		setHint(false)
		showList(false)
		if save then
			commit()
		else
			revert()
			smartOn = smartSnap
			setSmartView()
		end
		for _, e in pairs(entries) do
			removeBox(e)
		end
		if smartOn then
			reflowAll()
		end
		TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.3, function()
			if not editing then
				overlay.Visible = false
			end
		end)
		setPanel(false)
		refreshButtons()
	end

	function resetAll()
		for _, e in pairs(entries) do
			restore(e, e.def)
			e.touched = false
			e.reset = true
		end
	end
end

overlay.Active = true
overlay.InputBegan:Connect(function(input)
	if editing and isPress(input) and not drag then
		selectEntry(nil)
	end
end)

btnEdit.MouseButton1Click:Connect(startEdit)
btnSave.MouseButton1Click:Connect(function()
	stopEdit(true)
end)
btnCancel.MouseButton1Click:Connect(function()
	stopEdit(false)
end)
btnReset.MouseButton1Click:Connect(resetAll)
btnClose.MouseButton1Click:Connect(function()
	setPanel(false)
end)

UserInputService.InputBegan:Connect(function(input)
	if editing or panelOpen or not isPress(input) then
		return
	end
	if input.Position.Y <= SWIPE_ZONE then
		swipe = { input = input, y = input.Position.Y }
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if drag then
		if tracks(drag.input, input) then
			if drag.input.UserInputType == Enum.UserInputType.MouseButton1 and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				endDrag()
			else
				updateDrag()
			end
		end
	elseif swipe and tracks(swipe.input, input) then
		if input.Position.Y - swipe.y >= SWIPE_DIST then
			swipe = nil
			setPanel(true)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if drag and sameRelease(drag.input, input) then
		endDrag()
	end
	if hold and sameRelease(hold.input, input) then
		hold = nil
	end
	if swipe and sameRelease(swipe.input, input) then
		swipe = nil
	end
end)

-- frame factory
do
	local reserved = { Name = true, Layout = true, FillDirection = true, Scale = true, Type = true, Image = true }
	local layoutProps = {
		Padding = true,
		CellSize = true,
		CellPadding = true,
		HorizontalAlignment = true,
		VerticalAlignment = true,
		SortOrder = true,
		StartCorner = true,
		FillDirectionMaxCells = true,
	}

	local function enumItem(enum, name)
		local ok, v = pcall(function()
			return enum[name]
		end)
		return ok and v or nil
	end

	local function applySaved(e)
		local d = layouts[e.key]
		if not d then
			return
		end
		local fd = d[11] and enumItem(Enum.FillDirection, d[11])
		if fd then
			e.layout.FillDirection = fd
		end
		local sc = d[12] and e.layout:IsA('UIGridLayout') and enumItem(Enum.StartCorner, d[12])
		if sc then
			e.layout.StartCorner = sc
		end
		e.uiscale.Scale = d[5] or 1
		e.frame.Position = UDim2.fromScale(d[1], d[2])
		e.frame.Size = UDim2.fromScale(d[3], d[4])
		if d[6] then
			setPad(e, d[6], d[7] or d[6])
		end
		local ha = d[8] and enumItem(Enum.HorizontalAlignment, d[8])
		if ha then
			e.layout.HorizontalAlignment = ha
		end
		local va = d[9] and enumItem(Enum.VerticalAlignment, d[9])
		if va then
			e.layout.VerticalAlignment = va
		end
		if d[10] ~= nil then
			e.frame.Visible = d[10]
		end
		if e.kind == 'text' and type(d[15]) == 'string' and d[15] ~= '' then
			e.frame.Text = d[15]
			e.textEdited = true
		end
		if e.kind == 'image' then
			if type(d[16]) == 'string' and d[16] ~= '' then
				applyImage(e, d[16])
				e.srcEdited = true
			end
			if type(d[17]) == 'number' and d[17] >= 0 then
				e.frame.ImageTransparency = d[17]
				e.trEdited = true
			end
		end
		if e.style and type(d[18]) == 'table' then
			sty.load(e, d[18])
		end
	end

	function New(config)
		config = config or {}
		local tname = string.lower(tostring(config.Type or 'Layout'))
		local kind = 'layout'
		if tname == 'image' or tname == 'imagelabel' then
			kind = 'image'
		elseif tname == 'text' or tname == 'textlabel' then
			kind = 'text'
		elseif tname == 'credit' then
			kind = 'credit'
		end

		local frame
		if kind == 'image' then
			frame = Instance.new('ImageLabel')
			frame.ScaleType = Enum.ScaleType.Stretch
			frame.Size = UDim2.fromScale(0.2, 0.2)
		elseif kind == 'text' then
			frame = Instance.new('TextLabel')
			frame.Font = Enum.Font.GothamMedium
			frame.TextColor3 = WHITE
			frame.Text = 'Text'
			frame.Size = UDim2.fromScale(0.3, 0.08)
		elseif kind == 'credit' then
			frame = Instance.new('Frame')
			frame.Size = UDim2.fromScale(1, 1)
			frame.ClipsDescendants = true
		else
			frame = Instance.new('Frame')
			frame.Size = UDim2.fromScale(0.3, 0.3)
		end
		frame.Name = config.Name or (kind == 'credit' and 'Credit' or 'UIFrame')
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0

		local layout = Instance.new((kind == 'layout' and config.Layout == 'Grid') and 'UIGridLayout' or 'UIListLayout')
		layout.FillDirection = Enum.FillDirection[config.FillDirection or 'Vertical']
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = (kind ~= 'credit') and frame or nil

		local uiscale = Instance.new('UIScale')
		uiscale.Scale = config.Scale or 1
		uiscale.Parent = frame

		for k, v in pairs(config) do
			if not reserved[k] then
				local target = layoutProps[k] and layout or frame
				pcall(function()
					target[k] = v
				end)
			end
		end

		if kind == 'text' then
			frame.TextScaled = true
		end

		local key = frame.Name
		local n = 1
		while entries[key] do
			n += 1
			key = frame.Name .. n
		end

		local e = {
			key = key,
			kind = kind,
			frame = frame,
			layout = layout,
			uiscale = uiscale,
			defaultPos = frame.Position,
			defaultSize = frame.Size,
			defaultScale = uiscale.Scale,
			defaultHA = layout.HorizontalAlignment.Name,
			defaultVA = layout.VerticalAlignment.Name,
			touched = false,
			reset = false,
		}
		e.defaultPadX, e.defaultPadY = getPad(e)
		sty.init(e, config)
		if kind == 'image' then
			e.defaultImgTr = frame.ImageTransparency
			if config.Image ~= nil then
				applyImage(e, config.Image)
			end
		end
		e.def = ops.captureState(e)
		entries[key] = e
		frame.Parent = root

		local W0, H0 = screenSize()
		e.baseDefault = makeBase(e, W0, H0)
		applySaved(e)
		local sd = layouts[key]
		e.base = sd and makeBase(e, sd[13] or W0, sd[14] or H0) or e.baseDefault
		if smartOn then
			smartApply(e)
		end
		if editing then
			snapshot(e)
			if frame.Visible then
				makeBox(e)
				refreshReadout(e)
			end
			rebuildList()
		end

		frame.Destroying:Connect(function()
			stopAnim(e)
			removeBox(e)
			entries[key] = nil
			if editing then
				rebuildList()
			end
		end)

		return frame
	end
end

return {
	New = New,
	StartEdit = function()
		setPanel(true)
		startEdit()
	end,
	StopEdit = stopEdit,
	SetUIEnabled = function(v)
		setUIEnabled(v and true or false)
		setToggleView(uiOn)
	end,
}
