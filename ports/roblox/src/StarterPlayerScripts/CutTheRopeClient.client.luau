local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local LevelRuntime = require(ReplicatedStorage.CutTheRope.Shared.LevelRuntime)
local Layout = require(ReplicatedStorage.CutTheRope.Shared.ViewportLayout)
local LevelData = require(ReplicatedStorage.CutTheRope.Shared.LevelData)
local BoxFrames = require(ReplicatedStorage.CutTheRope.Shared.BoxFrames)
local SplitFrames = require(ReplicatedStorage.CutTheRope.Shared.SplitFrames)
local WheelFrames = require(ReplicatedStorage.CutTheRope.Shared.WheelFrames)
local AdvancedFrames = require(ReplicatedStorage.CutTheRope.Shared.AdvancedFrames)
local DiscFrames = require(ReplicatedStorage.CutTheRope.Shared.DiscFrames)
local GhostFrames = require(ReplicatedStorage.CutTheRope.Shared.GhostFrames)
local SteamFrames = require(ReplicatedStorage.CutTheRope.Shared.SteamFrames)
local LanternFrames = require(ReplicatedStorage.CutTheRope.Shared.LanternFrames)
local CheeseFrames = require(ReplicatedStorage.CutTheRope.Shared.CheeseFrames)
local PillowFrames = require(ReplicatedStorage.CutTheRope.Shared.PillowFrames)
local MechanicalFrames = require(ReplicatedStorage.CutTheRope.Shared.MechanicalFrames)
local LevelBackground = require(ReplicatedStorage.CutTheRope.Shared.LevelBackground)
local Sprites = require(ReplicatedStorage.CutTheRope.Shared.DxSprites)
local Session = require(ReplicatedStorage.CutTheRope.Shared.SessionState)
local SaveClient = require(ReplicatedStorage.CutTheRope.Shared.SaveClient)
local DragScroll = require(ReplicatedStorage.CutTheRope.Shared.DragScroll)
local FinishedPopup = require(ReplicatedStorage.CutTheRope.Shared.FinishedPopup)
SaveClient.start(Players.LocalPlayer:WaitForChild("PlayerGui"))
local AudioController = require(ReplicatedStorage.CutTheRope.Shared.AudioController)
local LevelAudio = require(ReplicatedStorage.CutTheRope.Shared.LevelAudio)
local audio = AudioController.new()
audio:preload()
local Locale = require(ReplicatedStorage.CutTheRope.Shared.Localization)
local SkinFrames = require(ReplicatedStorage.CutTheRope.Shared.SkinFrames)
local SkinMenu = require(ReplicatedStorage.CutTheRope.Shared.SkinMenu)
local PackSelection = require(ReplicatedStorage.CutTheRope.Shared.PackSelection)
local FingerTrace = require(ReplicatedStorage.CutTheRope.Shared.FingerTrace)
local TraceFrames = require(ReplicatedStorage.CutTheRope.Shared.TraceFrames)
local OmNomFrames = require(ReplicatedStorage.CutTheRope.Shared.OmNomFrames)
local Credits = require(ReplicatedStorage.CutTheRope.Shared.CreditsData)
local BitmapFont = require(ReplicatedStorage.CutTheRope.Shared.BitmapFont)
local LocaleFonts = require(ReplicatedStorage.CutTheRope.Shared.LocaleFonts)
local SmallFont = require(ReplicatedStorage.CutTheRope.Shared.SmallFont)
local Atlas = require(ReplicatedStorage.CutTheRope.Shared.AtlasSprite)
local Effects = require(ReplicatedStorage.CutTheRope.Shared.EffectFrames)
local HazardFrames = require(ReplicatedStorage.CutTheRope.Shared.HazardFrames)
local TextureCache = require(ReplicatedStorage.CutTheRope.Shared.TextureCache)
local ResultConfetti = require(ReplicatedStorage.CutTheRope.Shared.ResultConfetti)
local BoxTransition = require(ReplicatedStorage.CutTheRope.Shared.BoxTransition)
local LevelHud = require(ReplicatedStorage.CutTheRope.Shared.LevelHud)
local HudFrames = require(ReplicatedStorage.CutTheRope.Shared.HudFrames)
local ResultPresentation = require(ReplicatedStorage.CutTheRope.Shared.ResultPresentation)
local textures = TextureCache.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
local resultConfetti, resultPresentation
local paused, pauseLayer = false, nil
local focusSuspended, focusJustResumed = false, false
local elapsedTime, activeResult = 0, nil
local levelIndex, bestStars = 1, 0
local selectedPack = 1
local level = LevelData.get(levelIndex)

local gui = Instance.new("ScreenGui")
gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "CutTheRopeGui", true, false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size, backdrop.BackgroundColor3, backdrop.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0
backdrop.Parent = gui

local tiledBackground = Instance.new("ImageLabel")
tiledBackground.Name = "DimmedTileBackground"
tiledBackground.Size, tiledBackground.BackgroundTransparency = UDim2.fromScale(1, 1), 1
tiledBackground.Image, tiledBackground.ImageTransparency = "rbxassetid://133921403010010", .75
tiledBackground.ScaleType, tiledBackground.TileSize, tiledBackground.Parent = Enum.ScaleType.Tile, UDim2.fromOffset(180, 180), backdrop

local board = Instance.new("Frame")
board.AnchorPoint, board.Position, board.Size = Vector2.new(.5, .5), UDim2.fromScale(.5, .5), UDim2.fromScale(1, 1)
board.BackgroundColor3, board.BorderSizePixel, board.ClipsDescendants = Color3.fromRGB(202, 176, 123), 0, true
board.Parent = backdrop
local hudLeft = Layout.group(board,"HudTopLeft","content",nil,Vector2.zero,20)
local hudRight = Layout.group(board,"HudTopRight","content",nil,Vector2.new(1,0),20)

local levelBackground = Instance.new("ImageLabel")
levelBackground.Name = "CardboardBox01Background"
levelBackground.Size, levelBackground.BackgroundTransparency = UDim2.fromScale(1, 1), 1
levelBackground.Image, levelBackground.ScaleType, levelBackground.Parent = "rbxassetid://93414504665497", Enum.ScaleType.Crop, board
local scrollingBackground = LevelBackground.new(levelBackground)

local function label(text, size, position)
	local out = Instance.new("TextLabel")
	out.Size, out.Position, out.BackgroundTransparency = size, position, 1
	out.Text, out.Font, out.TextColor3 = text, Enum.Font.GothamBold, Color3.fromRGB(247, 255, 239)
	out.TextXAlignment = Enum.TextXAlignment.Left
	out.Parent = board
	return out
end
local note = label("", UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0))
note.Visible = false

local hudStars = {}
for index = 1, 3 do
	local hudStar = Instance.new("ImageLabel")
	hudStar.Name, hudStar.AnchorPoint = "HudStar" .. index, Vector2.new(.5, .5)
	hudStar.Position = UDim2.fromScale((21 + (index - 1) * 37) / 1120, 21 / 630)
	hudStar.Size = UDim2.fromScale(48 / 1120, 48 / 630)
	hudStar.BackgroundTransparency, hudStar.Image, hudStar.ZIndex, hudStar.Parent = 1, Sprites.Hud.starEmpty, 20, hudLeft
	hudStar.ImageTransparency = .35
	hudStars[index] = hudStar
end

