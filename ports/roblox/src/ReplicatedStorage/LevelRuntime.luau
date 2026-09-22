local Physics = require(script.Parent.DxPhysics)
local Camera = require(script.Parent.GameplayCamera)
local SimulationClock = require(script.Parent.SimulationClock)
local Drawing = require(script.Parent.RopeDrawing)
local RopeRenderer = require(script.Parent.RopeRenderer)
local Sprites = require(script.Parent.DxSprites)
local Atlas = require(script.Parent.AtlasSprite)
local TargetAnimator = require(script.Parent.TargetAnimator)
local XmlTargetAnimator = require(script.Parent.XmlTargetAnimator)
local OmNomFrames = require(script.Parent.OmNomFrames)
local SkinAvailability = require(script.Parent.SkinAvailability)
local HookRadius = require(script.Parent.HookRadius)
local Effects = require(script.Parent.EffectFrames)
local HazardFrames = require(script.Parent.HazardFrames)
local CandyBreak = require(script.Parent.CandyBreak)
local SkinFrames = require(script.Parent.SkinFrames)
local Session = require(script.Parent.SessionState)
local BoxVisuals = require(script.Parent.BoxVisuals)
local BoxFrames = require(script.Parent.BoxFrames)
local SplitFrames = require(script.Parent.SplitFrames)
local WheelFrames = require(script.Parent.WheelFrames)
local AdvancedFrames = require(script.Parent.AdvancedFrames)
local DiscFrames = require(script.Parent.DiscFrames)
local DiscVisuals = require(script.Parent.DiscVisuals)
local GhostFrames = require(script.Parent.GhostFrames)
local GhostVisuals = require(script.Parent.GhostVisuals)
local SteamFrames = require(script.Parent.SteamFrames)
local SteamVisuals = require(script.Parent.SteamVisuals)
local LanternFrames = require(script.Parent.LanternFrames)
local LanternVisuals = require(script.Parent.LanternVisuals)
local CheeseFrames = require(script.Parent.CheeseFrames)
local PillowFrames = require(script.Parent.PillowFrames)
local MechanicalFrames = require(script.Parent.MechanicalFrames)
local ConveyorVisuals = require(script.Parent.ConveyorVisuals)
local NightVisuals = require(script.Parent.NightVisuals)
local MouseVisuals = require(script.Parent.MouseVisuals)
local AdvancedVisuals = require(script.Parent.AdvancedBoxVisuals)
local TimedStarRing = require(script.Parent.TimedStarRing)
local Layers = require(script.Parent.GameplayLayers)
local TweenService = game:GetService("TweenService")
local runtime = {}
runtime.__index = runtime

local function position(object, point)
	object.Position = UDim2.fromScale(point.X / 2560, point.Y / 1440)
end

local starBobPositions = {0, -3, 0, 3, 0}
local function starBob(phase)
	local scaled = (phase % 2) * 2
	local segment = math.floor(scaled)
	local fraction = scaled - segment
	local eased = segment % 2 == 0 and (1 - (1 - fraction) ^ 2) or fraction ^ 2
	local from, to = starBobPositions[segment + 1], starBobPositions[segment + 2]
	return from + (to - from) * eased
end
local function image(parent, name, asset, size, z)
	local object = Instance.new("ImageLabel")
	object.Name, object.Image, object.BackgroundTransparency = name, asset, 1
	object.AnchorPoint, object.Size = Vector2.new(.5, .5), UDim2.fromScale(size.X / 1120, size.Y / 630)
	object.ScaleType, object.ZIndex, object.Parent = Enum.ScaleType.Fit, z, parent
	return object
end
local function frame(parent, name, size, z)
	local object = Instance.new("Frame")
	object.Name, object.BackgroundTransparency, object.BorderSizePixel = name, 1, 0
	object.AnchorPoint, object.Size, object.ZIndex, object.Parent = Vector2.new(.5, .5), UDim2.fromScale(size.X / 1120, size.Y / 630), z, parent
	return object
end
local function childimage(parent, name, asset, z)
	local object = image(parent, name, asset, Vector2.new(1120, 630), z)
	object.Position = UDim2.fromScale(.5, .5)
	return object
end

