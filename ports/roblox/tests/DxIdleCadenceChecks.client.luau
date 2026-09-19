local shared = game.ReplicatedStorage.CutTheRope.Shared
local Animator, Frames = require(shared.XmlTargetAnimator), require(shared.OmNomFrames)
local root = Instance.new("ScreenGui")
root.Name, root.Enabled, root.Parent = "DxIdleCadenceChecks", false, game.Players.LocalPlayer.PlayerGui
local function make(slot)
	local parent = Instance.new("Frame", root)
	parent.Size = UDim2.fromOffset(512,512)
	local a = Animator.new(parent, slot, Random.new(177))
	a:play("idle")
	return a
end
local function close(a,b) assert(math.abs(a-b)<.00001, tostring(a).." ~= "..tostring(b)) end
for slot=1,15 do
	local data = Frames[slot]
	local a = make(slot)
	local first = (slot==10 and 1.333333 or 1.3)/.6
	assert(data.idleCadence.mode=="root")
	close(data.idleCadence.first,first)
	a.idlecount=1000
	a:update(first-.001)
	assert(a.idlecount==1000,"Premature idle tick")
	a:update(.002)
	assert(a.idlecount==999,"Missing root keyframe tick")
	a:update(.5)
	a:play("chewing")
	a:update(10)
	assert(a.idlecount==999 and a.id==data.config.timelines.Chewing,"Chewing advanced idle")
	a:play("idle")
	a:update(first-.001)
	assert(a.idlecount==999,"Explicit Play retained old cadence")
	a:update(.002)
	assert(a.idlecount==998)
	a:play("idle")
	a.idlecount=1
	a:update(first+.001)
	if #data.config.idleVariants > 0 then
		assert(a.state=="variation" and a.parent:GetAttribute("Animation")=="variation")
		local variationDuration=data.timelines[tostring(a.id)].duration
		a:update(variationDuration+.001)
		assert(a.id==data.config.timelines.IdleLoop and a.state=="idle","Followup stayed in old state")
	else
		assert(a.state=="idle" and a.idlecount>=5,"Invented a variation for a skin without any")
	end
	assert(a.parent:GetAttribute("Animation")=="idle")

	local b=make(slot)
	a:play("idle") b:play("idle")
	a.idlecount,b.idlecount=1000,1000
	for _=1,1200 do a:update(1/60) end
	for _=1,600 do b:update(1/30) end
	local expected=1000-math.floor(20/data.idleCadence.period+.00001)
	assert(a.idlecount==expected and b.idlecount==expected,"Cadence differs across update rates")
	close(a.time,b.time)
	a.parent:Destroy() b.parent:Destroy()
end
-- Retain the backend's one-second fallback for XML without a root driver.
local a=make(2)
a.data=table.clone(a.data)
a.data.idleCadence={mode="synthetic",first=1,period=1}
a:play("idle") a.idlecount=1000
a:update(7.4)
assert(a.idlecount==993)
a.parent:Destroy()
root:SetAttribute("Passed",16)
print("DX IDLE CADENCE CHECKS PASS: 15 root-driven skins, state transitions, 30/60Hz agreement, synthetic fallback")
