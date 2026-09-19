-- MenuController.CreatePackSelect / MonsterSlot, with PackStripLayout at 2560x1440.
-- Box fronts translate. Om Nom does NOT: each moving hole reveals the same screen point.
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Sprites = require(script.Parent.DxSprites)
local Scroller = require(script.Parent.PackScroller)
local Font = require(script.Parent.BitmapFont)
local Locale = require(script.Parent.Localization)
local Session = require(script.Parent.SessionState)
local Layout = require(script.Parent.ViewportLayout)
local PackSelection = {atlas="rbxassetid://95640655976550"}
local colors={{70,37,0},{39,52,0},{44,45,54},{31,42,84},{69,31,50},{75,33,0},
	{84,22,0},{0,51,78},{98,0,0},{66,40,0},{0,47,90},{0,58,0},{63,42,0},
	{89,12,0},{56,45,0},{37,32,104},{55,38,62}}
-- Original TexturePacker rectangles, not restored-canvas guesses.
local quads={
	[2]={112,1,544,253}, [3]={345,367,60,60},
	[1]={112,443,168,176}, [4]={1,1,97,620}, [5]={100,1,10,610},
	[6]={422,367,115,134}, [7]={539,367,109,128}, [8]={282,443,138,138}, [9]={422,256,212,109},
}
local function frame(parent,name,x,y,w,h,z)
	local out=Instance.new("Frame")
	out.Name,out.BackgroundTransparency,out.BorderSizePixel=name,1,0
	out.Position,out.Size=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h)
	out.ZIndex,out.Parent=z,parent
	return out
end
local function sprite(parent,name,quad,x,y,z,rotation)
	local q=quads[quad]
	local out=Instance.new("ImageLabel")
	out.Name,out.BackgroundTransparency,out.Image=name,1,PackSelection.atlas
	out.ImageRectOffset,out.ImageRectSize=Vector2.new(q[1],q[2]),Vector2.new(q[3],q[4])
	out.Position,out.Size=UDim2.fromOffset(x,y),UDim2.fromOffset(q[3],q[4])
	out.Rotation,out.ZIndex,out.Parent=rotation or 0,z,parent
	return out
end
local function quad(image,index)
	local q=quads[index]
	local flip=image:GetAttribute("MirrorX")
	image.ImageRectOffset=Vector2.new(q[1]+(flip and q[3] or 0),q[2])
	image.ImageRectSize=Vector2.new(flip and -q[3] or q[3],q[4])
	image.Size=UDim2.fromOffset(q[3],q[4])
