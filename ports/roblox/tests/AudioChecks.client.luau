if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Audio=require(shared.AudioController)
local Catalog=require(shared.AudioCatalog)
local LevelAudio=require(shared.LevelAudio)
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Session=require(shared.SessionState)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxAudioChecks",false,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn) results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX AUDIO CHECK",name,message) end task.wait()
end
local function mock()
	local ids={} for name in pairs(Catalog.resources) do ids[name]="mock:"..name end
	local created={}
	local controller=Audio.new({name="DxAudioTestBackend",assets=ids,preferences={music=true,sound=true,omnom=0},
		random={NextInteger=function(_,_,last) return last end},create=function(name)
			local sound={Name=name,IsLoaded=true,IsPlaying=false,plays=0,pauses=0,resumes=0,TimePosition=0}
			function sound:Play() self.IsPlaying=true self.plays+=1 end
			function sound:Pause() self.IsPlaying=false self.pauses+=1 end
			function sound:Resume() self.IsPlaying=true self.resumes+=1 end
			function sound:Stop() self.IsPlaying=false end
			function sound:Destroy() self:Stop() self.destroyed=true end
			table.insert(created,sound) return sound
		end})
	return controller,created
end
local function eventcount(a,name)
	local count=0 for _,e in ipairs(a.events) do if e.resource==name then count+=1 end end return count
