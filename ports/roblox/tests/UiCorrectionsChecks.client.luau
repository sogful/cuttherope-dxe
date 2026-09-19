local shared = game.ReplicatedStorage:WaitForChild("CutTheRope"):WaitForChild("Shared")
local Font = require(shared.BitmapFont)
local Small = require(shared.SmallFont)
local Locale = require(shared.Localization)
local Fonts = require(shared.LocaleFonts)
local Session = require(shared.SessionState)
local RunService = game:GetService("RunService")
local gui = Instance.new("ScreenGui")
gui.Name, gui.Enabled, gui.Parent = "DxUiCorrectionsChecks", false, game.Players.LocalPlayer:WaitForChild("PlayerGui")
local board = Instance.new("Frame")
board.Size, board.Parent = UDim2.fromOffset(2560, 1440), gui
local results = {}
local errors = 0
local errorConnection = game:GetService("ScriptContext").Error:Connect(function(message)
	if string.find(message, "Parent property") then errors += 1 end
end)
local function check(name, callback)
	local ok, message = pcall(callback)
	results[name] = ok and "PASS" or tostring(message)
	gui:SetAttribute(name, ok)
	if not ok then warn("DX UI check", name, message) end
end
local label = Instance.new("TextLabel")
label.Size, label.Parent = UDim2.fromOffset(900, 100), board
local oldlocale = Session.locale
check("AllLocaleGlyphs", function()
	local data = require(shared.LocaleData)
	for _, code in ipairs(Locale.codes) do
		Locale.set(code)
		local family = Fonts[code == "zh_tw" and "zh" or code] or Fonts.latin
		local seen = {}
		for _, value in pairs(data[code]) do
			for _, point in utf8.codes(value) do
				local char = utf8.char(point)
				if point > 32 and char ~= " " then
					assert(family.big.glyphs[char] or Fonts.latin.big.glyphs[char], code .. ": " .. char)
					seen[char] = true
				end
			end
		end
		local chars = {}
		for char in pairs(seen) do table.insert(chars, char) end
		Font.render(label, table.concat(chars))
		assert(label.TextTransparency == 1 and label.BitmapText.Visible)
		assert(label:GetAttribute("DxFont") == family.big.source)
		local visible = 0
		for _, image in label.BitmapText:GetChildren() do if image.Visible then visible += 1 end end
		assert(visible == #chars, code .. " byte splitting or lost glyphs")
	end
end)
Locale.set(oldlocale)
check("CreditsWrap", function()
	local text = Instance.new("TextLabel")
	text.Size, text.Parent = UDim2.fromOffset(1300, 1), board
	Font.block(text, require(shared.CreditsData)[6], Small, board)
	assert(text.BitmapText and text.Size.Y.Offset > 100)
	assert(text:GetAttribute("DxFont") == "gooddog_new-webfont.ttf")
	text:Destroy()
end)
check("PirateSanitized", function()
	local skins = require(shared.OmNomFrames)
	assert(skins[7].pipeRemoved == true, "Unmodified Pirate artwork must remain blocked")
	assert(#skins[7].library.pages == 7)
	for _, image in ipairs(skins[7].library.pages) do assert(string.match(image, "^rbxassetid://%d+$")) end
	for slot, skin in pairs(skins) do assert(skin.uploadComplete, "Missing skin " .. slot) end
end)
check("HudRegistration", function()
	local hud = require(shared.LevelHud).new(board, {})
	hud:reset(1, 7)
	assert(hud.texts.Number.Position.X.Offset == 40)
	assert(hud.texts.Number.Position.Y.Offset == 1435)
	assert(hud.texts.Level.Position.Y.Offset < hud.texts.Number.Position.Y.Offset)
	assert(hud.texts.Number.Size.Y.Offset == 90)
	hud.label:Destroy()
end)
check("ResultFade", function()
	local parent = Instance.new("Frame")
	parent.Size, parent.Parent = UDim2.fromScale(1, 1), board
	for _, name in ipairs({"StarBonus", "StarBonusScore", "LevelScore"}) do
		local text = Instance.new("TextLabel")
		text.Name, text.ZIndex, text.Parent = name, 10, parent
	end
	local result = require(shared.ResultPresentation).new(parent, {score=4500,starbonus=3000,timebonus=1500,elapsed=15})
	result:update(2)
	assert(result.time == 0 and result.group.GroupTransparency == 1, "Fade consumed while page hidden")
	parent:SetAttribute("PageReady", true)
	result:update(.1)
	assert(math.abs(result.group.GroupTransparency - .5) < .001)
	result:update(.1)
	assert(result.group.GroupTransparency == 0)
	local start = os.clock()
	result:hide()
	assert(os.clock() - start >= .18 and result.group.GroupTransparency == 1)
	parent:Destroy()
end)
RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()
check("DestroyedLabelCallbacks", function() assert(errors == 0, "Deferred resize revived a destroyed glyph") end)
errorConnection:Disconnect()
local passed = true
for _, value in pairs(results) do if value ~= "PASS" then passed = false end end
gui:SetAttribute("AllPassed", passed)
print("DX UI corrections checks", game.HttpService:JSONEncode(results))