function runtime.new(layer, level, visible)
	layer:ClearAllChildren()
	for name in pairs(layer:GetAttributes()) do
		if string.match(name, "^Hook%d+Captured$") or string.match(name, "^Hook%d+RadiusAlpha$") or string.match(name,"^Half%d+") then layer:SetAttribute(name, nil) end
	end
	layer:SetAttribute("PresentationTime", 0)
	layer:SetAttribute("ScoreTime", 0)
	layer:SetAttribute("HitSpike", nil)
	layer:SetAttribute("CandyBreakTime", nil)
	layer:SetAttribute("SpiderStoleCandy", nil)
	layer:SetAttribute("LastGravityButton", nil)
	for _,name in ipairs({"LastPressWorldX","LastPressWorldY","LastPressHandled","LastLanternPressed"}) do layer:SetAttribute(name,nil) end
	local self = setmetatable({ layer = layer, level = level, physics = Physics.new(level), stars = {}, bubbles = {}, ropes = {}, radii = {}, bursts = {}, elapsed = 0, clock = 0, count = 0, state = "playing", pops = {} }, runtime)
	self.ropeOutlines = {}
	self.camera,self.accumulator = Camera.new(level, visible),0
	self.scheduler=SimulationClock.new()
	self.spikes={}
	for index,definition in ipairs(level.spikes or {}) do
		local spike
		if definition.electric then
			local visual=BoxVisuals.sprite(layer,"Spike"..index,"electro",0,1,Layers.Hazard)
			spike=visual.frame
			self.electrics=self.electrics or {}
			self.electrics[index]=visual
		elseif definition.group~=nil then
			spike=BoxVisuals.sprite(layer,"Spike"..index,"spike",definition.size-1,1,Layers.Hazard,AdvancedFrames).frame
		else spike=CandyBreak.image(layer,"Spike"..index,HazardFrames.spikes[definition.size],definition.point) end
		spike.Rotation,spike.ZIndex=definition.angle,Layers.Hazard
		spike:SetAttribute("SourceQuad",definition.group~=nil and definition.size-1 or definition.size+7)
		self.spikes[index]=spike
	end
	for index, definition in ipairs(level.ropes) do
		local automatic = (definition.radius or -1) >= 0
		position(image(layer, "HookBack" .. index, automatic and Sprites.Hook.autoBack or Sprites.Hook.static, Vector2.new(120, 120), Layers.HookBack), definition.anchor)
		position(image(layer, "HookFront" .. index, automatic and Sprites.Hook.autoFront or Sprites.Hook.staticFront, Vector2.new(120, 120), Layers.HookFront), definition.anchor)
		if definition.rail then layer["HookBack"..index].Visible=false layer["HookFront"..index].Visible=false end
		if automatic then self.radii[index] = HookRadius.new(layer, index, definition) end
		self.ropes[index] = {}
		self.ropeOutlines[index] = {}
	end
	self.candy = frame(layer, "Candy", Vector2.new(130, 138), Layers.Candy)
	self.halves={}
	for index,body in ipairs(self.physics.split or {}) do
		local visual=BoxVisuals.sprite(layer,"CandyHalf"..index,"half"..Session.candy,index-1,.71,Layers.Candy,SplitFrames)
		self.halves[index]={body=body,frame=visual.frame}
	end
	if self.physics.split then
		self.mergeEffect=frame(layer,"CandyMerge",Vector2.new(1,1),Layers.Effect)
		self.mergeAtlas=Atlas.new(self.mergeEffect,{"merge"},SplitFrames,true)
	end
	local candyGroup = "candy" .. Session.candy
	for index = 0, 2 do
		local visual = childimage(self.candy, "CandyLayer" .. (index + 1), "", 7 + index)
		local sprite = Atlas.new(visual, {candyGroup}, SkinFrames)
		sprite:show(candyGroup, index)
	end
	layer:SetAttribute("CandySkin", Session.candy)
	layer:SetAttribute("RopeSkin", Session.rope)
	local starRandom = Random.new()
	for index, point in ipairs(level.stars) do
		local container = frame(layer, "Star" .. index, Vector2.new(245, 245), Layers.Star)
		local glow = Atlas.new(childimage(container, "Glow", "", 5), {"stars"})
		glow:show("stars", 0)
		local idle = Atlas.new(childimage(container, "Idle", "", 6), {"stars"})
		idle:show("stars", 1)
		position(container, point)
		local burst = frame(layer, "StarBurst" .. index, Vector2.new(552, 552) * (1120 / 2560), Layers.StarBurst)
		position(burst, point)
		local effect = Atlas.new(burst, {"starburst"}, Effects, true)
		local timeout=level.starTimeouts and level.starTimeouts[index] or -1
		self.stars[index] = { point = point, container = container, idle = idle, glow = glow, collected = false, burst = burst, effect = effect,
			bobPhase = starRandom:NextInteger(0, 20) / 10, idlePhase = starRandom:NextInteger(0, 20) / 10,
			timeout=timeout,ring=timeout>0 and TimedStarRing.new(layer) or nil }
	end
	local pack=level.pack or 1
	local support=BoxVisuals.sprite(layer,"OmNomSupport","support",pack<=4 and pack-1 or pack<=6 and pack-5 or pack<=8 and pack-7 or pack<=10 and pack-9 or 0,1,Layers.Support,pack<=4 and BoxFrames or pack<=6 and SplitFrames or pack<=8 and WheelFrames or pack<=10 and AdvancedFrames or pack==11 and DiscFrames or pack==12 and GhostFrames or pack==13 and SteamFrames or pack==14 and LanternFrames or pack==15 and CheeseFrames or pack==16 and PillowFrames or MechanicalFrames)
	position(support.frame,level.target)
	self.target = image(layer, "OmNom", "", Vector2.new(270, 270), Layers.Target)
	position(self.target, level.target)
	local selectedSkin = Session.omnom
	if not SkinAvailability.check(selectedSkin) then
		layer:SetAttribute("UnavailableOmNomSkin", selectedSkin)
		selectedSkin = 0
	end
	if selectedSkin > 0 then
		local canvas = OmNomFrames[selectedSkin].canvas
		self.target.Size = UDim2.fromScale(canvas / 2560, canvas / 1440)
		self.animator = XmlTargetAnimator.new(self.target, selectedSkin)
	else
		self.animator = TargetAnimator.new(self.target)
	end
	layer:SetAttribute("OmNomSkin", selectedSkin)
	for index, point in ipairs(level.bubbles) do
		local shadow = image(layer, "BubbleShadow" .. index, Sprites.Bubble.shadows[(index - 1) % 3 + 1], Vector2.new(449, 446) * (1120 / 2560), Layers.BubbleShadow)
		position(shadow, point)
		local visual = image(layer, "Bubble" .. index, "", Vector2.new(449, 446) * (1120 / 2560), Layers.Bubble)
		position(visual, point)
		local sprite = Atlas.new(visual, {"bubble"})
		sprite:show("bubble", 0)
		self.bubbles[index] = { point = point, visual = visual, sprite = sprite, shadow = shadow, state = "free" }
	end
	self.ropeRenderer = RopeRenderer.new(layer)
	self.objects=BoxVisuals.new(layer,self.physics,level.pack or 1)
	self.advanced=AdvancedVisuals.new(layer,self.physics)
	self.discs=DiscVisuals.new(layer,self.physics.mechanics.discs)
	self.ghosts=GhostVisuals.new(layer,self.physics.ghosts)
	self.ghosts:update(0)
	self.steam=SteamVisuals.new(layer,self.physics.steam)
	self.conveyors=ConveyorVisuals.new(layer,self.physics.conveyors)
	self.lanterns=LanternVisuals.new(layer,self.physics.lanterns,Session.candy)
	self.mice=MouseVisuals.new(layer,self.physics.mice)
	self.night=NightVisuals.new(self)
	self.night:tick(0)
	self.discs:update()
	self.objects:update(0)
	self:draw()
	return self
