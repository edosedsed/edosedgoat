-- HUD: pillole semi-trasparenti, punteggio di squadra, palla in mano, morte improvvisa,
-- avviso palla in arrivo e pannello opzioni (tasto P).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraFX = require(script.Parent.CameraFX)
local ClientSettings = require(script.Parent.ClientSettings)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "DodgeballHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(18, 20, 28)
local WHITE = Color3.fromRGB(245, 246, 250)
local MUTED = Color3.fromRGB(176, 182, 196)
local DANGER = Color3.fromRGB(255, 90, 90)
local BOLD = Enum.Font.GothamBold

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
local timer = text(top, UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 28), 28, WHITE, BOLD)

-- Banner morte improvvisa
local sdBanner = text(gui, UDim2.fromOffset(520, 36), UDim2.new(0.5, -260, 0, 132), 26, Color3.fromRGB(255, 110, 110), BOLD)
sdBanner.Text = "MORTE IMPROVVISA"
sdBanner.Visible = false

-- Punteggio squadre: giocatori vivi + punti
local scorePills = {}
for i, team in Config.Teams do
	local left = i == 1
	local p = pill(UDim2.fromOffset(210, 40), UDim2.new(left and 0 or 1, left and 16 or -16, 0, 16), Vector2.new(left and 0 or 1, 0))
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Position = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = team.Color
	dot.BorderSizePixel = 0
	dot.Parent = p
	corner(dot, 6)
	local lbl = text(p, UDim2.new(1, -40, 1, 0), UDim2.fromOffset(34, 0), 17, WHITE, BOLD, Enum.TextXAlignment.Left)
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
	local l = text(bg, UDim2.fromScale(1, 1), UDim2.new(), 13, WHITE, BOLD)
	l.Text = label
	l.ZIndex = 2
	return { bg = bg, fill = fill, color = color }
end
local bars = {
	{ bar = makeBar("F · Afferra", -80, Color3.fromRGB(110, 190, 140)), attr = "CatchCooldownEnd", cd = Config.CatchCooldown },
	{ bar = makeBar("Q · Schiva", 80, Color3.fromRGB(110, 165, 225)), attr = "DodgeCooldownEnd", cd = Config.DodgeCooldown },
}

-- Palla in mano (tipo + effetto)
local ballPill = pill(UDim2.fromOffset(260, 34), UDim2.new(0.5, 0, 1, -88), Vector2.new(0.5, 1))
ballPill.Visible = false
local ballDot = Instance.new("Frame")
ballDot.Size = UDim2.fromOffset(12, 12)
ballDot.Position = UDim2.fromOffset(14, 11)
ballDot.BorderSizePixel = 0
ballDot.Parent = ballPill
corner(ballDot, 6)
local ballLabel = text(ballPill, UDim2.new(1, -40, 1, 0), UDim2.fromOffset(34, 0), 14, WHITE, BOLD, Enum.TextXAlignment.Left)

local hint = text(gui, UDim2.fromOffset(820, 20), UDim2.new(0.5, 0, 1, -20), 14, WHITE)
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.TextTransparency = 0.15

-- Avviso palla in arrivo: freccia verso la palla + suggerimento
local arrow = text(gui, UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 28, DANGER, BOLD)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Text = "▲"
arrow.Visible = false
local dangerHint = text(gui, UDim2.fromOffset(320, 22), UDim2.new(0.5, 0, 0.5, 72), 15, Color3.fromRGB(255, 170, 170), BOLD)
dangerHint.AnchorPoint = Vector2.new(0.5, 0.5)
dangerHint.Text = "Q schiva  ·  F afferra"
dangerHint.Visible = false

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
local elimText = text(gui, UDim2.fromOffset(600, 70), UDim2.fromScale(0.5, 0.4), 44, WHITE, BOLD)
elimText.AnchorPoint = Vector2.new(0.5, 0.5)
elimText.TextTransparency = 1
local marker = text(gui, UDim2.fromOffset(50, 50), UDim2.fromScale(0.5, 0.5), 34, Color3.fromRGB(255, 120, 120), BOLD)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Text = "✕"
marker.TextTransparency = 1

local state = { Phase = "Waiting", Message = "", EndsAt = 0, Alive = { 0, 0 }, Queued = 0, Score = { 0, 0 }, SuddenDeath = false }
Remotes.State.OnClientEvent:Connect(function(s)
	state = s
end)

