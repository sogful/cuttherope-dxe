local Frames = require(script.Parent.SkinFrames)
local Font = require(script.Parent.BitmapFont)
local Locale = require(script.Parent.Localization)
local Session = require(script.Parent.SessionState)
local TraceFrames = require(script.Parent.TraceFrames)
local Atlas = require(script.Parent.AtlasSprite)
local TargetAnimator = require(script.Parent.TargetAnimator)
local XmlTargetAnimator = require(script.Parent.XmlTargetAnimator)
local OmNomFrames = require(script.Parent.OmNomFrames)
local Availability = require(script.Parent.SkinAvailability)
local RunService = game:GetService("RunService")
local Layout = require(script.Parent.ViewportLayout)
local DragScroll = require(script.Parent.DragScroll)
local menu = {}
menu.background = "rbxassetid://108840607015492"

local function picture(parent, name, group, index, x, y, width, height, z)
	local label = Instance.new("ImageLabel")
	label.Name, label.BackgroundTransparency = name, 1
	label.AnchorPoint, label.Position = Vector2.new(.5, .5), UDim2.fromOffset(x, y)
	local q = Frames[group][index + 1]
	label.Image, label.ImageRectOffset = Frames.pages[q[1]], Vector2.new(q[2], q[3])
	label.ImageRectSize, label.Size = Vector2.new(q[4], q[5]), UDim2.fromOffset(width or q[4], height or q[5])
	label.ZIndex, label.Parent = z or 5, parent
	return label
end
local function setquad(label, group, index)
	local q = Frames[group][index + 1]
	label.Image, label.ImageRectOffset, label.ImageRectSize = Frames.pages[q[1]], Vector2.new(q[2], q[3]), Vector2.new(q[4], q[5])
end
local function text(parent, name, value, x, y, width, height)
	local label = Instance.new("TextLabel")
	label.Name, label.Text, label.BackgroundTransparency = name, value, 1
	label.AnchorPoint, label.Position = Vector2.new(.5, .5), UDim2.fromOffset(x, y)
	label.Size, label.ZIndex = UDim2.fromOffset(width, height), 9
	label.Font, label.TextScaled, label.TextColor3 = Enum.Font.FredokaOne, true, Color3.new(1, 1, 1)
	label.TextStrokeTransparency, label.Parent = 0, parent
	Font.render(label, value)
	return label
end
local function hit(parent, name, x, y, width, height)
	local button = Instance.new("TextButton")
	button.Name, button.Text, button.BackgroundTransparency = name, "", 1
	button.AnchorPoint, button.Position = Vector2.new(.5, .5), UDim2.fromOffset(x, y)
	button.Size, button.ZIndex, button.Parent = UDim2.fromOffset(width, height), 12, parent
	return button
