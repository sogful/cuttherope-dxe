-- BoxOpenClose.ShowOpenCloseAnim and LoadingView.Draw, in 2560x1440 design units.
local RunService = game:GetService("RunService")
local Sprites = require(script.Parent.DxSprites)
local Layout = require(script.Parent.ViewportLayout)
local box = {}
box.__index = box
local function image(parent, name, asset, z)
	local out = Instance.new("ImageLabel")
	out.Name, out.BackgroundTransparency, out.Image = name, 1, asset
	out.ScaleType, out.ZIndex, out.Parent = Enum.ScaleType.Stretch, z, parent
	return out
end
local function rect(object, x, y, w, h)
	object.Position, object.Size = UDim2.fromScale(x / 2560, y / 1440), UDim2.fromScale(w / 2560, h / 1440)
end
function box.new(parent, pack, seams, initial)
	local root = Instance.new("Frame")
	root.Name, root.Size, root.BackgroundTransparency = "BoxPanels", UDim2.fromScale(1, 1), 1
	root.ZIndex, root.Active = 70, true
	Layout.bind(root, parent, "cover")
	local self = setmetatable({root = root}, box)
	self.left = image(root, "CoverLeft", Sprites.Menu.covers[pack], 72)
	self.right = image(root, "CoverRight", Sprites.Menu.covers[pack], 72)
	self.right.Rotation = 180
	-- The side resource is a restored 2560x1440 canvas, with art at x=1284,w=72.
	self.sideLeft = image(root, "SideLeft", Sprites.Menu.coverRight, 71)
	self.sideRight = image(root, "SideRight", Sprites.Menu.coverRight, 71)
	if seams then
		self.seamLeft = image(root, "SeamLeft", Sprites.Menu.loading[1], 73)
		self.seamRight = image(root, "SeamRight", Sprites.Menu.loading[2], 73)
	end
	self:set(initial == nil and 1 or initial)
	root.Parent = parent
	return self
end
function box:set(closed)
	local width, height = 1293 * closed, 1440 * (1.1 - .1 * closed)
	rect(self.left, -13, 0, width, height)
	rect(self.right, 2573 - width, 1440 - height, width, height)
	self.left.ImageColor3 = Color3.new(1 - .15 * closed, 1 - .15 * closed, 1 - .15 * closed)
	self.right.ImageColor3 = Color3.new(.4 + .45 * closed, .4 + .45 * closed, .4 + .45 * closed)
	local side = 1 - closed
	rect(self.sideLeft, -25 + 1293 * closed - 1284 * side, 0, 2560 * side, 1440 * (1 + .3 * closed))
	rect(self.sideRight, 2560 - 1260 * closed - 1284 * side, 0, 2560 * side, 1440 * (1 + .3 * closed))
	if self.seamLeft then
		rect(self.seamLeft, -40 + 1283 * closed, 80, 60 * closed, 1305 * (1.3 - .3 * closed))
		rect(self.seamRight, 2585 - 1295 * closed, 80, 67 * closed, 1305 * (1.3 - .3 * closed))
	end
	self.root:SetAttribute("ClosedFraction", closed)
end
function box:animate(open)
	local elapsed = 0
	while self.root.Parent and elapsed < .5 do
		local fraction = math.min(1, elapsed / .5)
		self:set(open and 1 - fraction or fraction)
		elapsed += RunService.RenderStepped:Wait()
	end
	if self.root.Parent then self:set(open and 0 or 1) end
end
function box:destroy() self.root:Destroy() end
return box
