-- Shared by native Luau CLI checks and the real Studio diagnostic LocalScript.
local Physics=require(script.Parent.DxPhysics)
local Levels=require(script.Parent.LevelPack14)
local Camera=require(script.Parent.GameplayCamera)
return function(traces)
	local results={}
	for _,trace in ipairs(traces) do
		local level=Levels[trace.level]
		local p=Physics.new(level)
		local camera=Camera.new(level)
		local sampleIndex,actionIndex=1,1
		local r={id=level.id,mode=trace.mode,candy=0,previous=0,lantern=0,angle=0,states=0,topology=0,ownership=0,input=0}
		for tick=0,trace.samples[#trace.samples][1] do
			if tick>0 then
				while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
					local a=trace.actions[actionIndex]
					if a[2]=="lantern" then
						local object=p.lanterns.objects[a[3]]
						if p.mechanics:press(object.point)~=a[4] then r.input+=1 end
						p.mechanics:release(object.point)
					elseif a[2]=="cut" then for _,rope in ipairs(p.ropes) do p:sever(rope,1) end
					elseif a[2]=="pop" then p:popBubble(p:activeBodies()[a[3]]) end
					actionIndex+=1
				end
				p:tick()
				for _,body in ipairs(p:activeBodies()) do if camera:outside(body.pos) then p:retireCandy(body) end end
			end
			local sample=trace.samples[sampleIndex]
			if sample and sample[1]==tick then
				local bodies=p:activeBodies()
				if #bodies~=#sample[2] then r.topology+=1 end
				for i,b in ipairs(sample[2]) do if bodies[i] then
					local error=(bodies[i].pos-Vector2.new(b[1],b[2])).Magnitude
					if error>r.candy then r.candy,r.tick=error,tick end
					if error>.001 and not r.firstDifference then r.firstDifference={tick,bodies[i].pos.X,bodies[i].pos.Y,b[1],b[2]} end
					r.previous=math.max(r.previous,(bodies[i].previous-Vector2.new(b[3],b[4])).Magnitude)
					if (p:hasBubble(bodies[i])==true)~=b[5] or (bodies[i].disableGravity==true)~=b[6] then r.ownership+=1 end
				end end
				if (p.lanterns.inLantern==true)~=sample[3] or (p.lanterns.shared~=nil)~=sample[4] then r.ownership+=1 end
				for i,l in ipairs(sample[5]) do
					local actual=p.lanterns.objects[i]
					r.lantern=math.max(r.lantern,(actual.point-Vector2.new(l[1],l[2])).Magnitude)
					r.angle=math.max(r.angle,math.abs(actual.angle-l[3]))
					if actual.state~=l[4] then r.states+=1 end
				end
				sampleIndex+=1
			end
		end
		r.passed=r.candy<.5 and r.previous<.5 and r.lantern<.01 and r.angle<.001 and r.states==0 and r.topology==0 and r.ownership==0 and r.input==0
		table.insert(results,r)
	end
	return results
end
