local Session=require(script.Parent.SessionState)
local Data=require(script.Parent.ProgressData)
local save={}
function save.start(playergui)
	local backdrop=Instance.new("ScreenGui")
	backdrop.Name,backdrop.IgnoreGuiInset,backdrop.ResetOnSpawn,backdrop.DisplayOrder="DxBlackBackdrop",true,false,-100
	local black=Instance.new("Frame")
	black.BackgroundColor3,black.BorderSizePixel,black.Size=Color3.new(0,0,0),0,UDim2.fromScale(1,1)
	black.Parent,backdrop.Parent=backdrop,playergui
	local state=Instance.new("Folder") state.Name,state.Parent="DxSaveState",playergui
	state:SetAttribute("Status","Loading")
	local remotes=game.ReplicatedStorage.CutTheRope:WaitForChild("ProfileRemotes",15)
	if not remotes then state:SetAttribute("Status","Unavailable") return end
	local load=remotes:WaitForChild("LoadProfile",10)
	local command=remotes:WaitForChild("ProfileCommand",10)
	local status=remotes:WaitForChild("ProfileStatus",10)
	if not load or not command or not status then state:SetAttribute("Status","Unavailable") return end
	local completed,response=false,nil
	task.spawn(function()
		local ok,result=pcall(function() return load:InvokeServer() end)
		if ok then response=result end completed=true
	end)
	local deadline=os.clock()+20
	while not completed and os.clock()<deadline do task.wait(.05) end
	if not completed or type(response)~="table" or not response.profile then
		state:SetAttribute("Status",response and response.status or "Unavailable") return
	end
	Session.load(response.profile)
	state:SetAttribute("Status",response.status)
	state:SetAttribute("Persistent",response.persistent==true)
	state:SetAttribute("UnlockAll",false)
	Session.onChange=function(value)
		command:FireServer(value)
		if value.kind=="cheat" then state:SetAttribute("UnlockAll",value.enabled) end
	end
	status.OnClientEvent:Connect(function(value) state:SetAttribute("Status",value) end)
	local last=Data.settings(Session)
	task.spawn(function()
		while state.Parent do
			task.wait(1)
			local next=Data.settings(Session) local changed=false
			for key,value in pairs(next) do if last[key]~=value then changed=true break end end
			if changed then last=next command:FireServer({kind="settings",settings=next}) end
		end
	end)
end
return save
