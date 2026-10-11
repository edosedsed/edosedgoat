-- Aggiorna lo schermo della pre-lobby con stato della partita e timer.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local screen = workspace:WaitForChild("Arena"):WaitForChild("LobbyScreen")
local gui = screen:WaitForChild("SurfaceGui")
local status = gui:WaitForChild("Status")
local timer = gui:WaitForChild("Timer")

local state = { Phase = "Waiting", Message = "", EndsAt = 0, Queued = 0 }
Remotes.State.OnClientEvent:Connect(function(s)
	state = s
end)

RunService.Heartbeat:Connect(function()
	local text
	if state.Phase == "Waiting" then
		text = state.Message ~= "" and state.Message or string.format("In attesa di giocatori  (%d/%d)", #Players:GetPlayers(), Config.MinPlayers)
	else
		text = state.Message ~= "" and state.Message or "..."
		if state.Phase == "Intermission" and (state.Queued or 0) > 0 then
			text ..= string.format("  ·  in campo: %d", state.Queued)
		end
	end

	local clock = ""
	if state.EndsAt > 0 then
		local left = math.max(0, math.ceil(state.EndsAt - workspace:GetServerTimeNow()))
		clock = string.format("%d:%02d", left // 60, left % 60)
	end

	if status.Text ~= text then status.Text = text end
	if timer.Text ~= clock then timer.Text = clock end
end)
