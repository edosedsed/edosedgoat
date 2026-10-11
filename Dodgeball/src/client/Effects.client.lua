-- Effetti visivi della schivata (visibili a tutti): sobri e puliti.
--  scia sottile + piccolo sbuffo di polvere ai piedi + dissolvenza morbida del personaggio.
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.DodgeFX.OnClientEvent:Connect(function(plr)
	local char = plr and plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Polvere ai piedi (pochi granelli, niente nuvolone)
	local feet = Instance.new("Attachment")
	feet.Position = Vector3.new(0, -2.8, 0)
	feet.Parent = hrp
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.3, 0.45)
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	dust.Transparency = NumberSequence.new(0.55, 1)
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 238, 245))
	dust.LightEmission = 0
	dust.Parent = feet
	dust:Emit(5)
	Debris:AddItem(feet, 1)

	-- Scia sottile
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 1.2, 0), Vector3.new(0, -1.2, 0)
	a0.Parent, a1.Parent = hrp, hrp
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.22
	trail.LightEmission = 0
	trail.Color = ColorSequence.new(Color3.fromRGB(240, 243, 250))
	trail.Transparency = NumberSequence.new(0.6, 1)
	trail.Parent = hrp
	Debris:AddItem(trail, 0.7)
	Debris:AddItem(a0, 0.7)
	Debris:AddItem(a1, 0.7)

	-- Il personaggio sfuma in semitrasparenza e torna visibile in modo graduale (solo effetto locale)
	local parts = {}
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d ~= hrp then table.insert(parts, d) end
	end
	local dur = Config.DodgeInvuln
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local a
		if t >= dur then
			a = 0
		elseif t < 0.06 then
			a = t / 0.06
		elseif t > dur - 0.12 then
			a = (dur - t) / 0.12
		else
			a = 1
		end
		for _, d in parts do
			if d.Parent then d.LocalTransparencyModifier = 0.55 * a end
		end
		if t >= dur then conn:Disconnect() end
	end)
end)