local reset = Instance.new("ImageButton")
reset.Name, reset.AnchorPoint = "RestartButton", Vector2.new(.5, .5)
reset.Position, reset.Size = UDim2.fromScale(.895, .039), UDim2.fromScale(43 / 1120, 43 / 630)
reset.BackgroundTransparency, reset.Image, reset.ZIndex, reset.Parent = 1, Sprites.Hud.restart, 20, hudRight
reset.ImageTransparency = .35

local menu = Instance.new("ImageButton")
menu.Name, menu.AnchorPoint = "MenuButton", Vector2.new(.5, .5)
menu.Position, menu.Size = UDim2.fromScale(.958, .039), UDim2.fromScale(91 / 1120, 43 / 630)
menu.BackgroundTransparency, menu.Image, menu.ZIndex, menu.Parent = 1, Sprites.Hud.menuEn, 20, hudRight
menu.ImageTransparency = .35

local layer = Instance.new("Frame")
layer.Name, layer.Position, layer.Size, layer.BackgroundTransparency = "GameLayer", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 1
layer.Parent = board
local activeLevel
local traceLayer = Instance.new("Frame")
traceLayer.Name, traceLayer.Size, traceLayer.BackgroundTransparency = "FingerTraceLayer", UDim2.fromScale(1,1), 1
traceLayer.ZIndex, traceLayer.Parent = 25, board
Layout.bind(traceLayer,board,"logical")
local fingerTrace = FingerTrace.new(traceLayer)
local hud = LevelHud.new(board, hudStars)
local held, lastPoint, objectHeld = false, nil, false
local function resetLevel(prepared)
	LevelAudio.unbind(activeLevel)
	audio:clearScene()
	audio:setPaused(false)
	fingerTrace:reset()
	elapsedTime, activeResult, held, lastPoint, objectHeld = 0, nil, false, nil, false
	level = assert(LevelData.get(levelIndex, selectedPack))
	gui:SetAttribute("Paused", false)
	if prepared then
		layer:Destroy()
		layer, activeLevel = prepared.layer, prepared
		layer.Name, layer.Visible, layer.ZIndex = "GameLayer", true, 1
	else activeLevel = LevelRuntime.new(layer, level, Layout.compute(board.AbsoluteSize).visible) end
	activeLevel:resize(Layout.compute(board.AbsoluteSize).visible)
	scrollingBackground:setPack(selectedPack)
	scrollingBackground:update(activeLevel.camera,activeLevel.physics)
	layer:SetAttribute("DebugFreeze", false)
	hud:reset(selectedPack, levelIndex)
	if gui.Enabled then LevelAudio.bind(activeLevel,audio) end
end
local function point(input)
	local p, origin, size = input.Position, board.AbsolutePosition, board.AbsoluteSize
	return (Vector2.new(p.X,p.Y)-origin)/Layout.compute(size).pixels
end
board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	-- A held gesture has points in the old projection. End it without cutting or
	-- teleporting a dragged object; the next press uses the new inverse transform.
	if activeLevel then
		if objectHeld then activeLevel:release() end
		held,lastPoint,objectHeld=false,nil,false
		fingerTrace:reset()
		activeLevel:resize(Layout.compute(board.AbsoluteSize).visible)
		scrollingBackground:update(activeLevel.camera,activeLevel.physics)
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not gui.Enabled or paused or processed or not activeLevel then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if activeLevel.camera:press() then return end
	local screen = point(input)
	local touch = activeLevel.camera:world(screen)
	if activeLevel:pop(touch) then return end
	if activeLevel:press(touch) then objectHeld = true return end
	if not Session.drag then activeLevel:cut(touch, touch, 57) return end
	fingerTrace:begin(screen)
	held, lastPoint = true, touch
end)
UserInputService.InputChanged:Connect(function(input)
	if paused or not gui.Enabled or (not held and not objectHeld) then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local screen = point(input)
	local now = activeLevel.camera:world(screen)
	if objectHeld then activeLevel:drag(now) return end
	fingerTrace:append(screen)
	activeLevel:cut(lastPoint, now)
	lastPoint = now
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		held, lastPoint, objectHeld = false, nil, false
		if activeLevel then activeLevel:release(not paused and activeLevel.camera:world(point(input)) or nil) end
		fingerTrace:finish()
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	held, lastPoint, objectHeld = false, nil, false
	if activeLevel then activeLevel:release() end
	fingerTrace:finish()
	focusSuspended = true
	audio:setFocused(false)
end)
UserInputService.WindowFocused:Connect(function()
	if not focusSuspended then return end
	focusSuspended, focusJustResumed = false, true
	audio:setFocused(true)
end)
local menuGui = Instance.new("ScreenGui")
menuGui.Name, menuGui.IgnoreGuiInset, menuGui.ResetOnSpawn = "CutTheRopeMenus", true, false
menuGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
menuGui.Parent = Players.LocalPlayer.PlayerGui
gui.Enabled = false
local boundAudioButtons=setmetatable({},{__mode="k"})
local audioButtonActions=setmetatable({},{__mode="k"})
local function bindAudioButton(object)
	if not object:IsA("GuiButton") or object.Name=="PackDragSurface" or boundAudioButtons[object] then return end
	boundAudioButtons[object]=true
	object.Activated:Connect(function()
		local scroll=object:FindFirstAncestorOfClass("ScrollingFrame")
		if object.Interactable and not (scroll and DragScroll.blocked(scroll)) then
			audio:play("tap","ui")
			local callback=audioButtonActions[object]
			if callback then callback() end
		end
	end)
end
local function activateButton(object,callback)
	audioButtonActions[object]=callback
	bindAudioButton(object)
end
for _,root in ipairs({gui,menuGui}) do
	for _,object in ipairs(root:GetDescendants()) do bindAudioButton(object) end
	root.DescendantAdded:Connect(bindAudioButton)
end
script.Destroying:Connect(function() LevelAudio.unbind(activeLevel) audio:destroy() end)
local menuBackdrop = Instance.new("Frame")
menuBackdrop.Size, menuBackdrop.BackgroundColor3, menuBackdrop.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0
menuBackdrop.Parent = menuGui
local menuTile = Instance.new("ImageLabel")
menuTile.Size, menuTile.BackgroundTransparency, menuTile.Image = UDim2.fromScale(1, 1), 1, "rbxassetid://133921403010010"
menuTile.ImageTransparency, menuTile.ScaleType, menuTile.TileSize = .75, Enum.ScaleType.Tile, UDim2.fromOffset(180, 180)
menuTile.Parent = menuBackdrop
local menuBoard = Instance.new("Frame")
menuBoard.Name, menuBoard.AnchorPoint, menuBoard.Position = "DxMenuCanvas", Vector2.new(.5, .5), UDim2.fromScale(.5, .5)
menuBoard.Size, menuBoard.BackgroundColor3, menuBoard.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0
menuBoard.ClipsDescendants, menuBoard.Parent = true, menuBackdrop
local pageLayer = Instance.new("Frame")
pageLayer.Size, pageLayer.BackgroundTransparency, pageLayer.Parent = UDim2.fromScale(1, 1), 1, menuBoard
local pageContent, pageCover, pageBack, pageTop
local function menuImage(name, asset, x, y, width, height, z, isButton, parent)
	local object = Instance.new(isButton and "ImageButton" or "ImageLabel")
	object.Name, object.Image, object.BackgroundTransparency = name, asset, 1
	object.AnchorPoint, object.Position = Vector2.new(.5, .5), UDim2.fromScale(x, y)
	object.Size, object.ZIndex, object.ScaleType = UDim2.fromScale(width, height), z or 1, Enum.ScaleType.Fit
	object.Parent = parent or pageContent
	if isButton then bindAudioButton(object) end
	return object
