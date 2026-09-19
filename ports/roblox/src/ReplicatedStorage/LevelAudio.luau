-- Source event calls live in the corresponding mechanics; this binds only the
-- active runtime, never hidden/prepared levels or standalone physics tests.
local levelaudio={}
local voices={opening="monster_open",closing="monster_close",chewing="monster_chewing",sad="monster_sad"}

function levelaudio.bind(runtime,audio)
	local p=runtime.physics
	p.audio,p.bouncers.audio=audio,audio
	for _,rope in ipairs(p.ropes) do if rope.wheel then rope.wheel.audio=audio end end
	local skin=runtime.layer:GetAttribute("OmNomSkin") or 0
	local sleeping=runtime.animator.state=="sleeping"
	local sleepTime=sleeping and .9 or 0
	local lit=table.clone(p.night.lit)
	runtime.animator.onSound=function(state)
		if voices[state] then audio:omnom(voices[state],skin) end
		if state=="sleeping" then sleepTime=.9 end
	end
	runtime.audioTick=function(delta)
		for index,hazard in ipairs(p.hazards.objects) do
			if hazard.electric then audio:loop("electric"..index,"electric",hazard.on) end
		end
		if p.night.enabled then
			for index,value in ipairs(p.night.lit) do
				if value and lit[index]==false then audio:randomSound({"star_light01","star_light02"}) end
				lit[index]=value
			end
		end
		if delta>0 and runtime.animator.state=="sleeping" and runtime.state=="playing" then
			sleepTime+=.016
			if sleepTime>4 then
				sleepTime=0
				audio:omnom(({"monster_sleep01","monster_sleep02","monster_sleep03"})[audio.random:NextInteger(1,3)],skin)
			end
		end
	end
	audio:omnom("monster_greeting",skin)
	if #p.mice.objects>0 then audio:play("mouse_rustle") end
	if p.lanterns.shared then audio:play("lantern_teleport_in") end
	runtime.audioTick(0)
end

function levelaudio.unbind(runtime)
	if not runtime then return end
	local p=runtime.physics
	if p.audio then
		for index,hazard in ipairs(p.hazards.objects) do if hazard.electric then p.audio:loop("electric"..index,nil,false) end end
	end
	p.audio,p.bouncers.audio=nil,nil
	for _,rope in ipairs(p.ropes) do if rope.wheel then rope.wheel.audio=nil end end
	runtime.audioTick,runtime.animator.onSound=nil,nil
end

return levelaudio
