--!native
local raster = {}
raster.__index = raster
local tile = 16
local function byte(value: number): number return math.clamp(math.floor(value + .5), 0, 255) end
local function pack(r: number, g: number, b: number, a: number): number return byte(r) + byte(g)*256 + byte(b)*65536 + byte(a)*16777216 end

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

function raster:triangle(a: Vector2,b: Vector2,c: Vector2,ca: Color3,cb: Color3,cc: Color3,aa: number,ab: number,ac: number)
	local ax,ay,bx,by,cx,cy=a.X*2,a.Y*2,b.X*2,b.Y*2,c.X*2,c.Y*2
	local area=(bx-ax)*(cy-ay)-(by-ay)*(cx-ax)
	if math.abs(area)<1e-8 then return end
	if area<0 then bx,by,cx,cy,cb,cc,ab,ac=cx,cy,bx,by,cc,cb,ac,ab area=-area end
	local miny=math.max(0,math.floor(math.min(ay,by,cy)))
	local maxy=math.min(self.height*2-1,math.ceil(math.max(ay,by,cy))-1)
	if miny>maxy then return end
	local first,last=math.max(0,math.floor(math.min(ax,bx,cx)/2/tile)),math.min(self.columns-1,math.floor(math.max(ax,bx,cx)/2/tile))
	if first>last then return end
	self.left,self.top=math.min(self.left or self.width,first*tile),math.min(self.top or self.height,math.floor(miny/2/tile)*tile)
	self.right,self.bottom=math.max(self.right or 0,math.min(self.width,(last+1)*tile)),math.max(self.bottom or 0,math.min(self.height,(math.floor(maxy/2/tile)+1)*tile))
	for y=math.floor(miny/2/tile),math.floor(maxy/2/tile) do
		for x=first,last do self.dirty[y*self.columns+x]=true end
	end
	local abtop=by<ay or (by==ay and bx>ax)
	local bctop=cy<by or (cy==by and cx>bx)
	local catop=ay<cy or (ay==cy and ax>cx)
	local pixels,stride=self.pixels,self.stride
	local inverse=1/area
	local r1,g1,b1=ca.R*aa*255,ca.G*aa*255,ca.B*aa*255
	local r2,g2,b2=cb.R*ab*255,cb.G*ab*255,cb.B*ab*255
	local r3,g3,b3=cc.R*ac*255,cc.G*ac*255,cc.B*ac*255
	aa,ab,ac=aa*255,ab*255,ac*255
	local abmin,abmax=math.min(ay,by),math.max(ay,by)
	local bcmin,bcmax=math.min(by,cy),math.max(by,cy)
	local camin,camax=math.min(cy,ay),math.max(cy,ay)
	local abslope,bcslope,caslope=(bx-ax)/(by-ay),(cx-bx)/(cy-by),(ax-cx)/(ay-cy)
	for y=miny,maxy do
		local py=y+.5
		local low,high=math.huge,-math.huge
		-- Scan only the thin triangle's span, not its potentially enormous box.
		if py>=abmin and py<abmax then local x=ax+(py-ay)*abslope low,high=math.min(low,x),math.max(high,x) end
		if py>=bcmin and py<bcmax then local x=bx+(py-by)*bcslope low,high=math.min(low,x),math.max(high,x) end
		if py>=camin and py<camax then local x=cx+(py-cy)*caslope low,high=math.min(low,x),math.max(high,x) end
		local minx,maxx=math.max(0,math.floor(low)),math.min(stride-1,math.ceil(high)-1)
		local px=minx+.5
		local w1=(cx-bx)*(py-by)-(cy-by)*(px-bx)
		local w2=(ax-cx)*(py-cy)-(ay-cy)*(px-cx)
		local w3=(bx-ax)*(py-ay)-(by-ay)*(px-ax)
		for x=minx,maxx do
			if (w1>1e-7 or w1>=-1e-7 and bctop) and (w2>1e-7 or w2>=-1e-7 and catop) and (w3>1e-7 or w3>=-1e-7 and abtop) then
				local u,v,w=w1*inverse,w2*inverse,w3*inverse
				local alpha=u*aa+v*ab+w*ac
				if alpha>0 then
					local offset=(y*stride+x)*4
					local old=buffer.readu32(pixels,offset)
					local red,green,blue=u*r1+v*r2+w*r3,u*g1+v*g2+w*g3,u*b1+v*b2+w*b3
					if old~=0 then
						local keep=1-alpha/255
						red+=bit32.band(old,255)*keep
						green+=bit32.band(bit32.rshift(old,8),255)*keep
						blue+=bit32.band(bit32.rshift(old,16),255)*keep
						alpha+=bit32.rshift(old,24)*keep
					end
					buffer.writeu32(pixels,offset,pack(red,green,blue,alpha))
				end
			end
			w1-=cy-by w2-=ay-cy w3-=by-ay
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
				if bit32.bor(a,b,c,d)==0 then continue end
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
