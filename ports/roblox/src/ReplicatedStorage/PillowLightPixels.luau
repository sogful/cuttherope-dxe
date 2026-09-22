--!native
local data=require(script.Parent.PillowLightData)
local function decode(hex)
	return buffer.fromstring((hex:gsub("..",function(pair) return string.char(tonumber(pair,16)) end)))
end
local light,background=decode(data.light),decode(data.background)
local size,width,height=data.lightSize,data.backgroundWidth,data.backgroundHeight
local rows,coordinates={},{}
for index=0,size-1 do coordinates[index+1]=(index+.5)/size-.5 end
for y=0,size-1 do
	local row={}
	for x=0,size-1 do
		local offset=(y*size+x)*4
		local strength=buffer.readu8(light,offset+3)/255*.6
		local red=buffer.readu8(light,offset)/255*strength
		local green=buffer.readu8(light,offset+1)/255*strength
		local blue=buffer.readu8(light,offset+2)/255*strength
		if red>0 or green>0 or blue>0 then row[#row+1]={offset,x+1,red,green,blue} end
	end
	rows[y+1]=row
end

local pixels={}
pixels.__index=pixels
local function sample(left,right,top,bottom,fx,fy,channel)
	local a=buffer.readu8(background,top+left+channel)
	local b=buffer.readu8(background,top+right+channel)
	local c=buffer.readu8(background,bottom+left+channel)
	local d=buffer.readu8(background,bottom+right+channel)
	return ((a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy)/255
end
local function byte(value)
	return math.clamp(math.floor(value*255+.5),0,255)
end

function pixels.new()
	return setmetatable({output=buffer.create(size*size*4),left={},right={},fraction={}},pixels)
end

function pixels:update(point,radius,camera)
	local visible=camera.visible or Vector2.new(2560,1440)
	local scale=math.max(visible.X/camera.scale/2048,visible.Y/camera.scale/1152)
	if self.point and (self.point-point).Magnitude<.5 and self.scale==scale and self.radius==radius then return nil end
	self.point,self.scale,self.radius=point,scale,radius
	local spanx,spany=radius*3,radius*3*425/405
	local left,right,fraction=self.left,self.right,self.fraction
	for x=1,size do
		local world=point.X+coordinates[x]*spanx
		local u=(((world-1280)/scale+1024)/2048*width-.5)%width
		local ix=math.floor(u)
		left[x],right[x],fraction[x]=ix*3,((ix+1)%width)*3,u-ix
	end
	local output=self.output
	for y,row in ipairs(rows) do
		local world=point.Y+coordinates[y]*spany
		local v=(((world-720)/scale+576)/1152*height-.5)%height
		local iy=math.floor(v)
		local top,bottom,fy=iy*width*3,((iy+1)%height)*width*3,v-iy
		for _,texel in ipairs(row) do
			local offset,x=texel[1],texel[2]
			local a,b,fx=left[x],right[x],fraction[x]
			local red=sample(a,b,top,bottom,fx,fy,0)
			local green=sample(a,b,top,bottom,fx,fy,1)
			local blue=sample(a,b,top,bottom,fx,fy,2)
			local ar,ag,ab=math.min(1-red,texel[3]),math.min(1-green,texel[4]),math.min(1-blue,texel[5])
			local alpha=math.min(.38,math.max(ar/math.max(.0001,1-red),ag/math.max(.0001,1-green),ab/math.max(.0001,1-blue)))
			if alpha>0 then
				buffer.writeu32(output,offset,byte(red+ar/alpha)+byte(green+ag/alpha)*256+byte(blue+ab/alpha)*65536+byte(alpha)*16777216)
			else
				buffer.writeu32(output,offset,0)
			end
		end
	end
	return output
end

return pixels
