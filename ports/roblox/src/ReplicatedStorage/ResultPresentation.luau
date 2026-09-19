-- BoxOpenClose.Update: star bonus, time countdown, final score; .2/1 second phases.
local Font = require(script.Parent.BitmapFont)
local Small = require(script.Parent.SmallFont)
local Locale = require(script.Parent.Localization)
local TweenService = game:GetService("TweenService")
local presentation = {}
presentation.__index = presentation
function presentation.new(page, result)
	local group = Instance.new("CanvasGroup")
	group.Name, group.Size, group.BackgroundTransparency = "ResultContent", UDim2.fromScale(1, 1), 1
	group.ZIndex, group.GroupTransparency, group.Parent = 10, 1, page
	local refs = {}
	for _, object in ipairs(page:GetChildren()) do
		if object ~= group and object:IsA("GuiObject") and object.ZIndex >= 8 then
			refs[object.Name] = object
			object.Parent = group
		end
	end
	return setmetatable({page = page, group = group, refs = refs, result = result, time = 0, values = {}}, presentation)
end
function presentation:text(name, value)
	value = value == "Final Score" and Locale.get("FINAL_SCORE") or Locale.text(value)
	if self.values[name] == value then return end
	self.values[name] = value
	local label = self.refs[name]
	label.Text = value
	Font.render(label, value, Small)
end
function presentation:update(dt)
	if self.hiding or not self.page:GetAttribute("PageReady") then return end
	self.time += dt
	local t, r = self.time, self.result
	self.group.GroupTransparency = 1 - math.min(1, t / .2)
	local score, title, value, alpha = 0, "Star Bonus", tostring(r.starbonus), math.clamp((t - .8) / .2, 0, 1)
	if t >= 1 and t < 2 then
		local f = t - 1
		score, value = math.floor(r.starbonus * f), tostring(math.floor(r.starbonus * (1 - f)))
	elseif t >= 2 and t < 2.2 then
		score, value, alpha = r.starbonus, "0", 1 - (t - 2) / .2
	elseif t >= 2.2 and t < 3.6 then
		local f = math.clamp(t - 2.4, 0, 1)
		local seconds = math.floor(r.elapsed * (1 - f) + .5)
		title, value = "Time", string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
		score = math.floor(r.starbonus + r.timebonus * f)
		alpha = t < 2.4 and (t - 2.2) / .2 or t >= 3.4 and 1 - (t - 3.4) / .2 or 1
	elseif t >= 3.6 then
		score, title, value, alpha = r.score, "Final Score", "", math.min(1, (t - 3.6) / .2)
		self.refs.StarBonus.Position = UDim2.fromScale(.5, .455)
	end
	local stamp = self.refs.ImprovedResultStamp
	if stamp then
		local f = math.clamp((t - 3.8) / .5, 0, 1)
		local eased = f * f
		stamp.Visible, stamp.ImageTransparency = f > 0, 1 - eased
		stamp.Size = UDim2.fromScale(239/2560 * (3 - 2 * eased), 238/1440 * (3 - 2 * eased))
	end
	self:text("StarBonus", title)
	self:text("StarBonusScore", value)
	self:text("LevelScore", tostring(score))
	for _, name in ipairs({"StarBonus", "StarBonusScore"}) do
		local label = self.refs[name]
		local bitmap = label:FindFirstChild("BitmapText")
		if not bitmap or not bitmap.Visible then label.TextTransparency = 1 - alpha end
		for _, glyph in ipairs(self.refs[name]:GetDescendants()) do
			if glyph:IsA("ImageLabel") then glyph.ImageTransparency = 1 - alpha end
		end
	end
	self.page:SetAttribute("DisplayedScore", score)
	self.page:SetAttribute("ResultAnimationTime", t)
end
function presentation:hide()
	self.hiding = true
	local fade = TweenService:Create(self.group, TweenInfo.new(.2, Enum.EasingStyle.Linear), {GroupTransparency = 1})
	fade:Play()
	fade.Completed:Wait()
end
return presentation
