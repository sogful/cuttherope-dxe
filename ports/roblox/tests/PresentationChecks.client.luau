local shared = game:GetService("ReplicatedStorage"):WaitForChild("CutTheRope"):WaitForChild("Shared")
local Runtime = require(shared.LevelRuntime)
local Levels = require(shared.LevelData)
local Animator = require(shared.TargetAnimator)
local Confetti = require(shared.ResultConfetti)
local gui = Instance.new("ScreenGui")
gui.Name, gui.Enabled, gui.Parent = "DxPresentationChecks", false, game.Players.LocalPlayer:WaitForChild("PlayerGui")
local results = {}
local function check(name, callback)
	local ok, message = pcall(callback)
	gui:SetAttribute(name, ok)
	results[name] = ok and "PASS" or tostring(message)
	if not ok then warn("DX presentation check " .. name .. ": " .. tostring(message)) end
end
local function layer()
	local object = Instance.new("Frame")
	object.Size, object.Parent = UDim2.fromOffset(1120, 630), gui
	return object
end

check("WinKeepsAnimating", function()
	local game = Runtime.new(layer(), Levels.get(1))
	for _ = 1, 60 do game:update(1 / 60) end
	for _, rope in ipairs(game.physics.ropes) do game.physics:sever(rope, 1) end
	for _ = 1, 240 do
		game:update(1 / 60)
		if game.state == "won" then break end
	end
	assert(game.state == "won", "No win")
	local scoretime, clock, count = game.elapsed, game.clock, game.count
	for _ = 1, 60 do game:update(1 / 60) end
	assert(game.clock > clock + .99, "Presentation stopped")
	assert(game.elapsed == scoretime and game.count == count, "Score changed after win")
	assert(game.animator.state == "eating", "Chewing did not enter original 32..40 loop")
	assert(game.physics.ropes[1].remaining < 1, "Cut rope stopped fading")
	game.layer:Destroy()
end)
check("LossKeepsAnimating", function()
	local game = Runtime.new(layer(), {id="losstest", candyStart=Vector2.new(1280,1900), target=Vector2.new(200,1000), ropes={}, stars={}, bubbles={}})
	game.physics.candy.pos, game.physics.candy.previous = Vector2.new(1280, 1900), Vector2.new(1280, 1900)
	game:update(1 / 60)
	assert(game.state == "failed" and game.animator.state == "sad")
	local time = game.elapsed
	for _ = 1, 45 do game:update(1 / 60) end
	assert(game.animator.frame == 13 and game.animator.state == "sad", "Sad animation interrupted")
	assert(game.elapsed == time)
	game.layer:Destroy()
end)
check("OriginalIdleCadence", function()
	local parent = layer()
	local target = Animator.new(parent, Random.new(42))
	target.idlecount = 1
	target:update(.051)
	assert(target.state == "variationone" or target.state == "variationtwo")
	assert(target.idlecount >= 5 and target.idlecount <= 20)
	for _ = 1, 100 do target:update(.02) end
	assert(target.state == "idle")
	target:play("variationtwo")
	for _ = 1, 31 do target:update(.05) end
	assert(target.state == "variationtwo" and target.frame == 32)
	target:update(.05)
	assert(target.state == "idle")
	parent:Destroy()
end)
check("MouthLifecycle", function()
	local parent = layer()
	local target = Animator.new(parent)
	target:proximity(199, 0)
	assert(target.state == "opening" and target.mouth)
	for _ = 1, 20 do target:update(.05) end
	assert(target.state == "opening" and target.frame == 9)
	target:proximity(201, .99)
	assert(target.mouth)
	target:proximity(201, .02)
	assert(not target.mouth and target.state == "closing")
	for _ = 1, 4 do target:update(.05) end
	assert(target.state == "cheerful")
	target:play("chewing")
	for _ = 1, 4 do target:update(.05) end
	assert(target.state == "eating")
	parent:Destroy()
end)
check("ConfettiLifecycle", function()
	local parent = layer()
	local particles = Confetti.new(parent, Random.new(42))
	assert(#particles.particles == 70)
	local first = particles.particles[1]
	local y = first.object.Position.Y.Scale
	particles:update(.5)
	assert(first.object.Position.Y.Scale > y and first.sprite.transparency > 0)
	assert(first.object.Size.X.Scale > 0)
	particles:update(5)
	assert(parent:GetAttribute("ConfettiAlive") == 0)
	parent:Destroy()
end)
local passed = true
check("CollectionBurstLifecycle", function()
	local game = Runtime.new(layer(), {id = "bursttest", candyStart = Vector2.new(1000, 500), target = Vector2.new(2200, 1200), ropes = {}, stars = {Vector2.new(1000, 500)}, bubbles = {}})
	game:update(1 / 60)
	assert(game.count == 1 and #game.bursts == 1)
	assert(not game.stars[1].container.Visible)
	local burst = game.bursts[1]
	assert(burst.visual.Parent == game.layer)
	game:update(.2)
	assert(game.count == 1 and #game.bursts == 1)
	game:update(.5)
	assert(#game.bursts==1,"stall must not fast-forward effects beyond simulated time")
	game:update(.25)
	assert(#game.bursts == 0 and burst.visual.Parent == nil)
	game.layer:Destroy()
end)
check("RadiusVisualLifecycle", function()
	local game = Runtime.new(layer(), Levels.get(10))
	assert(game.layer:GetAttribute("AttachedRopes") == 1)
	assert(game.radii[1] and game.radii[2] and game.radii[3])
	assert(not game.radii[4])
	for _, rope in ipairs(game.physics.ropes) do if rope.active then game.physics:sever(rope, 1) end end
	for _ = 1, 180 do game:update(1 / 60) end
	assert(game.physics.ropes[1].captured)
	assert(game.physics.ropes[1].radiusAlpha == 0)
	for _, segment in ipairs(game.radii[1].segments) do assert(not segment.object.Visible) end
	game.layer:Destroy()
end)
check("SourceMouthRectangle", function()
	local game = Runtime.new(layer(), {id="mouthtest", candyStart=Vector2.new(1000,920), target=Vector2.new(1000,1000), ropes={}, stars={}, bubbles={}})
	game:update(1/60)
	assert(game.state == "playing", "Candy was eaten above the source mouth box")
	game.physics.candy.pos, game.physics.candy.previous = Vector2.new(1000,985), Vector2.new(1000,985)
	game:update(1/60)
	assert(game.state == "won", "Candy was not eaten inside the source mouth box")
	game.layer:Destroy()
end)
check("HudSourceFramesAndLabel", function()
	local parent = layer()
	local stars = {}
	for i=1,3 do stars[i]=Instance.new("ImageLabel",parent) end
	local hud = require(shared.LevelHud).new(parent,stars)
	local function quad() return hud.stars[1].pending and hud.stars[1].pending.index or hud.stars[1].index end
	local children=#stars[1]:GetChildren()
	hud:reset(1,7)
	hud:update(.1,1)
	assert(quad() == 1)
	hud:update(.25,1)
	assert(quad() == 6)
	hud:update(.4,1)
	assert(quad() == 11 and #stars[1]:GetChildren()==children)
	assert(hud.label.GroupTransparency > 0 and hud.label.GroupTransparency < 1)
	hud:update(2,1)
	assert(hud.label.GroupTransparency == 1)
	parent:Destroy()
end)
check("ResultCountAndGlyphReuse", function()
	local parent = layer()
	parent:SetAttribute("PageReady", true)
	for _,name in ipairs({"StarBonus","StarBonusScore","LevelScore"}) do
		local text=Instance.new("TextLabel")
		text.Name,text.ZIndex,text.Parent=name,10,parent
	end
	local result={score=4500,starbonus=3000,timebonus=1500,elapsed=15}
	local presentation=require(shared.ResultPresentation).new(parent,result)
	for _=1,90 do presentation:update(.05) end
	assert(parent:GetAttribute("DisplayedScore") == 4500)
	assert(presentation.group.GroupTransparency == 0)
	assert(presentation.refs.StarBonus.Text == require(shared.Localization).get("FINAL_SCORE"))
	local count=0
	for _,child in presentation.refs.LevelScore:GetChildren() do if child.Name=="BitmapText" then count+=1 end end
	assert(count==1,"Score rendering accumulated text holders")
	parent:Destroy()
end)
for _, value in pairs(results) do if value ~= "PASS" then passed = false end end
gui:SetAttribute("AllPassed", passed)
print("DX presentation checks", game:GetService("HttpService"):JSONEncode(results))
