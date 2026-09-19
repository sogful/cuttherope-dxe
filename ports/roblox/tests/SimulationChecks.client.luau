if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Clock=require(shared.SimulationClock)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxSimulationChecks",false,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX SIMULATION",name,message) end
	task.wait()
end
local function create(level)
	local layer=Instance.new("Frame",root)
	layer.Size=UDim2.fromOffset(1280,720)
	return Runtime.new(layer,level),layer
end
local function snapshot(r)
	local bodies={}
	for _,b in ipairs(r.physics:activeBodies()) do table.insert(bodies,{b.pos,b.previous,b.rotation or 0}) end
	return {state=r.state,stars=r.count,time=r.elapsed,clock=r.clock,bodies=bodies,ticks=r.scheduler.ticks,
		mouse=r.physics.mice.active and r.physics.mice.active.index or 0}
end
local function same(a,b)
	assert(a.state==b.state and a.stars==b.stars and a.ticks==b.ticks,"outcome/tick mismatch")
	assert(a.time==b.time and a.clock==b.clock and a.mouse==b.mouse,"timer/ownership mismatch")
	assert(#a.bodies==#b.bodies,"body count")
	for i,v in ipairs(a.bodies) do for j=1,3 do assert(v[j]==b.bodies[i][j],"body/rotation drift") end end
end
check("FixedClockAt4To240Fps",function()
	for _,fps in ipairs({4,5,10,20,30,60,120,144,240}) do
		local c,n=Clock.new(),0
		for _=1,fps*3 do c:advance(1/fps,function(dt) assert(dt==1/60) n+=1 end) end
		assert(n==180 and c.ticks==180 and c.remainder<1e-8 and c.dropped==0,tostring(fps))
	end
end)
check("LagCannotSkipStarsOrMouth",function()
	local reference
	for _,fps in ipairs({60,4,5,10,20,144}) do
		local r,layer=create(Levels.get(1,1))
		for _,rope in ipairs(r.physics.ropes) do r.physics:sever(rope,1) end
		for _=1,fps*3 do r:advance(1/fps) end
		assert(r.state=="won" and r.count==3,"freefall must collect all three stars and win at "..fps)
		local s=snapshot(r)
		if reference then same(reference,s) else reference=s end
		r:present()
		assert(layer:GetAttribute("Stars")==3 and layer:GetAttribute("State")=="won")
		layer:Destroy()
	end
end)
check("RenderNeverAdvancesGameplay",function()
	local r,layer=create(Levels.get(1,15))
	r:advance(.2)
	local before=snapshot(r)
	for _=1,75 do r:present() r:draw() end
	same(before,snapshot(r))
	layer:Destroy()
end)
check("MechanicsAndTimersIndependentOfRenderRate",function()
	for _,id in ipairs({{1,7},{3,7},{4,4},{5,1},{6,15},{7,7},{8,1},{10,4},{11,18},{12,1},{13,22},{14,8},{15,1},{15,19},{16,1},{16,9},{16,25},{17,1},{17,16},{17,24},{17,25}}) do
		local reference
		for _,fps in ipairs({60,4,10,144}) do
			local r,layer=create(Levels.get(id[2],id[1]))
			for frame=1,fps*2 do
				r:advance(1/fps)
				if fps~=4 then r:present() end
				if frame%30==0 then task.wait() end
			end
			local s=snapshot(r)
			if reference then same(reference,s) else reference=s end
			layer:Destroy()
			task.wait()
		end
		task.wait()
	end
end)
check("LongStallIsBoundedSlowdownNotTeleport",function()
	local a,la=create(Levels.get(1,1))
	local b,lb=create(Levels.get(1,1))
	for _,r in ipairs({a,b}) do for _,rope in ipairs(r.physics.ropes) do r.physics:sever(rope,1) end end
	a:advance(5)
	for _=1,15 do b:advance(1/60) end
	same(snapshot(a),snapshot(b))
	assert(a.scheduler.dropped==4.75 and a.scheduler.ticks==15)
	la:Destroy() lb:Destroy()
end)
root:SetAttribute("Results",game.HttpService:JSONEncode(results))
root:SetAttribute("Complete",true)
print("DX SIMULATION CHECKS",game.HttpService:JSONEncode(results))
