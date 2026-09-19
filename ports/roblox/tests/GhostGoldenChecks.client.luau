if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Camera=require(shared.GameplayCamera)
local results={}
for _,trace in ipairs(require(shared.GhostGoldenData)) do
	local p=Physics.new(Levels.get(trace.level,12))
	local camera=Camera.new(Levels.get(trace.level,12))
	local sampleIndex,actionIndex=1,1
	local r={id="12_"..trace.level,mode=trace.mode,candy=0,forms=0,topology=0,ownership=0,input=0}
	for tick=1,trace.samples[#trace.samples][1] do
		while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
			local a=trace.actions[actionIndex]
			if a[2]=="ghost" then
				local g=p.ghosts.objects[a[3]]
				if p.ghosts:touch(g,g.point)~=a[4] then r.input+=1 end
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
				local bubble=p:hasBubble(bodies[i])==true
				local index=bodies[i]==p.candy and p.bubbleIndex or bodies[i].bubbleIndex
				local ghost=bubble and p.ghosts.bubbleApps[index]~=nil
				if bubble~=b[3] or ghost~=b[4] then r.ownership+=1 end
			end end
			for i,g in ipairs(sample[3]) do
				local actual=p.ghosts.objects[i]
				if actual.form~=g[1] then r.forms+=1 end
				local rope=actual.app and actual.app.rope
				if (rope and #rope.bodies or 0)~=g[2] then r.topology+=1 end
			end
			local grabs,bouncers,bubbles=0,0,#(Levels.get(trace.level,12).bubbles)
			for _,rope in ipairs(p.ropes) do if not rope.removed then grabs+=1 end end
			for _,object in ipairs(p.bouncers.objects) do if not object.removed then bouncers+=1 end end
			for _,app in ipairs(p.ghosts.apps) do if app.form==2 then bubbles+=1 end end
			if grabs~=sample[4] or bouncers~=sample[5] or bubbles~=sample[6] then
				r.topology+=1
				r.firstTopology=r.firstTopology or {tick,grabs,sample[4],bouncers,sample[5],bubbles,sample[6]}
			end
			sampleIndex+=1
		end
	end
	r.passed=r.candy<.25 and r.forms==0 and r.topology==0 and r.ownership==0 and r.input==0
	if not r.passed then warn("DX GHOST DIFFERENTIAL",game.HttpService:JSONEncode(r)) end
	table.insert(results,r)
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxGhostGoldenResults",game.HttpService:JSONEncode(results))
local passed=true
for _,r in ipairs(results) do if not r.passed then passed=false end end
gui:SetAttribute("DxGhostGoldenPassed",passed)
print("DX GHOST GOLDEN",passed,#results)
