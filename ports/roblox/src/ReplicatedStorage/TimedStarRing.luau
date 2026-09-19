local Frames=require(script.Parent.AnimationFrames)
local Layers=require(script.Parent.GameplayLayers)
local ring={}
ring.__index=ring

local function image(parent,quad)
	local q=Frames.stars[quad+1]
	local label=Instance.new("ImageLabel")
	label.BackgroundTransparency,label.Image=1,Frames.pages[q[1]]
	label.ImageRectOffset,label.ImageRectSize=Vector2.new(q[2],q[3]),Vector2.new(q[4],q[5])
	label.Size,label.ZIndex,label.Parent=UDim2.fromScale(1,1),parent.ZIndex,parent
	return label
end

function ring.new(layer)
	local q=Frames.stars[21]
	local root=Instance.new("Frame")
	root.Name,root.AnchorPoint,root.BackgroundTransparency="TimedStarRing",Vector2.new(.5,.5),1
	root.Size,root.ZIndex,root.Parent=UDim2.fromScale(q[4]/2560,q[5]/1440),Layers.StarRing,layer
	local empty=image(root,20)
	local self=setmetatable({root=root,empty=empty,halves={}},ring)
	for index=1,2 do
		local clip=Instance.new("Frame")
		clip.Name,clip.BackgroundTransparency,clip.ClipsDescendants="Half"..index,1,true
		clip.Size,clip.Position,clip.ZIndex,clip.Parent=UDim2.fromScale(.5,1),UDim2.fromScale((index-1)*.5,0),5,root
		local full=image(clip,19)
		full.Size,full.Position=UDim2.fromScale(2,1),UDim2.fromScale(index==1 and 0 or -1,0)
		local gradient=Instance.new("UIGradient",full)
		gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.4999,0),NumberSequenceKeypoint.new(.5001,1),NumberSequenceKeypoint.new(1,1)})
		self.halves[index]={clip=clip,full=full,gradient=gradient}
	end
	return self
end

function ring:update(point,fraction,alpha)
	self.root.Position=UDim2.fromScale(point.X/2560,point.Y/1440)
	self.empty.ImageTransparency=alpha or 0
	local left,right=self.halves[1],self.halves[2]
	left.clip.Visible=fraction>0
	right.clip.Visible=fraction>.5
	left.gradient.Enabled=fraction<.5
	right.gradient.Enabled=fraction<1
	left.gradient.Rotation=180-360*fraction
	right.gradient.Rotation=180-360*fraction
	left.full.ImageTransparency,right.full.ImageTransparency=alpha or 0,alpha or 0
end

return ring
