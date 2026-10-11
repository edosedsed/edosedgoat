local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

-- Remotes devono esistere prima che i client li cerchino
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)

-- Gruppi di collisione: la barriera centrale ferma i giocatori ma non le palle
for _, name in { "Players", "Balls", "Barrier" } do
	PhysicsService:RegisterCollisionGroup(name)
end
PhysicsService:CollisionGroupSetCollidable("Barrier", "Balls", false)

require(script.Parent.Environment).Apply()
require(script.Parent.ArenaBuilder).Build()
local BallService = require(script.Parent.BallService)
local MatchService = require(script.Parent.MatchService)

-- Anti-spam: intervallo minimo tra due richieste accettate dallo stesso giocatore (Config.RemoteMinInterval)
local Players = game:GetService("Players")
local function makeLimiter(minInterval)
	local last = {}
	Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
	return function(player)
		local now = os.clock()
		if now - (last[player] or -100) < minInterval then return false end
		last[player] = now
		return true
	end
end
local allowThrow = makeLimiter(Config.RemoteMinInterval.Throw)
local allowCatch = makeLimiter(Config.RemoteMinInterval.Catch)
local allowDodge = makeLimiter(Config.RemoteMinInterval.Dodge)

Remotes.Throw.OnServerEvent:Connect(function(player, target, origin)
	if typeof(target) ~= "Vector3" or target ~= target then return end -- valida (no NaN); distanza e inf li controlla BallService
	if typeof(origin) ~= "Vector3" or origin ~= origin then origin = nil end -- origine facoltativa: se non valida si ignora
	if not allowThrow(player) then return end
	BallService.Throw(player, target, origin)
end)

Remotes.Catch.OnServerEvent:Connect(function(player)
	if not allowCatch(player) then return end
	BallService.TryCatch(player)
end)

Remotes.Dodge.OnServerEvent:Connect(function(player)
	if not allowDodge(player) then return end
	if BallService.TryDodge(player) then
		Remotes.DodgeFX:FireAllClients(player)
	end
end)

MatchService.Start()