Remotes.Eliminated.OnClientEvent:Connect(function(reason)
	CameraFX.Shake(1.0)
	ClientSettings.PlaySound("Eliminated")
	elimText.Text = reason
	elimText.TextTransparency = 0
	flash.BackgroundTransparency = 0.75
	TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(elimText, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
end)

Remotes.HitMarker.OnClientEvent:Connect(function()
	CameraFX.Kick(2)
	ClientSettings.PlaySound("Hit")
	marker.TextTransparency = 0
	marker.Size = UDim2.fromOffset(64, 64)
	TweenService:Create(marker, TweenInfo.new(0.3), { TextTransparency = 1, Size = UDim2.fromOffset(50, 50) }):Play()
end)

player:GetAttributeChangedSignal("HasBall"):Connect(function()
	if player:GetAttribute("HasBall") then ClientSettings.PlaySound("Pickup") end
end)

-- ========== Pannello opzioni (tasto P) ==========
local PANEL_W, ROW_H = 360, 38
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(PANEL_W, 46 + 7 * ROW_H + 44)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = INK
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = true -- i clic sul pannello non diventano lanci
panel.Parent = gui
corner(panel, 16)
local title = text(panel, UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 10), 18, WHITE, BOLD, Enum.TextXAlignment.Left)
title.Text = "Opzioni"

local refreshers = {}
local function refreshAll()
	for _, f in refreshers do f() end
end

local function styledButton(txt, pos, size)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.Text = txt
	b.Font = BOLD
	b.TextSize = 15
	b.TextColor3 = WHITE
	b.BackgroundColor3 = Color3.fromRGB(60, 66, 84)
	b.BorderSizePixel = 0
	b.Parent = panel
	corner(b, 8)
	return b
end

local function rowLabel(i, labelText)
	local y = 46 + (i - 1) * ROW_H
	local l = text(panel, UDim2.fromOffset(170, 30), UDim2.fromOffset(16, y), 14, WHITE, nil, Enum.TextXAlignment.Left)
	l.Text = labelText
	return y
end

local function addStepRow(i, labelText, key, fmt)
	local y = rowLabel(i, labelText)
	local minus = styledButton("−", UDim2.fromOffset(196, y + 1), UDim2.fromOffset(30, 28))
	local val = text(panel, UDim2.fromOffset(76, 30), UDim2.fromOffset(228, y), 14, WHITE, BOLD)
	local plus = styledButton("+", UDim2.fromOffset(310, y + 1), UDim2.fromOffset(30, 28))
	minus.Activated:Connect(function() ClientSettings.Step(key, -1) end)
	plus.Activated:Connect(function() ClientSettings.Step(key, 1) end)
	table.insert(refreshers, function() val.Text = fmt(ClientSettings.Get(key)) end)
end

local function addToggleRow(i, labelText, key, textFn, onClick)
	local y = rowLabel(i, labelText)
	local b = styledButton("", UDim2.fromOffset(196, y + 1), UDim2.fromOffset(144, 28))
	b.Activated:Connect(onClick or function() ClientSettings.Set(key, not ClientSettings.Get(key)) end)
	table.insert(refreshers, function() b.Text = textFn(ClientSettings.Get(key)) end)
end

local function onOff(v) return v and "Sì" or "No" end
addStepRow(1, "Sensibilità", "Sensitivity", function(v) return string.format("%.1fx", v) end)
addStepRow(2, "Sensibilità mira", "AimSensitivity", function(v) return string.format("%.1fx", v) end)
addStepRow(3, "Campo visivo (FOV)", "FovOffset", function(v) return string.format("%+d", math.round(v)) end)
addToggleRow(4, "Inverti asse Y", "InvertY", onOff)
addToggleRow(5, "Spalla camera", "ShoulderSide", function(v) return v == 1 and "Destra" or "Sinistra" end, function()
	CameraFX.SwapShoulder()
end)
addToggleRow(6, "Zoom mira (clic destro)", "AimZoom", onOff)
addToggleRow(7, "Avviso palla in arrivo", "DangerWarning", onOff)

local footer = text(panel, UDim2.new(1, -32, 0, 30), UDim2.new(0, 16, 1, -38), 12, MUTED)
footer.Text = "P chiude il pannello · le opzioni valgono per questa partita"
refreshAll()
ClientSettings.Changed.Event:Connect(refreshAll)

local function setPanel(open)
	panel.Visible = open
	CameraFX.SetUIBlocked(open)
end

local gear = Instance.new("TextButton")
gear.Size = UDim2.fromOffset(104, 28)
gear.Position = UDim2.new(1, -16, 0, 64)
gear.AnchorPoint = Vector2.new(1, 0)
gear.Text = "P · Opzioni"
gear.Font = BOLD
gear.TextSize = 13
gear.TextColor3 = WHITE
gear.BackgroundColor3 = INK
gear.BackgroundTransparency = 0.3
gear.BorderSizePixel = 0
gear.Parent = gui
corner(gear, 10)
gear.Activated:Connect(function() setPanel(not panel.Visible) end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then setPanel(not panel.Visible) end
end)

