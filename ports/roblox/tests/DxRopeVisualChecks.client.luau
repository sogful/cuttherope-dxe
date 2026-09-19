local shared = game.ReplicatedStorage.CutTheRope.Shared
local Drawing = require(shared.RopeDrawing)
local function close(a, b) assert(math.abs(a-b) < .00001, tostring(a) .. " ~= " .. tostring(b)) end
local points = {Vector2.new(0,0),Vector2.new(70,130),Vector2.new(180,160),Vector2.new(200,300)}
local samples = Drawing.samples(points)
assert(#samples == 13)
table.remove(points)
assert(Drawing.samples(points) == samples and #samples == 9)
local fresh = Drawing.samples(table.clone(points))
for i, p in ipairs(samples) do assert((p-fresh[i]).Magnitude < .00001) end
assert(samples[#samples] == points[#points])
table.clear(points)
assert(#Drawing.samples(points) == 0)
points[1] = Vector2.new(1,2)
assert(#Drawing.samples(points) == 1)
points[2] = Vector2.new(101,2)
assert(#Drawing.samples(points) == 5)

local rope = {active=true,cut=true,split=3,remaining=1.95,points={}}
for i=1,6 do rope.points[i]=Vector2.new(i*105,0) end
local paths = Drawing.paths(rope)
local head, tail = paths[1], paths[2]
assert(#paths==2 and #head==3 and #tail==3)
rope.points[4] += Vector2.new(0,20)
assert(Drawing.paths(rope)==paths and paths[1]==head and paths[2]==tail)
table.remove(rope.points)
assert(#Drawing.paths(rope)==1 and paths[1]==head and #tail==2)
rope.active=false
assert(#Drawing.paths(rope)==0)

local straight = {Vector2.zero,Vector2.new(105,0),Vector2.new(210,0)}
local default = Drawing.style(straight, {}, 0)
close(Drawing.color(1,8,default).R,.675555556*.45)
local teal = Drawing.style(straight, {}, 2)
close(Drawing.color(1,8,teal).R,.773)
close(Drawing.color(4,8,teal).R,.404)
assert(teal.outline and not default.outline)
straight[2] = Vector2.new(113,0)
local stretched = Drawing.style(straight, {}, 2)
close(stretched.base[1].R,.475)
close(stretched.shade[1].R,.404*.4*113/105*2)
local highlight = Drawing.style(straight, {highlighted=true}, 2)
close(highlight.shade[1].R,.404*.4*3)
local flash = Drawing.style(straight, {cut=true,pendingCut=2,remaining=1.96},2)
assert(flash.alpha==1 and Drawing.color(1,8,flash)==Color3.new(1,1,1))
local fading = Drawing.style(straight,{cut=true,remaining=.975},2)
close(fading.alpha,.5)
for skin=0,8 do
	local style = Drawing.style({Vector2.zero,Vector2.new(105,0)}, {}, skin)
	assert(style.alpha==1 and not style.white)
end
script:SetAttribute("Passed",true)
print("DX ROPE VISUAL CHECKS PASS: shrinking/growing samples, retained cut paths, 9 palettes, stretch/highlight/cut/fade")
