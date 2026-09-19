-- Horizontal specialization of Framework/Visual/ScrollableContainer.cs.
-- Coordinates, speeds and the five-frame release window are DX design units.
local Scroller = {}
Scroller.__index = Scroller
local function approach(value, target, speed, dt)
	return value + math.sign(target - value) * math.min(math.abs(target - value), speed * dt)
end
function Scroller.new(count, selected)
	selected = math.clamp(selected or 1, 1, count)
	return setmetatable({count=count, selected=selected, x=-(selected-1)*640,
		-- HBox: leading spacer 680, -20 spacing, 660-wide boxes, 1000 trailing padding.
		minimum=-(680+count*640+1000-1980), samples={}, cursor=1, pending=0,
		moving=false, down=false, total=0}, Scroller)
end
function Scroller:moveTo(index, multiplier)
	self.selected=math.clamp(index,1,self.count)
	self.target=-(self.selected-1)*640
	self.multiplier=multiplier or .8
	self.moving=true
end
function Scroller:begin(x)
	self.down,self.moving,self.last,self.total,self.pending=true,false,x,0,0
	self.dragged=false
	self.samples,self.cursor={},1
end
function Scroller:drag(x)
	if not self.down then return end
	local delta=x-self.last
	self.last=x
	-- DX drops a discontinuous pointer jump whole; it does not cap a swipe.
	if math.abs(delta)>640 then return end
	self.total+=delta
	self.dragged=self.dragged or math.abs(self.total)>5
	if self.x>0 or self.x<self.minimum then delta*=.5 end
	self.x+=delta
	self.pending+=delta
end
function Scroller:release()
	if not self.down then return false end
	self.down=false
	if not self.dragged then return true end
	local distance,duration=0,0
	for _,sample in pairs(self.samples) do distance+=sample[1] duration+=sample[2] end
	local speed=duration>0 and distance/duration or 0
	local direction=math.abs(speed)>5 and math.sign(speed) or 0
	local nearest,best=nil,math.huge
	for index=1,self.count do
		local offset=-(index-1)*640-self.x
		if (direction==0 or offset==0 or math.sign(offset)==direction) and math.abs(offset)<best then
			nearest,best=index,math.abs(offset)
		end
	end
	nearest=nearest or math.clamp(math.floor(-self.x/640+.5)+1,1,self.count)
	local aligned=math.sign(-(nearest-1)*640-self.x)==math.sign(speed)
	self:moveTo(nearest,aligned and math.max(1,math.abs(speed)/500) or .5)
	return false
end
function Scroller:update(dt)
	local settled=false
	if not self.down then
		if self.x>0 then self.x=approach(self.x,0,50+math.abs(self.x)*5,dt)
		elseif self.x<self.minimum then self.x=approach(self.x,self.minimum,50+math.abs(self.minimum-self.x)*5,dt) end
	end
	if self.moving then
		self.x=approach(self.x,self.target,math.max(100,math.abs(self.target-self.x)*4*self.multiplier),dt)
		if self.x==self.target then self.moving=false settled=true end
	end
	self.samples[self.cursor]={self.pending,dt}
	self.cursor=self.cursor%5+1
	self.pending=0
	return settled
end
return Scroller
