local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")
local Layout=require(script.Parent.ViewportLayout)
local Locale=require(script.Parent.Localization)
local Font=require(script.Parent.BitmapFont)
local Small=require(script.Parent.SmallFont)
local Atlas=require(script.Parent.AtlasSprite)
local Frames=require(script.Parent.SkinFrames)
local popup={image="rbxassetid://125393897695949"}
local function wrapped(value,width,small,scale)
	local lines={}
	for _,paragraph in ipairs(string.split(value,"\n")) do
		local line=""
		for word in paragraph:gmatch("%S+%s*") do
			if line~="" and Font.measure(line..word,small)*scale>width then table.insert(lines,(line:gsub("%s+$",""))) line="" end
			for _,code in utf8.codes(word) do
				local char=utf8.char(code)
				if line~="" and Font.measure(line..char,small)*scale>width then table.insert(lines,line) line="" end
				line..=char
			end
		end
		table.insert(lines,(line:gsub("%s+$","")))
	end
	return table.concat(lines,"\n"),#lines
end
function popup.show(page,textures,tap)
	page:SetAttribute("ModalOpen",true)
	local shade=Instance.new("TextButton")
	shade.Name,shade.Text,shade.AutoButtonColor="GameFinishedPopup","",false
	shade.BackgroundColor3,shade.BackgroundTransparency,shade.BorderSizePixel=Color3.new(0,0,0),.5,0
	shade.Size,shade.ZIndex,shade.Visible=UDim2.fromScale(1,1),50,false
	shade.Parent=page
	local design=Layout.group(shade,"PopupLayout","content",{780,180,1780,1160},nil,51)
	local content=Instance.new("Frame")
	content.AnchorPoint,content.Position,content.Size=Vector2.new(.5,.5),UDim2.fromScale(.5,.5),UDim2.fromOffset(2560,1440)
	content.BackgroundTransparency,content.ZIndex,content.Parent=1,51,design
	local scale=Instance.new("UIScale",content)
	local paper=Instance.new("ImageLabel")
	paper.Name,paper.Image,paper.BackgroundTransparency="PopupPaper",popup.image,1
	paper.ImageRectOffset,paper.ImageRectSize=Vector2.new(1,1),Vector2.new(794,794)
	paper.Position,paper.Size=UDim2.fromOffset(798.8,194.4),UDim2.fromOffset(952.8,952.8)
	paper.ZIndex,paper.Parent=51,content
	local function text(name,value,x,y,width,small)
		local _,em=Font.measure("",small)
		local typescale=em
		local string,count=wrapped(value,width,small,typescale)
		local lineheight=small and 80 or 133
		local label=Instance.new("TextLabel")
		label.Name,label.BackgroundTransparency=name,1
		label.AnchorPoint,label.Position=Vector2.new(.5,.5),UDim2.fromOffset(x,y)
		label.Size,label.ZIndex,label.Parent=UDim2.fromOffset(width,count*lineheight*typescale),53,content
		Font.render(label,string,small and Small or nil,{scale=typescale,lineheight=lineheight,y=small and -30*typescale or 0})
	end
	text("FinishedTitle",Locale.get("GAME_FINISHED_TEXT"),1289.6,402.8,600,false)
	text("FinishedThanks",Locale.get("GAME_FINISHED_THANKS"),1289.6,748.8,700,true)
	local button=Instance.new("ImageButton")
	button.Name,button.Image,button.BackgroundTransparency="FinishedOK","",1
	button.AnchorPoint,button.Position,button.Size=Vector2.new(.5,.5),UDim2.fromOffset(1289.6,1086),UDim2.fromOffset(737,176)
	button.ZIndex,button.Parent=54,content
	local function buttonframe(index)
		local q=Frames.buttons[index+1]
		button.Image,button.ImageRectOffset,button.ImageRectSize=Frames.pages[q[1]],Vector2.new(q[2],q[3]),Vector2.new(q[4],q[5])
	end
	buttonframe(0)
	button.MouseButton1Down:Connect(function() buttonframe(1) end)
	button.MouseButton1Up:Connect(function() buttonframe(0) end)
	button.MouseLeave:Connect(function() buttonframe(0) end)
	text("FinishedOKLabel",Locale.get("OK"),1289.6,1086,300,false)
	content.FinishedOKLabel.ZIndex=55
	local closing=false
	button.Activated:Connect(function()
		if closing then return end closing=true if tap then tap() end
		local tween=TweenService:Create(scale,TweenInfo.new(.3,Enum.EasingStyle.Linear),{Scale=0})
		tween:Play() tween.Completed:Wait()
		if page.Parent then page:SetAttribute("ModalOpen",false) end shade:Destroy()
	end)
	task.spawn(function()
		textures:surface(shade)
		while page.Parent and not page:GetAttribute("PageReady") do RunService.RenderStepped:Wait() end
		if not page.Parent then return end
		scale.Scale=0 shade.Visible=true
		for _,step in ipairs({{1.1,.3},{.9,.1},{1,.2}}) do
			if closing or not shade.Parent then break end
			local tween=TweenService:Create(scale,TweenInfo.new(step[2],Enum.EasingStyle.Linear),{Scale=step[1]})
			tween:Play() tween.Completed:Wait()
		end
	end)
	return shade
end
return popup