end
function PackSelection.new(parent,selected,onSelected,onOpen,canInput)
	local self={model=Scroller.new(#Sprites.Menu.boxes,selected),connections={},cards={},alive=true,settleTime=0}
	local root=frame(parent,"PackStripLayout",0,0,2560,1440,4)
	root.AnchorPoint,root.Position=Vector2.new(.5,.5),UDim2.fromScale(.5,.5)
	local scale=Instance.new("UIScale",root)
	local function connect(signal,callback) table.insert(self.connections,signal:Connect(callback)) end
	local stripWidth,stripLeft,packOffset=1980,290,0
	local strip=frame(root,"PackStrip",290,0,1980,1440,5)
	strip.ClipsDescendants=true
	self.root,self.strip=root,strip
	-- PlacePackEdge uses trimmed edges, anchored against the strip, not 660px images.
	sprite(root,"SlotLeftBack",4,288,410,4)
	sprite(root,"SlotRightBack",4,2175,410,4,180)
	sprite(root,"SlotLeftFront",5,283,415,10)
	sprite(root,"SlotRightFront",5,2267,415,10,180)
	for index,asset in ipairs(Sprites.Menu.boxes) do
		local unlocked=Session.packUnlocked(index)
		local card=frame(strip,"Box"..index,0,390,660,660,5)
		card:SetAttribute("Unlocked",unlocked)
		local hole=frame(card,"HoleBackground",214,334,231,185,5)
		hole.BackgroundTransparency,hole.BackgroundColor3=0,Color3.fromRGB(table.unpack(colors[index]))
		local window=frame(card,"MonsterReveal"..index,0,0,200,1440,6)
		window.ClipsDescendants=true
		local monster=sprite(window,"ScreenLockedOmNom",1,0,742,6)
		local front=Instance.new("ImageLabel")
		front.Name,front.BackgroundTransparency,front.Image="BoxFront",1,asset
		front.Size,front.ZIndex,front.Parent=UDim2.fromScale(1,1),7,card
		local title=Instance.new("TextLabel")
		title.Name,title.BackgroundTransparency="BoxLabel",1
		title.Position,title.Size=UDim2.fromScale(15/660,140/660),UDim2.fromScale(630/660,120/660)
		title.ZIndex,title.Parent=8,card
		local _,em=Font.measure("")
		local narrow=Session.locale=="en" or Session.locale=="de"
		Font.render(title,index..". "..Locale.get("BOX"..index.."_LABEL"),nil,{scale=em*.75,xScale=narrow and .7/.75 or 1,y=0,referenceSize=Vector2.new(630,120)})
		if not unlocked then
			local lock=sprite(card,"PackLock",2,58,280,8)
			lock.Position,lock.Size=UDim2.fromScale(58/660,280/660),UDim2.fromScale(544/660,253/660)
			local count=Instance.new("TextLabel")
			count.Name,count.BackgroundTransparency="RequiredStars",1
			count.Position,count.Size=UDim2.fromScale(240/660,403/660),UDim2.fromScale(140/660,100/660)
			count.ZIndex,count.Parent=9,card
			Font.render(count,tostring(Session.thresholds[index]),nil,{scale=em*.7,y=0,referenceSize=Vector2.new(140,100)})
			local star=sprite(card,"RequiredStar",3,380,430,9)
			star.Position,star.Size=UDim2.fromScale(380/660,430/660),UDim2.fromScale(60/660,60/660)
		end
		if Session.total(index)==75 then
			local perfect=sprite(card,"PerfectPack",8,100,422,8)
			perfect.Position,perfect.Size=UDim2.fromScale(100/660,422/660),UDim2.fromScale(138/660,138/660)
		end
		if index==17 then
			local badge=sprite(card,"HardestLabel",9,358,461,8)
			badge.Position,badge.Size=UDim2.fromScale(358/660,461/660),UDim2.fromScale(212/660,109/660)
			local caption=Instance.new("TextLabel")
			caption.BackgroundTransparency,caption.Size,caption.Rotation=1,UDim2.fromScale(1,1),-16
			caption.ZIndex,caption.Parent=9,badge
			Font.render(caption,Locale.get("HARDEST_LABEL"),nil,{scale=em*.35,referenceSize=Vector2.new(212,109)})
		end
		table.insert(self.cards,{card=card,hole=hole,front=front,title=title,window=window,monster=monster,unlocked=unlocked})
	end
	local surface=Instance.new("TextButton")
	surface.Name,surface.Text,surface.BackgroundTransparency="PackDragSurface","",1
	surface.Size,surface.ZIndex,surface.AutoButtonColor,surface.Parent=UDim2.fromScale(1,1),12,false,strip
	local function enabled() return self.alive and parent.Visible and parent:GetAttribute("PageReady")==true and canInput() end
	local function select(index)
		self.model:moveTo(index,.8)
		onSelected(self.model.selected)
		self.settleTime=nil
	end
	local function openSelected()
		if not self.model.moving and not self.model.down then onOpen(self.model.selected) end
	end
	for _,direction in ipairs({-1,1}) do
		local button=Instance.new("TextButton")
		button.Name=direction<0 and "PreviousPack" or "NextPack"
		button.Text,button.BackgroundTransparency,button.AutoButtonColor="",1,false
		button.Position=UDim2.fromOffset(direction<0 and 135 or 2310,653)
		button.Size,button.ZIndex,button.Parent=UDim2.fromOffset(115,134),12,root
		local art=sprite(button,"Arrow",6,0,0,12)
		art:SetAttribute("MirrorX",direction>0)
		quad(art,6)
		connect(button.MouseButton1Down,function() if enabled() then quad(art,7) art.Position=UDim2.fromOffset(3,3) end end)
		local function restore() quad(art,6) art.Position=UDim2.fromOffset(0,0) end
		connect(button.MouseButton1Up,restore)
		connect(button.MouseLeave,restore)
		connect(button.Activated,function() if enabled() then select(self.model.selected+direction) end end)
	end
	local pointer,startY
	local function logical(position) return (Vector2.new(position.X,position.Y)-root.AbsolutePosition)/scale.Scale end
	connect(surface.InputBegan,function(input)
		if not enabled() or pointer then return end
		if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
		pointer=input
		local point=logical(input.Position)
		startY=point.Y
		self.model:begin(point.X)
		self.settleTime=nil
	end)
	connect(Input.InputChanged,function(input)
		if not enabled() then return end
		if pointer and (input==pointer or input.UserInputType==Enum.UserInputType.MouseMovement and pointer.UserInputType==Enum.UserInputType.MouseButton1) then
			self.model:drag(logical(input.Position).X)
		elseif input.UserInputType==Enum.UserInputType.MouseWheel then
			local point=logical(Input:GetMouseLocation())
			if point.X>=stripLeft and point.X<=stripLeft+stripWidth and point.Y>=0 and point.Y<=1440 then
				select(self.model.selected-math.sign(input.Position.Z))
			end
		end
	end)
	connect(Input.InputEnded,function(input)
		if input~=pointer then return end
		pointer=nil
		local tap=self.model:release()
		if not enabled() then return end
		if tap then
			local point=logical(input.Position)
			if math.abs(point.Y-startY)<=5 and point.Y>=390 and point.Y<=1050 then
				for index=1,#self.cards do
					local left=stripLeft+660-packOffset+(index-1)*640+self.model.x
					local visible=math.min(left+640,stripLeft+stripWidth)-math.max(left,stripLeft)
					if point.X>=left and point.X<=left+640 and visible>320 then
						if index==self.model.selected and math.abs(self.model.x+(index-1)*640)<1 then openSelected()
						else select(index) end
						return
					end
				end
			end
			-- A background tap while a snap was in flight must not strand boxes between slots.
			self.model:moveTo(self.model.selected,.8)
		else onSelected(self.model.selected) end
	end)
	connect(Input.InputBegan,function(input,processed)
		-- Roblox's default controls can mark arrow keys processed even on a 2D menu.
		if not enabled() or Input:GetFocusedTextBox() or game:GetService("GuiService").MenuIsOpen then return end
		if input.KeyCode==Enum.KeyCode.Left then select(self.model.selected-1)
		elseif input.KeyCode==Enum.KeyCode.Right then select(self.model.selected+1)
		elseif input.KeyCode==Enum.KeyCode.Return or input.KeyCode==Enum.KeyCode.Space then openSelected() end
	end)
	connect(Input.WindowFocusReleased,function()
		if pointer then
			pointer=nil
			self.model:release()
			self.model:moveTo(self.model.selected,.8)
		end
	end)
	local lastX,lastSx,lastSy,lastMoving,lastSelected
	local function draw(dt,force)
		if self.model:update(dt) then self.settleTime=0 onSelected(self.model.selected) end
		if self.settleTime then self.settleTime+=dt end
		local sx,sy=1,1
		if self.settleTime and self.settleTime<.6 then
			local t=self.settleTime
			local a,b,duration,offset
			if t<.15 then a,b,duration,offset=1,.95,.15,0
			elseif t<.35 then a,b,duration,offset=.95,1.05,.2,.15
			else a,b,duration,offset=1.05,1,.25,.35 end
			local f=1-(1-(t-offset)/duration)^2
			sx=a+(b-a)*f sy=2-sx
		end
		local moving=self.model.moving or self.model.down
		if not force and lastX==self.model.x and lastSx==sx and lastSy==sy and lastMoving==moving and lastSelected==self.model.selected then return end
		lastX,lastSx,lastSy,lastMoving,lastSelected=self.model.x,sx,sy,moving,self.model.selected
		for index,entry in ipairs(self.cards) do
			local left=660-packOffset+(index-1)*640+self.model.x
			entry.card.Visible=left+660>0 and left<stripWidth
			if not entry.card.Visible then continue end
			local ax,ay=index==self.model.selected and sx or 1,index==self.model.selected and sy or 1
			-- Squash around the box center. Keep the revealed character in screen space.
			entry.card.Position=UDim2.fromOffset(left+330*(1-ax),390+330*(1-ay))
			entry.card.Size=UDim2.fromOffset(660*ax,660*ay)
			entry.hole.Position,entry.hole.Size=UDim2.fromScale(214/660,334/660),UDim2.fromScale(231/660,185/660)
			local windowLeft,windowRight=math.max(left+240,0),math.min(left+440,stripWidth)
			entry.window.Position=UDim2.fromOffset(windowLeft-entry.card.Position.X.Offset,-entry.card.Position.Y.Offset)
			entry.window.Size=UDim2.fromOffset(math.max(0,windowRight-windowLeft),1440)
			entry.window.Visible=entry.unlocked and windowRight>windowLeft
			entry.monster.Position=UDim2.fromOffset(909-packOffset-windowLeft,742)
		end
		root:SetAttribute("SelectedPack",self.model.selected)
		root:SetAttribute("ScrollOffset",self.model.x)
		root:SetAttribute("Scrolling",self.model.moving or self.model.down)
		root:SetAttribute("MonsterScreenX",1199)
	end
	local function resize()
		local snapshot=Layout.compute(parent.AbsoluteSize)
		local content=math.min(snapshot.content,snapshot.visible.X/980)
		scale.Scale=snapshot.pixels*content
		local count=math.clamp(math.floor((snapshot.visible.X-200)/(660*content)),1,3)
		stripWidth,packOffset=count*660,(3-count)*330
		stripLeft=(2560-stripWidth)/2
		strip.Position,strip.Size=UDim2.fromOffset(stripLeft,0),UDim2.fromOffset(stripWidth,1440)
		root.SlotLeftBack.Position=UDim2.fromOffset(stripLeft-2,410)
		root.SlotRightBack.Position=UDim2.fromOffset(stripLeft+stripWidth-95,410)
		root.SlotLeftFront.Position=UDim2.fromOffset(stripLeft-7,415)
		root.SlotRightFront.Position=UDim2.fromOffset(stripLeft+stripWidth-3,415)
		root.PreviousPack.Position=UDim2.fromOffset(stripLeft-155,653)
		root.NextPack.Position=UDim2.fromOffset(stripLeft+stripWidth+40,653)
		root:SetAttribute("VisibleBoxes",count)
		-- Resizing cancels only an in-flight pointer gesture, not the selected box.
		if pointer then pointer=nil self.model:release() self.model:moveTo(self.model.selected,.8) end
		draw(0,true)
	end
	connect(parent:GetPropertyChangedSignal("AbsoluteSize"),resize)
	resize()
	draw(0)
	connect(RunService.RenderStepped,function(dt) if parent.Visible then draw(dt) end end)
	connect(root.Destroying,function()
		self.alive=false
		for _,connection in ipairs(self.connections) do connection:Disconnect() end
	end)
	return self
end
return PackSelection
