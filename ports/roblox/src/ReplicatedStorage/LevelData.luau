local levels = {}
levels.packs = {
	[1] = require(script.Parent.LevelPack01),
	[2] = require(script.Parent.LevelPack02),
	[3] = require(script.Parent.LevelPack03),
	[4] = require(script.Parent.LevelPack04),
	[5] = require(script.Parent.LevelPack05),
	[6] = require(script.Parent.LevelPack06),
	[7] = require(script.Parent.LevelPack07),
	[8] = require(script.Parent.LevelPack08),
	[9] = require(script.Parent.LevelPack09),
	[10] = require(script.Parent.LevelPack10),
	[11] = require(script.Parent.LevelPack11),
	[12] = require(script.Parent.LevelPack12),
	[13] = require(script.Parent.LevelPack13),
	[14] = require(script.Parent.LevelPack14),
	[15] = require(script.Parent.LevelPack15),
	[16] = require(script.Parent.LevelPack16),
	[17] = require(script.Parent.LevelPack17)
}
levels.list = levels.packs[1]

function levels.get(index, pack)
	local list = levels.packs[pack or 1]
	return list and list[index]
end

function levels.supported(pack, index)
	return levels.get(index, pack) ~= nil
end

return levels