end
local function menuHitbox(name, x, y, width, height, z, parent)
	local button = Instance.new("TextButton")
	button.Name, button.Text, button.BackgroundTransparency = name, "", 1
	button.AutoButtonColor, button.BorderSizePixel = false, 0
	button.AnchorPoint, button.Position = Vector2.new(.5, .5), UDim2.fromScale(x, y)
	button.Size, button.ZIndex, button.Parent = UDim2.fromScale(width, height), z or 12, parent or pageContent
	bindAudioButton(button)
	return button
end

local function menuText(name, value, x, y, width, height, z, parent, forceText)
	value = Locale.text(value)
	local object = Instance.new("TextLabel")
	object.Name, object.Text, object.BackgroundTransparency = name, value, 1
	object.AnchorPoint, object.Position = Vector2.new(.5, .5), UDim2.fromScale(x, y)
	object.Size, object.ZIndex = UDim2.fromScale(width, height), z or 10
	object.Font, object.TextScaled = Enum.Font.FredokaOne, true
	object.TextColor3, object.TextStrokeColor3, object.TextStrokeTransparency = Color3.new(1, 1, 1), Color3.new(0, 0, 0), 0
	object.Parent = parent or pageContent
	if not forceText then BitmapFont.render(object, value) end
	return object
end
local function buttonStates(art, button, short, selected)
	local sprite = Atlas.new(art, {"buttons"}, SkinFrames)
	local up = short and (selected and 2 or 3) or 0
	local down = short and (selected and 3 or 2) or 1
	sprite:show("buttons", up)
	button.MouseButton1Down:Connect(function() sprite:show("buttons", down) end)
	button.MouseButton1Up:Connect(function() sprite:show("buttons", up) end)
	button.MouseLeave:Connect(function() sprite:show("buttons", up) end)
end
local function clearPage(name)
	if name~="ZeptolabSplash" and name~="LevelLoading" and name~="LevelResults" then
		audio:setPaused(false)
		audio:setContext("menu")
	end
	local previous = pageLayer
	previous.Name = "PreviousPage"
	for _, object in ipairs(previous:GetDescendants()) do
		if object:IsA("GuiButton") then object.Interactable = false end
	end
	local nextPage = Instance.new("Frame")
	nextPage.Name, nextPage.Size, nextPage.BackgroundTransparency = name, UDim2.fromScale(1, 1), 1
	nextPage.Visible, nextPage.Parent = false, menuBoard
	pageLayer, resultConfetti, resultPresentation = nextPage, nil, nil
	local bounds = name == "MainMenu" and {800,25,1770,1240}
		or name == "LanguageSelection" and {540,280,2020,1120}
		or name == "ZeptolabSplash" and {400,200,2160,1380}
		or name:find("LevelSelection") and {685,35,1875,1380}
		or name == "ResetConfirmation" and {480,400,2080,1200}
		or {760,75,1800,1390}
	pageContent = Layout.group(nextPage,"MenuContent","content",bounds,nil,5)
	pageCover = Layout.group(nextPage,"MenuCover","cover",nil,nil,2)
	pageBack = Layout.group(nextPage,"BottomLeftChrome","content",nil,Vector2.new(0,1),15)
	pageTop = Layout.group(nextPage,"TopRightChrome","content",nil,Vector2.new(1,0),15)
	-- Build synchronously, reveal the complete warmed page on a later render frame.
	task.defer(function()
		local ready = textures:surface(nextPage)
		if pageLayer == nextPage and nextPage.Parent then
			nextPage.Visible = true
			nextPage:SetAttribute("TexturesReady", ready)
			nextPage:SetAttribute("PageReady", true)
			local content=nextPage:FindFirstChild("MenuContent")
			if content then content:SetAttribute("PageReady",true) end
		end
		previous:Destroy()
	end)
end
local function menuBackground(withFabric)
	local backdropGroup=Layout.group(pageLayer,"MenuBackdrop","coverBottom",nil,nil,1)
	menuImage("MenuBgrQuad0", Sprites.Menu.background, .5, .5, 1, 1, 1,false,backdropGroup).ScaleType = Enum.ScaleType.Stretch
	if withFabric then
		menuImage("MenuBgrQuad1", Sprites.Menu.fabric, .5, .5, 1, 1, 2,false,backdropGroup).ScaleType = Enum.ScaleType.Stretch
	end
	-- MenuController uses MenuBgrShadow quad 0 at scale 2 and 45 degrees.
	local rotatingShadow = menuImage("MenuBgrShadowQuad0", Sprites.Menu.shadow, .5, .5, 2, 2, 3,false,backdropGroup)
	rotatingShadow.Rotation = 45
	TweenService:Create(rotatingShadow, TweenInfo.new(75, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 405 }):Play()
end
local transitioning = false
-- Input transitions and simulation readiness are separate. The opening panels and
-- the white fade reveal a running level, not a half-second frozen snapshot.
local surfacePending = false
local function transitionTo(callback, color, duration)
	if transitioning then return end
	transitioning = true
	held, lastPoint = false, nil
	local fadeGui = Instance.new("ScreenGui")
	fadeGui.Name, fadeGui.IgnoreGuiInset, fadeGui.ResetOnSpawn = color and "DxWhiteFade" or "DxBlackFade", true, false
	fadeGui.DisplayOrder, fadeGui.Parent = 100, Players.LocalPlayer.PlayerGui
	local black = Instance.new("Frame")
	black.Name, black.Size, black.BackgroundColor3 = "Transition", UDim2.fromScale(1, 1), color or Color3.new(0, 0, 0)
	black.BorderSizePixel, black.BackgroundTransparency, black.Active, black.Parent = 0, 1, true, fadeGui
	local fadeOut = TweenService:Create(black, TweenInfo.new(duration or .2, Enum.EasingStyle.Linear), { BackgroundTransparency = 0 })
	fadeOut.Completed:Connect(function()
		surfacePending = gui.Enabled
		local ok, message = xpcall(callback, debug.traceback)
		if not ok then warn("DX transition failed: " .. tostring(message)) end
		if menuGui.Enabled then
			while pageLayer.Parent and not pageLayer:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
		elseif gui.Enabled then textures:surface(gui) end
		surfacePending = false
		local fadeIn = TweenService:Create(black, TweenInfo.new(duration or .2, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 })
		fadeIn.Completed:Connect(function()
			fadeGui:Destroy()
			transitioning = false
		end)
		fadeIn:Play()
	end)
	fadeOut:Play()
end

local showMain, showPacks, showLevels, showOptions, showResults, showPause
local function boxOverlay(seams, initial, order)
	local overlay = Instance.new("ScreenGui")
	overlay.Name, overlay.IgnoreGuiInset, overlay.ResetOnSpawn, overlay.DisplayOrder = "DxBoxTransition", true, false, order or 90
	overlay.Enabled = false
	local canvas = Instance.new("Frame")
	canvas.AnchorPoint, canvas.Position, canvas.Size = Vector2.new(.5, .5), UDim2.fromScale(.5, .5), UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency, canvas.ClipsDescendants, canvas.Parent = 1, true, overlay
	local panels = BoxTransition.new(canvas, selectedPack, seams, initial)
	overlay.Parent = Players.LocalPlayer.PlayerGui
	overlay.Enabled = true
	return overlay, panels
