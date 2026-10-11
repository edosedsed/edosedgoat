-- Gestione palle: spawn, raccolta, lancio, colpi e prese.
--  * Un solo ciclo Heartbeat (attivo SOLO quando ci sono palle in volo) controlla scadenza e colpi.
--  * I colpi ai giocatori sono verificati lungo la traiettoria (non si "salta" nessuno nemmeno con lag del server).
--  * Un controllo ogni secondo riporta a casa le palle finite fuori dall'arena (anti-blocco).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)

local BallService = {}
-- Fire(kind: "Hit" | "Catch", victim: Player, thrower: Player?, ballKind: string)
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
	if not ball.CanCollide then ball.CanCollide = true end -- (la palla "non ancora armata" di un lancio non deve restare fantasma)
	local idleColor = d and d.idleColor or IDLE_COLOR
	if ball.Color ~= idleColor then ball.Color = idleColor end
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
		BallService.Hit:Fire("Catch", plr, thrower, d.kind)
	else
		ball:SetAttribute("State", "Spent")
		d.armed = true
		ball.CanCollide = true -- una palla che ha colpito rimbalza sempre sul giocatore e non attraversa il pavimento
		ball.Color = d.idleColor
		d.trail.Enabled = false
		d.spentUntil = now + Config.SpentTime
		BallService.Hit:Fire("Hit", plr, thrower, d.kind)
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
			local now = os.clock()
			if d.bouncesLeft > 0 then
				-- palla Bouncy: rimbalza ancora invece di fermarsi (0.1s evita di contare lo stesso contatto due volte)
				if now - d.lastBounce > 0.1 then
					d.bouncesLeft -= 1
					d.lastBounce = now
				end
				return
			end
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

step = function(dt)
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
					if not d.armed then
						-- appena uscita dalla mano non collide con chi la lancia: si "arma" dopo pochi studs o 0.05s
						local root = d.thrower and getRoot(d.thrower)
						if now - d.thrownAt > 0.05 or not root or (cur - root.Position).Magnitude > 3.6 then
							d.armed = true
							ball.CanCollide = true
						end
					end
					sweep(ball, d, d.prev, cur)
					d.prev = cur
					if d.curve > 0 and ball:GetAttribute("State") == "Thrown" then
						-- palla Curve: curva lateralmente rispetto alla direzione orizzontale
						local vel = ball.AssemblyLinearVelocity
						local flat = Vector3.new(vel.X, 0, vel.Z)
						if flat.Magnitude > 1 then
							ball.AssemblyLinearVelocity = vel + flat.Unit:Cross(Vector3.yAxis) * d.curve * d.curveSign * dt
						end
					end
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
local function createBall(position, kind)
	local def = Config.BallKinds[kind] or Config.BallKinds.Normal
	local ball = Instance.new("Part")
	ball.Name = "Dodgeball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Config.BallSize
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = def.Color or IDLE_COLOR
	ball.Position = position
	ball.CollisionGroup = "Balls"
	ball.CustomPhysicalProperties = PhysicalProperties.new(def.Density or 0.7, 0.4, def.Elasticity or 0.7, 1, 1)
	ball:SetAttribute("State", "Idle")
	ball:SetAttribute("Kind", kind)

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
	trail.Color = ColorSequence.new(def.Color or THROWN_COLOR)
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
		kind = kind,
		def = def,
		idleColor = def.Color or IDLE_COLOR,
		curve = def.Curve or 0,
		curveSign = 1,
		bouncesLeft = 0,
		lastBounce = 0,
		thrownForce = Vector3.new(0, weight * (1 - (def.GravityScale or Config.BallGravityScale)), 0),
		idleForce = Vector3.new(0, weight * (1 - Config.BallIdleGravityScale), 0),
		thrownAt = 0,
		armed = true,
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

