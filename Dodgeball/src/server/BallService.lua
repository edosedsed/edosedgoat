-- Gestione palle: spawn, raccolta, lancio, colpi e prese.
--  * Un solo ciclo Heartbeat (attivo SOLO quando ci sono palle in volo) controlla scadenza e colpi.
--  * I colpi ai giocatori sono verificati lungo la traiettoria (non si "salta" nessuno nemmeno con lag del server).
--  * Un controllo ogni secondo riporta a casa le palle finite fuori dall'arena (anti-blocco).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local BallService = {}
-- Fire(kind: "Hit" | "Catch", victim: Player, thrower: Player?)
BallService.Hit = Instance.new("BindableEvent")

local ballsFolder = Instance.new("Folder")
ballsFolder.Name = "Balls"
ballsFolder.Parent = workspace

local balls = {} -- [Part] = dati lato Lua (riferimenti già pronti: niente FindFirstChild ripetuti)
local active = {} -- [Part] = true: palle in volo (Thrown) o appena usate (Spent)
local held = {} -- [Player] = Part
local roots = {} -- [Player] = HumanoidRootPart (cache)
local lastThrow = {}
local lastCatch = {}
local lastDodge = {}

local IDLE_COLOR = Color3.fromRGB(220, 60, 60)
local THROWN_COLOR = Color3.fromRGB(255, 190, 40)

-- ============ Cache dei personaggi ============
local function getRoot(player)
	local r = roots[player]
	if r and r.Parent then return r end
	return nil
end
BallService.GetRoot = getRoot