end
local function closeForResults(stars)
	if transitioning then return end
	audio:play("win")
	transitioning, held, lastPoint = true, false, nil
	task.spawn(function()
		local overlay, panels = boxOverlay(false, 1, -1)
		-- Acquire the actual panel drawing instances before stretching them.
		-- Keep the level underneath until the replacement page has drawn.
		textures:surface(overlay)
		panels:set(0)
		RunService.RenderStepped:Wait()
		overlay.DisplayOrder = 90
		panels:animate(false)
		showResults(stars)
		while not pageLayer:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
		menuGui.Enabled, gui.Enabled = true, false
		LevelAudio.unbind(activeLevel)
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		overlay:Destroy()
		transitioning = false
	end)
end
local menuReady = false
local function preloadValues(values, onProgress)
	local ready = textures:preload(values, onProgress)
	menuGui:SetAttribute("LastPreloadFailures", textures.root:GetAttribute("LastFailures"))
	return ready
end
local function loadingPage(exiting)
	clearPage("LevelLoading")
	local cover = Sprites.Menu.covers[selectedPack]
	local left = menuImage("LoadingCoverLeft", cover, 633.5/2560, .5, 1293/2560, 1, 2,false,pageCover)
	left.ScaleType, left.ImageColor3 = Enum.ScaleType.Stretch, Color3.fromRGB(217, 217, 217)
	local right = menuImage("LoadingCoverRight", cover, 1926.5/2560, .5, 1293/2560, 1, 2,false,pageCover)
	right.ScaleType, right.Rotation, right.ImageColor3 = Enum.ScaleType.Stretch, 180, Color3.fromRGB(217, 217, 217)
	local tapeMask, tapeParent = nil, pageCover
	if exiting then
		tapeMask = Instance.new("Frame")
		tapeMask.Name, tapeMask.BackgroundTransparency, tapeMask.ClipsDescendants, tapeMask.ZIndex = "LoadingTapeMask", 1, true, 4
		tapeMask.Size, tapeMask.Parent = UDim2.fromScale(1, 0), pageCover
		tapeParent = Instance.new("Frame")
		tapeParent.Size = UDim2.fromOffset(2560,1440)
		tapeParent.BackgroundTransparency, tapeParent.ZIndex, tapeParent.Parent = 1, 4, tapeMask
	end
	menuImage("LoadingSpineLeft", Sprites.Menu.loading[1], 1245/2560, 732.5/1440, 60/2560, 1305/1440, 4, false, tapeParent).ScaleType = Enum.ScaleType.Stretch
	menuImage("LoadingSpineRight", Sprites.Menu.loading[2], 1306.5/2560, 732.5/1440, 67/2560, 1305/1440, 4, false, tapeParent).ScaleType = Enum.ScaleType.Stretch
	menuText("LoadingLabel", "Loading...", .5, .5, 300/2560, .068, 12)
	local rocket = menuImage(exiting and "LoadingTapeRoller" or "LoadingCutter", Sprites.Menu.loading[exiting and 3 or 4], 0, 0, (exiting and 307 or 837)/2560, (exiting and 407 or 791)/1440, 9,false,pageCover)
	rocket.AnchorPoint, rocket.ScaleType = Vector2.zero, Enum.ScaleType.Stretch
	rocket.Position = UDim2.fromScale((exiting and 1084 or 454)/2560, (exiting and -100 or 700)/1440)
	return rocket, tapeMask
end
local function goGame(withLoading)
	if transitioning then return end
	transitioning, held, lastPoint = true, false, nil
	if withLoading == nil then withLoading = true end
	task.spawn(function()
		if resultPresentation then resultPresentation:hide() end
		local rocket = withLoading and loadingPage() or nil
		local overlay, panels
		if not withLoading then
			overlay, panels = boxOverlay(false, gui.Enabled and 0 or 1)
			if gui.Enabled then panels:set(0) panels:animate(false) end
		end
		preloadValues({ levelBackground.Image, LevelBackground.seam, Sprites.Hud, Sprites.Candy01, Sprites.Hook,
			Atlas.pages, Effects.pages, HazardFrames.pages, HudFrames.pages, Sprites.OmNomSupport, Sprites.Bubble.shadows })
		if withLoading then
			while not pageLayer:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
			local elapsed = 0
			while elapsed < .5 do
				rocket.Position = UDim2.fromScale(454/2560, (700 - 1250 * math.min(1, elapsed/.5))/1440)
				elapsed += RunService.RenderStepped:Wait()
			end
			overlay, panels = boxOverlay(true)
		end
		surfacePending = true
		menuGui.Enabled, gui.Enabled, paused = false, true, false
		audio:setContext("game")
		if pauseLayer then pauseLayer:Destroy() pauseLayer = nil end
		resetLevel()
		textures:surface(gui)
		surfacePending = false
		panels:animate(true)
		overlay:Destroy()
		transitioning = false
	end)
end
local function leaveGame(callback)
	if transitioning then return end
	LevelAudio.unbind(activeLevel)
	audio:clearScene()
	audio:setContext("loading")
	transitioning, held, lastPoint = true, false, nil
	task.spawn(function()
		if resultPresentation then resultPresentation:hide() end
		local overlay, panels = boxOverlay(false, gui.Enabled and 0 or 1)
		if gui.Enabled then panels:set(0) panels:animate(false) end
		local cutter, tape = loadingPage(true)
		menuGui.Enabled, gui.Enabled, paused = true, false, false
		if pauseLayer then pauseLayer:Destroy() pauseLayer = nil end
		while not pageLayer:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
		overlay:Destroy()
		local elapsed = 0
		while elapsed < .5 do
			local progress = math.min(1, elapsed / .5)
			cutter.Position = UDim2.fromScale(1084/2560, (1120 * progress - 100)/1440)
			tape.Size = UDim2.fromScale(1, 1200 * progress / 1440)
			elapsed += RunService.RenderStepped:Wait()
		end
		transitioning = false
		transitionTo(callback)
	end)
end
local function backButton(callback)
	menuImage("MenuExtraButtonsQuad0Back", Sprites.Menu.back, .14, .92, .275, .15, 15,false,pageBack)
	local button = menuHitbox("BackHitbox", .045, .92, .09, .14, 16,pageBack)
	activateButton(button,function() transitionTo(callback) end)
end
local function showPlaceholder(title, backTo)
	clearPage("Placeholder")
	menuBackground(true)
	menuText("PlaceholderTitle", title, .5, .42, .5, .1, 5)
	menuText("PlaceholderInfo", "This screen is not ported yet", .5, .53, .5, .055, 5)
	backButton(backTo or showMain)
end
local function showSkins()
	clearPage("SkinSelection")
	SkinMenu.new(pageLayer)
	backButton(showMain)