end
function menu.new(page)
	local background = Instance.new("ImageLabel")
	background.Name, background.Image, background.BackgroundTransparency = "SkinBackground", menu.background, 1
	background.Size, background.ScaleType, background.Parent = UDim2.fromScale(1, 1), Enum.ScaleType.Crop, page
	local root = Instance.new("Frame")
	root.Name, root.Size, root.BackgroundTransparency, root.Parent = "SkinDesignCanvas", UDim2.fromOffset(2560, 1440), 1, page
	Layout.bind(root,page,"content",{555,45,2005,1340})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name, scroll.BackgroundTransparency, scroll.BorderSizePixel = "SkinGrid", 1, 0
	scroll.Position, scroll.Size = UDim2.fromOffset(708, 220), UDim2.fromOffset(1144, 1100)
	scroll.ScrollBarThickness, scroll.ScrollingDirection = 0, Enum.ScrollingDirection.Y
	scroll.TopImage, scroll.MidImage, scroll.BottomImage = "", "", ""
	scroll.ZIndex, scroll.Parent = 4, root
	local scrolling = DragScroll.attach(scroll)
	local tabs, active = {}, "candy"
	local previewAnimator
	local animation = RunService.RenderStepped:Connect(function(dt)
		if previewAnimator and page.Visible then previewAnimator:update(dt) end
	end)
	page.Destroying:Connect(function() animation:Disconnect() end)
	local function populate(mode)
		scrolling.stop()
		previewAnimator = nil
		active = mode
		page:SetAttribute("SkinTab", mode)
		for key, tab in pairs(tabs) do setquad(tab, "selection", key == mode and 5 or 4) end
		scroll:ClearAllChildren()
		scroll.CanvasPosition = Vector2.zero
		local count = mode == "candy" and 52 or mode == "rope" and 9 or mode == "trace" and 11 or 16
		local rows = math.ceil(count / 4)
		scroll.CanvasSize = UDim2.fromOffset(1144, rows * 413.2 - 10)
		local slots = {}
		if mode == "omnom" and not Availability.check(Session.omnom) then Session.omnom = 0 end
		for index = 0, count - 1 do
			local x, y = 135.5 + index % 4 * 291, 201.6 + math.floor(index / 4) * 413.2
			local function selected() return Session[mode] == index end
			local art = picture(scroll, "SlotArt" .. index, "selection", selected() and 2 or 0, x, y, 271, 336)
			local slotAnimator
			local available, reason = true, nil
			if mode == "omnom" then available, reason = Availability.check(index) end
			if not available then
				text(scroll, "Unavailable" .. index, "Unavailable", x, y, 240, 50)
			elseif mode == "trace" or mode == "omnom" then
				local preview = Instance.new("Frame")
				preview.Name, preview.BackgroundTransparency = "Preview" .. index, 1
				preview.AnchorPoint, preview.Position = Vector2.new(.5,.5), UDim2.fromOffset(x,y-(mode=="omnom" and 10 or 20))
				local size = mode == "omnom" and (index == 0 and 480 or OmNomFrames[index].canvas * 1.25 / 1.73) or 234
				preview.Size, preview.ZIndex, preview.Parent = UDim2.fromOffset(size,size),6,scroll
				if mode == "trace" then Atlas.new(preview,{"previews"},TraceFrames):show("previews",index)
				elseif index == 0 then slotAnimator = TargetAnimator.new(preview)
				else slotAnimator = XmlTargetAnimator.new(preview, index) slotAnimator:preview() end
				if slotAnimator and selected() then
					previewAnimator = slotAnimator
					if index > 0 then slotAnimator:activatePreview() end
				end
			else
				picture(scroll, "Preview" .. index, "selection", (mode == "candy" and 6 or 60) + index, x, y - 20, nil, nil, 6)
			end
			local button = hit(scroll, "Select_" .. mode .. index, x, y, 271, 336)
			slots[index] = {art = art, button = button, animator = slotAnimator}
			button:SetAttribute("Equipped", selected())
			button:SetAttribute("Available", available)
			button:SetAttribute("UnavailableReason", reason)
			button.MouseButton1Down:Connect(function() setquad(art, "selection", selected() and 3 or 1) end)
			button.MouseButton1Up:Connect(function() setquad(art, "selection", selected() and 2 or 0) end)
			button.MouseLeave:Connect(function() setquad(art, "selection", selected() and 2 or 0) end)
			button.Activated:Connect(function()
				if not available or DragScroll.blocked(scroll) then return end
				Session[mode] = index
				if mode == "candy" then Session.candyChanged = true end
				page:SetAttribute("Selected" .. mode, index)
				for number, slot in pairs(slots) do
					setquad(slot.art, "selection", number == index and 2 or 0)
					slot.button:SetAttribute("Equipped", number == index)
					if slot.animator then
						if number == index then
							previewAnimator = slot.animator
							if number > 0 then slot.animator:activatePreview() else slot.animator:play("idle") end
						elseif number > 0 then slot.animator:preview()
						else slot.animator:play("idle") end
					end
				end
			end)
		end
	end
	for index, entry in ipairs({{"candy", "CANDIES_BTN"}, {"rope", "ROPE_SKINS_BTN"}, {"omnom", "OM_NOM_BTN"}, {"trace", "TRACES_BTN"}}) do
		local x = 1280 + (index - 2.5) * 364
		tabs[entry[1]] = picture(root, "TabArt_" .. entry[1], "selection", 4, x, 120, 340, 140)
		text(root, "TabText_" .. entry[1], Locale.get(entry[2]), x, 120, 300, 68)
		hit(root, "Tab_" .. entry[1], x, 120, 340, 140).Activated:Connect(function() populate(entry[1]) end)
	end
	populate(active)
end
return menu