end

function runtime:press(point)
	if self.state~="playing" or self.camera.ignoreTouches then return false end
	local used=self.physics.mechanics:press(point)
	if game:GetService("RunService"):IsStudio() then
		self.layer:SetAttribute("LastPressWorldX",point.X)
		self.layer:SetAttribute("LastPressWorldY",point.Y)
		self.layer:SetAttribute("LastPressHandled",used)
		self.layer:SetAttribute("LanternSharedPoint",self.physics.lanterns.shared~=nil)
		self.layer:SetAttribute("LastLanternPressed",self.physics.lanterns.lastPressed)
	end
	return used
end

function runtime:drag(point)
	if self.state=="playing" then self.physics.mechanics:drag(point) end
end

function runtime:release(point)
	self.physics.mechanics:release(self.state=="playing" and point or nil)
end

function runtime:gravityShortcut()
	if self.state~="playing" or self.camera.ignoreTouches then return false end
	local used=self.physics.mechanics:toggleNearestGravity(self.camera:world(self.camera.visible*.5))
	if used then self.layer:SetAttribute("LastGravityButton",self.physics.mechanics.lastGravityButton) end
	return used
end

function runtime:pop(point)
	-- GameScene.Input.TryPopBodyBubble uses a 120x120 square, not the visible bubble radius.
	if self.state ~= "playing" or self.camera.ignoreTouches then return false end
	for _,body in ipairs(self.physics:activeBodies()) do
	if not self.physics:hasBubble(body) then continue end
	local distance=point-body.pos
	if distance.X < -60 or distance.X >= 60 or distance.Y < -60 or distance.Y >= 60 then continue end
	for _,bubble in ipairs(self.bubbles) do if bubble.body==body then
		bubble.state,bubble.visual.Visible="popped",false
		if self.attached==bubble then self.attached=nil end
	end end
	self.physics:popBubble(body)
	local pop = image(self.layer, "BubblePop", "", Vector2.new(449, 446) * (1120 / 2560), Layers.Effect)
	position(pop, body.pos)
	local sprite = Atlas.new(pop, {"bubble"})
	sprite:show("bubble", 18)
	table.insert(self.pops, { visual = pop, sprite = sprite, start = self.clock })
	return true
	end
	return false