end
showMain = function()
	clearPage("MainMenu")
	menuBackground(true)
	menuImage("MenuLogoNewQuad52", Sprites.Menu.logo, .5, .285, .37, .49, 5)
	local logoCandy = menuImage("MenuLogoCandy", "", .552, .475, .12, .2, 6)
	Atlas.new(logoCandy, {"logo"}, SkinFrames):show("logo", Session.candy)
	local candyAction = function() transitionTo(showSkins) end
	local candyButton = menuHitbox("LogoCandyButton", .552, .475, .095, .14, 12)
	activateButton(candyButton,candyAction)
	candyButton.MouseButton1Down:Connect(function() logoCandy.Size = UDim2.fromScale(.12 * .95, .2 * .95) end)
	local function restoreCandySize() logoCandy.Size = UDim2.fromScale(.12, .2) end
	candyButton.MouseButton1Up:Connect(restoreCandySize)
	candyButton.MouseLeave:Connect(restoreCandySize)
	if Session.claimTitleHint() then
		local hand = menuImage("CandySelectionFxQuad1Hand", Sprites.Menu.hand, .625, .51, .09, .15, 7)
		local hitbox = menuHitbox("LogoHandButton", .625, .51, .055, .10, 12)
		activateButton(hitbox,candyAction)
		local page = pageLayer
		task.spawn(function()
			while hand.Parent and (transitioning or not page:GetAttribute("PageReady")) do RunService.RenderStepped:Wait() end
			if not hand.Parent then return end
			local gesture = TweenService:Create(hand, TweenInfo.new(.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(.625 - 20/2560, .51) })
			gesture:Play()
			gesture.Completed:Wait()
			if not hand.Parent then return end
			local retract = TweenService:Create(hand, TweenInfo.new(.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(.625, .51) })
			retract:Play()
			retract.Completed:Wait()
			if not hand.Parent then return end
			hitbox:Destroy()
			local fade = TweenService:Create(hand, TweenInfo.new(.25), { ImageTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			hand:Destroy()
		end)
	end
	for index, entry in ipairs({
		{ "Play", .62, function() showPacks() end },
		{ "Options", .75, function() showOptions() end },
	}) do
		local art = menuImage("MenuButtonsQuad0_" .. index, "", .5, entry[2], .4, .295, 8)
		menuText("ButtonText_" .. index, entry[1], .5, entry[2], .22, .065, 10)
		local button = menuHitbox("MainMenuHitbox" .. index, .5, entry[2], .28, .11, 12)
		buttonStates(art, button, false)
		activateButton(button,function() transitionTo(entry[3]) end)
	end
end
local packNames = { "Cardboard Box", "Fabric Box", "Foil Box", "Magic Box", "Valentine's Box", "Toy Box", "Gift Box", "Cosmic Box", "Toolbox", "Buzz Box", "DJ Box", "Spooky Box", "Steam Box", "Lantern Box", "Cheese Box", "Pillow Box", "Mechanical" }
showPacks = function()
	clearPage("PackSelection")
	menuBackground(false)
	local page = pageLayer
	PackSelection.new(page, selectedPack, function(index) selectedPack = index end, function(index)
		if not Session.packUnlocked(index) then return end
		audio:play("tap","ui")
		selectedPack = index
		transitionTo(showLevels)
	end, function() return not transitioning and menuGui.Enabled and pageLayer == page and not page:GetAttribute("ModalOpen") end)
	menuText("TotalStars", string.format(Locale.get("TOTAL_STARS"), Session.total()), .928, .045, .095, .045, 11,pageTop)
	menuImage("MenuPackUiQuad3TotalStar", Sprites.Menu.star, .982, -.045, .55, .55, 12,false,pageTop)
	backButton(showMain)
end
showLevels = function()
	clearPage("Pack" .. selectedPack .. "LevelSelection")
	-- MenuController.CreateLevelSelect draws the same cover quad 0 twice,
	-- with the second copy rotated 180 degrees around the right half.
	local cover = Sprites.Menu.covers[selectedPack]
	local left = menuImage("BoxCoverQuad0Left", cover, .2525, .5, .505, 1, 2,false,pageCover)
	left.ScaleType, left.ImageColor3 = Enum.ScaleType.Stretch, Color3.fromRGB(217, 217, 217)
	local right = menuImage("BoxCoverQuad0Mirrored", cover, .7475, .5, .505, 1, 2,false,pageCover)
	right.ScaleType, right.Rotation, right.ImageColor3 = Enum.ScaleType.Stretch, 180, Color3.fromRGB(217, 217, 217)
	local coverShadow = menuImage("MenuBgrShadowQuad0", Sprites.Menu.shadow, .5, .5, 2, 2, 3,false,pageCover)
	coverShadow.Rotation = 45
	TweenService:Create(coverShadow, TweenInfo.new(75, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 405 }):Play()
	menuImage("MenuLevelUiQuad6SpineLeft", Sprites.Menu.loading[1], .486, .499, .0234, .906, 4,false,pageCover).ScaleType = Enum.ScaleType.Stretch
	menuImage("MenuLevelUiQuad7SpineRight", Sprites.Menu.loading[2], .510, .499, .0262, .906, 4,false,pageCover).ScaleType = Enum.ScaleType.Stretch
	for row = 1, 5 do
		for column = 1, 5 do
			local index = (row - 1) * 5 + column
			local x, y = .320 + (column - 1) * .0895, .136 + (row - 1) * .181
			local unlocked = Session.levelUnlocked(selectedPack,index)
			local card = menuImage("MenuLevelUiQuad0Level" .. index, unlocked and Sprites.Menu.levelOpen or Sprites.Menu.levelLocked, x, y, .086, .15, 5, true)
			card.Interactable = unlocked
			card:SetAttribute("Unlocked",unlocked)
			if unlocked then menuText("Level" .. index .. "Label", tostring(index), x, y, .04, .06, 7) end
			if unlocked and LevelData.supported(selectedPack, index) then
				local earned = Session.record(selectedPack, index).stars
				menuImage("MenuLevelUiStars" .. earned, Sprites.Menu.levelBadges[earned + 1], x, y, .103, .17, 7)
			end
			activateButton(card,function()
				if not Session.levelUnlocked(selectedPack,index) then return end
				if LevelData.supported(selectedPack, index) then
					levelIndex = index
					goGame()
				else
					transitionTo(function() showPlaceholder(packNames[selectedPack] .. " - level " .. index, showLevels) end)
				end
			end)
		end
	end
	menuText("BoxStarCount", Session.total(selectedPack) .. "/75", .935, .045, .066, .045, 10,pageTop)
	menuImage("MenuPackUiQuad3BoxStar", Sprites.Menu.star, .982, -.045, .55, .55, 11,false,pageTop)
	backButton(showPacks)
end
local function darkText(name, value, x, y, width, height, z, parent)
	value = Locale.text(value)
	local out = menuText(name, value, x, y, width, height, z, parent, true)
	out.TextColor3, out.TextStrokeTransparency = Color3.fromRGB(26, 20, 14), 1
	BitmapFont.render(out, value, SmallFont)
	return out
end
local function longRedButton(name, value, x, y, callback, parent, z)
	local art = menuImage(name .. "Art", "", x, y, .4, .295, z or 8, false, parent)
	menuText(name .. "Text", value, x, y, .25, .065, (z or 8) + 2, parent)
	local button = menuHitbox(name, x, y, .28, .11, (z or 8) + 4, parent)
	buttonStates(art, button, false)
	activateButton(button,callback)
	return button
end
local function shortRedButton(name, value, x, y, callback, parent, z, selected)
	local art = menuImage(name .. "Art", "", x, y, .37, .29, z or 8, false, parent)
	menuText(name .. "Text", value, x, y, .18, .065, (z or 8) + 2, parent)
	local button = menuHitbox(name, x, y, .16, .11, (z or 8) + 4, parent)
	buttonStates(art, button, true, selected)
	activateButton(button,callback)
	return button
end
local function showReset()
	clearPage("ResetConfirmation")
	menuBackground(false)
	menuText("ResetQuestion", "Are you sure you want to reset your progress?", .5, .35, .62, .065, 10)
	longRedButton("ConfirmResetYes", "Yes", .5, .625, function()
		Session.reset()
		bestStars = 0
		transitionTo(showOptions)
	end)
	longRedButton("ConfirmResetNo", "No", .5, .778, function() transitionTo(showOptions) end)
	backButton(showOptions)
end
local function showCredits()
	clearPage("Credits")
	menuBackground(false)
	local creditsCanvas=Instance.new("Frame")
	creditsCanvas.Name,creditsCanvas.BackgroundTransparency,creditsCanvas.ZIndex="CreditsCanvas",1,6
	creditsCanvas.AnchorPoint,creditsCanvas.Position,creditsCanvas.Parent=Vector2.new(.5,.5),UDim2.fromScale(.5,.5),pageLayer
	local creditsScale=Instance.new("UIScale",creditsCanvas)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CreditsScroll"
	scroll.AnchorPoint, scroll.Position = Vector2.new(.5, .5), UDim2.fromScale(.5, .5)
	scroll.Size, scroll.CanvasSize = UDim2.fromScale(.58, 1), UDim2.new()
	scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
	scroll.AutomaticCanvasSize, scroll.ScrollingDirection = Enum.AutomaticSize.Y, Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness, scroll.ZIndex, scroll.Parent = 0, 6, creditsCanvas
	local function resizeCredits()
		local view=Layout.compute(menuBoard.AbsoluteSize)
		creditsScale.Scale=view.pixels*view.content
		creditsCanvas.Size=UDim2.fromOffset(2560,view.visible.Y/view.content)
		scroll.Size=UDim2.fromOffset(math.min(1300,view.visible.X-96)/view.content,(view.visible.Y-340)/view.content)
	end
	local creditsResize=menuBoard:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeCredits)
	creditsCanvas.Destroying:Connect(function() creditsResize:Disconnect() end)
	resizeCredits()
	scroll.TopImage, scroll.MidImage, scroll.BottomImage = "", "", ""
	local layout = Instance.new("UIListLayout", scroll)
	layout.HorizontalAlignment, layout.SortOrder = Enum.HorizontalAlignment.Center, Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 55)
	local padding = Instance.new("UIPadding", scroll)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 114), UDim.new(0, 229)
	local logo = Instance.new("ImageLabel")
	logo.Name, logo.Image, logo.BackgroundTransparency = "CreditsDxLogo", Sprites.Menu.creditsLogo, 1
	logo.Size, logo.ScaleType, logo.ZIndex, logo.Parent = UDim2.new(1, 0, 0, 480), Enum.ScaleType.Fit, 7, scroll
	for index, value in ipairs(Credits) do
		local text = Instance.new("TextLabel")
		text.Name, text.Text, text.LayoutOrder = "CreditBlock" .. index, Locale.text(value), index
		text.Size = UDim2.new(1, -69, 0, 1)
		text.TextColor3, text.TextStrokeTransparency = Color3.new(0, 0, 0), 1
		text.BackgroundTransparency, text.ZIndex, text.Parent = 1, 7, scroll
		BitmapFont.block(text, Locale.text(value), SmallFont, creditsCanvas)
	end
	local automatic = true
	DragScroll.attach(scroll,function() automatic=false end)
	scroll.InputBegan:Connect(function() automatic = false end)
	scroll.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then automatic = false end
	end)
	task.spawn(function()
		while scroll.Parent do
			local dt = RunService.Heartbeat:Wait()
			if automatic then
				local maximum = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
				scroll.CanvasPosition = Vector2.new(0, math.min(maximum, scroll.CanvasPosition.Y + 30 * dt))
			end
		end
	end)
	backButton(showOptions)
