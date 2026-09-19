local Shared=game.ReplicatedStorage:WaitForChild("CutTheRope"):WaitForChild("Shared")
local Font=require(Shared.BitmapFont)
local RunService=game:GetService("RunService")
local gui=Instance.new("ScreenGui")
gui.Name,gui.Enabled,gui.Parent="DxMenuRepairChecks",false,game.Players.LocalPlayer:WaitForChild("PlayerGui")
local card=Instance.new("Frame")
card.Size,card.Parent=UDim2.fromOffset(660,660),gui
local label=Instance.new("TextLabel")
label.Position,label.Size=UDim2.fromScale(15/660,140/660),UDim2.fromScale(630/660,120/660)
label.Parent=card
local _,em=Font.measure("")
Font.render(label,"1. Cardboard Box",nil,{scale=em*.75,xScale=.7/.75,y=0,referenceSize=Vector2.new(630,120)})
RunService.RenderStepped:Wait()
local glyph=label.BitmapText:FindFirstChildOfClass("ImageLabel")
local size,position,reference=glyph.AbsoluteSize,glyph.AbsolutePosition-label.AbsolutePosition,label.AbsoluteSize
for _,factor in {Vector2.new(.95,1.05),Vector2.new(1.05,.95),Vector2.one} do
	card.Size=UDim2.fromOffset(660*factor.X,660*factor.Y)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	local actual=label.AbsoluteSize/reference
	local at=glyph.AbsolutePosition-label.AbsolutePosition
	assert(math.abs(glyph.AbsoluteSize.X-size.X*actual.X)<.02,"Title width did not follow box")
	assert(math.abs(glyph.AbsoluteSize.Y-size.Y*actual.Y)<.02,"Title height did not follow box")
	assert(math.abs(at.X-position.X*actual.X)<1,"Title X drifted")
	assert(math.abs(at.Y-position.Y*actual.Y)<1,"Title Y drifted")
end
assert(require(Shared.DxSprites).Menu.creditsLogo=="rbxassetid://74852854661204")
gui:SetAttribute("AllPassed",true)
print("DX menu repair checks: title affine transform and complete credits logo PASS")
gui:Destroy()
