-- GameScene.Init HUD quad 1..11; GameScene.Show's level-label timeline.
local Atlas = require(script.Parent.AtlasSprite)
local Frames = require(script.Parent.HudFrames)
local Font = require(script.Parent.BitmapFont)
local Locale = require(script.Parent.Localization)
local Layout = require(script.Parent.ViewportLayout)
local hud = {}
hud.__index = hud
function hud.new(board, stars)
	local self = setmetatable({stars = {}, time = 0, collected = {}}, hud)
	for _, parent in ipairs(stars) do
		local sprite = Atlas.new(parent, {"hud"}, Frames, {hud={1,2,3,4,5,6,7,8,9,10,11}})
		sprite:fade(.35)
		sprite:show("hud", 1)
		table.insert(self.stars, sprite)
	end
	self.label = Instance.new("CanvasGroup")
	self.label.Name, self.label.BackgroundTransparency, self.label.ZIndex = "LevelLabel", 1, 20
	self.label.Position, self.label.Size = UDim2.fromScale(0, 0), UDim2.fromScale(1, 1)
	self.label.GroupTransparency, self.label.Parent = 1, board
	local design = Instance.new("Frame")
	design.Name, design.Size, design.BackgroundTransparency, design.Parent = "Design", UDim2.fromOffset(2560, 1440), 1, self.label
	Layout.bind(design, self.label, "content", nil, Vector2.new(0,1))
	self.texts = {}
	for index, name in ipairs({"Number", "Level"}) do
		local text = Instance.new("TextLabel")
		text.Name, text.BackgroundTransparency, text.ZIndex = name, 1, 20
		text.AnchorPoint, text.Parent = Vector2.new(0, 1), design
		self.texts[name] = text
	end
	return self
end
function hud:reset(pack, level)
	self.time, self.collected = 0, {}
	for _, sprite in ipairs(self.stars) do sprite:show("hud", 1) end
	local value, secondary = pack .. " - " .. level, Locale.get("LEVEL")
	local width, em, ratio = Font.measure(value)
	local session = require(script.Parent.SessionState)
	local latin = not table.find({"ru", "ko", "ja", "zh", "zh_tw"}, session.locale)
	local scale = latin and em or 1
	local height, chinese = 100 * ratio - 10, session.locale == "zh" or session.locale == "zh_tw"
	local bottom = 1440 - (chinese and 20 or 5)
	local number, leveltext = self.texts.Number, self.texts.Level
	number.Position, number.Size = UDim2.fromOffset(40, bottom), UDim2.fromOffset(width * scale, height)
	leveltext.Position = UDim2.fromOffset(40, bottom - height + (chinese and 3 or 30) - 12)
	leveltext.Size = UDim2.fromOffset(Font.measure(secondary) * scale * .7, height * .7)
	Font.render(number, value, nil, {scale = scale, left = true, y = -10})
	Font.render(leveltext, secondary, nil, {scale = scale * .7, left = true, y = -7})
	self.label.GroupTransparency = 1
end
function hud:update(dt, count)
	self.time += dt
	for index, sprite in ipairs(self.stars) do
		if index <= count then
			self.collected[index] = self.collected[index] or self.time
			sprite:show("hud", math.min(11, 1 + math.floor((self.time - self.collected[index]) / .05 + 1e-6)))
		end
	end
	local t = self.time
	local alpha = t < .5 and 0 or t < 1 and (t - .5) * 2 or t < 2 and 1 or math.max(0, 1 - (t - 2) * 2)
	self.label.GroupTransparency = 1 - alpha
end
return hud
