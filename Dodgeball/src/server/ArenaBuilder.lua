-- Arena e pre-lobby in stile pulito e minimale (colori tenui, materiali opachi).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local ArenaBuilder = {}

local WHITE = Color3.fromRGB(246, 247, 250)
local SOFT = Color3.fromRGB(226, 229, 236)
local GRAPHITE = Color3.fromRGB(34, 37, 48)
local SAGE = Color3.fromRGB(128, 168, 142)

local function make(parent, name, size, pos, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = typeof(pos) == "Vector3" and CFrame.new(pos) or pos
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function decor(parent, name, size, pos, color, props)
	local p = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	for k, v in props or {} do p[k] = v end
	return make(parent, name, size, pos, color, p)
end

local function disk(parent, name, diameter, height, pos, color, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return make(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, props)
end

local function softLight(part, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 240, 220)
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = part
end

local function newScreen(parent, name, size, pos, face)
	local part = make(parent, name, size, pos, GRAPHITE, { Material = Enum.Material.SmoothPlastic })
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	local w = (face == Enum.NormalId.Back or face == Enum.NormalId.Front) and size.X or size.Z
	gui.CanvasSize = Vector2.new(1000, 1000 * size.Y / w)
	gui.LightInfluence = 0
	gui.Parent = part
	return part, gui
end

local function label(gui, name, text, y, h, color, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.9, h)
	l.Position = UDim2.fromScale(0.05, y)
	l.Font = font or Enum.Font.GothamBold
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.Parent = gui
	return l
end

local function accentBars(gui, y)
	for i, team in Config.Teams do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = team.Color
		f.Size = UDim2.fromScale(0.3, 0.025)
		f.Position = UDim2.fromScale(i == 1 and 0.2 or 0.5, y)
		f.Parent = gui
	end
end

-- ============ ARENA ============
local function buildCourt(folder)
	local L, W, H = Config.Arena.Length, Config.Arena.Width, Config.Arena.WallHeight

	make(folder, "Ground", Vector3.new(900, 4, 900), Vector3.new(0, -4, 100), Color3.fromRGB(152, 155, 164), { Material = Enum.Material.Concrete })

	for i, team in Config.Teams do
		local s = i == 1 and -1 or 1
		make(folder, "Floor" .. i, Vector3.new(L / 2, 2, W), Vector3.new(s * L / 4, -1, 0), team.Color:Lerp(WHITE, 0.55), { Reflectance = 0.04 })
		decor(folder, "BackLine", Vector3.new(0.5, 0.1, W - 1), Vector3.new(s * (L / 2 - 0.6), 0.05, 0), team.Color)
		for _, z in { -1, 1 } do
			decor(folder, "SideLine", Vector3.new(L / 2 - 0.6, 0.1, 0.4), Vector3.new(s * L / 4, 0.05, z * (W / 2 - 0.6)), WHITE)
		end
	end

	-- Linea centrale e cerchio (segmenti opachi)
	decor(folder, "MidLine", Vector3.new(0.5, 0.1, W), Vector3.new(0, 0.05, 0), WHITE)
	local segments, radius = 36, 9
	for i = 1, segments do
		local theta = (i / segments) * math.pi * 2
		local len = 2 * math.pi * radius / segments + 0.12
		decor(folder, "CenterRing", Vector3.new(len, 0.1, 0.4),
			CFrame.new(math.cos(theta) * radius, 0.05, math.sin(theta) * radius) * CFrame.Angles(0, -(theta + math.pi / 2), 0), WHITE)
	end

	-- Pareti di vetro con zoccolo e bordo bianco
	local glass = { Material = Enum.Material.Glass, Transparency = 0.8, Reflectance = 0.05 }
	local gc = Color3.fromRGB(200, 225, 245)
	make(folder, "WallN", Vector3.new(L + 4, H, 2), Vector3.new(0, H / 2, -W / 2 - 1), gc, glass)
	make(folder, "WallS", Vector3.new(L + 4, H, 2), Vector3.new(0, H / 2, W / 2 + 1), gc, glass)
	make(folder, "WallW", Vector3.new(2, H, W), Vector3.new(-L / 2 - 1, H / 2, 0), gc, glass)
	make(folder, "WallE", Vector3.new(2, H, W), Vector3.new(L / 2 + 1, H / 2, 0), gc, glass)
	for _, z in { -1, 1 } do
		decor(folder, "TopRail", Vector3.new(L + 4, 0.5, 2.2), Vector3.new(0, H, z * (W / 2 + 1)), WHITE)
		decor(folder, "Plinth", Vector3.new(L + 4, 1.4, 2.2), Vector3.new(0, 0.7, z * (W / 2 + 1)), WHITE)
	end
	for _, x in { -1, 1 } do
		decor(folder, "TopRail", Vector3.new(2.2, 0.5, W), Vector3.new(x * (L / 2 + 1), H, 0), WHITE)
		decor(folder, "Plinth", Vector3.new(2.2, 1.4, W), Vector3.new(x * (L / 2 + 1), 0.7, 0), WHITE)
	end
	make(folder, "Ceiling", Vector3.new(L + 4, 2, W + 4), Vector3.new(0, H + 1, 0), WHITE, { Transparency = 1, CanQuery = false })

	-- Barriera centrale quasi invisibile: ferma i giocatori, non le palle
	make(folder, "Barrier", Vector3.new(0.5, H, W), Vector3.new(0, H / 2, 0), WHITE, {
		Transparency = 0.9, CollisionGroup = "Barrier", CanTouch = false, CanQuery = false, CastShadow = false,
	})

	-- Pilastri d'angolo con faro morbido (nessun neon)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (L / 2 + 1), sz * (W / 2 + 1)
			make(folder, "Pillar", Vector3.new(2.6, H + 2, 2.6), Vector3.new(x, (H + 2) / 2, z), SOFT)
			local lamp = decor(folder, "Floodlight", Vector3.new(4, 0.6, 4), Vector3.new(x, H + 2.3, z), WHITE)
			softLight(lamp, 1.4, 80)
		end
	end
end

local function buildStands(folder)
	local L, W = Config.Arena.Length, Config.Arena.Width
	local muted = {}
	for i, team in Config.Teams do
		muted[i] = team.Color:Lerp(Color3.fromRGB(120, 124, 136), 0.45)
	end

	for _, side in { -1, 1 } do
		for i = 1, 4 do
			local z = side * (W / 2 + 2 + (i - 1) * 5 + 2.5)
			local top = 2.5 * i
			make(folder, "Stand" .. i, Vector3.new(L + 4, top + 2, 5), Vector3.new(0, (top - 2) / 2, z), Color3.fromRGB(184, 188, 198), { Material = Enum.Material.Concrete })
			for x = -L / 2 + 2, L / 2 - 2, 4 do
				decor(folder, "Seat", Vector3.new(2.6, 1.2, 2), Vector3.new(x, top + 0.6, z + side * 0.4), x < 0 and muted[1] or muted[2])
			end
		end
	end

	-- Tabelloni alle estremità: grafite con testo bianco
	local L2 = L / 2 + 14
	for i, team in Config.Teams do
		local s = i == 1 and -1 or 1
		local face = i == 1 and Enum.NormalId.Right or Enum.NormalId.Left
		local _, gui = newScreen(folder, "Billboard" .. i, Vector3.new(2, 12, 36), Vector3.new(s * L2, 13, 0), face)
		label(gui, "Title", "DODGEBALL", 0.12, 0.42, WHITE)
		label(gui, "Team", "TEAM " .. string.upper(team.Name), 0.56, 0.22, team.Color, Enum.Font.GothamMedium)
		for _, z in { -15, 15 } do
			make(folder, "BillboardPost", Vector3.new(1.2, 19, 1.2), Vector3.new(s * (L2 + 1.5), 9.5, z), SOFT)
		end
	end
end

-- ============ PRE-LOBBY ============
local function bench(folder, pos, yaw)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	make(folder, "BenchSeat", Vector3.new(7, 0.6, 2), base * CFrame.new(0, 1.5, 0), Color3.fromRGB(190, 160, 128), { Material = Enum.Material.Wood })
	for _, dx in { -2.8, 2.8 } do
		make(folder, "BenchLeg", Vector3.new(0.6, 1.5, 1.6), base * CFrame.new(dx, 0.75, 0), SOFT)
	end
end

local function tree(folder, pos)
	disk(folder, "Planter", 5, 1.2, pos + Vector3.new(0, 0.6, 0), WHITE)
	disk(folder, "Trunk", 0.8, 4, pos + Vector3.new(0, 3.2, 0), Color3.fromRGB(150, 120, 95), { Material = Enum.Material.Wood })
	make(folder, "Canopy", Vector3.new(6.5, 6.5, 6.5), pos + Vector3.new(0, 7.4, 0), SAGE, { Shape = Enum.PartType.Ball })
end

-- Cerchio d'ingresso: chi ci cammina dentro viene portato in campo (la logica è in MatchService)
local function buildPortal(folder)
	local P = Config.Portal
	local pos = Config.LobbyPosition + P.Offset
	local d = P.Radius * 2
	local function inert(extra)
		local t = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
		for k, v in extra or {} do t[k] = v end
		return t
	end

	local rim = disk(folder, "PortalRim", d + 1.4, 0.2, pos + Vector3.new(0, 0.12, 0), WHITE, inert())
	disk(folder, "PortalDisc", d, 0.24, pos + Vector3.new(0, 0.16, 0), P.OpenColor, inert({ Transparency = 0.1 }))
	disk(folder, "PortalBeam", d - 0.6, 12, pos + Vector3.new(0, 6, 0), P.OpenColor, inert({ Transparency = 0.9 }))
	softLight(rim, 0.8, 22)

	-- Cartello sospeso sopra il cerchio
	local sign = decor(folder, "PortalSign", Vector3.new(1, 1, 1), pos + Vector3.new(0, 13.5, 0), WHITE, { Transparency = 1 })
	local bb = Instance.new("BillboardGui")
	bb.Name = "Gui"
	bb.Size = UDim2.fromOffset(230, 40)
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.Adornee = sign
	bb.Parent = sign
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = GRAPHITE
	text.BackgroundTransparency = 0.15
	text.BorderSizePixel = 0
	text.Font = Enum.Font.GothamBold
	text.TextSize = 18
	text.TextColor3 = WHITE
	text.Text = "ENTRA IN CAMPO"
	text.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = text
end

local function buildLobby(folder)
	local lp = Config.LobbyPosition

	disk(folder, "LobbyRim", 84, 1.9, lp + Vector3.new(0, -1.05, 0), Color3.fromRGB(196, 200, 210))
	disk(folder, "LobbyFloor", 82, 2, lp + Vector3.new(0, -1, 0), Color3.fromRGB(236, 238, 243), { Reflectance = 0.04 })
	disk(folder, "InlayRing", 56, 0.1, lp + Vector3.new(0, 0.03, 0), Color3.fromRGB(212, 216, 226), { CanCollide = false, CanQuery = false })
	disk(folder, "Inlay", 54.6, 0.12, lp + Vector3.new(0, 0.04, 0), Color3.fromRGB(241, 242, 247), { CanCollide = false, CanQuery = false })

	-- Spawn invisibile
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = lp + Vector3.new(0, 0.2, 0)
	spawn.Transparency = 1
	for _, d in spawn:GetChildren() do
		if d:IsA("Decal") or d:IsA("Texture") then d:Destroy() end
	end
	spawn.Parent = folder

	-- Schermo informativo (aggiornato dal client con stato e timer)
	local screen, gui = newScreen(folder, "LobbyScreen", Vector3.new(44, 15, 1), lp + Vector3.new(0, 13, -36), Enum.NormalId.Back)
	label(gui, "Title", "DODGEBALL", 0.07, 0.34, WHITE)
	label(gui, "Status", "In attesa...", 0.45, 0.14, Color3.fromRGB(178, 184, 198), Enum.Font.GothamMedium)
	label(gui, "Timer", "", 0.62, 0.24, WHITE)
	accentBars(gui, 0.93)
	screen.Name = "LobbyScreen"
	for _, x in { -16, 16 } do
		make(folder, "ScreenPost", Vector3.new(1.2, 21, 1.2), lp + Vector3.new(x, 10.5, -37), SOFT)
	end

	-- Alberi in vaso (evitando lo schermo)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pos = lp + Vector3.new(math.cos(a) * 33, 0, math.sin(a) * 33)
		if not (math.abs(pos.X - lp.X) < 14 and pos.Z < lp.Z) then
			tree(folder, pos)
		end
	end

	-- Panchine
	for _, a in { math.rad(50), math.rad(130) } do
		local pos = lp + Vector3.new(math.cos(a) * 26, 0, math.sin(a) * 26)
		bench(folder, pos, -a + math.pi / 2)
	end

	-- Lampioni morbidi
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local base = lp + Vector3.new(math.cos(a) * 37, 0, math.sin(a) * 37)
		make(folder, "LampPole", Vector3.new(0.5, 10, 0.5), base + Vector3.new(0, 5, 0), GRAPHITE)
		local bulb = decor(folder, "LampBulb", Vector3.new(2, 2, 2), base + Vector3.new(0, 10.5, 0), WHITE, { Shape = Enum.PartType.Ball })
		softLight(bulb, 1, 40)
	end

	buildPortal(folder)
end

function ArenaBuilder.Build()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = workspace
	buildCourt(folder)
	buildStands(folder)
	buildLobby(folder)
end

return ArenaBuilder