end
local function showLanguages()
	clearPage("LanguageSelection")
	menuBackground(false)
	pageLayer:SetAttribute("SelectedLocale", Session.locale)
	for index, code in ipairs(Locale.codes) do
		local x = .5 + ((index - 1) % 3 - 1) * .20
		local y = .29 + math.floor((index - 1) / 3) * .14
		local button = shortRedButton("Language_" .. code, Locale.names[index], x, y, function()
			Locale.set(code)
			showLanguages()
		end, nil, nil, Session.locale == code)
		button:SetAttribute("Selected", Session.locale == code)
	end
	backButton(showOptions)
end
showOptions = function()
	clearPage("Options")
	menuBackground(false)
	pageLayer:SetAttribute("CutMode", Session.drag and "drag" or "click")
	local function toggle(name, x, icon, enabled, callback)
		local button = menuImage(name, Sprites.Menu.optionsButton, x, .15, .14, .13, 8, true)
		menuImage(name .. "Icon", icon, x, .15, .067, .11, 10)
		if not enabled then menuImage(name .. "Disabled", Sprites.Menu.disabled, x, .15, .058, .09, 11) end
		activateButton(button,callback)
	end
	toggle("SoundToggle", .43, Sprites.Menu.sound, Session.sound, function() audio:setSound(not Session.sound) showOptions() end)
	toggle("MusicToggle", .57, Sprites.Menu.music, Session.music, function() audio:setMusic(not Session.music) showOptions() end)
	longRedButton("LanguageButton", "Language", .5, .274, function() transitionTo(showLanguages) end)
	longRedButton("ResetGameButton", "Reset game", .5, .398, function() transitionTo(showReset) end)
	longRedButton("CreditsButton", "Credits", .5, .525, function() transitionTo(showCredits) end)
	menuImage("MenuOptionsPackedQuad5Drag", Sprites.Menu.drag, .44, .71, .105, .25, 8)
	menuImage("MenuOptionsPackedQuad6Click", Sprites.Menu.click, .56, .71, .105, .25, 8)
	darkText("DragToCut", "Drag to cut", .44, .85, .13, .042, 10)
	darkText("ClickToCut", "Click to cut", .56, .85, .13, .042, 10)
	menuImage("DragSelected", Session.drag and Sprites.Menu.check or Sprites.Menu.unchecked, .44, .9, .04, .055, 10)
	menuImage("ClickSelected", Session.drag and Sprites.Menu.unchecked or Sprites.Menu.check, .56, .9, .04, .055, 10)
	local drag = menuHitbox("DragModeButton", .44, .76, .115, .345, 12)
	local click = menuHitbox("ClickModeButton", .56, .76, .115, .345, 12)
	activateButton(drag,function() Session.drag = true showOptions() end)
	activateButton(click,function() Session.drag = false showOptions() end)
	pageLayer:SetAttribute("UnlockAll",Session.unlockAll)
	local saveState=Players.LocalPlayer.PlayerGui:FindFirstChild("DxSaveState")
	local saveStatus=saveState and saveState:GetAttribute("Status")
	if saveStatus and saveStatus~="Saved" and saveStatus~="Pending" and saveStatus~="StudioSession" then
		darkText("SaveUnavailable","Save unavailable. This session will not replace your saved progress.",.5,.045,.65,.032,12)
	end
	menuImage("UnlockAllCheck",Session.unlockAll and Sprites.Menu.check or Sprites.Menu.unchecked,.64,.965,.028,.039,10)
	darkText("UnlockAllLabel","Unlock all levels",.49,.965,.24,.035,10)
	local unlock=menuHitbox("UnlockAllToggle",.51,.965,.32,.055,12)
	activateButton(unlock,function() Session.setUnlockAll(not Session.unlockAll) showOptions() end)
	backButton(showMain)
