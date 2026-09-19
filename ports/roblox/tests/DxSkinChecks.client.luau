local shared = game.ReplicatedStorage.CutTheRope.Shared
local Animator = require(shared.XmlTargetAnimator)
local Frames = require(shared.OmNomFrames)
local Runtime = require(shared.LevelRuntime)
local Levels = require(shared.LevelData)
local Session = require(shared.SessionState)
local Availability = require(shared.SkinAvailability)
local root = Instance.new("ScreenGui")
root.Name, root.Enabled, root.Parent = "DxSkinChecks", false, game.Players.LocalPlayer.PlayerGui
local states = {"idle", "opening", "closing", "chewing", "excited", "greeting", "sad", "sleeping"}
local total = 0
for slot = 1, 15 do
	local parent = Instance.new("Frame", root)
	parent.Size = UDim2.fromOffset(512, 512)
	local a = Animator.new(parent, slot, Random.new(101))
	a:preview()
	for _, state in ipairs(states) do
		a:play(state)
		assert(a.id ~= nil)
		for _ = 1, 300 do a:update(1/60) end
		assert(a.visual.current and a.visual.current.Visible)
		total += 1
	end
	a:play("chewing")
	for _ = 1, 2400 do a:update(1/60) end
	assert(a.id == Frames[slot].config.timelines.Chewing, "Idle interrupted chewing")
	a:play("idle")
	a:proximity(100, .016)
	assert(a.mouth and a.state == "opening")
	a:proximity(1000, 1.1)
	assert(not a.mouth and a.state == "closing")
	parent:Destroy()
end
local previous = Session.omnom
for slot = 0, 15 do
	Session.omnom = slot
	local layer = Instance.new("Frame", root)
	local runtime = Runtime.new(layer, Levels.get(1))
	local expected = Availability.check(slot) and slot or 0
	assert(layer:GetAttribute("OmNomSkin") == expected)
	assert(expected == 0 or runtime.target.Size == UDim2.fromScale(Frames[slot].canvas/2560,Frames[slot].canvas/1440))
	if expected ~= slot then assert(layer:GetAttribute("UnavailableOmNomSkin") == slot) end
	layer:Destroy()
end
Session.omnom = previous
root:SetAttribute("Passed", total + 16)
print("DX SKIN CHECKS PASS: " .. total .. " animation states, 15 chewing/proximity checks, 16 runtime selections")
