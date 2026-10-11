-- Effetti delle palle (solo locali): scintille, luci, etichetta per la palla dorata,
-- scossa quando una palla colpisce vicino a te e contorno sulla palla più vicina da raccogliere.
-- Usa l'attributo "Kind" e "State" che il server mette su ogni palla.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CameraFX = require(script.Parent.CameraFX)
local ClientSettings = require(script.Parent.ClientSettings)

local player = Players.LocalPlayer

local DEFAULT_COLOR = Color3.fromRGB(255, 190, 40)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function makeEmitter(parent, texture, color, rate, lifetime, speed, size, spread)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime[1], lifetime[2])
	e.Speed = NumberRange.new(speed[1], speed[2])
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Parent = parent
	return e
end

-- Lampo breve e morbido nel punto d'impatto (locale, nessuna collisione): si espande e svanisce in 0.2s.
local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalBallFX"
fxFolder.Parent = workspace

local function flash(position, color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.35
	p.Size = Vector3.one * Config.BallSize * 0.7
	p.Position = position
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * Config.BallSize * 2.4,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.25)
end

local function setupBall(ball)
	if not ball:IsA("BasePart") then return end
	local kind = ball:GetAttribute("Kind") or "Normal"
	local def = Config.BallKinds[kind] or {}
	local color = def.Color or DEFAULT_COLOR

	local burst = makeEmitter(ball, SPARK, color, 0, { 0.3, 0.5 }, { 14, 26 }, 0.9, 180)
	local dust = makeEmitter(ball, SMOKE, Color3.fromRGB(230, 232, 238), 0, { 0.35, 0.5 }, { 3, 7 }, 1.2, 70)

	local light
	if kind ~= "Normal" then
		light = Instance.new("PointLight")
		light.Color = color
		light.Range = 9
		light.Brightness = 1.2
		light.Enabled = kind == "Golden"
		light.Parent = ball
	end

	-- La palla dorata brilla sempre e ha un'etichetta visibile anche attraverso i muri quando è a terra
	local tag
	if kind == "Golden" then
		makeEmitter(ball, SPARK, color, 10, { 0.6, 1 }, { 1, 3 }, 0.7, 180)
		tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(110, 24)
		tag.StudsOffset = Vector3.new(0, 3, 0)
		tag.AlwaysOnTop = true
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 14
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.5
		l.Text = "★ PALLA DORATA"
		l.Parent = tag
		tag.Parent = ball
	end

	local prev = ball:GetAttribute("State")
	local function onState()
		local current = ball:GetAttribute("State")
		if light and kind ~= "Golden" then light.Enabled = current == "Thrown" end
		if tag then tag.Enabled = current == "Idle" end
		if current == "Thrown" and prev == "Held" then
			-- rilascio: piccola scintilla (visibile a tutti) dove la palla lascia la mano
			burst:Emit(5)
		elseif current == "Held" and prev == "Thrown" then
			-- presa riuscita: lampo e scintille sulla palla appena afferrata
			burst:Emit(10)
			flash(ball.Position, color)
		elseif current == "Spent" then
			-- colpito un giocatore
			burst:Emit(16)
			flash(ball.Position, color)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - ball.Position).Magnitude < 25 then CameraFX.Shake(0.5) end
		elseif current == "Idle" and prev == "Thrown" then
			-- mancato: tocca terra o un muro (polvere + poche scintille, più discreto del colpo a segno)
			dust:Emit(5)
			burst:Emit(4)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - ball.Position).Magnitude < 50 then ClientSettings.PlaySound("Impact") end
		end
		prev = current
	end
	ball:GetAttributeChangedSignal("State"):Connect(onState)
	onState()
end

task.spawn(function()
	local folder = workspace:WaitForChild("Balls")
	for _, b in folder:GetChildren() do task.spawn(setupBall, b) end
	folder.ChildAdded:Connect(function(b) task.spawn(setupBall, b) end)
end)

-- Contorno sulla palla a terra più vicina (solo se sei in campo senza palla).
-- Il Highlight sta sulla camera locale e usa Adornee: non viene distrutto quando le palle vengono ricreate.
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0.25
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = workspace.CurrentCamera or workspace:WaitForChild("Camera")

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.15 then return end
	acc = 0
	local target
	if player:GetAttribute("InMatch") and not player:GetAttribute("HasBall") then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local folder = workspace:FindFirstChild("Balls")
		if hrp and folder then
			local best = 60
			for _, b in folder:GetChildren() do
				if b:GetAttribute("State") == "Idle" then
					local d = (b.Position - hrp.Position).Magnitude
					if d < best then best, target = d, b end
				end
			end
		end
	end
	if highlight.Adornee ~= target then highlight.Adornee = target end
end)
