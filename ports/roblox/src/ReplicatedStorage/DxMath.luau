-- CTRMathHelper uses a 1024-entry float table, not continuous trig.
local dx={}
local function float(x) return Vector2.new(x,0).X end
local pi=float(math.pi)
local tau=float(math.pi*2)
function dx.length(v) return float(math.sqrt(float(float(v.X*v.X)+float(v.Y*v.Y)))) end
local cosines,sines={},{}
for index=0,1023 do
	local angle=float(float(index*2*pi)/1024)
	cosines[index],sines[index]=float(math.cos(angle)),float(math.sin(angle))
end
function dx.radians(degrees) return float(float(degrees*pi)/180) end
function dx.trig(angle)
	local value=float(float(angle*1024)/tau)
	local index=(value<0 and math.ceil(value) or math.floor(value))%1024
	return cosines[index],sines[index]
end
function dx.rotate(point,angle)
	local c,s=dx.trig(angle)
	return Vector2.new(point.X*c,point.X*s)+Vector2.new(-point.Y*s,point.Y*c)
end
function dx.around(point,angle,center) return dx.rotate(point-center,angle)+center end
dx.float=float
return dx
