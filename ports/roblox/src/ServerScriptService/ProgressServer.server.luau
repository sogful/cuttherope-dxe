local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local shared=game.ReplicatedStorage:WaitForChild("CutTheRope"):WaitForChild("Shared")
local Data=require(shared.ProgressData)
local Store=require(shared.ProgressStore)
local persistent=not RunService:IsStudio()
local adapter
if persistent then adapter=game:GetService("DataStoreService"):GetDataStore("CutTheRopeDxProfilesV1")
else
	-- Studio diagnostics never write or reset the published experience's save.
	local records={}
	adapter={UpdateAsync=function(_,key,transform)
		local next=transform(Data.copy(records[key]))
		if next then records[key]=Data.copy(next) return Data.copy(next) end
	end}
end
local store=Store.new(adapter,game:GetService("HttpService"):GenerateGUID(false))
local remotes=Instance.new("Folder") remotes.Name,remotes.Parent="ProfileRemotes",shared.Parent
local load=Instance.new("RemoteFunction") load.Name,load.Parent="LoadProfile",remotes
local command=Instance.new("RemoteEvent") command.Name,command.Parent="ProfileCommand",remotes
local status=Instance.new("RemoteEvent") status.Name,status.Parent="ProfileStatus",remotes
local sessions,loading,failures,limits={},{},{},{}
local function open(player)
	if sessions[player] then return sessions[player] end
	if failures[player] then return nil,failures[player] end
	if loading[player] then
		while loading[player] and player.Parent do task.wait(.05) end
		return sessions[player],failures[player]
	end
	loading[player]=true
	local session,message
	for attempt=1,3 do
		session,message=store:open(tostring(player.UserId))
		if session or message=="ProfileInUse" then break end
		task.wait(attempt)
	end
	loading[player]=nil
	if not player.Parent then if session then store:save(session,true) end return end
	sessions[player],failures[player]=session,message
	return session,message
end
load.OnServerInvoke=function(player)
	local session,message=open(player)
	return session and {profile=Data.copy(session.profile),persistent=persistent,status=persistent and "Saved" or "StudioSession"} or {status=message or "Unavailable"}
end
command.OnServerEvent:Connect(function(player,value)
	local session=sessions[player]
	if not session then return end
	local now=os.clock() local limit=limits[player] or {time=now,tokens=24} limits[player]=limit
	limit.tokens=math.min(24,limit.tokens+(now-limit.time)*12) limit.time=now
	if limit.tokens<1 then return end limit.tokens-=1
	if store:command(session,value) and session.saved~=session.revision then
		if persistent then status:FireClient(player,"Pending") end
		if not session.queued then
			session.queued=true
			task.delay(5,function()
				session.queued=false
				if session.closed or session.closing or session.saving then return end
				local ok,message=store:save(session)
				if player.Parent then status:FireClient(player,ok and (persistent and "Saved" or "StudioSession") or message) end
			end)
		end
	end
end)
local function close(player)
	local session=sessions[player] if not session or session.closing then return end
	session.closing=true
	local deadline=os.clock()+20
	while session.saving and os.clock()<deadline do task.wait(.05) end
	for attempt=1,3 do
		local ok=store:save(session,true)
		if ok or session.closed then break end
		task.wait(attempt)
	end
	sessions[player],loading[player],failures[player],limits[player]=nil,nil,nil,nil
end
Players.PlayerRemoving:Connect(close)
task.spawn(function()
	while true do
		task.wait(45)
		for player,session in pairs(sessions) do
			local ok,message=store:save(session)
			if player.Parent then status:FireClient(player,ok and (persistent and "Saved" or "StudioSession") or message) end
		end
	end
end)
game:BindToClose(function()
	local pending=0
	for player in pairs(sessions) do pending+=1 task.spawn(function() close(player) pending-=1 end) end
	local deadline=os.clock()+25
	while pending>0 and os.clock()<deadline do task.wait(.05) end
end)