-- Sceglie un tipo di palla in base ai pesi di Config.BallKinds, rispettando MaxPerRound.
local function pickKind(counts)
	local pool, total = {}, 0
	for _, name in Config.BallKindOrder do
		local def = Config.BallKinds[name]
		if def and (def.Weight or 0) > 0 and (not def.MaxPerRound or (counts[name] or 0) < def.MaxPerRound) then
			total += def.Weight
			table.insert(pool, { name = name, w = def.Weight })
		end
	end
	local r = math.random() * total
	for _, e in pool do
		r -= e.w
		if r <= 0 then return e.name end
	end
	return "Normal"
end

function BallService.SpawnBalls()
	local n = Config.BallCount
	local counts = {}
	local pairKind
	for i = 1, n do
		local side = (i % 2 == 0) and 1 or -1
		local z = ((i - 0.5) / n - 0.5) * (Config.Arena.Width - 10)
		-- Le palle nascono a coppie uguali (una per metà campo) per restare giuste; la Golden è unica e va su un lato solo
		local kind
		if i % 2 == 1 then
			kind = pickKind(counts)
			pairKind = kind
		else
			kind = (Config.BallKinds[pairKind] and Config.BallKinds[pairKind].MaxPerRound) and "Normal" or pairKind
		end
		counts[kind] = (counts[kind] or 0) + 1
		createBall(Vector3.new(side * 8, 3, z), kind)
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
-- Ritorna la nuova direzione e la distanza del punto mirato (serve per compensare la caduta).
local function applyAimAssist(player, origin, dir, dist)
	local myTeam = player:GetAttribute("TeamIndex")
	local best, bestDist
	local bestAngle = math.rad(Config.AimAssistAngle)
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("InMatch") and other:GetAttribute("TeamIndex") ~= myTeam then
			local oh = getRoot(other)
			if oh then
				local to = oh.Position - origin
				local d = to.Magnitude
				if d > 3 and d <= Config.AimAssistRange then
					local ang = math.acos(math.clamp(dir:Dot(to.Unit), -1, 1))
					if ang < bestAngle then
						best, bestDist, bestAngle = to.Unit, d, ang
					end
				end
			end
		end
	end
	if best then
		return dir:Lerp(best, Config.AimAssistStrength).Unit, bestDist
	end
	return dir, dist
end

-- Alza la mira quanto basta perché la palla passi dal punto mirato.
-- Ogni palla compensa la propria caduta, tranne quelle che cadono PIÙ della standard (Heavy): per loro si compensa
-- come se fossero normali, così "cadono di più" resta la loro identità rispetto al mirino.
local function compensateDrop(dir, dist, def)
	local gs = def.GravityScale or Config.BallGravityScale
	local speed = Config.BallSpeed * (def.Speed or 1)
	if gs > Config.BallGravityScale then
		gs, speed = Config.BallGravityScale, Config.BallSpeed
	end
	local raise = Ballistics.Raise(
		workspace.Gravity * gs,
		speed,
		dist,
		dir.Y,
		Config.BallDropCompensation,
		math.rad(30)
	)
	if raise <= 0 then return dir end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then return dir end
	local elev = math.asin(math.clamp(dir.Y, -1, 1)) + raise
	return (flat.Unit * math.cos(elev) + Vector3.yAxis * math.sin(elev)).Unit
end

-- ============ Punto di partenza del lancio ============
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.CollisionGroup = "Balls" -- come la palla: attraversa la barriera centrale, si ferma su muri e giocatori

