local Data=require(script.Parent.ProgressData)
local real=Data.new()
local active=real
local state = { records = real.records, sound = true, music = true, drag = true, locale = "en", candy = 0, rope = 0, trace = 0, omnom = 0, unlockAll=false }
local function changed(command) if state.onChange then state.onChange(command) end end

function state.load(profile)
	real=Data.sanitize(profile)
	active=state.unlockAll and Data.copy(real) or real
	state.records=active.records
	for key,value in pairs(real.settings) do state[key]=value end
end
function state.export()
	local out=Data.copy(real)
	out.settings=Data.settings(state)
	return out
end
function state.setUnlockAll(enabled)
	if state.unlockAll==enabled then return end
	state.unlockAll=enabled==true
	active=state.unlockAll and Data.copy(real) or real
	state.records=active.records
	changed({kind="cheat",enabled=state.unlockAll})
end
function state.packUnlocked(pack) return Data.valid(pack,1) and (state.unlockAll or Data.packUnlocked(active,pack)) end
function state.levelUnlocked(pack,level) return Data.valid(pack,level) and (state.unlockAll or Data.levelUnlocked(active,pack,level)) end
function state.unlockNext(pack,level)
	Data.unlockNext(active,pack,level)
	if not state.unlockAll then changed({kind="skip",pack=pack,level=level}) end
end
state.thresholds=Data.thresholds

-- Session-scoped tutorial state, deliberately not cleared by progress reset.
function state.claimTitleHint()
	if state.titleHintShown or state.candyChanged then return false end
	state.titleHintShown = true
	return true
end

function state.result(elapsed, stars)
	return Data.result(elapsed,stars)
end

function state.complete(pack, level, result)
	Data.complete(active,pack,level,result)
	if not state.unlockAll then changed({kind="complete",pack=pack,level=level,stars=result.stars,elapsed=result.elapsed}) end
end

function state.record(pack, level)
	return state.records[pack .. ":" .. level] or { stars = 0, score = 0 }
end

function state.total(pack)
	local stars = 0
	for key, record in pairs(state.records) do
		if not pack or string.match(key, "^(%d+):") == tostring(pack) then stars += record.stars end
	end
	return stars
end

function state.reset()
	table.clear(active.records)
	active.unlocked={["1:1"]=true}
	if not state.unlockAll then changed({kind="reset"}) end
end

return state
