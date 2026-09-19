local Physics=require(script.Parent.DxPhysics)
local Levels=require(script.Parent.LevelPack16)
local Camera=require(script.Parent.GameplayCamera)
return function(traces)
	local results={}
	for _,trace in ipairs(traces) do
		local level=Levels[trace.level]
		local p=Physics.new(level)
		local camera=Camera.new(level)
		local sampleIndex,actionIndex=1,1
		local r={id=level.id,mode=trace.mode,candy=0,bulb=0,previous=0,states=0,light=0}
		local bodies={p.candy,table.unpack(p.bulbs)}
		for tick=0,trace.samples[#trace.samples][1] do
			if tick>0 and tick%120==0 then task.wait() end
			if tick>0 then
				while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
					local a=trace.actions[actionIndex]
					if a[2]=="cut" then p:sever(p.ropes[a[3]],1)
					elseif a[2]=="pop" then p:popBubble(bodies[a[3]]) end
					actionIndex+=1
				end
				p:tick()
				for _,b in ipairs(p.bulbs) do if not b.removed and not b.transport and camera:outside(b.pos) then p:retireCandy(b) end end
			end
			local sample=trace.samples[sampleIndex]
			if sample and sample[1]==tick then
				for i,b in ipairs(sample[2]) do
					local actual=bodies[i]
					local err=(actual.pos-Vector2.new(b[1],b[2])).Magnitude
					local key=i==1 and "candy" or "bulb"
					if err>r[key] then r[key],r.tick=err,tick end
					if err>.001 and not r.firstDifference then r.firstDifference={tick,i,actual.pos.X,actual.pos.Y,b[1],b[2]} end
					if tick>0 then r.previous=math.max(r.previous,((actual.previous or Vector2.zero)-Vector2.new(b[3],b[4])).Magnitude) end
					local hidden=i==1 and p.transport~=nil or i>1 and actual.transport~=nil
					local present=not hidden and not actual.removed and not (i==1 and p.retired)
					if (p:hasBubble(actual)==true)~=b[5] or present~=b[6] or hidden~=b[7] then
						r.states+=1
						if not r.firstState then r.firstState={tick,i,p:hasBubble(actual)==true,present,hidden,b[5],b[6],b[7]} end
					end
				end
				-- Collected stars are removed from the source lighting pass; position
				-- routes compare remaining illumination only in the focused checks.
				sampleIndex+=1
			end
		end
		r.passed=r.candy<.5 and r.bulb<.5 and r.previous<.5 and r.states==0
		table.insert(results,r)
		task.wait()
	end
	return results
end
