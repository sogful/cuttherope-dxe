local Physics=require(script.Parent.DxPhysics)
local Levels=require(script.Parent.LevelPack17)
local Camera=require(script.Parent.GameplayCamera)
return function(traces)
	local results={}
	for _,trace in ipairs(traces) do
		local level=table.clone(Levels[trace.level])
		level.stars=table.clone(level.stars)
		-- Star.CreateAnimations seeds a random +/-3-unit idle bob BEFORE
		-- binding (WillBind stops it). Match that recorded randomized input.
		for i,d in ipairs(trace.items) do if d[1]=="star" then
			local s=trace.samples[1][4][i]
			level.stars[d[2]]=Vector2.new(s[1],s[2])
		end end
		local p=Physics.new(level)
		local camera=Camera.new(level)
		local manager=p.conveyors
		local items,belts={},{}
		for i,d in ipairs(trace.items) do items[i]=assert(manager.byKind[d[1]][d[2]],"Missing "..d[1]..d[2]) end
		for i,d in ipairs(trace.belts) do
			for _,b in ipairs(manager.objects) do if (b.point-Vector2.new(d[1],d[2])).Magnitude<.1 then belts[i]=b break end end
			assert(belts[i],"Missing belt")
		end
		local actionIndex,lost=1,false
		local r={id=level.id,mode=trace.mode,candy=0,previous=0,hook=0,item=0,position=0,scale=0,ownership=0,topology=0,states=0}
		for _,sample in ipairs(trace.samples) do
			local tick=sample[1]
			if tick>0 and tick%120==0 then task.wait() end
			local removals={}
			if tick>0 then
				while trace.actions[actionIndex] and trace.actions[actionIndex][1]==tick do
					local a=trace.actions[actionIndex]
					local point=Vector2.new(a[4],a[5])
					if a[2]=="cut" then p:sever(p.ropes[a[3]],1)
					elseif a[2]=="down" then manager:press(point)
					elseif a[2]=="drag" then manager:drag(point)
					elseif a[2]=="up" then manager:release(point)
					elseif a[2]=="removeStar" then table.insert(removals,a[3]) end
					actionIndex+=1
				end
				p:tick()
				for _,b in ipairs(p:activeBodies()) do if camera:outside(b.pos) then
					if b.part then p:retireCandy(b) end
					if not lost then lost=true manager:cancel() end
				end end
				for _,i in ipairs(removals) do manager:remove(manager.byKind.star[i]) end
			end
			local bodies=p:activeBodies()
			if #bodies~=#sample[2] then r.topology+=1 end
			for i,b in ipairs(sample[2]) do if bodies[i] then
				local err=(bodies[i].pos-Vector2.new(b[1],b[2])).Magnitude
				r.candy=math.max(r.candy,err)
				if err>.001 and not r.firstCandy then r.firstCandy={tick,i,bodies[i].pos.X,bodies[i].pos.Y,b[1],b[2]} end
				if tick>0 then r.previous=math.max(r.previous,(bodies[i].previous-Vector2.new(b[3],b[4])).Magnitude) end
				if (p:hasBubble(bodies[i])==true)~=b[5] then r.states+=1 end
			end end
			for i,h in ipairs(sample[3]) do
				local rope=p.ropes[i]
				r.hook=math.max(r.hook,(rope.anchor-Vector2.new(h[1],h[2])).Magnitude)
				local cut=not rope.active and -2 or rope.cut and rope.cutIndex or -1
				if cut~=h[3] then r.states+=1 if not r.firstCut then r.firstCut={tick,i,cut,h[3]} end end
			end
			for i,s in ipairs(sample[4]) do
				local item=items[i]
				local point=manager:get(item)
				local err=(point-Vector2.new(s[1],s[2])).Magnitude
				r.item=math.max(r.item,err)
				r.position=math.max(r.position,math.abs((item.position or 0)-s[3]))
				r.scale=math.max(r.scale,math.abs(item.scale-s[4]))
				if err>.001 and not r.firstItem then r.firstItem={tick,trace.items[i],point.X,point.Y,s[1],s[2]} end
				if item.belt~=belts[s[5]] then r.ownership+=1 if not r.firstOwner then r.firstOwner={tick,trace.items[i],item.belt and item.belt.index or 0,s[5]} end end
			end
		end
		r.wraps,r.handoffs=manager.wraps,manager.handoffs
		r.passed=r.candy<.5 and r.previous<.5 and r.item<.1 and r.hook<.1 and r.position<.1 and r.scale<.001 and r.ownership==0 and r.states==0 and r.topology==0
		table.insert(results,r)
		task.wait()
	end
	return results
end
