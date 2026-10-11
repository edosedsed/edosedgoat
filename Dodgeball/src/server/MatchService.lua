-- Ciclo di partita: pre-lobby (cerchio d'ingresso) -> partita -> fine.
--  * Durante la pre-lobby chi entra nel cerchio viene teletrasportato in campo e aspetta l'inizio.
--  * Allo scadere del timer parte il round con chi è entrato (almeno Config.MinPlayers).
--  * A round in corso si può ancora entrare dal cerchio, a meno che tu non sia già stato eliminato in quel round.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BallService = require(script.Parent.BallService)

local MatchService = {}

local teamList = {}
for i, t in Config.Teams do
	local team = Instance.new("Team")
	team.Name = t.Name
	team.TeamColor = BrickColor.new(t.Color)
	team.AutoAssignable = false
	team.Parent = Teams
	teamList[i] = team
end

local PORTAL_CENTER = Config.LobbyPosition + Config.Portal.Offset

-- State inviato ai client. Campi nuovi (compatibili): Score = { rossi, blu } e SuddenDeath = true/false
local current = { Phase = "Waiting", Message = "", EndsAt = 0, Alive = { 0, 0 }, Queued = 0, Score = { 0, 0 }, SuddenDeath = false }
local score = { 0, 0 } -- punti di squadra del round (spareggio)
local scoreDirty = false
local lastAction = os.clock() -- ultimo colpo/presa (anti-stallo)
local roundPlayed = {} -- [Player] = true: è già entrato in questo round
local noticeAt = {} -- anti-spam dei messaggi
local portal -- { disc, beam, label }

-- ============ Utilità ============
local function queuedPlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Queued") then table.insert(list, p) end
	end
	return list
end

local function countAlive()
	local c = { 0, 0 }
	for _, p in Players:GetPlayers() do
		local ti = p:GetAttribute("TeamIndex")
		if p:GetAttribute("InMatch") and ti then
			c[ti] += 1
		end
	end
	return c
end

local function push()
	current.Alive = countAlive()
	current.Queued = #queuedPlayers()
	current.Score = { score[1], score[2] }
	Remotes.State:FireAllClients(current)
end

local function setPortal(open)
	if not portal then return end
	local color = open and Config.Portal.OpenColor or Config.Portal.ClosedColor
	portal.disc.Color = color
	portal.beam.Color = color
	portal.label.Text = open and "ENTRA IN CAMPO" or "PARTITA FINITA"
end

local function setPhase(phase, message, duration)
	current.Phase = phase
	current.Message = message
	current.EndsAt = (duration and duration > 0) and (workspace:GetServerTimeNow() + duration) or 0
	setPortal(phase ~= "Ended")
	push()
end

local function teleport(player, cf)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hum and hum.Health > 0 then
		char:PivotTo(cf)
	end
end

-- Punto casuale nella lobby, lontano dal cerchio, già rivolto verso di esso
local function lobbyCFrame()
	local a = math.random() * math.pi * 2
	local r = 4 + math.random() * 7
	local pos = Config.LobbyPosition + Vector3.new(math.cos(a) * r, 4, math.sin(a) * r)
	return CFrame.lookAt(pos, Vector3.new(PORTAL_CENTER.X, pos.Y, PORTAL_CENTER.Z))
end

local function teamSpawn(teamIndex)
	local half = Config.Arena.Length / 2
	local sign = teamIndex == 1 and -1 or 1
	local x = sign * (4 + math.random() * (half - 8))
	local z = (math.random() - 0.5) * (Config.Arena.Width - 8)
	return CFrame.lookAt(Vector3.new(x, 4, z), Vector3.new(0, 4, z))
end

local function pickTeam()
	local c = { 0, 0 }
	for _, p in Players:GetPlayers() do
		local ti = p:GetAttribute("TeamIndex")
		if ti and (p:GetAttribute("InMatch") or p:GetAttribute("Queued")) then c[ti] += 1 end
	end
	if c[1] == c[2] then return math.random(2) end
	return c[1] < c[2] and 1 or 2
end

local function assignTeam(player, ti)
	player.Team = teamList[ti]
	player:SetAttribute("TeamIndex", ti)
	player:SetAttribute("SpawnYaw", ti == 1 and -math.pi / 2 or math.pi / 2) -- la camera parte rivolta verso gli avversari
end

local function notice(player, message)
	local now = os.clock()
	if now - (noticeAt[player] or -100) < 3 then return end
	noticeAt[player] = now
	Remotes.Notice:FireClient(player, message)
end

-- ============ Ingresso dal cerchio ============
function MatchService.Join(player)
	if player:GetAttribute("InMatch") or player:GetAttribute("Queued") then return end
	if current.Phase == "Ended" then return end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	if current.Phase == "Playing" then
		if roundPlayed[player] then
			notice(player, "Sei stato eliminato: rientri al prossimo round")
			return
		end
		roundPlayed[player] = true
		local ti = pickTeam()
		assignTeam(player, ti)
		teleport(player, teamSpawn(ti))
		player:SetAttribute("InMatch", true)
		notice(player, "Sei in campo!")
	else
		-- Pre-lobby: ti porta in campo e aspetti l'inizio
		local ti = pickTeam()
		assignTeam(player, ti)
		teleport(player, teamSpawn(ti))
		player:SetAttribute("Queued", true)
		notice(player, "Sei in campo: la partita sta per iniziare")
	end
	push()
end

function MatchService.Eliminate(player, reason)
	if not player:GetAttribute("InMatch") then return end
	player:SetAttribute("InMatch", false)
	BallService.Drop(player)
	Remotes.Eliminated:FireClient(player, reason or "Colpito!")
	teleport(player, lobbyCFrame())
end

local function setupPlayer(player)
	player:SetAttribute("InMatch", false)
	player:SetAttribute("Queued", false)
	player:SetAttribute("HasBall", false)

	local function onChar(char)
		player:SetAttribute("Queued", false)

		local function apply(d)
			if d:IsA("BasePart") then d.CollisionGroup = "Players" end
		end
		for _, d in char:GetDescendants() do apply(d) end
		char.DescendantAdded:Connect(apply)

		local hum = char:WaitForChild("Humanoid")
		hum.WalkSpeed = Config.WalkSpeed
		hum.UseJumpPower = false
		hum.JumpHeight = Config.JumpHeight
		hum.Died:Connect(function()
			player:SetAttribute("Queued", false)
			MatchService.Eliminate(player, "Sei caduto!")
			push()
		end)
	end
	if player.Character then task.spawn(onChar, player.Character) end
	player.CharacterAdded:Connect(onChar)

	Remotes.State:FireClient(player, current)
end

local function endCleanup()
	BallService.Clear()
	for _, p in Players:GetPlayers() do
		p:SetAttribute("InMatch", false)
		p:SetAttribute("Queued", false)
		p:SetAttribute("TeamIndex", nil)
		p.Team = nil
		teleport(p, lobbyCFrame())
	end
end

-- Se le squadre in coda differiscono di 2 o più giocatori (es. qualcuno è uscito), sposta chi serve
local function rebalanceQueued(queued)
	local lists = { {}, {} }
	for _, p in queued do
		local ti = p:GetAttribute("TeamIndex")
		if ti then table.insert(lists[ti], p) end
	end
	while math.abs(#lists[1] - #lists[2]) >= 2 do
		local from = #lists[1] > #lists[2] and 1 or 2
		local p = table.remove(lists[from], math.random(#lists[from]))
		table.insert(lists[3 - from], p)
		assignTeam(p, 3 - from)
	end
end

local function addScore(player, points)
	local ti = player:GetAttribute("TeamIndex")
	if ti then
		score[ti] += points
		scoreDirty = true
	end
	player:SetAttribute("RoundScore", (player:GetAttribute("RoundScore") or 0) + points)
	lastAction = os.clock()
end

-- ============ Un ciclo completo ============
local function runMatch()
	-- Pre-lobby: tutti liberi di entrare nel cerchio
	setPhase("Intermission", "Entra nel cerchio per giocare", Config.IntermissionTime)
	local t = os.clock() + Config.IntermissionTime
	while os.clock() < t do
		task.wait(0.25)
	end

	local queued = queuedPlayers()
	if #queued < Config.MinPlayers then
		setPhase("Waiting", string.format("Servono almeno %d giocatori in campo", Config.MinPlayers), 0)
		task.wait(2)
		return -- nuovo giro di pre-lobby
	end

	-- Via al round: chi è già in campo viene sistemato sulla propria metà
	table.clear(roundPlayed)
	rebalanceQueued(queued)
	score[1], score[2] = 0, 0
	scoreDirty = false
	current.SuddenDeath = false
	for _, p in queued do
		roundPlayed[p] = true
		p:SetAttribute("RoundScore", 0)
		teleport(p, teamSpawn(p:GetAttribute("TeamIndex")))
		p:SetAttribute("Queued", false)
		p:SetAttribute("InMatch", true)
	end

	BallService.Reset()
	lastAction = os.clock()
	setPhase("Playing", "Schiva, prendi e lancia!", Config.RoundTime)

	local endTime = os.clock() + Config.RoundTime
	local seen = { false, false } -- una squadra "esiste" da quando ha avuto almeno un giocatore vivo
	local last1, last2 = -1, -1
	local suddenDeath, stalled = false, false
	while true do
		local now = os.clock()
		local a = countAlive()
		for i = 1, 2 do
			if a[i] > 0 then seen[i] = true end
		end
		if a[1] ~= last1 or a[2] ~= last2 or scoreDirty then
			last1, last2 = a[1], a[2]
			scoreDirty = false
			push()
		end
		if (seen[1] and a[1] == 0) or (seen[2] and a[2] == 0) then break end
		if suddenDeath and a[1] ~= a[2] then break end -- morte improvvisa: la prima eliminazione decide

		if now >= endTime then
			if not suddenDeath and seen[1] and seen[2] and a[1] == a[2] then
				-- tempo scaduto con i vivi pari: morte improvvisa
				suddenDeath = true
				current.SuddenDeath = true
				endTime = now + Config.SuddenDeathTime
				lastAction = now
				setPhase("Playing", "MORTE IMPROVVISA! Chi elimina per primo vince", Config.SuddenDeathTime)
			else
				break
			end
		elseif not stalled and not suddenDeath and now - lastAction >= Config.StallTime and endTime - now > Config.StallCountdown then
			-- nessuno colpisce da troppo: la partita viene accorciata
			stalled = true
			endTime = now + Config.StallCountdown
			setPhase("Playing", "Nessuno attacca: la partita sta per finire!", Config.StallCountdown)
		end
		task.wait(0.2)
	end

	-- Vittoria: più giocatori vivi; a parità, più punti; altrimenti pareggio
	local a = countAlive()
	local winner, byScore
	if a[1] ~= a[2] then
		winner = a[1] > a[2] and 1 or 2
	elseif score[1] ~= score[2] then
		winner, byScore = score[1] > score[2] and 1 or 2, true
	end
	local msg = "Pareggio!"
	if winner then
		msg = Config.Teams[winner].Name .. (byScore and " vincono ai punti!" or " vincono!")
	end
	current.SuddenDeath = false
	setPhase("Ended", msg, Config.EndedTime)
	endCleanup()
	task.wait(Config.EndedTime)
end

function MatchService.Start()
	local arena = workspace:WaitForChild("Arena")
	portal = {
		disc = arena:WaitForChild("PortalDisc"),
		beam = arena:WaitForChild("PortalBeam"),
		label = arena:WaitForChild("PortalSign"):WaitForChild("Gui"):WaitForChild("Text"),
	}

	BallService.Hit.Event:Connect(function(kind, victim, thrower, ballKind)
		local def = Config.BallKinds[ballKind] or {}
		if kind == "Hit" then
			if thrower then
				Remotes.HitMarker:FireClient(thrower)
				addScore(thrower, def.Score or Config.Score.Hit)
			end
			MatchService.Eliminate(victim, "Colpito!")
		elseif kind == "Catch" and thrower then
			Remotes.HitMarker:FireClient(victim) -- chi afferra riceve il feedback
			addScore(victim, math.max(Config.Score.Catch, def.Score or 0))
			MatchService.Eliminate(thrower, "Palla afferrata!")
		end
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in Players:GetPlayers() do task.spawn(setupPlayer, p) end
	Players.PlayerRemoving:Connect(function(p)
		roundPlayed[p] = nil
		noticeAt[p] = nil
		task.defer(push)
	end)

	-- Rilevamento del cerchio (controllo a distanza: più affidabile di Touched)
	task.spawn(function()
		local radius = Config.Portal.Radius
		while true do
			task.wait(0.2)
			if current.Phase ~= "Ended" then
				for _, p in Players:GetPlayers() do
					-- chi è già in campo o in coda non serve controllarlo
					if not p:GetAttribute("InMatch") and not p:GetAttribute("Queued") then
						local hrp = BallService.GetRoot(p)
						if hrp then
							local d = hrp.Position - PORTAL_CENTER
							if d.X * d.X + d.Z * d.Z <= radius * radius and math.abs(d.Y) < 8 then
								MatchService.Join(p)
							end
						end
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			runMatch()
			task.wait(1)
		end
	end)
end

return MatchService