local function trackPlayer(player)
	local function onChar(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp and char.Parent then roots[player] = hrp end
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(onChar)
	player.CharacterRemoving:Connect(function() roots[player] = nil end)
end
Players.PlayerAdded:Connect(trackPlayer)
for _, p in Players:GetPlayers() do trackPlayer(p) end

local function getHand(char)
	return char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
end

-- ============ Stati della palla ============
local loopConn -- connessione Heartbeat, esiste solo se active non è vuoto
local step -- definita sotto

local function ensureLoop()
	if not loopConn then loopConn = RunService.Heartbeat:Connect(step) end
end

local function stopLoop()
	if loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

local function setIdle(ball)
	local d = balls[ball]
	active[ball] = nil
	ball:SetAttribute("State", "Idle")
	if ball.Color ~= IDLE_COLOR then ball.Color = IDLE_COLOR end
	if d then
		d.trail.Enabled = false
		-- A terra gravità normale (o quella scelta in Config): la palla si ferma e smette di essere simulata
		if Config.BallIdleGravityScale >= 1 then
			d.vf.Enabled = false
		else
			d.vf.Force = d.idleForce
			d.vf.Enabled = true
		end
	end
end

local function release(ball)
	local weld = ball:FindFirstChild("HoldWeld")
	if weld then weld:Destroy() end
	ball.Massless = false
	ball.CanCollide = true
	ball.CanTouch = true
	setIdle(ball)
	pcall(function() ball:SetNetworkOwner(nil) end)
end

local function pickup(player, ball)
	local d = balls[ball]
	if not d or ball:GetAttribute("State") ~= "Idle" then return end
	if held[player] or not player:GetAttribute("InMatch") then return end
	local char = player.Character
	local hand = getHand(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hand or not hum or hum.Health <= 0 then return end

	ball:SetAttribute("State", "Held")
	active[ball] = nil
	d.vf.Enabled = false
	ball.CanTouch = false -- da tenuta in mano non genera più eventi Touched
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CanCollide = false
	ball.Massless = true
	ball.CFrame = hand.CFrame * CFrame.new(0, -0.6, -1.2)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HoldWeld"
	weld.Part0 = hand
	weld.Part1 = ball
	weld.Parent = ball

	held[player] = ball
	player:SetAttribute("HasBall", true)
end

-- Una palla lanciata raggiunge un giocatore (da Touched o dal controllo lungo la traiettoria).
-- Lo stato "Thrown" fa da guardia: un solo colpo per lancio, nessuna elaborazione doppia.
local function resolveHit(ball, plr)
	local d = balls[ball]
	if not d or ball:GetAttribute("State") ~= "Thrown" then return end

	local thrower = d.thrower
	if thrower and thrower.Parent ~= Players then thrower = nil end
	if plr == thrower or not plr:GetAttribute("InMatch") then return end
	if plr:GetAttribute("TeamIndex") == d.throwerTeam then return end

	local now = os.clock()
	if now <= (plr:GetAttribute("DodgeUntil") or 0) then return end -- schivata: la palla passa oltre

	local caught = now <= (plr:GetAttribute("CatchUntil") or 0) + 0.1
	if caught and not held[plr] then
		setIdle(ball)
		pickup(plr, ball)
		BallService.Hit:Fire("Catch", plr, thrower)
	else
		ball:SetAttribute("State", "Spent")
		ball.Color = IDLE_COLOR
		d.trail.Enabled = false
		d.spentUntil = now + Config.SpentTime
		BallService.Hit:Fire("Hit", plr, thrower)
	end
end

local function onTouched(ball, other)
	local state = ball:GetAttribute("State")
	if state ~= "Idle" and state ~= "Thrown" then return end
	local group = other.CollisionGroup
	if group == "Balls" then return end

	if group == "Players" then
		local char = other:FindFirstAncestorOfClass("Model")
		local plr = char and Players:GetPlayerFromCharacter(char)
		if not plr then return end
		if state == "Idle" then
			pickup(plr, ball)
		else
			resolveHit(ball, plr)
		end
	elseif state == "Thrown" and other.CanCollide then
		local d = balls[ball]
		if d and os.clock() - d.thrownAt > 0.08 then
			-- un pezzo di personaggio non ancora nel gruppo "Players" non conta come terra/muro
			local m = other:FindFirstAncestorOfClass("Model")
			if m and Players:GetPlayerFromCharacter(m) then return end
			setIdle(ball) -- ha toccato terra/muro: ora si può raccogliere
		end
	end
end

-- ============ Controllo lungo la traiettoria ============
-- Distanza dal centro del giocatore al segmento percorso dalla palla in questo frame.
local function sweep(ball, d, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local R, H = Config.BallHitRadius, Config.BallHitHeight
	local hits
	for _, plr in Players:GetPlayers() do
		if plr ~= d.thrower and plr:GetAttribute("InMatch") and plr:GetAttribute("TeamIndex") ~= d.throwerTeam then
			local root = getRoot(plr)
			if root then
				local p = root.Position
				local t = len2 > 1e-6 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
				local c = a + ab * t
				local dx, dz = c.X - p.X, c.Z - p.Z
				if dx * dx + dz * dz <= R * R and math.abs(c.Y - p.Y) <= H then
					hits = hits or {}
					table.insert(hits, { plr = plr, t = t })
				end
			end
		end
	end
	if not hits then return end
	table.sort(hits, function(x, y) return x.t < y.t end) -- prima chi sta più vicino alla mano
	for _, h in hits do
		resolveHit(ball, h.plr)
		if ball:GetAttribute("State") ~= "Thrown" then return end
	end
end

step = function()
	local now = os.clock()
	for ball, d in active do
		if not ball.Parent then
			active[ball] = nil
		else
			local state = ball:GetAttribute("State")
			if state == "Thrown" then
				if now >= d.expireAt then
					setIdle(ball)
				else
					local cur = ball.Position
					sweep(ball, d, d.prev, cur)
					d.prev = cur
				end
			elseif state == "Spent" then
				if now >= d.spentUntil then setIdle(ball) end
			else
				active[ball] = nil
			end
		end
	end
	if next(active) == nil then stopLoop() end
end

-- ============ Creazione / reset ============
local function createBall(position)
	local ball = Instance.new("Part")
	ball.Name = "Dodgeball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Config.BallSize
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = IDLE_COLOR
	ball.Position = position
	ball.CollisionGroup = "Balls"
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.4, 0.7, 1, 1)
	ball:SetAttribute("State", "Idle")

	local att = Instance.new("Attachment")
	att.Parent = ball

	local vf = Instance.new("VectorForce")
	vf.Name = "VectorForce"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Parent = ball

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, Config.BallSize / 2, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -Config.BallSize / 2, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(THROWN_COLOR)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = ball

	ball.Parent = ballsFolder

	-- Compensa parte della gravità: in volo per traiettorie tese, a terra secondo BallIdleGravityScale
	local weight = ball.AssemblyMass * workspace.Gravity
	local d = {
		vf = vf,
		trail = trail,
		home = position,
		thrownForce = Vector3.new(0, weight * (1 - Config.BallGravityScale), 0),
		idleForce = Vector3.new(0, weight * (1 - Config.BallIdleGravityScale), 0),
		thrownAt = 0,
		expireAt = 0,
		spentUntil = 0,
		prev = position,
	}
	balls[ball] = d
	setIdle(ball)
	pcall(function() ball:SetNetworkOwner(nil) end)

	ball.Touched:Connect(function(other) onTouched(ball, other) end)
	return ball
end

function BallService.SpawnBalls()
	local n = Config.BallCount
	for i = 1, n do
		local side = (i % 2 == 0) and 1 or -1
		local z = ((i - 0.5) / n - 0.5) * (Config.Arena.Width - 10)
		createBall(Vector3.new(side * 8, 3, z))
	end
end

function BallService.Clear()
	for player in held do
		player:SetAttribute("HasBall", false)
	end
	table.clear(held)
	table.clear(active)
	table.clear(balls)
	stopLoop()
	ballsFolder:ClearAllChildren()
end

function BallService.Reset()
	BallService.Clear()
	BallService.SpawnBalls()
end

function BallService.Drop(player)
	local ball = held[player]
	held[player] = nil
	player:SetAttribute("HasBall", false)
	if ball and ball.Parent then release(ball) end
end

-- ============ Mira assistita ============
-- Piccolo aiuto alla mira: se un nemico è vicino alla linea di tiro, la palla si piega verso di lui.
local function applyAimAssist(player, origin, dir)
	local myTeam = player:GetAttribute("TeamIndex")
	local best
	local bestAngle = math.rad(Config.AimAssistAngle)
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("InMatch") and other:GetAttribute("TeamIndex") ~= myTeam then
			local oh = getRoot(other)
			if oh then
				local to = oh.Position - origin
				local dist = to.Magnitude
				if dist > 3 and dist <= Config.AimAssistRange then
					local ang = math.acos(math.clamp(dir:Dot(to.Unit), -1, 1))
					if ang < bestAngle then
						best, bestAngle = to.Unit, ang
					end
				end
			end
		end
	end
	if best then
		return dir:Lerp(best, Config.AimAssistStrength).Unit
	end
	return dir
end

-- ============ Lancio, presa, schivata ============
function BallService.Throw(player, target)
	local ball = held[player]
	if not ball or not player:GetAttribute("InMatch") then return end
	local d = balls[ball]
	if not d then return end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < Config.ThrowCooldown * 0.8 then return end
	local char = player.Character
	local hrp = getRoot(player)
	if not hrp then return end

	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local toTarget = target - origin
	local dist = toTarget.Magnitude
	if not (dist < Config.MaxThrowTargetDistance) then return end -- scarta bersagli assurdi (inf/NaN o troppo lontani)
	lastThrow[player] = now

	local dir = dist > 0.1 and toTarget.Unit or hrp.CFrame.LookVector
	dir = applyAimAssist(player, origin, dir)

	held[player] = nil
	player:SetAttribute("HasBall", false)
	local weld = ball:FindFirstChild("HoldWeld")
	if weld then weld:Destroy() end

	ball.Massless = false
	ball.CanCollide = true
	ball.CanTouch = true
	d.vf.Force = d.thrownForce
	d.vf.Enabled = true
	-- La palla parte dalla mano (niente "salto" dal petto), ma sempre davanti al corpo
	local startPos = origin + dir * 2.5
	local hand = getHand(char)
	if hand then
		local p = hand.Position + dir * 1.2
		local along = (p - origin):Dot(dir)
		if along < 2 then p += dir * (2 - along) end
		startPos = p
	end
	ball.CFrame = CFrame.new(startPos)
	ball.AssemblyLinearVelocity = dir * Config.BallSpeed
	pcall(function() ball:SetNetworkOwner(nil) end)

	ball.Color = THROWN_COLOR
	d.trail.Enabled = true
	d.thrower = player
	d.throwerTeam = player:GetAttribute("TeamIndex")
	d.thrownAt = now
	d.expireAt = now + Config.BallLifetime
	d.prev = startPos
	ball:SetAttribute("Thrower", player.UserId)
	ball:SetAttribute("ThrowerTeam", d.throwerTeam)
	ball:SetAttribute("ThrownAt", now)
	ball:SetAttribute("State", "Thrown")

	active[ball] = true
	ensureLoop()
end

function BallService.TryCatch(player)
	if not player:GetAttribute("InMatch") or held[player] then return end
	local now = os.clock()
	if now - (lastCatch[player] or -100) < Config.CatchCooldown then return end
	lastCatch[player] = now
	player:SetAttribute("CatchUntil", now + Config.CatchWindow)
end

function BallService.TryDodge(player)
	if not player:GetAttribute("InMatch") then return false end
	local now = os.clock()
	if now - (lastDodge[player] or -100) < Config.DodgeCooldown * 0.9 then return false end
	lastDodge[player] = now
	player:SetAttribute("DodgeUntil", now + Config.DodgeInvuln)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	BallService.Drop(player)
	roots[player] = nil
	lastThrow[player], lastCatch[player], lastDodge[player] = nil, nil, nil
end)

-- ============ Anti-blocco: palle fuori dall'arena tornano al punto di partenza ============
-- L'arena è chiusa da pareti e soffitto: questo è solo una rete di sicurezza (glitch di fisica, teletrasporti).
task.spawn(function()
	local halfL = Config.Arena.Length / 2 + 6
	local halfW = Config.Arena.Width / 2 + 6
	local maxY = Config.Arena.WallHeight + 60
	while true do
		task.wait(1)
		for ball, d in balls do
			if not ball.Parent then
				balls[ball] = nil
				active[ball] = nil
			elseif ball:GetAttribute("State") ~= "Held" then
				local p = ball.Position
				if p.Y < -20 or p.Y > maxY or math.abs(p.X) > halfL or math.abs(p.Z) > halfW then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.AssemblyAngularVelocity = Vector3.zero
					ball.CFrame = CFrame.new(d.home)
					setIdle(ball)
					pcall(function() ball:SetNetworkOwner(nil) end)
				end
			end
		end
	end
end)

return BallService