-- La palla parte da dove il client dice che era la mano al rilascio (così coincide con ciò che vede chi lancia),
-- ma solo se è plausibile; altrimenti dalla posizione della palla in mano; altrimenti davanti al petto.
-- Se tra petto e punto di partenza c'è un muro la palla viene fermata prima: non nasce mai dentro/dietro un ostacolo.
-- Ritorna posizione e se è stata accorciata da un ostacolo.
local function resolveStart(char, ball, chest, hint, fallbackDir)
	local tol = Config.ThrowOriginTolerance
	local cand
	if typeof(hint) == "Vector3" and (hint - chest).Magnitude <= tol then
		cand = hint
	elseif ball.Parent and (ball.Position - chest).Magnitude <= tol then
		cand = ball.Position
	else
		cand = chest + fallbackDir * 2.5
	end

	local radius = Config.BallSize / 2
	local off = cand - chest
	local len = off.Magnitude
	if len < 0.01 then return chest, false end
	local unit = off / len
	rayParams.FilterDescendantsInstances = { char, ballsFolder }
	local res = workspace:Raycast(chest, unit * (len + radius), rayParams)
	if res then
		local back = res.Distance - radius - 0.05
		return chest + unit * math.max(back, 0), true
	end
	return cand, false
end

-- ============ Lancio, presa, schivata ============
-- originHint: posizione della mano al rilascio, comunicata dal client (facoltativa, validata da resolveStart).
function BallService.Throw(player, target, originHint)
	local ball = held[player]
	if not ball or not player:GetAttribute("InMatch") then return end
	local d = balls[ball]
	if not d then return end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < Config.ThrowCooldown * 0.8 then return end
	local char = player.Character
	local hrp = getRoot(player)
	if not hrp then return end

	local chest = hrp.Position + Vector3.new(0, 1.5, 0)
	local toChest = target - chest
	if not (toChest.Magnitude < Config.MaxThrowTargetDistance) then return end -- scarta bersagli assurdi (inf/NaN o troppo lontani)
	lastThrow[player] = now

	local look = hrp.CFrame.LookVector
	local chestDir = toChest.Magnitude > 0.1 and toChest.Unit or look
	local startPos, blocked = resolveStart(char, ball, chest, originHint, chestDir)

	-- Direzione dalla posizione reale di partenza al punto mirato (niente errore di parallasse mano/petto)
	local toTarget = target - startPos
	local dist = toTarget.Magnitude
	local aimDir, aimDist
	if dist > 4 then
		aimDir, aimDist = toTarget.Unit, dist
	else
		aimDir, aimDist = look, 0 -- mira quasi ai piedi: tira dritto davanti a sé
	end
	aimDir, aimDist = applyAimAssist(player, startPos, aimDir, aimDist)
	local dir = compensateDrop(aimDir, aimDist, d.def)

	held[player] = nil
	player:SetAttribute("HasBall", false)
	local weld = ball:FindFirstChild("HoldWeld")
	if weld then weld:Destroy() end

	-- Un ostacolo entro pochi studs davanti alla palla: collide subito. Altrimenti resta "fantasma"
	-- per un istante per non urtare la mano/il corpo di chi lancia (si arma in step).
	local armedNow = blocked
	if not armedNow then
		rayParams.FilterDescendantsInstances = { char, ballsFolder }
		armedNow = workspace:Raycast(startPos, dir * 5, rayParams) ~= nil
	end

	local speed = Config.BallSpeed * (d.def.Speed or 1)
	d.curveSign = math.random(2) == 1 and 1 or -1

	ball.Massless = false
	ball.CanCollide = armedNow
	ball.CanTouch = true
	d.armed = armedNow
	d.vf.Force = d.thrownForce
	d.vf.Enabled = true
	ball.CFrame = CFrame.new(startPos)
	ball.AssemblyLinearVelocity = dir * speed
	-- Rotazione: effetto all'indietro lungo la traiettoria (le palle a curva girano di lato)
	local spinAxis = d.curve > 0 and Vector3.yAxis * d.curveSign or dir:Cross(Vector3.yAxis)
	ball.AssemblyAngularVelocity = spinAxis * (Config.BallSpin * speed / (Config.BallSize / 2))
	pcall(function() ball:SetNetworkOwner(nil) end)

	ball.Color = d.def.Color or THROWN_COLOR
	d.trail:Clear()
	d.trail.Enabled = true
	d.bouncesLeft = d.def.Bounces or 0
	d.lastBounce = 0
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
