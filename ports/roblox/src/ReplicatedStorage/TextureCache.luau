local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local cache = {}
cache.__index = cache

function cache.new(playerGui)
	local root = Instance.new("ScreenGui")
	root.Name, root.ResetOnSpawn, root.Enabled = "DxTextureCache", false, true
	root.DisplayOrder = -1000
	root.Parent = playerGui
	return setmetatable({ root = root, images = {} }, cache)
end

function cache:preload(values, progress)
	local seen, requests = {}, {}
	local function gather(value)
		if type(value) == "table" then
			for _, child in pairs(value) do gather(child) end
		elseif type(value) == "string" and string.find(value, "rbxassetid://", 1, true) and not seen[value] then
			seen[value] = true
			local image = self.images[value]
			if not image then
				image = Instance.new("ImageLabel")
				image.Name, image.Image, image.BackgroundTransparency = "ResidentTexture", value, 1
				-- Hidden images do not acquire drawable textures even after PreloadAsync.
				-- Keep one-pixel instances behind the opaque game/menu backdrops.
				image.Visible, image.Size, image.Parent = true, UDim2.fromOffset(1, 1), self.root
				self.images[value] = image
			end
			if not image.IsLoaded then table.insert(requests, image) end
		end
	end
	gather(values)
	local done = 0
	for first = 1, #requests, 16 do
		local batch = {}
		for index = first, math.min(first + 15, #requests) do table.insert(batch, requests[index]) end
		local ok, message = pcall(function() ContentProvider:PreloadAsync(batch) end)
		if not ok then warn("DX texture request:", message) end
		done += #batch
		if progress then progress(done / #requests) end
	end
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	local retry = {}
	for _, image in ipairs(requests) do if not image.IsLoaded then table.insert(retry, image) end end
	if #retry > 0 then
		pcall(function() ContentProvider:PreloadAsync(retry) end)
		RunService.RenderStepped:Wait()
	end
	local failures, total, ready = 0, 0, 0
	for _, image in ipairs(requests) do if not image.IsLoaded then failures += 1 end end
	for _, image in pairs(self.images) do total += 1 if image.IsLoaded then ready += 1 end end
	self.root:SetAttribute("ResidentTextures", total)
	self.root:SetAttribute("LoadedTextures", ready)
	self.root:SetAttribute("UnavailableTextures", total - ready)
	self.root:SetAttribute("LastFailures", failures)
	if failures > 0 then warn("DX texture cache: " .. failures .. " images are not ready after retry") end
	if progress then progress(1) end
	return failures == 0
end

function cache:surface(root)
	local values, images = {}, {}
	for _, object in ipairs(root:GetDescendants()) do
		if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and object.Image ~= "" then
			table.insert(values, object.Image)
			table.insert(images, object)
		end
	end
	local ok = self:preload(values)
	-- Warm actual drawing instances as well as retaining the shared content.
	local success = pcall(function() ContentProvider:PreloadAsync(images) end)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	return ok and success
end

return cache
