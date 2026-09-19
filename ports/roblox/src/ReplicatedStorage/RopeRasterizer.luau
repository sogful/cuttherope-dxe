--!native
local raster = {}
raster.__index = raster
local tile = 16
local function byte(value: number): number return math.clamp(math.floor(value + .5), 0, 255) end
local function pack(r: number, g: number, b: number, a: number): number return byte(r) + byte(g)*256 + byte(b)*65536 + byte(a)*16777216 end
local function channel(value: number, shift: number): number return bit32.band(bit32.rshift(value, shift), 255) end

function raster.new(width, height)
	return setmetatable({width=width,height=height,stride=width*2,
		pixels=buffer.create(width*height*16),output=buffer.create(width*height*4),dirty={},columns=math.ceil(width/tile)},raster)
end

function raster:clear()
	self.left,self.top,self.right,self.bottom=self.width,self.height,0,0
	for key in pairs(self.dirty) do
		local left,top=key%self.columns*tile,math.floor(key/self.columns)*tile
		local right,bottom=math.min(self.width,left+tile),math.min(self.height,top+tile)
		self.left,self.top=math.min(self.left,left),math.min(self.top,top)
		self.right,self.bottom=math.max(self.right,right),math.max(self.bottom,bottom)
		for y=top*2,bottom*2-1 do buffer.fill(self.pixels,(y*self.stride+left*2)*4,0,(right-left)*8) end
		for y=top,bottom-1 do buffer.fill(self.output,(y*self.width+left)*4,0,(right-left)*4) end
	end
	table.clear(self.dirty)
end

local function edge(a: Vector2,b: Vector2,x: number,y: number): number return (b.X-a.X)*(y-a.Y)-(b.Y-a.Y)*(x-a.X) end
local function top(a: Vector2,b: Vector2): boolean return b.Y<a.Y or (b.Y==a.Y and b.X>a.X) end
local function inside(value: number, inclusive: boolean): boolean return value>1e-7 or (value>=-1e-7 and inclusive) end

function raster:triangle(a: Vector2,b: Vector2,c: Vector2,ca: Color3,cb: Color3,cc: Color3,aa: number,ab: number,ac: number)
	a,b,c=a*2,b*2,c*2
	local area=edge(a,b,c.X,c.Y)
	if math.abs(area)<1e-8 then return end
	if area<0 then b,c,cb,cc,ab,ac=c,b,cc,cb,ac,ab area=-area end
	local miny=math.max(0,math.floor(math.min(a.Y,b.Y,c.Y)))
	local maxy=math.min(self.height*2-1,math.ceil(math.max(a.Y,b.Y,c.Y))-1)
	if miny>maxy then return end
	local first,last=math.max(0,math.floor(math.min(a.X,b.X,c.X)/2/tile)),math.min(self.columns-1,math.floor(math.max(a.X,b.X,c.X)/2/tile))
	if first>last then return end
	self.left,self.top=math.min(self.left or self.width,first*tile),math.min(self.top or self.height,math.floor(miny/2/tile)*tile)
	self.right,self.bottom=math.max(self.right or 0,math.min(self.width,(last+1)*tile)),math.max(self.bottom or 0,math.min(self.height,(math.floor(maxy/2/tile)+1)*tile))
	for y=math.floor(miny/2/tile),math.floor(maxy/2/tile) do
		for x=first,last do self.dirty[y*self.columns+x]=true end
	end
	local abtop,bctop,catop=top(a,b),top(b,c),top(c,a)
	local inverse=1/area
	local r1,g1,b1=ca.R*aa*255,ca.G*aa*255,ca.B*aa*255
	local r2,g2,b2=cb.R*ab*255,cb.G*ab*255,cb.B*ab*255
	local r3,g3,b3=cc.R*ac*255,cc.G*ac*255,cc.B*ac*255
	aa,ab,ac=aa*255,ab*255,ac*255
	local abmin,abmax=math.min(a.Y,b.Y),math.max(a.Y,b.Y)
	local bcmin,bcmax=math.min(b.Y,c.Y),math.max(b.Y,c.Y)
	local camin,camax=math.min(c.Y,a.Y),math.max(c.Y,a.Y)
	local abslope,bcslope,caslope=(b.X-a.X)/(b.Y-a.Y),(c.X-b.X)/(c.Y-b.Y),(a.X-c.X)/(a.Y-c.Y)
	for y=miny,maxy do
		local py=y+.5
		local low,high=math.huge,-math.huge
		-- Scan only the thin triangle's span, not its potentially enormous box.
		if py>=abmin and py<abmax then local x=a.X+(py-a.Y)*abslope low,high=math.min(low,x),math.max(high,x) end
		if py>=bcmin and py<bcmax then local x=b.X+(py-b.Y)*bcslope low,high=math.min(low,x),math.max(high,x) end
		if py>=camin and py<camax then local x=c.X+(py-c.Y)*caslope low,high=math.min(low,x),math.max(high,x) end
		local minx,maxx=math.max(0,math.floor(low)),math.min(self.stride-1,math.ceil(high)-1)
		local w1,w2,w3=edge(b,c,minx+.5,py),edge(c,a,minx+.5,py),edge(a,b,minx+.5,py)
		for x=minx,maxx do
			if inside(w1,bctop) and inside(w2,catop) and inside(w3,abtop) then
				local u,v,w=w1*inverse,w2*inverse,w3*inverse
				local alpha=u*aa+v*ab+w*ac
				if alpha>0 then
					local offset=(y*self.stride+x)*4
					local old=buffer.readu32(self.pixels,offset)
					local keep=1-alpha/255
					buffer.writeu32(self.pixels,offset,pack(u*r1+v*r2+w*r3+channel(old,0)*keep,
						u*g1+v*g2+w*g3+channel(old,8)*keep,u*b1+v*b2+w*b3+channel(old,16)*keep,alpha+channel(old,24)*keep))
				end
			end
			w1-=c.Y-b.Y w2-=a.Y-c.Y w3-=b.Y-a.Y
		end
	end
