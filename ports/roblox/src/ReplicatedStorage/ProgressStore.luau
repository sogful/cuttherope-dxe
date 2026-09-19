local Data=require(script.Parent.ProgressData)
local store={}
store.__index=store
function store.new(adapter,token,clock)
	return setmetatable({adapter=adapter,token=token,clock=clock or os.time,sessions={}},store)
end
function store:open(key)
	if self.sessions[key] then return self.sessions[key] end
	local now=self.clock()
	local ok,value=pcall(function()
		return self.adapter:UpdateAsync(key,function(old)
			if type(old)=="table" and ((old.version or 1)>1 or (old.owner and old.owner~=self.token and (old.expires or 0)>now)) then return nil end
			local profile=Data.sanitize(old)
			profile.owner,profile.expires=self.token,now+180
			return profile
		end)
	end)
	if not ok or type(value)~="table" or value.owner~=self.token then return nil,ok and "ProfileInUse" or "LoadFailed" end
	local session={key=key,profile=Data.sanitize(value),revision=0,saved=0,cheat=false}
	self.sessions[key]=session
	return session
end
function store:command(session,command)
	if not session or session.closed or type(command)~="table" then return false end
	local kind,pack,level=command.kind,command.pack,command.level
	if kind=="cheat" and type(command.enabled)=="boolean" then session.cheat=command.enabled return true end
	if kind=="settings" then session.profile.settings=Data.settings(command.settings)
	elseif session.cheat then return false
	elseif kind=="reset" then
		local settings=session.profile.settings session.profile=Data.new() session.profile.settings=settings
	elseif (kind=="complete" or kind=="skip") and Data.valid(pack,level) and Data.levelUnlocked(session.profile,pack,level) then
		if kind=="skip" then Data.unlockNext(session.profile,pack,level)
		else
			local elapsed,stars=command.elapsed,command.stars
			if type(elapsed)~="number" or elapsed~=elapsed or elapsed<0 or elapsed>86400 or type(stars)~="number" or stars%1~=0 or stars<0 or stars>3 then return false end
			Data.complete(session.profile,pack,level,Data.result(elapsed,stars))
		end
	else return false end
	session.revision+=1 return true
end
function store:save(session,release)
	if not session or session.closed or session.saving then return false,"Unavailable" end
	session.saving=true
	local revision=session.revision
	local snapshot=Data.copy(session.profile)
	local now=self.clock()
	local ok,value=pcall(function()
		return self.adapter:UpdateAsync(session.key,function(old)
			if type(old)~="table" or old.owner~=self.token then return nil end
			local out=Data.copy(snapshot)
			if not release then out.owner,out.expires=self.token,now+180 end
			return out
		end)
	end)
	session.saving=false
	if not ok then return false,"SaveFailed" end
	if not value then session.closed=true return false,"ProfileInUse" end
	session.saved=revision
	if release then session.closed=true self.sessions[session.key]=nil end
	return true
end
return store
