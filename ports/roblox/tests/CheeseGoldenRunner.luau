local Physics=require(script.Parent.DxPhysics)
local Levels=require(script.Parent.LevelPack15)
local Camera=require(script.Parent.GameplayCamera)
return function(traces)
	local results={}
	for _,trace in ipairs(traces) do
		local level=Levels[trace.level]
		local p=Physics.new(level)
		local camera=Camera.new(level)
		local sampleIndex,actionIndex=1,1
		local r={id=level.id,mode=trace.mode,candy=0,previous=0,elapsed=0,states=0,topology=0,ownership=0,input=0}
		for tick=0,trace.samples[#trace.samples][1] do
			if tick>0 and tick%120==0 then task.wait() end
			if tick>0 then
				while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
					local a=trace.actions[actionIndex]
					if a[2]=="mouse" then
						local object=p.mice.objects[a[3]]
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
				if p.mice.active.index~=sample[3] then r.states+=1 end
				for i,m in ipairs(sample[4]) do
					local a=p.mice.objects[i]
					r.elapsed=math.max(r.elapsed,math.abs(a.elapsed-m[5]))
					if a.active~=m[1] or (a.carry~=nil)~=m[2] or a.retreating~=m[3] or a.grabbing==true~=m[4] then
						r.states+=1
						if not r.firstState then r.firstState={tick,i,a.active,a.carry~=nil,a.retreating,a.grabbing==true,m} end
					end
				end
				sampleIndex+=1
			end
		end
		r.passed=r.candy<.5 and r.previous<.5 and r.elapsed<.0001 and r.states==0 and r.topology==0 and r.ownership==0 and r.input==0
		table.insert(results,r)
		task.wait()
	end
	return results
end