end

function raster:finish()
	local pixels: buffer=self.pixels
	local output: buffer=self.output
	local stride: number=self.stride
	local width: number=self.width
	for key in pairs(self.dirty) do
		local left,top=key%self.columns*tile,math.floor(key/self.columns)*tile
		for y=top,math.min(self.height-1,top+tile-1) do
			for x=left,math.min(self.width-1,left+tile-1) do
				local offset=(y*2*stride+x*2)*4
				local a,b=buffer.readu32(pixels,offset),buffer.readu32(pixels,offset+4)
				local c,d=buffer.readu32(pixels,offset+stride*4),buffer.readu32(pixels,offset+stride*4+4)
				local alpha=(bit32.rshift(a,24)+bit32.rshift(b,24)+bit32.rshift(c,24)+bit32.rshift(d,24))*.25
				if alpha>0 then
					local gain=255/(alpha*4)
					buffer.writeu32(output,(y*width+x)*4,pack(
						(bit32.band(a,255)+bit32.band(b,255)+bit32.band(c,255)+bit32.band(d,255))*gain,
						(bit32.band(bit32.rshift(a,8),255)+bit32.band(bit32.rshift(b,8),255)+bit32.band(bit32.rshift(c,8),255)+bit32.band(bit32.rshift(d,8),255))*gain,
						(bit32.band(bit32.rshift(a,16),255)+bit32.band(bit32.rshift(b,16),255)+bit32.band(bit32.rshift(c,16),255)+bit32.band(bit32.rshift(d,16),255))*gain,alpha))
				end
			end
		end
	end
	return self.output
end

function raster:region()
	local w,h=(self.right or 0)-(self.left or self.width),(self.bottom or 0)-(self.top or self.height)
	if w<=0 or h<=0 then return nil end
	local bytes=w*h*4
	if not self.upload or buffer.len(self.upload)~=bytes then self.upload=buffer.create(bytes) end
	for y=0,h-1 do buffer.copy(self.upload,y*w*4,self.output,((self.top+y)*self.width+self.left)*4,w*4) end
	return self.upload,Vector2.new(self.left,self.top),Vector2.new(w,h)
end

return raster
