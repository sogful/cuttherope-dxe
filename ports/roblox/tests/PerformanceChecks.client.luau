if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local root=Instance.new("ScreenGui")
root.Name,root.IgnoreGuiInset,root.ResetOnSpawn="DxPerformanceChecks",true,false
root.Parent=game.Players.LocalPlayer.PlayerGui
local rows={}
local function summary(values)
	table.sort(values)
	local total=0 for _,n in values do total+=n end
	return {mean=total/#values,median=values[math.ceil(#values*.5)],p95=values[math.ceil(#values*.95)]}
end
for _,map in {{1,1},{1,7},{7,25},{11,25},{16,25},{17,25}} do
	local layer=Instance.new("Frame") layer.Size=UDim2.fromScale(1,1) layer.Parent=root
	local active=Runtime.new(layer,Levels.get(map[2],map[1]),Vector2.new(2560,1440))
	local physics,visual,rope,resolve,upload={},{},{},{},{}
	for index=1,40 do
		local start=os.clock() active:advance(1/60) local step=(os.clock()-start)*1000
		start=os.clock() active:present() local draw=(os.clock()-start)*1000
		if index>10 then
			table.insert(physics,step) table.insert(visual,draw)
			local renderer=active.ropeRenderer
			table.insert(rope,renderer and renderer.milliseconds or 0)
			table.insert(resolve,renderer and renderer.resolveMilliseconds or 0)
			table.insert(upload,renderer and renderer.uploadMilliseconds or 0)
		end
		game:GetService("RunService").Heartbeat:Wait()
	end
	table.insert(rows,{map=map[1].."-"..map[2],physics=summary(physics),visual=summary(visual),rope=summary(rope),resolve=summary(resolve),upload=summary(upload),instances=#layer:GetDescendants(),renderer=layer:GetAttribute("RopeRenderer")})
	layer:Destroy()
end
root:SetAttribute("Results",game:GetService("HttpService"):JSONEncode(rows))
root:SetAttribute("Complete",true)
root.Enabled=false
