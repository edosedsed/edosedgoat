-- Camera: mouse libero (camera di default) oppure Shift Lock (camera da spalla, mouse bloccato).
-- Shift Lock migliorato:
--  * la camera non "scatta" quando tocca muri o altri giocatori: si avvicina subito, si riallontana piano
--  * vetri e parti non solide non spingono la camera
--  * nei salti la camera sale piano (niente rimbalzi), in orizzontale resta reattiva
--  * partenza dall'alto, rivolta verso gli avversari; passaggio morbido quando premi Shift
-- In entrambe le modalità: FOV dinamico e shake leggero.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local C = Config.Camera
local gameSettings = UserSettings():GetService("UserGameSettings")

local CameraFX = {}

local locked = Config.ShiftLockDefault
local active = false -- true solo con Shift Lock attivo in partita
local fovActive = false
local yaw, pitch = 0, C.StartPitch
local kick, shake = 0, 0
local focus = Vector3.zero
local camDist = nil -- distanza attuale dal personaggio (dopo le collisioni)
local blend, blendFrom = 1, nil -- transizione quando premi Shift
local pendingYaw = nil -- direzione iniziale a inizio round
local userToggled = false

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

function CameraFX.IsActive() return active end
function CameraFX.IsLocked() return locked end
function CameraFX.SetLocked(v)
	locked = v
	userToggled = true
end
function CameraFX.GetYaw() return yaw end
function CameraFX.Kick(amount) kick = math.max(kick, amount) end
function CameraFX.Shake(amount) shake = math.max(shake, amount) end

local function easeOut(t) return 1 - (1 - t) ^ 3 end

-- A inizio round la camera guarda verso gli avversari (direzione decisa dal server)
player:GetAttributeChangedSignal("InMatch"):Connect(function()
	if player:GetAttribute("InMatch") then
		pendingYaw = player:GetAttribute("SpawnYaw")
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if active and input.UserInputType == Enum.UserInputType.MouseMovement then
		local sens = C.Sensitivity * gameSettings.MouseSensitivity
		yaw -= input.Delta.X * sens
		pitch = math.clamp(pitch - input.Delta.Y * sens, C.MinPitch, C.MaxPitch)
	end
end)

-- Raggio di collisione della camera: ignora personaggi, palle, vetri e parti non solide
local function castCamera(origin, direction, char)
	local list = {}
	if char then table.insert(list, char) end
	local balls = workspace:FindFirstChild("Balls")
	if balls then table.insert(list, balls) end
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character ~= char then table.insert(list, p.Character) end
	end
	for _ = 1, 5 do
		params.FilterDescendantsInstances = list
		local result = workspace:Raycast(origin, direction, params)
		if not result then return nil end
		local part = result.Instance
		if part.Transparency > 0.4 or not part.CanCollide then
			table.insert(list, part)
		else
			return result
		end
	end
	return nil
end

local function update(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local inMatch = player:GetAttribute("InMatch") == true and hum ~= nil and hum.Health > 0 and hrp ~= nil
	local want = inMatch and locked and UserInputService.MouseEnabled

	if want and not active then
		active = true
		local _, ry = hrp.CFrame:ToOrientation()
		yaw = pendingYaw or ry
		pitch = C.StartPitch
		focus = hrp.Position
		camDist = nil
		hum.CameraOffset = Vector3.zero
		if userToggled then
			blendFrom, blend = camera.CFrame, 0 -- passaggio morbido dalla camera libera
		else
			blend = 1 -- inizio round: stacco netto
		end
		userToggled = false
	elseif not want and active then
		active = false
		userToggled = false
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	if inMatch then pendingYaw = nil end

	-- FOV dinamico (valido in entrambe le modalità)
	if inMatch then
		fovActive = true
		local v = hrp.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local targetFov = C.FOV + math.clamp(speed / Config.WalkSpeed, 0, 1.5) * 3 + kick
		camera.FieldOfView += (targetFov - camera.FieldOfView) * (1 - math.exp(-10 * dt))
	elseif fovActive then
		fovActive = false
		camera.FieldOfView = C.FOV
	end

	if not active then
		if hum then
			hum.CameraOffset = (inMatch and shake > 0.01)
				and Vector3.new((math.random() - 0.5) * shake * 0.4, (math.random() - 0.5) * shake * 0.4, 0)
				or Vector3.zero
		end
		kick *= math.exp(-9 * dt)
		shake *= math.exp(-10 * dt)
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	-- Punto seguito: reattivo in orizzontale, morbido in verticale
	local hp = hrp.Position
	if (hp - focus).Magnitude > 30 then
		focus = hp -- teletrasporto: nessun "volo" della camera
	else
		local fx, fy = 1 - math.exp(-30 * dt), 1 - math.exp(-7 * dt)
		focus = Vector3.new(
			focus.X + (hp.X - focus.X) * fx,
			focus.Y + (hp.Y - focus.Y) * fy,
			focus.Z + (hp.Z - focus.Z) * fx
		)
	end

	local head = focus + Vector3.new(0, C.Height, 0)
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local offset = rot:VectorToWorldSpace(Vector3.new(C.Shoulder, 0.5, C.Distance))
	local len = offset.Magnitude

	-- Collisione morbida: si avvicina subito, si riallontana gradualmente
	local hit = castCamera(head, offset, char)
	local targetDist = hit and math.max(hit.Distance - 0.4, 1.2) or len
	camDist = camDist or len
	if targetDist < camDist then
		camDist = targetDist
	else
		camDist += (targetDist - camDist) * (1 - math.exp(-6 * dt))
	end

	local cf = CFrame.new(head + offset.Unit * camDist) * rot
	if shake > 0.01 then
		cf *= CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
	end

	if blend < 1 then
		blend = math.min(1, blend + dt / 0.22)
		cf = blendFrom:Lerp(cf, easeOut(blend))
	end

	camera.CFrame = cf
	camera.Focus = CFrame.new(head)

	kick *= math.exp(-9 * dt)
	shake *= math.exp(-10 * dt)
end

RunService:BindToRenderStep("DodgeballCamera", Enum.RenderPriority.Camera.Value + 1, update)

return CameraFX
