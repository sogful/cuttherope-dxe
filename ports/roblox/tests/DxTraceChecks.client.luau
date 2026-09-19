local shared=game.ReplicatedStorage.CutTheRope.Shared
local Trace=require(shared.FingerTrace)
local Session=require(shared.SessionState)
local Font=require(shared.BitmapFont)
local Small=require(shared.SmallFont)
local Metrics=require(shared.FontMetrics)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxTraceChecks",false,game.Players.LocalPlayer.PlayerGui
local canvas=Instance.new("Frame",root)
canvas.Size=UDim2.fromOffset(1120,630)
local renderer=Trace.new(canvas)
local previous=Session.trace
for mode=0,10 do
	Session.trace=mode
	renderer:begin(Vector2.new(200,400))
	for step=1,12 do
		renderer:append(Vector2.new(200+step*30,400+math.sin(step*.4)*80))
		renderer:update(1/60)
	end
	assert(canvas:GetAttribute("TraceSkin")==mode)
	assert(mode==0 or #renderer.particles>0,"No particles for trace "..mode)
	renderer:finish()
	for _=1,120 do renderer:update(1/60) end
	assert(#renderer.particles==0 and #renderer.segments==0,"Trace did not expire")
end
Session.trace=previous
renderer:reset()
local label=Instance.new("TextLabel",canvas)
label.Size=UDim2.fromOffset(400,80)
assert(Font.render(label,"Om Nom Play Candies"))
assert(Font.render(label,"12345",Small))
assert(Metrics.big["i"]<Metrics.big["M"])
assert(Font.glyphs["M"][5]~=nil,"Missing glyph bearing")
root:SetAttribute("Passed",12)
print("DX TRACE/FONT CHECKS PASS: 11 trace lifecycles and font metrics")
