-- Atmosfera pulita: luce diurna morbida, niente neon o bagliori eccessivi.
local Lighting = game:GetService("Lighting")

local Environment = {}

function Environment.Apply()
	for _, c in Lighting:GetChildren() do
		if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("PostEffect") then
			c:Destroy()
		end
	end

	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(120, 126, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 146, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 244, 230)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.4

	local sky = Instance.new("Sky")
	sky.StarCount = 0
	sky.Parent = Lighting

	local atm = Instance.new("Atmosphere")
	atm.Density = 0.3
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(196, 212, 235)
	atm.Decay = Color3.fromRGB(150, 168, 200)
	atm.Glare = 0
	atm.Haze = 0.6
	atm.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.12
	bloom.Size = 18
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.04
	cc.Saturation = 0.05
	cc.Parent = Lighting
end

return Environment
