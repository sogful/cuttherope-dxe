local shared=game.ReplicatedStorage.CutTheRope.Shared
local Hazards,Physics=require(shared.SpikeHazards),require(shared.DxPhysics)
local Runtime,Levels=require(shared.LevelRuntime),require(shared.LevelData)
local Break,Frames=require(shared.CandyBreak),require(shared.HazardFrames)
local gui=Instance.new("ScreenGui")
gui.Name,gui.Enabled,gui.Parent="DxHazardChecks",false,game.Players.LocalPlayer.PlayerGui
local edges={Vector2.new(0,100),Vector2.new(200,100),Vector2.new(0,110),Vector2.new(200,110)}
for _,case in ipairs({{100,100,100,100,15,true},{100,130,100,60,1,true},{500,500,500,500,15,false},
	{100,120,100,80,15,true},{100,300,100,300,15,false},{-16,101,-16,101,15,false},{-15,101,-15,101,15,true}}) do
	assert(Hazards.hits(edges[1],edges[2],edges[3],edges[4],Vector2.new(case[1],case[2]),Vector2.new(case[3],case[4]),case[5])==case[6])
end
local turned=Hazards.new({{point=Vector2.new(500,600),size=2,angle=90}})
assert((turned.bars[1][1]-Vector2.new(505,433.5)).Magnitude<.0001)
assert(turned:hit(Vector2.new(530,600),Vector2.new(470,600))==1)
assert(not turned:hit(Vector2.new(550,600),Vector2.new(550,600)))
gui:SetAttribute("SourceCollisionCases",true)
local definition={id="spiketest",candyStart=Vector2.new(1280,500),target=Vector2.new(1280,1000),ropes={},stars={},bubbles={},
	spikes={{point=Vector2.new(1280,700),size=2,angle=0}}}
local a,b=Physics.new(definition),Physics.new(definition)
for _=1,120 do a:update(1/60) end
for _=1,60 do b:update(1/30) end
assert(a.hazard==1 and b.hazard==1 and a.retired and b.retired)
assert((a.candy.pos-b.candy.pos).Magnitude<.001)
gui:SetAttribute("FixedStepHazard",true)
local parent=Instance.new("Frame") parent.Size,parent.Parent=UDim2.fromOffset(1120,630),gui
local runtime=Runtime.new(parent,definition)
for _=1,120 do runtime:update(1/60) if runtime.state=="breaking" then break end end
assert(runtime.state=="breaking" and runtime.broken and #runtime.broken.particles==5)
assert(not runtime.candy.Visible and runtime.physics.retired)
assert(runtime.lossDelay==1.3 and not runtime:cut(Vector2.zero,Vector2.new(2560,1440)))
local score=runtime.elapsed
for _=1,20 do runtime:update(1/60) end
assert(runtime.state=="failed" and runtime.animator.state=="sad" and runtime.elapsed==score)
local fragment=runtime.broken.particles[1]
assert(fragment.image.Rotation~=0 and fragment.image.Visible)
parent:Destroy()
gui:SetAttribute("BreakAndLossLifecycle",true)
for skin=0,51 do
	local parent=Instance.new("Frame") parent.Parent=gui
	local particles=Break.new(parent,Vector2.new(1000,500),skin,Random.new(42))
	assert(#Frames["candy"..skin]==5)
	for _,p in ipairs(particles.particles) do
		assert(p.image:GetAttribute("SourceQuad")>=3 and p.image:GetAttribute("SourceQuad")<=7)
		assert(p.image.ImageRectSize.X>0 and p.image.ImageRectSize.Y>0)
	end
	for _=1,190 do particles:update(.016) end
	for _,p in ipairs(particles.particles) do assert(not p.image.Visible) end
	parent:Destroy()
end
assert(Levels.supported(1,25) and #Levels.get(16).spikes==2 and not Levels.supported(1,26))
gui:SetAttribute("AllCandyFragments",true)
gui:SetAttribute("Passed",true)
print("DX HAZARD CHECKS PASS: source collision cases, sweeps/rotation, fixed-step death, delayed loss, 52 fragment sets")
