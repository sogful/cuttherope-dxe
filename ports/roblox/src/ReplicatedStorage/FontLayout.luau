local localeFonts = require(script.Parent.LocaleFonts)
local session = require(script.Parent.SessionState)
local metrics = require(script.Parent.FontMetrics)
local layouts = setmetatable({}, {__mode = "k"})
local layout = {}
local function selectfont(default, small)
	local code = session.locale
	local family = (code == "zh_tw" and "zh") or (localeFonts[code] and code) or "latin"
	local extra = localeFonts[family][small and "small" or "big"]
	return family == "latin" and default or extra, extra, small and metrics.small or metrics.big
end
local function characters(value)
	local result = {}
	for _, code in utf8.codes(value) do table.insert(result, utf8.char(code)) end
	return result
end
function layout.render(label, value, default, small, options)
	if not label.Parent then return false end
	options = options or {}
	local atlas, extra, original = selectfont(default, small)
	local advances = atlas.advances or original
	local function glyphfor(char)
		if char == " " or char == " " then return nil, atlas end
		if atlas.glyphs[char] then return atlas.glyphs[char], atlas end
		if extra.glyphs[char] then return extra.glyphs[char], extra end
		local latin = localeFonts.latin[small and "small" or "big"]
		if latin.glyphs[char] then return latin.glyphs[char], latin end
		return atlas.glyphs["?"], atlas
	end
	local function advance(char)
		return advances[char] or extra.advances[char] or localeFonts.latin[small and "small" or "big"].advances[char] or advances["?"] or 40
	end
	local widths, lines, maximum = {}, {}, 0
	for _, text in ipairs(string.split(value, "\n")) do
		local line, width = {}, 0
		for _, char in ipairs(characters(text)) do
			table.insert(line, char)
			width += advance(char)
		end
		table.insert(lines, line)
		table.insert(widths, width)
		maximum = math.max(maximum, width)
	end
	label.Text, label.TextTransparency, label.TextStrokeTransparency = value, 1, 1
	label:SetAttribute("DxFont", extra.source)
	label:SetAttribute("DxFontLocale", session.locale)
	local state = layouts[label]
	if not state then
		local holder = Instance.new("Frame")
		holder.Name, holder.BackgroundTransparency, holder.Size = "BitmapText", 1, UDim2.fromScale(1, 1)
		holder.ZIndex, holder.Parent = label.ZIndex, label
		state = {holder = holder, pool = {}, alive = true}
		layouts[label] = state
		label.Destroying:Connect(function() state.alive = false end)
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if state.resize then state.resize() end end)
	end
	state.holder.Visible = true
	local images = {}
	for lineindex, line in ipairs(lines) do
		local cursor = 0
		for _, char in ipairs(line) do
			local glyph, source = glyphfor(char)
			if glyph then
				local image = state.pool[#images + 1] or Instance.new("ImageLabel")
				state.pool[#images + 1] = image
				image.Visible, image.BackgroundTransparency, image.ZIndex = true, 1, label.ZIndex
				image.Image = source.pages and source.pages[glyph[6]] or source.image
				image.ImageRectOffset, image.ImageRectSize = Vector2.new(glyph[1], glyph[2]), Vector2.new(glyph[3], glyph[4])
				image.Parent = state.holder
				table.insert(images, {image = image, x = cursor + (glyph[5] or 0), y = (glyph[7] or 0) + (source.verticalOffset or 0), line = lineindex, w = glyph[3], h = glyph[4]})
			end
			cursor += advance(char)
		end
	end
	for index = #images + 1, #state.pool do state.pool[index].Visible = false end
	state.resize = function()
		if not state.alive or not label.Parent then return end
		local size, inherited, ancestor = label.AbsoluteSize, 1, label
		while ancestor and not ancestor:IsA("ScreenGui") do
			local scale = ancestor:FindFirstChildOfClass("UIScale")
			if scale then inherited *= scale.Scale end
			ancestor = ancestor.Parent
		end
		if inherited > 0 then size /= inherited end
		if options.referenceSize then
			size = options.referenceSize
		end
		local scale = options.scale or math.min(size.Y * (atlas.factor or 1.3) / (156 * #lines), size.X / math.max(1, maximum))
		local lineheight = options.lineheight or 156
		local xscale = scale * (options.xScale or 1)
		for _, glyph in ipairs(images) do
			local x = options.left and 0 or (size.X - widths[glyph.line] * xscale) * .5
			local y = options.y or (size.Y - lineheight * #lines * scale) * .5
			if options.referenceSize then
				glyph.image.Size = UDim2.fromScale(glyph.w * xscale / size.X, glyph.h * scale / size.Y)
				glyph.image.Position = UDim2.fromScale((x + glyph.x * xscale) / size.X, (y + ((glyph.line - 1) * lineheight + glyph.y) * scale) / size.Y)
			else
				glyph.image.Size = UDim2.fromOffset(glyph.w * xscale, glyph.h * scale)
				glyph.image.Position = UDim2.fromOffset(x + glyph.x * xscale, y + ((glyph.line - 1) * lineheight + glyph.y) * scale)
			end
		end
	end
	state.resize()
	return true
end
function layout.measure(value, small)
	local code = session.locale
	local family = (code == "zh_tw" and "zh") or (localeFonts[code] and code) or "latin"
	local atlas = localeFonts[family][small and "small" or "big"]
	local width = 0
	for _, char in ipairs(characters(value)) do width += atlas.advances[char] or atlas.advances["?"] end
	return width, atlas.emScale, atlas.sourceScale
end
function layout.block(label, value, default, board)
	local busy, alive = false, true
	local function resize()
		if busy or not alive or not label.Parent then return end
		busy = true
		local _, em, ratio = layout.measure("", true)
		local code = session.locale
		local latin = not localeFonts[code] and code ~= "zh_tw"
		local inherited,ancestor=1,label
		while ancestor and not ancestor:IsA("ScreenGui") do
			local scaler=ancestor:FindFirstChildOfClass("UIScale")
			if scaler then inherited*=scaler.Scale end
			ancestor=ancestor.Parent
		end
		local pixelscale = board.AbsoluteSize.X / 2560 / math.max(inherited,.001)
		local scale = pixelscale * (latin and em * 72 / 60 or 72 / 60)
		local width = label.AbsoluteSize.X / math.max(scale*inherited, .001)
		local lines = {}
		for _, paragraph in ipairs(string.split(value, "\n")) do
			local line = ""
			for word in string.gmatch(paragraph, "%S+%s*") do
				if line ~= "" and layout.measure(line .. word, true) > width then
					table.insert(lines, (string.gsub(line, "%s+$", "")))
					line = ""
				end
				for _, char in ipairs(characters(word)) do
					if line ~= "" and layout.measure(line .. char, true) > width then table.insert(lines, line) line = "" end
					line ..= char
				end
			end
			table.insert(lines, line)
		end
		local lineheight = (72 * ratio + 5) * pixelscale / math.max(scale, .001)
		label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, (#lines * (72 * ratio + 5) + 25) * pixelscale)
		layout.render(label, table.concat(lines, "\n"), default, true, {scale = scale, y = -20 * pixelscale, lineheight = lineheight})
		busy = false
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	local connection = board:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	label.Destroying:Connect(function() alive = false connection:Disconnect() end)
	resize()
end
return layout
