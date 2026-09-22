local Catalog=require(script.Parent.AudioCatalog)
local Assets=require(script.Parent.AudioAssets)
local Session=require(script.Parent.SessionState)
local SoundService=game:GetService("SoundService")
local ContentProvider=game:GetService("ContentProvider")
local audio={}
audio.__index=audio

function audio.new(options)
	options=options or {}
	local root=Instance.new("Folder")
	root.Name,root.Parent=options.name or "DxAudio",SoundService
	local self=setmetatable({root=root,preferences=options.preferences or Session,assets=options.assets or Assets,
		create=options.create,random=options.random or Random.new(),voices={},loops={},pool={},serial=0,
		paused=false,focused=true,context="splash",missing={},events={},failed={},loaded={},resident={},alive=true},audio)
	for _,name in ipairs({"Music","Effects"}) do
		local group=Instance.new("SoundGroup") group.Name,group.Volume,group.Parent=name,1,root self[name]=group
	end
	self:status()
	return self
end

function audio:status()
	local assigned,missing,failed,loaded=0,0,0,0
	for name in pairs(Catalog.resources) do if self.assets[name] then assigned+=1 else missing+=1 end end
	for _ in pairs(self.failed) do failed+=1 end
	for _ in pairs(self.loaded) do loaded+=1 end
	self.root:SetAttribute("Assigned",assigned) self.root:SetAttribute("Missing",missing)
	self.root:SetAttribute("Failed",failed) self.root:SetAttribute("Loaded",loaded)
	self.root:SetAttribute("SoundEnabled",self.preferences.sound) self.root:SetAttribute("MusicEnabled",self.preferences.music)
	self.root:SetAttribute("Paused",self.paused) self.root:SetAttribute("Context",self.context)
	self.root:SetAttribute("Focused",self.focused)
	self.root:SetAttribute("MusicResource",self.track or "")
end

function audio:record(name,kind)
	self.serial+=1
	local entry={resource=name,kind=kind,sequence=self.serial}
	table.insert(self.events,entry) if #self.events>128 then table.remove(self.events,1) end
	self.root:SetAttribute("LastResource",name) self.root:SetAttribute("EventCount",self.serial)
end

function audio:make(name,kind)
	local id=self.assets[name]
	if not id or not Catalog.resources[name] then self.missing[name]=true return nil end
	if self.create then return self.create(name,id,kind) end
	local sound=Instance.new("Sound")
	sound.Name,sound.SoundId=name,id
	sound.Volume,sound.SoundGroup,sound.Parent=1,kind=="music" and self.Music or self.Effects,self.root
	return sound
end

function audio:preload()
	if self.create or self.preloading then return end
	self.preloading=true
	local names={} for name in pairs(Catalog.resources) do if self.assets[name] then table.insert(names,name) end end
	for _,name in ipairs(names) do
		local sound=self:make(name,Catalog.resources[name].kind=="music" and "music" or "effect")
		self.resident[name]=sound
		if Catalog.resources[name].kind=="sfx" then
			local voice={sound=sound}
			self.pool[name]={voice} table.insert(self.voices,voice)
		else
			sound:SetAttribute("PreloadOnly",true)
		end
	end
	local cursor=0
	for _=1,4 do task.spawn(function()
		while self.alive do
			cursor+=1 local name=names[cursor] if not name then break end
			local sound=self.resident[name]
			-- A bare audio ID takes Roblox's generic fetch path and can report Failure.
			local ok,message=pcall(function() ContentProvider:PreloadAsync({sound},function(_,status)
				if status==Enum.AssetFetchStatus.Success then self.loaded[name]=true self.failed[name]=nil
				else self.failed[name]=tostring(status) end
			end) end)
			if not ok then self.failed[name]=tostring(message) end
			if self.alive then self:status() self:refreshMusic() end
		end
	end) end
end

function audio:play(name,scope)
	if not name or not self.preferences.sound or not self.focused then return nil end
	self:record(name,"effect")
	local pool=self.pool[name]
	if not pool then pool={} self.pool[name]=pool end
	local voice
	for _,candidate in ipairs(pool) do
		if not candidate.sound.IsPlaying and not candidate.paused then voice=candidate break end
	end
	if not voice then
		if #pool>=8 then return nil end
		local active=0 for _,candidate in ipairs(self.voices) do if candidate.sound.IsPlaying or candidate.paused then active+=1 end end
		if active>=96 then return nil end
		local sound=self:make(name,"effect") if not sound then return nil end
		voice={sound=sound} table.insert(pool,voice) table.insert(self.voices,voice)
	end
	local sound=voice.sound
	-- Do not play a missed effect seconds later when Roblox finishes fetching it.
	if not sound.IsLoaded then return nil end
	voice.scope,voice.paused=scope or "scene",false
	sound.TimePosition=0 sound:Play()
	return voice
end

