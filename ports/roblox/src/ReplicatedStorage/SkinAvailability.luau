local Frames = require(script.Parent.OmNomFrames)
local ContentProvider = game:GetService("ContentProvider")
local availability = {}

function availability.check(slot)
	if slot == 0 then return true end
	local data = Frames[slot]
	if not data then return false, "Unknown skin" end
	if slot == 7 and data.pipeRemoved ~= true then return false, "Pirate requires pipe-free artwork" end
	for _, image in ipairs(data.library.pages) do
		if not string.match(image, "^rbxassetid://%d+$") then return false, "Upload incomplete" end
		local status = ContentProvider:GetAssetFetchStatus(image)
		if status == Enum.AssetFetchStatus.Failure then return false, "Asset unavailable" end
		if status ~= Enum.AssetFetchStatus.Success then return false, "Textures not ready" end
	end
	return true
end

return availability