end

function runtime:cut(a, b, radius)
	if self.state ~= "playing" or self.camera.ignoreTouches then return false end
	return self.physics:cut(a, b, radius)
end

function runtime:resize(visible)
	self.camera:resize(visible)
	self:draw()
end

function runtime:draw()
	local camera = self.camera
	local v = camera.visible
	self.layer.Position = UDim2.fromScale(-camera.render.X*camera.scale/v.X,-camera.render.Y*camera.scale/v.Y)
	self.layer.Size = UDim2.fromScale(2560*camera.scale/v.X,1440*camera.scale/v.Y)
	self.layer:SetAttribute("ViewportWidth",v.X)
	self.layer:SetAttribute("ViewportHeight",v.Y)
	self.layer:SetAttribute("CameraScale",camera.scale)
	self.layer:SetAttribute("CameraX",camera.render.X)
	self.layer:SetAttribute("CameraY",camera.render.Y)
	self.layer:SetAttribute("CameraMode",camera.mode)
	self.layer:SetAttribute("CameraSpeed",camera.speed)
	self.layer:SetAttribute("IgnoreTouches",camera.ignoreTouches)
	local candyposition = self.physics.candy.pos
	self.candy.CandyLayer2.Rotation=self.physics.candy.rotation or 0
	if self.physics.stolen then
		local spider=self.physics.mechanics.spiders[self.physics.stolen]
		position(self.candy,spider.point+Vector2.new(0,-5))
	elseif self.state ~= "won" then position(self.candy, candyposition) end
	self.layer:SetAttribute("CandyX", candyposition.X)
	self.layer:SetAttribute("CandyY", candyposition.Y)
	self.layer:SetAttribute("Level", self.level.id)
	self.layer:SetAttribute("State", self.state)
	self.layer:SetAttribute("Stars", self.count)
	local bubbled=false
	for _,body in ipairs(self.physics:activeBodies()) do if self.physics:hasBubble(body) then bubbled=true end end
	self.layer:SetAttribute("Bubbled", bubbled)
	self.layer:SetAttribute("Teleports",self.physics.teleports or 0)
	self.layer:SetAttribute("Transporting",self.physics.transport~=nil)
	self.layer:SetAttribute("InLantern",self.physics.lanterns.inLantern==true)
	self.layer:SetAttribute("LanternSharedPoint",self.physics.lanterns.shared~=nil)
	self.layer:SetAttribute("LanternCaptures",self.physics.lanterns.captures)
	self.layer:SetAttribute("LanternReleases",self.physics.lanterns.releases)
	local mouse=self.physics.mice.active
	self.layer:SetAttribute("MouseIndex",mouse and mouse.index or 0)
	self.layer:SetAttribute("MouseHasCandy",mouse and mouse.carry~=nil or false)
	self.layer:SetAttribute("MouseCaptures",self.physics.mice.captures)
	self.layer:SetAttribute("MouseReleases",self.physics.mice.releases)
	self.layer:SetAttribute("MouseHandoffs",self.physics.mice.handoffs)
	if not self.physics.stolen and self.state~="won" and self.state~="breaking" and not self.broken then self.candy.Visible=self.physics.transport==nil and not self.physics.split and not self.physics.lanterns.inLantern end
	self.layer:SetAttribute("SplitCandy",self.physics.split~=nil)
	self.layer:SetAttribute("MergedCandy",self.physics.merged==true)
	for index,half in ipairs(self.halves) do
		position(half.frame,half.body.pos)
		half.frame.Rotation=half.body.rotation or 0
		half.frame.Visible=self.physics.split~=nil and not half.body.removed
		self.layer:SetAttribute("Half"..index.."X",half.body.pos.X)
		self.layer:SetAttribute("Half"..index.."Y",half.body.pos.Y)
		self.layer:SetAttribute("Half"..index.."Bubble",half.body.bubble==true)
	end
	for index,spike in ipairs(self.spikes) do
		local object=self.physics.hazards.objects[index]
		position(spike,object.point)
		spike.Rotation=object.angle
		if self.electrics and self.electrics[index] then
			self.electrics[index].atlas:show("electro",object.on and math.floor(object.clock*20)%4+1 or 0)
			spike:SetAttribute("Active",object.on)
		end
	end
	local attached = 0
	for ropeindex, rope in ipairs(self.physics.ropes) do
		if not rope.definition.ghost then
			position(self.layer["HookBack"..ropeindex],rope.anchor)
			position(self.layer["HookFront"..ropeindex],rope.anchor)
			local scale=rope.beltScale or 1
			self.layer["HookBack"..ropeindex].Size=UDim2.fromScale(120*scale/1120,120*scale/630)
			self.layer["HookFront"..ropeindex].Size=self.layer["HookBack"..ropeindex].Size
		end
		self.ropes[ropeindex]=self.ropes[ropeindex] or {}
		self.ropeOutlines[ropeindex]=self.ropeOutlines[ropeindex] or {}
		if rope.active and not rope.cut then attached += 1 end
		if self.radii[ropeindex] then self.radii[ropeindex]:update(rope.radiusAlpha,rope.anchor) end
		self.layer:SetAttribute("Hook" .. ropeindex .. "Captured", rope.captured)
		self.layer:SetAttribute("Hook" .. ropeindex .. "RadiusAlpha", rope.radiusAlpha)
		if not self.ropeRenderer then
		local paths = Drawing.paths(rope)
		local used = 0
		for _, path in ipairs(paths) do
			local samples = Drawing.samples(path)
			local style = Drawing.style(path, rope)
			for index = 1, #samples - 1 do
				used += 1
				local segment = self.ropes[ropeindex][used]
				if not segment then
					segment = Instance.new("Frame")
					segment.Name, segment.AnchorPoint, segment.BorderSizePixel = "Rope" .. ropeindex .. "Segment" .. used, Vector2.new(.5, .5), 0
					segment.ZIndex, segment.Parent = Layers.Rope, self.layer
					self.ropes[ropeindex][used] = segment
					local outline = Instance.new("Frame")
					outline.Name, outline.AnchorPoint, outline.BorderSizePixel = segment.Name .. "Outline", Vector2.new(.5, .5), 0
					outline.BackgroundColor3 = Color3.new(0, 0, 0)
					outline.ZIndex, outline.Parent = Layers.RopeOutline, self.layer
					self.ropeOutlines[ropeindex][used] = outline
				end
				local a, b = samples[index], samples[index + 1]
				local difference = Vector2.new((b.X - a.X) * self.layer.AbsoluteSize.X / 2560, (b.Y - a.Y) * self.layer.AbsoluteSize.Y / 1440)
				segment.Size = UDim2.fromOffset(difference.Magnitude + 1, math.max(1, self.layer.AbsoluteSize.X * 10 / 2560))
				segment.Rotation, segment.BackgroundColor3 = math.deg(math.atan2(difference.Y, difference.X)), Drawing.color(index, #samples - 1, style)
				segment.BackgroundTransparency, segment.Visible = 1 - style.alpha, not rope.cut or rope.remaining > 0
				local outline = self.ropeOutlines[ropeindex][used]
				outline.Size = UDim2.fromOffset(difference.Magnitude + 1, math.max(1, self.layer.AbsoluteSize.X * 14 / 2560))
				outline.Rotation = segment.Rotation
				outline.Visible, outline.BackgroundTransparency = style.outline and segment.Visible, 1 - .4 * style.alpha
				position(segment, (a + b) * .5)
				outline.Position = segment.Position
			end
		end
		for index = used + 1, #self.ropes[ropeindex] do
			self.ropes[ropeindex][index].Visible = false
			self.ropeOutlines[ropeindex][index].Visible = false
		end
		end
	end
	if not self.ropeRenderer then
		for i=#self.physics.ropes+1,#self.ropes do
			for _,segment in ipairs(self.ropes[i]) do segment.Visible=false end
			for _,segment in ipairs(self.ropeOutlines[i]) do segment.Visible=false end
		end
	end
	if self.ropeRenderer then
		local ok,message=pcall(self.ropeRenderer.draw,self.ropeRenderer,self.physics.ropes,camera)
		if not ok then
			self.ropeRenderer.image:Destroy()
			self.ropeRenderer=nil
			self.layer:SetAttribute("RopeRenderer","GuiFallback")
			self.layer:SetAttribute("RopeRendererError",tostring(message))
			self:draw()
		end
	end
	self.layer:SetAttribute("AttachedRopes", attached)
end

function runtime:step(delta)
	local wasPlaying=self.state=="playing"
	local intro=self.camera.mode=="intro"
	self.camera:tick(self.physics:focus())
	if intro then return end
	self.physics:tick()
	for _,b in ipairs(self.physics.bulbs) do
		if not b.removed and not b.transport and self.camera:outside(b.pos) then self.physics:retireCandy(b) end
	end
	self.clock += delta
	if self.state == "playing" then self.elapsed += delta end
	local point = self.physics.candy.pos
	if self.physics.merged and not self.mergeStart then self.mergeStart,self.mergePosition=self.clock,point end
	if self.state=="playing" and self.physics.stolen then
		self.state,self.lossDelay="failed",2
		self.animator:play("sad")
		self.layer:SetAttribute("SpiderStoleCandy",self.physics.stolen)
	end
	if self.broken then
		self.broken:update(.016)
	end
	if self.state=="playing" and self.physics.hazard then
		self:pop((self.physics.failedBody or self.physics.candy).pos)
		self.state,self.breaktime,self.lossDelay="breaking",self.clock,1.3
		self.candy.Visible=false
		self.broken=CandyBreak.new(self.layer,(self.physics.failedBody or self.physics.candy).pos,Session.candy,nil,self.physics.gravityInverted)
		if self.physics.audio then self.physics.audio:play("candy_break") end
		self.layer:SetAttribute("HitSpike",self.physics.hazard)
	elseif self.state=="breaking" and self.clock-self.breaktime>=.3 then
		self.state="failed"
		self.animator:play("sad")
	end
	self.night:tick(.016)
	if self.state == "playing" and not self.physics.transport and not self.physics.split and (not self.physics.night.enabled or self.physics.night.awake) then self.animator:proximity(self.physics.lanterns.inLantern and math.huge or (point - self.physics.target).Magnitude, delta) end
	self.animator:update(delta)
	for index, star in ipairs(self.stars) do
		star.point=self.physics.starPositions[index]
		if star.timeout>0 and not star.collected then
			local time=math.max(0,star.timeout-self.physics.mechanics.time)
			if time==0 and not star.expired then
				self.physics.conveyors:remove((self.physics.conveyors.byKind.star or {})[index])
				star.expired=self.clock
				star.shrink=Instance.new("UIScale",star.container)
			end
		end
		local touching=false
		for _,body in ipairs(self.physics:activeBodies()) do
			if body.isLight then continue end
			local d=(body==self.physics.candy and (#self.physics.lanterns.objects>0 or #self.physics.mice.objects>0) and body.drawPosition or body.pos)-star.point
			if body.part then
				-- GetSplitCandyBoundingBox against GetStarBoundingBox; the
				-- latter uses the un-restored 236x223 glow quad's top-left.
				if d.X>-94.5 and d.X<75.5 and d.Y>-90.5 and d.Y<67.5 then touching=true end
			elseif math.abs(d.X)<97 and math.abs(d.Y)<93 then touching=true end
		end
		if self.state == "playing" and touching and (not self.physics.night.enabled or self.physics.night.lit[index]) and not star.collected and not star.expired then
			star.collected, star.container.Visible = true, false
			self.physics.conveyors:remove((self.physics.conveyors.byKind.star or {})[index])
			if star.ring then star.ring.root.Visible=false end
			self.count += 1
			if self.physics.audio then
				self.physics.audio:play("star_"..self.count)
				if self.animator.state=="idle" and not self.animator.mouth then self.physics.audio:omnom("monster_excited",self.layer:GetAttribute("OmNomSkin")) end
			end
			self.animator:excited()
			local visual = star.burst
			position(visual, star.point)
			local sprite = star.effect
			sprite:show("starburst", 0)
			table.insert(self.bursts, { visual = visual, sprite = sprite, start = self.clock })
		end
	end
	self:checkOutcome(point)
	if self.audioTick then self.audioTick(delta) end
	if wasPlaying and self.state~="playing" then
		self.outcomeTime=self.clock
		self.physics.conveyors:cancel()
	end
	if self.state~="playing" and not self.physics.mice.locked then self.physics.mice:shutdown() end
end

function runtime:advance(delta)
	local before=self.clock
	self.scheduler:advance(delta,function(step) self:step(step) end)
	self.accumulator=self.scheduler.remainder
	self.pendingPresentation=(self.pendingPresentation or 0)+self.clock-before
end

function runtime:present()
	local delta=self.pendingPresentation or 0
	self.pendingPresentation=0
	self.presentationDelta=delta
	self.objects:update(delta)
	self.discs:update()
	self.ghosts:update(delta)
	self.steam:update()
	self.conveyors:update()
	self.lanterns:update()
	self.mice:update()
	position(self.target,self.physics.target)
	self.advanced:update()
	if self.mergeEffect and self.mergeStart then
		local age=self.clock-self.mergeStart
		self.mergeEffect.Visible=age<.25
		if age<.25 then
			local quad=math.min(4,math.floor(age/.05))
			local q=SplitFrames.merge[quad+1]
			self.mergeEffect.Size=UDim2.fromScale(q[8]/2560,q[9]/1440)
			self.mergeAtlas:show("merge",quad)
			position(self.mergeEffect,self.mergePosition)
		end
	end
	if self.physics.stolen then
		local spider=self.physics.mechanics.spiders[self.physics.stolen]
		position(self.candy,spider.point+Vector2.new(0,-5))
		self.candy.Visible=not spider.hidden
	end
	for index,star in ipairs(self.stars) do
		local visualPoint = star.point + Vector2.new(0, starBob(self.clock + star.bobPhase))
		position(star.container,visualPoint)
		local item=(self.physics.conveyors.byKind.star or {})[index]
		local scale=item and item.scale or 1
		star.container.Size=UDim2.fromScale(245*scale/1120,245*scale/630)
		local mover=self.physics.starMovers[index]
		if mover then star.container.Rotation=mover.angle end
		if not star.collected and not star.expired then star.idle:show("stars",math.floor((self.clock+star.idlePhase)*20)%18+1) end
		if star.timeout>0 and not star.collected then
			local time=math.max(0,star.timeout-self.physics.mechanics.time)
			local age=star.expired and self.clock-star.expired or 0
			star.ring:update(visualPoint,time/star.timeout,math.min(1,age/.5))
			if star.expired then star.shrink.Scale=math.max(0,1-age/.25) star.container.Visible=age<.25 end
		end
	end
	for bubbleindex, bubble in ipairs(self.bubbles) do
		if bubble.state=="free" then
			bubble.point=self.physics.bubbles[bubbleindex]
			local item=(self.physics.conveyors.byKind.bubble or {})[bubbleindex]
			local scale=item and item.scale or 1
			bubble.visual.Size=UDim2.fromScale(449*scale/2560,446*scale/1440)
			bubble.shadow.Size=bubble.visual.Size
			position(bubble.visual,bubble.point)
			position(bubble.shadow,bubble.point)
		end
		local owner=nil
		for _,body in ipairs(self.physics:activeBodies()) do
			local index=body==self.physics.candy and self.physics.bubbleIndex or body.bubbleIndex
			if self.physics:hasBubble(body) and index==bubbleindex then owner=body break end
		end
		if owner then
			if bubble.state=="free" then
				bubble.state="attached"
				bubble.shadow.Visible = false
				bubble.visual.ZIndex = Layers.AttachedBubble
				bubble.visual.Size = UDim2.fromScale(250 / 2560, 250 / 1440)
			end
			bubble.body=owner
			if owner==self.physics.candy then self.attached=bubble end
			-- Capture squash is a one-shot presentation, not a perpetual wobble.
			local age=math.max(0,self.physics.mechanics.time-(owner.bubbleCaptureTime or 0))
			-- Quad 7 is the circular neutral pose (157x157); quad 16 is still
			-- stretched (143x171) and must not be held after the capture cycle.
			bubble.sprite:show("bubble", age<.65 and math.min(12,math.floor(age*20))+4 or 7)
			position(bubble.visual,owner.pos)
		elseif bubble.state=="attached" or (bubble.state=="free" and self.physics.usedBubbles[bubbleindex]) then
			bubble.state,bubble.visual.Visible="popped",false
			bubble.shadow.Visible=false
			if self.attached==bubble then self.attached=nil end
		end
	end
	for index = #self.pops, 1, -1 do
		local pop = self.pops[index]
		local age = self.clock - pop.start
		if age >= .6 then pop.visual:Destroy() table.remove(self.pops, index)
		else pop.sprite:show("bubble", math.floor(age * 20) + 18) end
	end
	for index = #self.bursts, 1, -1 do
		local burst = self.bursts[index]
		local age = self.clock - burst.start
		if age >= .65 then burst.visual:Destroy() table.remove(self.bursts, index)
		else burst.sprite:show("starburst", math.floor(age * 20)) end
	end
	self:draw()
	self.night:update()
	self.layer:SetAttribute("PresentationTime", self.clock)
	self.layer:SetAttribute("ScoreTime", self.elapsed)
	self.layer:SetAttribute("SimulationTicks",self.scheduler.ticks)
	self.layer:SetAttribute("StallTimeDropped",self.scheduler.dropped)
end

function runtime:update(delta)
	self:advance(delta)
	self:present()
end

function runtime:checkOutcome(point)
	if self.state ~= "playing" then return end
	if self.physics.night.enabled then
		local any=false
		for _,b in ipairs(self.physics.bulbs) do if not b.removed then any=true break end end
		if not any then self.state="failed" self.animator:play("sad") return end
	end
	if self.physics.transport then return end
	local distance = point - self.physics.target
	-- Desktop GameScene.BoundingBoxes + LoadTarget, relative to sprite centers:
	-- candy [-54.5,57.5] x [-52,52], mouth [-56,52] x [30,32].
	if not self.physics.split and not self.physics.lanterns.inLantern and (not self.physics.night.enabled or self.physics.night.awake) and self.animator.mouth and distance.X > -113.5 and distance.X < 106.5 and distance.Y > -22 and distance.Y < 84 then
		self.state = "won"
		self.animator:play("chewing")
		self.physics:retireCandy()
		if self.attached then self.attached.visual.Visible = false end
		local shrink = Instance.new("UIScale", self.candy)
		TweenService:Create(shrink, TweenInfo.new(.1, Enum.EasingStyle.Linear), { Scale = 0 }):Play()
		TweenService:Create(self.candy, TweenInfo.new(.1, Enum.EasingStyle.Linear), { Position = UDim2.fromScale(self.physics.target.X / 2560, (self.physics.target.Y + 10) / 1440) }):Play()
	else
		for _,body in ipairs(self.physics:activeBodies()) do
			if body.isLight then continue end
			if self.camera:outside(body.pos) then
				self.state = "failed"
				if body.part then self.physics:retireCandy(body) else self.physics.disableCapture=true end
				self.animator:play("sad")
				break
			end
		end
	end
	self.layer:SetAttribute("State", self.state)
end

return runtime
