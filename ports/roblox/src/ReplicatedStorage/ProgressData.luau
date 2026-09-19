local data={}
-- content/ctroriginal_packs.json; CTRPreferences and UnlockNextLevel.
data.thresholds={0,30,80,170,240,300,350,400,450,500,550,600,650,700,750,800,850}
data.defaults={sound=true,music=true,drag=true,locale="en",candy=0,rope=0,trace=0,omnom=0}
local locales={en=true,de=true,fr=true,es=true,it=true,nl=true,pt_br=true,ru=true,ko=true,ja=true,zh=true,zh_tw=true}
local limits={candy=51,rope=8,trace=10,omnom=15}
local function integer(n,minimum,maximum)
	return type(n)=="number" and n==n and n%1==0 and n>=minimum and n<=maximum
end
function data.valid(pack,level) return integer(pack,1,17) and integer(level,1,25) end
function data.copy(value)
	if type(value)~="table" then return value end
	local out={} for key,item in pairs(value) do out[key]=data.copy(item) end return out
end
function data.new() return {version=1,records={},unlocked={["1:1"]=true},settings=data.copy(data.defaults)} end
function data.settings(value)
	local out=data.copy(data.defaults)
	if type(value)~="table" then return out end
	for key,default in pairs(out) do
		local candidate=value[key]
		if type(default)=="boolean" and type(candidate)=="boolean" then out[key]=candidate
		elseif key=="locale" and type(candidate)=="string" and locales[candidate] then out[key]=candidate
		elseif limits[key] and integer(candidate,0,limits[key]) then out[key]=candidate end
	end
	return out
end
function data.sanitize(value)
	local out=data.new()
	if type(value)~="table" then return out end
	out.settings=data.settings(value.settings)
	for pack=1,17 do for level=1,25 do
		local key=pack..":"..level
		local record=type(value.records)=="table" and value.records[key]
		if type(record)=="table" and integer(record.stars,0,3) and integer(record.score,0,6000) then
			out.records[key]={stars=record.stars,score=record.score}
			out.unlocked[key]=true
			if level<25 then out.unlocked[pack..":"..(level+1)]=true end
		end
		if type(value.unlocked)=="table" and value.unlocked[key]==true then out.unlocked[key]=true end
	end end
	return out
end
function data.total(profile,pack)
	local stars=0
	for key,record in pairs(profile.records) do
		if not pack or key:match("^(%d+):")==tostring(pack) then stars+=record.stars end
	end
	return stars
end
function data.packUnlocked(profile,pack)
	return data.valid(pack,1) and (profile.unlocked[pack..":1"]==true or data.total(profile)>=data.thresholds[pack])
end
function data.levelUnlocked(profile,pack,level)
	if not data.valid(pack,level) or not data.packUnlocked(profile,pack) then return false end
	return level==1 or profile.unlocked[pack..":"..level]==true
end
function data.unlockNext(profile,pack,level)
	if not data.valid(pack,level) then return end
	profile.unlocked[pack..":1"]=true
	if level<25 then profile.unlocked[pack..":"..(level+1)]=true end
end
function data.result(elapsed,stars)
	local starbonus=1000*stars
	local timebonus=math.max(0,30-elapsed)*100
	return {stars=stars,elapsed=elapsed,starbonus=starbonus,timebonus=timebonus,score=math.ceil(starbonus+timebonus)}
end
function data.complete(profile,pack,level,result)
	assert(data.valid(pack,level) and integer(result.stars,0,3) and integer(result.score,0,6000))
	local key=pack..":"..level
	local old=profile.records[key] or {stars=0,score=0}
	profile.records[key]={stars=math.max(old.stars,result.stars),score=math.max(old.score,result.score)}
	data.unlockNext(profile,pack,level)
end
return data
