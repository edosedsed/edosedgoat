-- Controlli: movimento morbido, mira, lancio, presa, schivata e Shift Lock.
--  Clic = lancia · Q = schiva · F = afferra · Shift = blocca/sblocca camera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraFX = require(script.Parent.CameraFX)
local Anim = require(script.Parent.Anim)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local char, hum, hrp
local dodging, throwing = false, false
local dodgeToken = nil
local dodgeReady, catchReady, throwReady = 0, 0, 0
local autoRotateOff = false
local smoothed = Vector3.zero

local function bindChar(c)
	char = c
	hum = c:WaitForChild("Humanoid")
	hrp = c:WaitForChild("HumanoidRootPart")
	dodging, throwing = false, false
	dodgeToken = nil
	smoothed = Vector3.zero
end
if player.Character then task.spawn(bindChar, player.Character) end
player.CharacterAdded:Connect(bindChar)

local function alive()
	return hum and hrp and hum.Health > 0 and hrp.Parent ~= nil
end

local function inMatch()
	return player:GetAttribute("InMatch") == true
end

-- ========== Mira e lancio ==========
local function aimPoint(screenPos)
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, workspace:FindFirstChild("Balls") }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	return result and result.Position or (ray.Origin + ray.Direction * 300)
end

local function flatToward(point)
	return Vector3.new(point.X - hrp.Position.X, 0, point.Z - hrp.Position.Z)
end

-- Il lancio è sincronizzato con il braccio: la palla parte a metà movimento (Config.ThrowRelease)
-- e la mira viene letta nell'istante del rilascio, non del clic.
local function throw(getScreenPos)
	if throwing or dodging or not alive() or not player:GetAttribute("HasBall") then return end
	if os.clock() < throwReady then return end
	throwing = true
	Anim.Swing(char)

	local function release()
		throwing = false
		if not alive() or not inMatch() or dodging or not player:GetAttribute("HasBall") then return end
		throwReady = os.clock() + Config.ThrowCooldown
		Remotes.Throw:FireServer(aimPoint(getScreenPos()))
		CameraFX.Kick(3)
	end
	if Config.ThrowRelease > 0 then
		task.delay(Config.ThrowRelease, release)
	else
		release()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not inMatch() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		throw(function()
			return CameraFX.IsActive() and (camera.ViewportSize / 2) or UserInputService:GetMouseLocation()
		end)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local pos = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		throw(function() return pos end)
	end
end)

-- ========== Orientamento ==========
RunService.RenderStepped:Connect(function(dt)
	if not alive() then return end
	local rotateAlpha = 1 - math.exp(-Config.TurnSpeed * dt)

	if CameraFX.IsActive() then
		-- Shift Lock: il personaggio guarda dove guarda la camera
		hum.AutoRotate = false
		autoRotateOff = true
		if not dodging then
			local target = CFrame.new(hrp.Position) * CFrame.Angles(0, CameraFX.GetYaw(), 0)
			hrp.CFrame = hrp.CFrame:Lerp(target, rotateAlpha)
		end
	elseif inMatch() and player:GetAttribute("HasBall") and UserInputService.MouseEnabled and not dodging then
		-- Mouse libero: con la palla in mano ti giri (morbidamente) verso il cursore
		hum.AutoRotate = false
		autoRotateOff = true
		local flat = flatToward(aimPoint(UserInputService:GetMouseLocation()))
		if flat.Magnitude > 3 then
			local target = CFrame.lookAt(hrp.Position, hrp.Position + flat)
			hrp.CFrame = hrp.CFrame:Lerp(target, rotateAlpha)
		end
	elseif autoRotateOff then
		hum.AutoRotate = true
		autoRotateOff = false
	end
end)

-- ========== Camminata morbida (accelerazione e frenata graduali) ==========
RunService:BindToRenderStep("DodgeballMove", Enum.RenderPriority.Input.Value + 1, function(dt)
	if not alive() then return end
	local raw = hum.MoveDirection
	if not inMatch() or dodging then
		smoothed = raw
		return
	end
	local rate = raw.Magnitude > 0.05 and Config.Accel or Config.Decel
	smoothed = smoothed:Lerp(raw, 1 - math.exp(-rate * dt))
	if smoothed.Magnitude < 0.02 then smoothed = Vector3.zero end
	hum:Move(smoothed, false)
end)

-- ========== Schivata ==========
-- Scatto pulito: partenza immediata, frenata morbida, nessuno stato "rimasto appeso".
local function dodge()
	if dodging or not alive() or not inMatch() then return end
	local now = os.clock()
	if now < dodgeReady then return end
	dodgeReady = now + Config.DodgeCooldown
	player:SetAttribute("DodgeCooldownEnd", dodgeReady)

	local move = hum.MoveDirection
	move = Vector3.new(move.X, 0, move.Z)
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	local dir, rollDir
	if move.Magnitude > 0.1 then
		dir, rollDir = move.Unit, 1
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
	else
		dir, rollDir = -look, -1 -- da fermo: balzo all'indietro
	end

	local token = {}
	dodgeToken = token
	dodging = true
	throwing = false
	Remotes.Dodge:FireServer()
	CameraFX.Kick(6)
	Anim.Roll(char, Config.DodgeDuration, rollDir)

	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	lv.VectorVelocity = dir * Config.DodgeSpeed * 0.4
	lv.Parent = hrp

	local conn
	local function finish()
		conn:Disconnect()
		lv:Destroy()
		att:Destroy()
		if dodgeToken == token then
			dodging = false
			dodgeToken = nil
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		local a = (os.clock() - now) / Config.DodgeDuration
		if a >= 1 or dodgeToken ~= token or not alive() then
			finish()
			return
		end
		local ramp = math.min(1, 0.4 + a * 6) -- accelerazione quasi istantanea
		lv.VectorVelocity = dir * Config.DodgeSpeed * ramp * (1 - a * a)
	end)
end

-- ========== Presa ==========
local function catch()
	if not alive() or player:GetAttribute("HasBall") then return end
	local now = os.clock()
	if now < catchReady then return end
	catchReady = now + Config.CatchCooldown
	player:SetAttribute("CatchCooldownEnd", catchReady)
	Remotes.Catch:FireServer()
	CameraFX.Kick(-3)
end

-- ========== Tasti ==========
local function onAction(name, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if name == "Dodge" then
		dodge()
	elseif name == "Catch" then
		catch()
	elseif name == "ShiftLock" then
		CameraFX.SetLocked(not CameraFX.IsLocked())
	end
	return Enum.ContextActionResult.Sink
end

local function refreshBindings()
	if inMatch() then
		ContextActionService:BindAction("Dodge", onAction, true, Enum.KeyCode.Q)
		ContextActionService:SetTitle("Dodge", "SCHIVA")
		ContextActionService:BindAction("Catch", onAction, true, Enum.KeyCode.F)
		ContextActionService:SetTitle("Catch", "AFFERRA")
		ContextActionService:BindAction("ShiftLock", onAction, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	else
		ContextActionService:UnbindAction("Dodge")
		ContextActionService:UnbindAction("Catch")
		ContextActionService:UnbindAction("ShiftLock")
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(refreshBindings)
refreshBindings()
