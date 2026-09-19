local camera = {}
camera.__index = camera
local viewport = Vector2.new(2560, 1440)

function camera:bounded(focus)
	local wanted = focus - viewport * .5
	return Vector2.new(math.clamp(wanted.X, self.origin.X, self.origin.X + self.range.X), math.clamp(wanted.Y, 0, self.range.Y))
end

function camera:fit()
	local function anchor(value, origin, travel, slack)
		return travel > slack and math.clamp((value-origin)/travel,0,1) or .5
	end
	local x = anchor(self.position.X,self.origin.X,self.scrollable.X,self.slack.X)
	local y = anchor(self.position.Y,0,self.scrollable.Y,self.slack.Y)
	self.render = self.origin + Vector2.new((self.scrollable.X-self.slack.X)*x,(self.scrollable.Y-self.slack.Y)*y)
end

function camera:resize(visible)
	self.visible = visible or viewport
	self.scale = math.min(self.visible.X/self.window.X,self.visible.Y/self.window.Y)
	self.slack = self.visible/self.scale-self.window
	-- Fit reads tracking state; it never mutates the physics/camera timeline.
	self:fit()
end

function camera.new(level, visible)
	local size = level.mapSize or viewport
	local window = Vector2.new(math.min(size.X,viewport.X),math.min(size.Y,viewport.Y))
	local self = setmetatable({size=size,origin=Vector2.new((viewport.X-size.X)*.5,0),
		range=Vector2.new(math.max(0,size.X-viewport.X),math.max(0,size.Y-viewport.Y)),
		window=window,scale=math.min(viewport.X/window.X,viewport.Y/window.Y),fast=false,speed=14,mode="follow",ignoreTouches=false},camera)
	self.scrollable = size-window
	self.visible = visible or viewport
	self.scale = math.min(self.visible.X/window.X,self.visible.Y/window.Y)
	self.slack = self.visible/self.scale-window
	local target = self:bounded(level.candyStart)
	self.position = target
	if self.scrollable.X>self.slack.X or self.scrollable.Y>self.slack.Y then
		self.mode,self.speed,self.ignoreTouches = "intro",20,true
		if size.X>viewport.X then
			self.position=self.origin+Vector2.new(level.candyStart.X>self.origin.X+size.X*.5 and 0 or self.range.X,0)
		else
			self.position=self.origin+Vector2.new(0,level.candyStart.Y>size.Y*.5 and 0 or self.range.Y)
		end
	end
	self.initialDistance=(target-self.position).Magnitude
	self:fit()
	return self
end

function camera:tick(focus, frozen)
	local delta=.016
	local target=self:bounded(focus)
	local difference=target-self.position
	if not frozen or self.mode=="intro" then
		local distance=difference.Magnitude
		if distance>0 then
			local movement=self.mode=="intro" and math.min(distance,self.speed*delta) or math.min(distance,distance*self.speed*delta)
			self.position+=difference*(movement/distance)
		end
	end
	if self.mode=="intro" then
		local distance=(target-self.position).Magnitude
		if distance<100 then self.ignoreTouches=false end
		if self.fast then
			if self.speed<5500 then self.speed*=1.5 end
		elseif distance>self.initialDistance*.5 then self.speed=math.min(1000,self.speed+delta*800)
		else self.speed=math.max(300,self.speed-delta*400) end
		if math.abs(self.position.X-target.X)<1 and math.abs(self.position.Y-target.Y)<1 then
			self.mode,self.speed="follow",14
		end
	end
	self:fit()
end

function camera:press()
	if not self.ignoreTouches then return false end
	if self.mode=="intro" then self.fast=true end
	return true
end

function camera:world(point)
	return point/self.scale+self.render
end

function camera:screen(point)
	return (point-self.render)*self.scale
end

function camera:outside(point)
	-- GameScene.PointOutOfScreen, desktop margins and its horizontal safety net.
	return point.Y>self.size.Y+400 or point.Y< -400 or point.X< -viewport.X or point.X>self.size.X+viewport.X
end

return camera