end

showResults = function(collected)
	local result = activeResult or Session.result(elapsedTime, collected)
	-- Never enable the stale MainMenu/LevelLoading page during this handoff.
	-- closeForResults switches surfaces only after PageReady under closed panels.
	pageLayer.Visible, paused = false, false
	clearPage("LevelResults")
	menuBackground(false)
	local resultCover = menuImage("Bgr01CoverQuad0", Sprites.Menu.covers[selectedPack], 633.5/2560, .5, 1293/2560, 1, 2,false,pageCover)
	resultCover.ScaleType, resultCover.ImageColor3 = Enum.ScaleType.Stretch, Color3.fromRGB(217, 217, 217)
	local mirroredCover = menuImage("Bgr01CoverQuad0Mirrored", Sprites.Menu.covers[selectedPack], 1926.5/2560, .5, 1293/2560, 1, 2,false,pageCover)
	mirroredCover.ScaleType, mirroredCover.Rotation = Enum.ScaleType.Stretch, 180
	mirroredCover.ImageColor3 = Color3.fromRGB(217, 217, 217)
	if collected == 3 then resultConfetti = ResultConfetti.new(pageLayer) end
	menuText("ResultHeading", ({"Passable!", "Good!", "Great!", "Excellent!"})[collected + 1], .5, .214, .4, .064, 10)
	for i = 1, 3 do
		local x = .414 + (i - 1) * .081
		menuImage("ResultStarShadow" .. i, Sprites.Menu.resultShadow, x, .343, .085, .15, 8)
		if i <= collected then
			-- Quad 13 is 230x220 at (815,349); slot 14 is 212x205 at (824,357).
			local pixels = .085 * 2560 / 212
			menuImage("ResultStar" .. i, Sprites.Menu.resultStar, x, .343 - .5 * pixels / 1440, 230 * pixels / 2560, 220 * pixels / 1440, 9)
		end
	end
	darkText("StarBonus", "Star Bonus", .445, .455, .12, .04, 10)
	darkText("StarBonusScore", tostring(result.starbonus), .57, .455, .07, .04, 10)
	menuImage("ResultDottedLine", Sprites.Menu.resultDots, .5, .53, .24, .012, 8)
	darkText("LevelScore", tostring(result.score), .5, .569, .1, .05, 10)
	pageLayer:SetAttribute("Score", result.score)
	pageLayer:SetAttribute("ElapsedSeconds", result.elapsed)
	pageLayer:SetAttribute("Stars", collected)
	shortRedButton("ReplayButton", "Replay", .414, .69, function() if not transitioning then goGame(false) end end)
	shortRedButton("NextButton", "Next", .586, .69, function()
		if transitioning then return end
		if LevelData.supported(selectedPack, levelIndex + 1) then levelIndex += 1 goGame(false)
		else
			local finished=selectedPack==17 and levelIndex==25
			leaveGame(function()
				showPacks()
				if finished then FinishedPopup.show(pageLayer,textures,function() audio:play("tap","ui") end) end
			end)
		end
	end)
	shortRedButton("ResultMenuButton", "Menu", .5, .825, function() leaveGame(showLevels) end)
	if result.improved then menuImage("ImprovedResultStamp", Sprites.Menu.resultStamp, 1616/2560, 767/1440, 239/2560, 238/1440, 12).Visible = false end
	resultPresentation = ResultPresentation.new(pageContent, result)
end

local function resumeGame()
	paused = false
	audio:setPaused(false)
	if pauseLayer then pauseLayer:Destroy() pauseLayer = nil end
	gui:SetAttribute("Paused", false)
end

local function skipLevel()
	if transitioning then return end
	transitioning = true
	task.spawn(function()
		-- Stage the next level behind the current pause screen, then swap it
		-- atomically. No fade, cutter, box panels, or half-loaded first frame.
		local stage
		local ok, message = xpcall(function()
			Session.unlockNext(selectedPack,levelIndex)
			if LevelData.supported(selectedPack, levelIndex + 1) then
				stage = Instance.new("Frame")
				-- Visible-but-occluded crops acquire Roblox drawable textures;
				-- Visible=false crops can remain unloaded after PreloadAsync.
				stage.Name, stage.BackgroundTransparency, stage.ZIndex = "PreparedGameLayer", 1, 0
				stage.Size, stage.Parent = UDim2.fromScale(1, 1), board
				local prepared = LevelRuntime.new(stage, LevelData.get(levelIndex + 1, selectedPack),Layout.compute(board.AbsoluteSize).visible)
				textures:surface(stage)
				levelIndex += 1
				resetLevel(prepared)
				stage = nil
				menuGui.Enabled, gui.Enabled = false, true
			else
				LevelAudio.unbind(activeLevel)
				audio:clearScene()
				showLevels()
				while pageLayer.Parent and not pageLayer:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
				gui.Enabled, menuGui.Enabled = false, true
			end
			resumeGame()
		end, debug.traceback)
		if stage then stage:Destroy() end
		if not ok then warn("DX instant skip failed: " .. tostring(message)) end
		transitioning = false
	end)
end

showPause = function()
	if pauseLayer then pauseLayer:Destroy() end
	paused = true
	audio:setPaused(true)
	gui:SetAttribute("Paused", true)
	fingerTrace:reset()
	held, lastPoint = false, nil
	objectHeld = false
	if activeLevel then activeLevel:release() end
	pauseLayer = Instance.new("Frame")
	pauseLayer.Name, pauseLayer.Size, pauseLayer.BackgroundColor3 = "PauseOverlay", UDim2.fromScale(1, 1), Color3.new(0, 0, 0)
	pauseLayer.BackgroundTransparency, pauseLayer.BorderSizePixel, pauseLayer.ZIndex, pauseLayer.Parent = .54, 0, 30, board
	local content=Layout.group(pauseLayer,"PauseContent","content",{760,200,1800,1220},nil,32)
	local top=Layout.group(pauseLayer,"PauseTop","cover",nil,Vector2.new(.5,0),31)
	local corner=Layout.group(pauseLayer,"PauseCorner","content",nil,Vector2.new(1,0),33)
	menuImage("MenuPauseQuad0Top", Sprites.Menu.pauseTop, .5, .135, 1, .27, 31, false, top)
	darkText("BestScore", Locale.get("BEST_SCORE") .. ": " .. Session.record(selectedPack, levelIndex).score, .905, .045, .18, .05, 33, corner)
	longRedButton("ContinueButton", "Continue", .5, .245, function() if not transitioning then resumeGame() end end, content, 32)
	longRedButton("SkipLevelButton", "Skip level", .5, .37, skipLevel, content, 32)
	longRedButton("LevelSelectButton", "Level select", .5, .494, function() leaveGame(showLevels) end, content, 32)
	longRedButton("MainMenuButton", "Main menu", .5, .621, function() leaveGame(showMain) end, content, 32)
	local function pauseAudio(name, x, icon, enabled, callback)
		local button = menuImage(name, Sprites.Menu.optionsButton, x, .752, .14, .13, 32, true, content)
		menuImage(name .. "Icon", icon, x, .752, .067, .11, 34, false, content)
		if not enabled then menuImage(name .. "Disabled", Sprites.Menu.disabled, x, .752, .058, .09, 35, false, content) end
		activateButton(button,callback)
	end
	pauseAudio("PauseSound", .43, Sprites.Menu.sound, Session.sound, function() audio:setSound(not Session.sound) showPause() end)
	pauseAudio("PauseMusic", .57, Sprites.Menu.music, Session.music, function() audio:setMusic(not Session.music) showPause() end)