function audio:randomSound(names,scope)
	return self:play(names[self.random:NextInteger(1,#names)],scope)
end

function audio:omnom(name,skin)
	local optional=name=="monster_greeting" or name=="monster_excited"
	if optional and self.random:NextInteger(0,1)==0 then return end
	local mapping=Catalog.skins[skin or self.preferences.omnom]
	local resolved=mapping and mapping[name] or (not optional and name or nil)
	return self:play(resolved)
end

function audio:loop(key,name,enabled)
	local voice=self.loops[key]
	if not enabled then
		if voice then voice.sound:Destroy() self.loops[key]=nil end
		return
	end
	if not voice then
		local sound=self:make(name,"effect") if not sound then return end
		sound.Looped=true voice={sound=sound,started=false} self.loops[key]=voice
	end
	if self.preferences.sound and not self.paused and self.focused and voice.sound.IsLoaded then
		if voice.paused then voice.sound:Resume() voice.paused=false
		elseif not voice.started then voice.sound:Play() voice.started=true end
	elseif voice.sound.IsPlaying then voice.sound:Pause() voice.paused=true end
end

function audio:setSound(enabled)
	self.preferences.sound=enabled
	-- SoundMgr.SuspendSoundEffects pauses loops; existing one-shots ring out.
	for _,voice in pairs(self.loops) do
		if not enabled and voice.sound.IsPlaying then voice.sound:Pause() voice.paused=true
		elseif enabled and not self.paused and self.focused and voice.paused then voice.sound:Resume() voice.paused=false end
	end
	self:status()
end

function audio:stopMusic()
	if self.music then self.music:Destroy() self.music=nil end
	self.musicStarted,self.musicPaused=false,false
end

function audio:refreshMusic()
	if not self.alive or not self.preferences.music or not self.track then return end
	if not self.music then
		self.music=self:make(self.track,"music")
		local pending=self.music
		if pending and pending.Loaded then pending.Loaded:Once(function()
			if self.alive and self.music==pending then self:refreshMusic() end
		end) end
	end
	local sound=self.music
	if sound and sound.IsLoaded and not self.musicStarted then
		sound.Looped=true sound:Play() self.musicStarted=true
		if not self.focused or (self.paused and not self.musicWhilePaused) then sound:Pause() self.musicPaused=true end
	end
end

function audio:chooseMusic(context)
	if context=="menu" then return "menu_music" end
	if context~="game" then return nil end
	local names=Catalog.gameplay
	local name=names[self.random:NextInteger(1,#names)]
	for _=1,4 do if name~=self.previous then break end name=names[self.random:NextInteger(1,#names)] end
	self.previous=name return name
end

function audio:setContext(context,force)
	if self.context==context and not force then return end
	self.context=context self:stopMusic() self.track=self:chooseMusic(context)
	self.musicWhilePaused=false
	self:refreshMusic() self:status()
end

function audio:setMusic(enabled)
	self.preferences.music=enabled self:stopMusic()
	-- DX explicitly permits enabling music while its pause menu is open.
	self.musicWhilePaused=self.paused and enabled
	if enabled then self.track=self:chooseMusic(self.context) self:refreshMusic() end
	self:status()
end

function audio:setPaused(paused)
	if self.paused==paused then return end
	self.paused=paused
	-- Source Pause() owns only activeLoopedSounds and the current music ticket.
	for _,voice in pairs(self.loops) do
		if paused and voice.sound.IsPlaying then voice.sound:Pause() voice.paused=true
		elseif not paused and self.focused and voice.paused and self.preferences.sound then voice.sound:Resume() voice.paused=false end
	end
	if self.music then
		if paused and self.music.IsPlaying then self.music:Pause() self.musicPaused=true
		elseif not paused and self.focused and self.musicPaused and self.preferences.music then self.music:Resume() self.musicPaused=false end
	end
	if not paused then self.musicWhilePaused=false self:refreshMusic() end
	self:status()
end

function audio:setFocused(focused)
	if self.focused==focused then return end
	self.focused=focused
	for _,voice in pairs(self.loops) do
		if not focused and voice.sound.IsPlaying then voice.sound:Pause() voice.paused=true
		elseif focused and not self.paused and voice.paused and self.preferences.sound then voice.sound:Resume() voice.paused=false end
	end
	if self.music then
		if not focused and self.music.IsPlaying then self.music:Pause() self.musicPaused=true
		elseif focused and (not self.paused or self.musicWhilePaused) and self.musicPaused and self.preferences.music then
			self.music:Resume() self.musicPaused=false
		end
	end
	if focused then self:refreshMusic() end
	self:status()
end

function audio:clearScene()
	for key in pairs(self.loops) do self:loop(key,nil,false) end
	for _,voice in ipairs(self.voices) do if voice.scope~="ui" then voice.sound:Stop() voice.paused=false end end
end

function audio:destroy()
	self.alive=false self:clearScene() self:stopMusic()
	for _,voice in ipairs(self.voices) do voice.sound:Destroy() end
	self.root:Destroy()
end

return audio