-- ========== Palla in mano e minaccia in arrivo ==========
local function heldBallKind()
	local folder = workspace:FindFirstChild("Balls")
	local char = player.Character
	if not folder or not char then return nil end
	for _, b in folder:GetChildren() do
		if b:GetAttribute("State") == "Held" then
			local weld = b:FindFirstChild("HoldWeld")
			if weld and weld.Part0 and weld.Part0:IsDescendantOf(char) then
				return b:GetAttribute("Kind") or "Normal"
			end
		end
	end
	return nil
end

-- Palla nemica che sta per passare vicino a te: ritorna (palla, secondi all'impatto)
local function findThreat()
	local folder = workspace:FindFirstChild("Balls")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not folder or not hrp then return nil end
	local myTeam = player:GetAttribute("TeamIndex")
	local best, bestT
	for _, b in folder:GetChildren() do
		if b:GetAttribute("State") == "Thrown" and b:GetAttribute("ThrowerTeam") ~= myTeam then
			local r = b.Position - hrp.Position
			local v = b.AssemblyLinearVelocity
			local vv = v:Dot(v)
			if vv > 100 then
				local tc = -r:Dot(v) / vv -- istante di massimo avvicinamento
				if tc > 0 and tc < 1.5 and (r + v * tc).Magnitude < 6 and (not bestT or tc < bestT) then
					best, bestT = b, tc
				end
			end
		end
	end
	return best, bestT
end

local heldKind, heldTimer = nil, 0

RunService.RenderStepped:Connect(function(dt)
	message.Text = state.Message
	if state.EndsAt > 0 then
		local left = math.max(0, math.ceil(state.EndsAt - workspace:GetServerTimeNow()))
		timer.Text = string.format("%d:%02d", left // 60, left % 60)
	else
		timer.Text = ""
	end

	local playing = state.Phase == "Playing"
	local score = state.Score or { 0, 0 }
	for i, sp in scorePills do
		sp.frame.Visible = playing
		sp.label.Text = string.format("%s  %d  ·  %d pt", Config.Teams[i].Name, state.Alive[i] or 0, score[i] or 0)
	end

	sdBanner.Visible = playing and state.SuddenDeath == true
	if sdBanner.Visible then
		sdBanner.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 6))
	end

	local inMatch = player:GetAttribute("InMatch") == true
	local hasBall = player:GetAttribute("HasBall") == true
	crosshair.Visible = CameraFX.IsActive()
	crosshair.BackgroundTransparency = hasBall and 0 or 0.55 -- pieno solo quando puoi lanciare
	local sz = CameraFX.IsAiming() and 4 or 6
	crosshair.Size = UDim2.fromOffset(sz, sz)

	-- Palla in mano
	heldTimer += dt
	if heldTimer >= 0.1 then
		heldTimer = 0
		heldKind = (inMatch and hasBall) and heldBallKind() or nil
	end
	ballPill.Visible = heldKind ~= nil
	if heldKind then
		local info = ClientSettings.KindInfo[heldKind] or ClientSettings.KindInfo.Normal
		local def = Config.BallKinds[heldKind] or {}
		ballDot.BackgroundColor3 = def.Color or Color3.fromRGB(220, 60, 60)
		ballLabel.Text = info.Name .. "  ·  " .. info.Text
	end

	-- Suggerimenti
	if inMatch then
		local lockText = CameraFX.IsLocked() and "Shift: camera libera" or "Shift: blocca camera"
		local extra = CameraFX.IsActive() and "  ·  Clic destro: mira  ·  E: cambia spalla" or ""
		hint.Text = (hasBall and "Clic per lanciare" or "Raccogli una palla") .. "  ·  " .. lockText .. extra .. "  ·  P: opzioni"
	elseif player:GetAttribute("Queued") then
		hint.Text = "Sei in campo · si parte tra poco"
	elseif state.Phase == "Intermission" or state.Phase == "Playing" or state.Phase == "Waiting" then
		hint.Text = "Cammina dentro il cerchio per entrare in campo"
	else
		hint.Text = ""
	end

	-- Avviso palla in arrivo
	local threat, tc
	if inMatch and ClientSettings.Get("DangerWarning") then threat, tc = findThreat() end
	if threat then
		local cam = workspace.CurrentCamera
		local rel = cam.CFrame:PointToObjectSpace(threat.Position)
		local ang = math.atan2(rel.X, -rel.Z) -- 0 = davanti a te, positivo = a destra
		local urgency = 1 - tc / 1.5
		arrow.Visible = true
		arrow.Position = UDim2.new(0.5, math.sin(ang) * 150, 0.5, -math.cos(ang) * 150)
		arrow.Rotation = math.deg(ang)
		arrow.TextSize = 22 + 14 * urgency
		arrow.TextTransparency = 0.55 - 0.55 * urgency
		dangerHint.Visible = tc < 0.8
	else
		arrow.Visible = false
		dangerHint.Visible = false
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
