if not game:GetService("RunService"):IsStudio() then return end
local playergui=game.Players.LocalPlayer:WaitForChild("PlayerGui")
local evidence=Instance.new("Folder")
evidence.Name,evidence.Parent="DxStartupChecks",playergui
local deadline=os.clock()+30
local menus,page
repeat
	menus=playergui:FindFirstChild("CutTheRopeMenus")
	page=menus and menus:FindFirstChild("ZeptolabSplash",true)
	if page and page:GetAttribute("PageReady") then break end
	task.wait()
until os.clock()>deadline
local ok,message=pcall(function()
	assert(page and page:GetAttribute("PageReady"),"startup screen not ready")
	assert(not page:FindFirstChild("ZeptolabLogoAnimQuad6",true),"logo should be absent")
	assert(not page:FindFirstChild("StartupLoading",true),"texture status should be absent")
	local label=page:FindFirstChild("OriginalGameAttribution",true)
	assert(label and label.TextColor3==Color3.new(0,0,0) and label.TextStrokeTransparency==1)
	local glyphs=label:FindFirstChild("BitmapText")
	assert(glyphs and #glyphs:GetChildren()>100,"disclaimer glyphs missing")
	local small=require(game.ReplicatedStorage.CutTheRope.Shared.SmallFont)
	for _,glyph in glyphs:GetChildren() do assert(glyph.Image==small.image,"outlined atlas used") end
	local audio=game:GetService("SoundService"):FindFirstChild("DxAudio")
	assert(audio and (audio:GetAttribute("EventCount") or 0)==0,"startup must be silent")
	local capture=menus:Clone()
	capture.Name,capture.DisplayOrder,capture.Enabled="DxStartupCapture",200,true
	capture.Parent=playergui
	task.delay(45,function() capture:Destroy() end)
end)
evidence:SetAttribute("Result",ok and "PASS" or tostring(message))
evidence:SetAttribute("Complete",true)
if not ok then warn("DX STARTUP CHECK",message) end
