if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Camera=require(shared.GameplayCamera)
local Steam=require(shared.SteamMechanics)
local results={}
for _,trace in ipairs(require(shared.SteamGoldenData)) do
	local level=Levels.get(trace.level,13)
	local p=Physics.new(level)
	local camera=Camera.new(level)
	local sampleIndex,actionIndex=1,1
	local r={id=level.id,mode=trace.mode,candy=0,height=0,valve=0,states=0,topology=0,ownership=0,input=0}
	for tick=1,trace.samples[#trace.samples][1] do
		while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
			local a=trace.actions[actionIndex]
			if a[2]=="valve" then
				local t=p.steam.objects[a[3]]
				if p.steam:touch(t,Steam.valvePoint(t))~=a[4] then r.input+=1 end
			elseif a[2]=="cut" then for _,rope in ipairs(p.ropes) do p:sever(rope,1) end
			elseif a[2]=="pop" then p:popBubble(p:activeBodies()[a[3]]) end
			actionIndex+=1
		end
		p:tick()
		for _,body in ipairs(p:activeBodies()) do if camera:outside(body.pos) then p:retireCandy(body) end end
		local sample=trace.samples[sampleIndex]
		if sample and sample[1]==tick then
			local bodies=p:activeBodies()
			if #bodies~=#sample[2] then r.topology+=1 end
			for i,b in ipairs(sample[2]) do if bodies[i] then
				local error=(bodies[i].pos-Vector2.new(b[1],b[2])).Magnitude
				if error>r.candy then r.candy,r.tick=error,tick end
				if error>.0001 and not r.firstDifference then r.firstDifference={tick,bodies[i].pos.X,bodies[i].pos.Y,b[1],b[2]} end
				if (p:hasBubble(bodies[i])==true)~=b[3] then r.ownership+=1 end
			end end
			for i,t in ipairs(sample[3]) do
				local actual=p.steam.objects[i]
				if actual.state~=t[1] then r.states+=1 end
				r.height=math.max(r.height,math.abs(Steam.height(actual,true)-t[2]))
				r.valve=math.max(r.valve,math.abs(actual.valveRotation-t[3]))
			end
			sampleIndex+=1
		end
	end
	-- Half a 1440-high world pixel; long automatic-rope traces amplify float rounding.
	r.passed=r.candy<.5 and r.height<.001 and r.valve<.001 and r.states==0 and r.topology==0 and r.ownership==0 and r.input==0
	if not r.passed then warn("DX STEAM DIFFERENTIAL",game.HttpService:JSONEncode(r)) end
	table.insert(results,r)
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxSteamGoldenResults",game.HttpService:JSONEncode(results))
local passed=true
for _,r in ipairs(results) do if not r.passed then passed=false end end
gui:SetAttribute("DxSteamGoldenPassed",passed)
print("DX STEAM GOLDEN",passed,#results)
