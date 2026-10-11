-- HUD minimale: pillole semi-trasparenti, niente effetti vistosi.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraFX = require(script.Parent.CameraFX)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "DodgeballHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(18, 20, 28)
local WHITE = Color3.fromRGB(245, 246, 250)
local MUTED = Color3.fromRGB(176, 182, 196)

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = inst
end

local function pill(size, pos, anchor)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = INK
	f.BackgroundTransparency = 0.3
	f.BorderSizePixel = 0
	f.Parent = gui
	corner(f, 14)
	return f
end

local function text(parent, size, pos, textSize, color, font, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Text = ""
	l.Parent = parent
	return l
end

-- Pillola centrale: messaggio + timer
local top = pill(UDim2.fromOffset(300, 66), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
local message = text(top, UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6), 15, MUTED)
local timer = text(top, UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 28), 28, WHITE, Enum.Font.GothamBold)

-- Punteggio squadre
local scorePills = {}
for i, team in Config.Teams do
	local left = i == 1
	local p = pill(UDim2.fromOffset(150, 40), UDim2.new(left and 0 or 1, left and 16 or -16, 0, 16), Vector2.new(left and 0 or 1, 0))
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Position = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = team.Color
	dot.BorderSizePixel = 0
	dot.Parent = p
	corner(dot, 6)
	local lbl = text(p, UDim2.new(1, -40, 1, 0), UDim2.fromOffset(34, 0), 18, WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	p.Visible = false
	scorePills[i] = { frame = p, label = lbl }
end

-- Mirino (solo con Shift Lock)
local crosshair = Instance.new("Frame")
crosshair.Size = UDim2.fromOffset(6, 6)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.BackgroundColor3 = WHITE
crosshair.BorderSizePixel = 0
crosshair.Visible = false
crosshair.Parent = gui
corner(crosshair, 3)
local outline = Instance.new("UIStroke")
outline.Color = INK
outline.Transparency = 0.5
outline.Parent = crosshair

-- Barre cooldown
local function makeBar(label, xOffset, color)
	local bg = pill(UDim2.fromOffset(150, 28), UDim2.new(0.5, xOffset, 1, -52), Vector2.new(0.5, 1))
	bg.Visible = false
	bg.ClipsDescendants = true
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.25
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local l = text(bg, UDim2.fromScale(1, 1), UDim2.new(), 13, WHITE, Enum.Font.GothamBold)
	l.Text = label
	l.ZIndex = 2
	return { bg = bg, fill = fill, color = color }
end
local bars = {
	{ bar = makeBar("F · Afferra", -80, Color3.fromRGB(110, 190, 140)), attr = "CatchCooldownEnd", cd = Config.CatchCooldown },
	{ bar = makeBar("Q · Schiva", 80, Color3.fromRGB(110, 165, 225)), attr = "DodgeCooldownEnd", cd = Config.DodgeCooldown },
}

local hint = text(gui, UDim2.fromOffset(720, 20), UDim2.new(0.5, 0, 1, -20), 14, WHITE)
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.TextTransparency = 0.15

-- Messaggio breve sotto la pillola centrale (es. "Sei in campo!")
local toast = pill(UDim2.fromOffset(400, 34), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0))
toast.BackgroundTransparency = 1
local toastText = text(toast, UDim2.fromScale(1, 1), UDim2.new(), 15, WHITE)
toastText.TextTransparency = 1
local toastId = 0
Remotes.Notice.OnClientEvent:Connect(function(msg)
	toastId += 1
	local id = toastId
	toast.BackgroundTransparency = 0.3
	toastText.Text = msg
	toastText.TextTransparency = 0
	task.delay(2.5, function()
		if id ~= toastId then return end
		TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(toastText, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	end)
end)

-- Flash eliminazione + hitmarker
local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui
local elimText = text(gui, UDim2.fromOffset(600, 70), UDim2.fromScale(0.5, 0.4), 44, WHITE, Enum.Font.GothamBold)
elimText.AnchorPoint = Vector2.new(0.5, 0.5)
elimText.TextTransparency = 1
local marker = text(gui, UDim2.fromOffset(50, 50), UDim2.fromScale(0.5, 0.5), 34, Color3.fromRGB(255, 120, 120), Enum.Font.GothamBold)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Text = "✕"
marker.TextTransparency = 1

local state = { Phase = "Waiting", Message = "", EndsAt = 0, Alive = { 0, 0 }, Queued = 0 }
Remotes.State.OnClientEvent:Connect(function(s)
	state = s
end)

Remotes.Eliminated.OnClientEvent:Connect(function(reason)
	CameraFX.Shake(1.0)
	elimText.Text = reason
	elimText.TextTransparency = 0
	flash.BackgroundTransparency = 0.75
	TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(elimText, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
end)

Remotes.HitMarker.OnClientEvent:Connect(function()
	CameraFX.Kick(2)
	marker.TextTransparency = 0
	marker.Size = UDim2.fromOffset(64, 64)
	TweenService:Create(marker, TweenInfo.new(0.3), { TextTransparency = 1, Size = UDim2.fromOffset(50, 50) }):Play()
end)

RunService.RenderStepped:Connect(function()
	message.Text = state.Message
	if state.EndsAt > 0 then
		local left = math.max(0, math.ceil(state.EndsAt - workspace:GetServerTimeNow()))
		timer.Text = string.format("%d:%02d", left // 60, left % 60)
	else
		timer.Text = ""
	end

	local playing = state.Phase == "Playing"
	for i, sp in scorePills do
		sp.frame.Visible = playing
		sp.label.Text = string.format("%s  %d", Config.Teams[i].Name, state.Alive[i] or 0)
	end

	local inMatch = player:GetAttribute("InMatch") == true
	crosshair.Visible = CameraFX.IsActive()
	crosshair.BackgroundTransparency = player:GetAttribute("HasBall") and 0 or 0.55 -- pieno solo quando puoi lanciare

	if inMatch then
		local lockText = CameraFX.IsLocked() and "Shift: camera libera" or "Shift: blocca camera"
		hint.Text = (player:GetAttribute("HasBall") and "Clic per lanciare" or "Raccogli una palla") .. "  ·  " .. lockText
	elseif player:GetAttribute("Queued") then
		hint.Text = "Sei in campo · si parte tra poco"
	elseif state.Phase == "Intermission" or state.Phase == "Playing" or state.Phase == "Waiting" then
		hint.Text = "Cammina dentro il cerchio per entrare in campo"
	else
		hint.Text = ""
	end

	for _, b in bars do
		b.bar.bg.Visible = inMatch
		local remaining = (player:GetAttribute(b.attr) or 0) - os.clock()
		if remaining > 0 then
			b.bar.fill.Size = UDim2.fromScale(1 - remaining / b.cd, 1)
			b.bar.fill.BackgroundTransparency = 0.7
		else
			b.bar.fill.Size = UDim2.fromScale(1, 1)
			b.bar.fill.BackgroundTransparency = 0.25
		end
	end
end)