end

local function showSplash()
	clearPage("ZeptolabSplash")
	local white = Instance.new("Frame")
	white.Size, white.BackgroundColor3, white.BorderSizePixel, white.Parent = UDim2.fromScale(1, 1), Color3.new(1, 1, 1), 0, pageLayer
	local disclaimer = "Original game by ZeptoLab.\nCut the Rope: DX is not, and will never be affiliated with or endorsed by ZeptoLab.\nAll rights to the original game and its assets belong to ZeptoLab."
	local legal = menuText("OriginalGameAttribution", disclaimer, .5, .91, .75, .105, 6, nil, true)
	legal.TextColor3, legal.TextStrokeTransparency = Color3.new(0, 0, 0), 1
	BitmapFont.render(legal, legal.Text, SmallFont, {lineheight=78})
	task.delay(2, function()
		while pageLayer.Name == "ZeptolabSplash" and not menuReady do task.wait(.05) end
		if pageLayer.Name == "ZeptolabSplash" then transitionTo(showMain) end
	end)
end
local function restartGame()
	if transitioning or not gui.Enabled or not activeLevel or GuiService.MenuIsOpen then return end
	transitionTo(function() resumeGame() resetLevel() end, Color3.new(1, 1, 1), .15)
end
local function togglePause()
	if transitioning or not gui.Enabled or not activeLevel or GuiService.MenuIsOpen then return end
	if paused then resumeGame() else showPause() end
end
activateButton(reset,restartGame)
activateButton(menu,togglePause)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.R then
		if gui.Enabled and not transitioning then audio:play("tap","ui") end
		restartGame()
	elseif input.KeyCode == Enum.KeyCode.P or input.KeyCode == Enum.KeyCode.Pause then
		if gui.Enabled and not transitioning then audio:play("tap","ui") end
		togglePause()
	elseif input.KeyCode == Enum.KeyCode.Space and gui.Enabled and activeLevel and not paused and not transitioning and not GuiService.MenuIsOpen then activeLevel:gravityShortcut() end
end)
-- Escape belongs to Roblox. Pause underneath its menu rather than attempting
-- to intercept a reserved key; closing it leaves our Continue/P controls ready.
GuiService.MenuOpened:Connect(function()
	if gui.Enabled and not paused and not transitioning then showPause() end
end)

RunService.RenderStepped:Connect(function(dt)
	if focusSuspended then return end
	if GuiService.MenuIsOpen then
		if gui.Enabled and not paused and not transitioning then showPause() end
		return
	end
	if gui.Enabled and not paused then fingerTrace:update(dt) else fingerTrace:reset() end
	if resultConfetti and resultConfetti.parent == pageLayer and pageLayer.Visible and menuGui.Enabled and not transitioning then
		resultConfetti:update(dt)
	end
	if resultPresentation and pageLayer.Visible and menuGui.Enabled and not transitioning then resultPresentation:update(dt) end
	if RunService:IsStudio() and layer:GetAttribute("DebugFreeze") then return end
	if not activeLevel or not gui.Enabled or paused then return end
	if surfacePending then return end
	activeLevel:present()
	scrollingBackground:update(activeLevel.camera,activeLevel.physics)
	hud:update(activeLevel.presentationDelta or 0,activeLevel.count)
end)

RunService.Heartbeat:Connect(function(dt)
	if focusSuspended or GuiService.MenuIsOpen or (RunService:IsStudio() and layer:GetAttribute("DebugFreeze")) then return end
	if focusJustResumed then dt, focusJustResumed = 0, false end
	if not activeLevel or not gui.Enabled or paused or surfacePending then return end
	layer:SetAttribute("SimulationDuringTransition", transitioning)
	local wasPlaying = activeLevel.state == "playing"
	activeLevel:advance(dt)
	elapsedTime = activeLevel.elapsed
	if wasPlaying and activeLevel.state ~= "playing" then
		activeLevel.outcomeTime = activeLevel.outcomeTime or activeLevel.clock
		if activeLevel.state == "won" then
			activeResult = Session.result(elapsedTime, activeLevel.count)
			local previous = Session.record(selectedPack, levelIndex)
			activeResult.improved = (previous.score > 0 and activeResult.score > previous.score) or (previous.stars > 0 and activeResult.stars > previous.stars)
			Session.complete(selectedPack, levelIndex, activeResult)
			bestStars = Session.record(1, 1).stars
		end
	end
	if activeLevel.outcomeTime and not activeLevel.outcomeHandled and not transitioning then
		local delay = activeLevel.state == "won" and 2 or (activeLevel.lossDelay or 1)
		if activeLevel.clock - activeLevel.outcomeTime >= delay then
			activeLevel.outcomeHandled = true
			if activeLevel.state == "won" then
				local stars = activeResult.stars
				closeForResults(stars)
			else transitionTo(resetLevel, Color3.new(1, 1, 1), .15) end
		end
	end
end)
resetLevel()
showSplash()
task.spawn(function()
	preloadValues({ Sprites.Menu, PackSelection.atlas, Sprites.Hud, BitmapFont.image, SmallFont.image, LocaleFonts, SkinFrames.pages, SkinMenu.background, TraceFrames.pages,
		OmNomFrames, BoxFrames, SplitFrames, WheelFrames, AdvancedFrames, DiscFrames, GhostFrames, SteamFrames, LanternFrames, CheeseFrames, PillowFrames, MechanicalFrames, Atlas.pages, Effects.pages, HazardFrames.pages, HudFrames.pages, tiledBackground.Image, levelBackground.Image, LevelBackground.seam, Sprites.Candy01,
		Sprites.Hook, Sprites.OmNomSupport, Sprites.Bubble.shadows })
	menuReady = true
end)
if RunService:IsStudio() then
	gui:GetAttributeChangedSignal("DxStudioResult"):Connect(function()
		if not Session.unlockAll or transitioning or not gui.Enabled or not activeLevel then return end
		activeLevel.state,activeLevel.count,activeLevel.outcomeHandled="won",3,true
		activeLevel.outcomeTime=activeLevel.clock
		activeResult=Session.result(activeLevel.elapsed,3)
		Session.complete(selectedPack,levelIndex,activeResult)
		closeForResults(3)
	end)
	local request = Instance.new("BindableEvent")
	request.Name, request.Parent = "DxStudioLoadLevel", gui
	request.Event:Connect(function(pack, index)
		if transitioning or not menuReady or not LevelData.supported(pack, index) then return end
		selectedPack, levelIndex = pack, index
		goGame(false)
	end)
	-- Studio's capability-isolated bridge cannot fire a game's BindableEvent.
	gui:GetAttributeChangedSignal("DxStudioLevel"):Connect(function()
		local value = gui:GetAttribute("DxStudioLevel")
		local pack, index = tostring(value):match("^(%d+)_(%d+)")
		pack, index = tonumber(pack), tonumber(index)
		if pack and index then request:Fire(pack, index) end
	end)
end
