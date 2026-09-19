-- Studio-only regression checks for source draw passes and sprite joins.
if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Layers=require(shared.GameplayLayers)
local Frames=require(shared.BoxFrames)
local results={}
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.ZIndexBehavior="DxRenderOrderChecks",false,Enum.ZIndexBehavior.Sibling
root.Parent=game.Players.LocalPlayer.PlayerGui
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX render order check",name,message) end
end
local function make(definition)
	local layer=Instance.new("Frame")
	layer.Size,layer.Parent=UDim2.fromOffset(1120,630),root
	return Runtime.new(layer,definition),layer
end
check("SourceDrawPasses",function()
	local definition=table.clone(Levels.get(1,4))
	definition.pumps={{point=definition.candyStart,angle=0}}
	definition.bubbles={definition.candyStart}
	definition.spikes={{point=Vector2.new(800,500),size=1,angle=0}}
	local runtime,layer=make(definition)
	local function before(a,b) assert(a.ZIndex<b.ZIndex,a.Name.." must be behind "..b.Name) end
	before(layer.OmNomSupport,layer.OmNom)
	before(layer.OmNom,layer.Bubble1)
	before(layer.Bubble1,layer.Pump1)
	before(layer.Pump1,layer.Spike1)
	before(layer.Spike1,layer.HatPivot1)
	before(layer.HatPivot1,layer.HookBack1)
	before(layer.HookBack1,layer.HookFront1)
	before(layer.HookFront1,layer.Star1)
	before(layer.Star1,layer.Candy)
	assert(runtime.candy.ZIndex==Layers.Candy)
	layer:Destroy()
end)
check("ElectrodeRegistration",function()
	local runtime,layer=make(Levels.get(15,3))
	for _,visual in pairs(runtime.electrics) do
		local first=visual.atlas.fixedFrames["electro:0"]
		for index=1,4 do
			local frame=visual.atlas.fixedFrames["electro:"..index]
			assert(frame.Position==first.Position and frame.Size==first.Size)
			assert(frame.ImageRectSize==first.ImageRectSize)
		end
	end
	layer:Destroy()
end)
check("RailTilesAndJoins",function()
	local rails,vertical=0,0
	for number=1,25 do
		local runtime,layer=make(Levels.get(number,3))
		for index,rope in ipairs(runtime.physics.ropes) do
			if rope.definition.rail then
				rails+=1
				local rail=rope.definition.rail
				if rail.vertical then vertical+=1 end
				local length=rail.length+142
				local track=layer["HookRail"..index]
				local pieces={track.LeftCap,track.RightCap}
				for _,child in track:GetChildren() do
					if child.Name:find("^CenterRail") then
						assert(child.ImageRectSize.X<=Frames.rail[3][4]+2)
						assert(child.Size.X.Scale*length<=Frames.rail[3][4]+2.001)
						assert(math.abs(child.ImageRectSize.X-child.Size.X.Scale*length)<.001,"stretched tile")
						table.insert(pieces,child)
					end
				end
				table.sort(pieces,function(a,b) return a.Position.X.Scale<b.Position.X.Scale end)
				for piece=2,#pieces do
					local last,current=pieces[piece-1],pieces[piece]
					assert(current.Position.X.Scale<=last.Position.X.Scale+last.Size.X.Scale+.00001,"rail gap")
				end
				assert(track.ZIndex<Layers.Rope and layer["RailHook"..index].ZIndex<Layers.Candy)
			end
		end
		layer:Destroy()
		task.wait()
	end
	assert(rails>0 and vertical>0)
end)
check("AttachedBubbleAndSpiderPass",function()
	local definition=table.clone(Levels.get(1,1))
	definition.bubbles={definition.candyStart}
	local runtime,layer=make(definition)
	runtime:update(1/60)
	assert(runtime.attached and runtime.attached.visual.ZIndex>runtime.candy.ZIndex)
	assert(Layers.Spider>Layers.Candy and Layers.Effect>Layers.Spider)
	layer:Destroy()
end)
root:Destroy()
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
local all=true
for _,result in pairs(results) do if result~="PASS" then all=false end end
gui:SetAttribute("DxRenderOrderPassed",all)
gui:SetAttribute("DxRenderOrderChecks",game:GetService("HttpService"):JSONEncode(results))
print("DX RENDER ORDER CHECKS",game:GetService("HttpService"):JSONEncode(results))