end
check("CatalogAndSkinSourceDeclarations",function()
	local music,effects=0,0
	for _,row in pairs(Catalog.resources) do if row.kind=="music" then music+=1 else effects+=1 end end
	assert(music==6 and effects==149)
	assert(Catalog.skins[5].monster_chewing=="Medieval_chewing")
	assert(not Catalog.skins[5].monster_greeting)
	assert(Catalog.skins[10].monster_greeting=="Prehistoric_greeting")
	for _,mapping in pairs(Catalog.skins) do for _,name in pairs(mapping) do assert(Catalog.resources[name],name) end end
end)
check("PauseResumeMusicAndMenuToggle",function()
	local a=mock() a:setContext("game") local track=a.music
	assert(track.IsPlaying and track.Looped) track.TimePosition=12.5
	a:setPaused(true) assert(not track.IsPlaying and track.pauses==1)
	a:setPaused(true) assert(track.pauses==1)
	a:setPaused(false) assert(track.IsPlaying and track.resumes==1 and track.TimePosition==12.5)
	a:setPaused(true) a:setMusic(false) assert(track.destroyed and not a.music)
	a:setMusic(true) assert(a.music.IsPlaying,"DX enables music immediately inside pause")
	local enabled=a.music a:setPaused(true) assert(enabled.IsPlaying)
	a:setPaused(false) assert(enabled.IsPlaying and enabled.resumes==0)
	a:destroy()
end)
check("EffectsLoopsAndUiHaveSeparatePauseOwnership",function()
	local a=mock() local effect=a:play("bubble") a:loop("hazard","electric",true)
	local loop=a.loops.hazard a:setPaused(true)
	assert(effect.sound.IsPlaying and not effect.paused and loop.paused)
	local click=a:play("tap","ui") assert(click.sound.IsPlaying)
	a:setSound(false) assert(click.sound.IsPlaying and loop.paused)
	assert(a:play("tap","ui")==nil,"new effects should be muted")
	a:setPaused(false) assert(not loop.sound.IsPlaying)
	a:setSound(true) assert(loop.sound.IsPlaying and effect.sound.IsPlaying)
	a:loop("hazard","electric",false) assert(loop.sound.destroyed)
	a:clearScene() a:destroy()
end)
check("UnavailableAndLateEffectsNeverQueue",function()
	local a=mock() a.assets.bubble=nil
	assert(a:play("bubble")==nil and a.missing.bubble)
	a.assets.bubble="mock:bubble"
	local voice=a:play("bubble") voice.sound:Stop() voice.sound.IsLoaded=false
	assert(a:play("bubble")==nil)
	voice.sound.IsLoaded=true a:setPaused(true) a:setPaused(false)
	assert(not voice.sound.IsPlaying,"missed one-shot replayed later")
	a:setContext("menu") local old=a.music a:setContext("game")
	assert(old.destroyed and a.music~=old)
	a:destroy()
end)
check("SkinOptionalAndRequiredVoices",function()
	local a=mock()
	a:omnom("monster_greeting",0) assert(a.serial==0)
	a:omnom("monster_greeting",5) assert(a.serial==0)
	a:omnom("monster_greeting",10) assert(a.events[1].resource=="Prehistoric_greeting")
	a:omnom("monster_chewing",5) assert(a.events[2].resource=="Medieval_chewing")
	a:omnom("monster_chewing",0) assert(a.events[3].resource=="monster_chewing")
	a:destroy()
end)
check("BoundedVoiceReuseAndSceneCleanup",function()
	local a=mock()
	for _=1,40 do a:play("wheel") end assert(#a.pool.wheel==8)
	local first=a.pool.wheel[1] first.sound:Stop() a:play("wheel") assert(first.sound.plays==2)
	a:loop("one","electric",true) a:setPaused(true) a:clearScene()
	assert(next(a.loops)==nil)
	for _,voice in ipairs(a.voices) do assert(not voice.paused and not voice.sound.IsPlaying) end
	a:destroy()
end)
check("GameplayOneShotSourceSites",function()
	local a=mock() local p=Physics.new(Levels.get(1,1)) p.audio=a
	p:toggleGravity() p:toggleGravity()
	assert(a.events[1].resource=="gravity_on" and a.events[2].resource=="gravity_off")
	p.bubble=true p:popBubble(p.candy) p:popBubble(p.candy)
	assert(eventcount(a,"bubble_break")==1)
	local rope=p.ropes[1] local middle=(rope.points[2]+rope.points[3])*.5
	assert(p:cut(middle-Vector2.new(100,0),middle+Vector2.new(100,0)))
	local n=a.serial p:cut(middle-Vector2.new(100,0),middle+Vector2.new(100,0)) assert(a.serial==n)
	local pump={point=Vector2.zero,angle=0,shots=0} p.mechanics:fire(pump)
	assert(a.events[#a.events].resource=="pump_4")
	a:destroy()
end)
check("SteamMouseAndLanternEventSites",function()
	local a=mock()
	local p=Physics.new(Levels.get(1,13)) p.audio=a
	local steam=p.steam local tube=steam.objects[1]
	local Steam=require(shared.SteamMechanics)
	for _=1,3 do assert(steam:touch(tube,Steam.valvePoint(tube))) end
	assert(a.events[1].resource=="steam_start2" and a.events[2].resource=="steam_start" and a.events[3].resource=="steam_end")
	p=Physics.new(Levels.get(1,15)) p.audio=a local mouse=p.mice.active
	p.mice:grab(mouse,p.candy) assert(a.events[#a.events].resource=="mouse_idle")
	mouse.active,mouse.retreating=true,false assert(p.mice:press(mouse.point))
	assert(a.events[#a.events].resource=="mouse_tap")
	p=Physics.new(Levels.get(1,14)) p.audio=a local lantern=p.lanterns.objects[1]
	p.lanterns:capture(lantern) assert(a.events[#a.events].resource=="lantern_teleport_in")
	assert(p.lanterns:touch(lantern,lantern.point)) assert(a.events[#a.events].resource=="lantern_teleport_out")
	a:destroy()
end)
check("WheelPointerBatchAndDiscScratchDirections",function()
	local a=mock()
	local p=Physics.new({candyStart=Vector2.new(600,500),target=Vector2.new(700,900),stars={},bubbles={},
		ropes={{anchor=Vector2.new(600,200),length=300,radius=-1,wheel=true}}})
	local wheel=p.ropes[1].wheel wheel.audio=a
	local center=wheel.rope.anchor
	assert(wheel:begin(center+Vector2.new(100,0))) wheel:dragPointer(center+Vector2.new(0,100))
	assert(eventcount(a,"wheel")==1,"coalesced pointer subdivisions duplicated audio")
	p=Physics.new(Levels.get(1,11)) p.audio=a
	local discs=p.mechanics.discs local disc=discs.objects[1]
	assert(discs:press(disc.right))
	local vector=disc.right-disc.point
	discs:drag(disc.point+Vector2.new(-vector.Y,vector.X))
	assert(a.events[#a.events].resource=="scratch_out")
	discs:drag(disc.point+vector)
	assert(a.events[#a.events].resource=="scratch_in")
	a:destroy()
end)
check("GhostMorphAndAutomaticHookEvents",function()
	local a=mock() local p=Physics.new(Levels.get(1,12)) p.audio=a
	local ghost=p.ghosts.objects[1]
	assert(p.ghosts:touch(ghost,ghost.point)) assert(eventcount(a,"ghost_puff")==1)
	p.ghosts:reset(ghost,1) assert(eventcount(a,"ghost_puff")==1,"idle return should be silent")
	p=Physics.new({candyStart=Vector2.new(500,500),target=Vector2.new(700,900),stars={},bubbles={},
		ropes={{anchor=Vector2.new(400,200),length=300,radius=300}}}) p.audio=a
	p:attach(p.ropes[1],342,p.candy) assert(eventcount(a,"rope_get")==1)
	a:destroy()
end)
check("CardboardThreeStarsChewAndUnbind",function()
	local a=mock() local old=Session.omnom Session.omnom=0
	local layer=Instance.new("Frame",root) layer.Size=UDim2.fromOffset(1280,720)
	local r=Runtime.new(layer,Levels.get(1,1)) LevelAudio.bind(r,a)
	local rope=r.physics.ropes[1] local point=(rope.points[2]+rope.points[3])*.5
	r:cut(point-Vector2.new(120,0),point+Vector2.new(120,0))
	for i=1,240 do r:step(1/60) if i%60==0 then task.wait() end end
	assert(r.state=="won" and r.count==3,r.state..":"..r.count)
	for i=1,3 do assert(eventcount(a,"star_"..i)==1,"star duplicate "..i) end
	assert(eventcount(a,"monster_chewing")==1)
	LevelAudio.unbind(r) assert(not r.physics.audio and not r.audioTick and not r.animator.onSound)
	layer:Destroy() a:destroy() Session.omnom=old
end)
check("AudioDoesNotChangePhysicsAcrossAllBoxes",function()
	local a=mock()
	for pack=1,17 do for _,index in ipairs({1,7,15,25}) do
		local data=Levels.get(index,pack) local first,second=Physics.new(data),Physics.new(data)
		second.audio,second.bouncers.audio=a,a
		for tick=1,120 do
			first:tick() second:tick()
			assert(first.candy.pos==second.candy.pos and first.candy.previous==second.candy.previous,pack.."-"..index..":"..tick)
			if tick%60==0 then task.wait() end
		end
		a:clearScene()
	end end
	a:destroy()
end)
root:SetAttribute("Results",game.HttpService:JSONEncode(results))
root:SetAttribute("Complete",true)
