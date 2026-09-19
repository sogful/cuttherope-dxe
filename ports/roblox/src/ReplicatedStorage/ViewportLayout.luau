-- DX ViewportLayout, ContentFit, FittedContentFit and LayoutMath.
-- World coordinates remain 2560x1440. Only presentation responds to the surface.
local layout = {design = Vector2.new(2560, 1440)}
function layout.compute(size)
	local pixels = math.max(1, math.min(size.X, size.Y)) / 1440
	local visible = Vector2.new(math.max(1,size.X), math.max(1,size.Y)) / pixels
	local aspect, design = visible.X/visible.Y, 2560/1440
	local content
	if aspect >= design then content = 1 + (math.min(aspect,2.5)-design)/(2.5-design)*.15
	else content = 1 + ((design-math.max(aspect,.4))/(design-.4))^3*.55 end
	return {visible=visible, pixels=pixels, content=content, aspect=aspect}
end

-- A centered design composition; bounds describe what it actually occupies, not
-- the empty margins of its authored canvas. Backgrounds instead cover every edge.
function layout.scale(snapshot, mode, bounds)
	local v = snapshot.visible
	if mode == "cover" or mode == "coverBottom" then return math.max(v.X/2560,v.Y/1440) end
	if mode == "logical" then return 1 end
	local desired = snapshot.content
	if bounds then
		local reachX=math.max(math.abs(bounds[1]-1280),math.abs(bounds[3]-1280))
		local reachY=math.max(math.abs(bounds[2]-720),math.abs(bounds[4]-720))
		local allowed=math.min((v.X/2-48)/math.max(1,reachX),(v.Y/2-48)/math.max(1,reachY))
		-- FittedContentFit does not shrink shipped content just to add its 48-unit
		-- margin. Like LevelGridFit, an actually overflowing composition can shrink.
		local safe=math.min(v.X/(2*math.max(1,reachX)),v.Y/(2*math.max(1,reachY)))
		desired=math.min(desired,math.max(1,allowed),safe)
	end
	return math.max(.01,desired)
end

function layout.bind(root, parent, mode, bounds, anchor)
	local scaler = Instance.new("UIScale")
	scaler.Name, scaler.Parent = "ViewportScale", root
	root.Size = UDim2.fromOffset(2560,1440)
	anchor = anchor or (mode == "logical" and Vector2.zero or mode == "coverBottom" and Vector2.new(.5,1) or Vector2.new(.5,.5))
	root.AnchorPoint, root.Position = anchor, UDim2.fromScale(anchor.X,anchor.Y)
	local function resize()
		local snapshot=layout.compute(parent.AbsoluteSize)
		scaler.Scale=snapshot.pixels*layout.scale(snapshot,mode,bounds)
		root:SetAttribute("LogicalWidth",snapshot.visible.X)
		root:SetAttribute("LogicalHeight",snapshot.visible.Y)
	end
	local connection=parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	root.Destroying:Connect(function() connection:Disconnect() end)
	resize()
	return scaler
end

function layout.group(parent,name,mode,bounds,anchor,z)
	local root=Instance.new("Frame")
	root.Name,root.BackgroundTransparency,root.BorderSizePixel=name,1,0
	root.ZIndex,root.Parent=z or 5,parent
	layout.bind(root,parent,mode,bounds,anchor)
	return root
end
return layout
