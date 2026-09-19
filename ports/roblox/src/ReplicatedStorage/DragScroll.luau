local Input=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local drag={}
function drag.blocked(scroll)
	return scroll:GetAttribute("DragActive")==true or os.clock()<(scroll:GetAttribute("DragReleasedUntil") or 0)
end
function drag.attach(scroll,onBegin)
	local connections,pointer,start,last,stamp,velocity,inertia={},nil,0,0,0,0,nil
	local function connect(signal,callback) table.insert(connections,signal:Connect(callback)) end
	local function scale()
		local value,node=1,scroll
		while node and not node:IsA("ScreenGui") do
			local item=node:FindFirstChildOfClass("UIScale") if item then value*=item.Scale end
			node=node.Parent
		end
		return math.max(value,.001)
	end
	local function visible()
		local node=scroll
		while node do
			if node:IsA("GuiObject") and not node.Visible or node:IsA("ScreenGui") and not node.Enabled then return false end
			node=node.Parent
		end
		return scroll.Parent~=nil
	end
	local function move(delta)
		local maximum=math.max(0,(scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteWindowSize.Y)/scale())
		local next=math.clamp(scroll.CanvasPosition.Y+delta,0,maximum)
		local changed=next~=scroll.CanvasPosition.Y
		scroll.CanvasPosition=Vector2.new(scroll.CanvasPosition.X,next)
		return changed
	end
	local function stop() if inertia then inertia:Disconnect() inertia=nil end velocity=0 end
	connect(Input.InputBegan,function(input)
		if input.UserInputType~=Enum.UserInputType.MouseButton1 or not visible() then return end
		local point=Vector2.new(input.Position.X,input.Position.Y)
		local p,s=scroll.AbsolutePosition,scroll.AbsoluteWindowSize
		if point.X<p.X or point.Y<p.Y or point.X>p.X+s.X or point.Y>p.Y+s.Y then return end
		stop() pointer=input start=input.Position.Y last=start stamp=os.clock()
		scroll:SetAttribute("DragActive",false)
		if onBegin then onBegin() end
	end)
	connect(Input.InputChanged,function(input)
		if input.UserInputType==Enum.UserInputType.MouseWheel then stop() return end
		if not pointer or input.UserInputType~=Enum.UserInputType.MouseMovement then return end
		local now=os.clock() local delta=(last-input.Position.Y)/scale()
		if not scroll:GetAttribute("DragActive") and math.abs(input.Position.Y-start)/scale()<5 then return end
		scroll:SetAttribute("DragActive",true)
		if math.abs(delta)<640 then
			move(delta)
			velocity=velocity*.35+delta/math.max(now-stamp,1/240)*.65
		end
		last,stamp=input.Position.Y,now
	end)
	local function release()
		if not pointer then return end pointer=nil
		if not scroll:GetAttribute("DragActive") then return end
		scroll:SetAttribute("DragActive",false)
		scroll:SetAttribute("DragReleasedUntil",os.clock()+.15)
		if os.clock()-stamp>.12 then velocity=0 end
		inertia=RunService.RenderStepped:Connect(function(dt)
			if not visible() or math.abs(velocity)<12 then stop() return end
			local decay=math.exp(-3*math.min(dt,.1))
			if not move(velocity*(1-decay)/3) then stop() return end
			velocity*=decay
		end)
	end
	connect(Input.InputEnded,function(input) if input==pointer then release() end end)
	connect(Input.WindowFocusReleased,function() release() stop() end)
	connect(scroll.Destroying,function() stop() for _,c in ipairs(connections) do c:Disconnect() end end)
	return {stop=stop}
end
return drag
