-- Camera: mouse libero (camera di default) oppure Shift Lock (camera da spalla, mouse bloccato).
-- Shift Lock migliorato:
--  * camera morbida: non scatta contro muri o giocatori, vetri e parti non solide non la spingono
--  * mirino stretto (clic destro / L2): zoom, camera più vicina, sensibilità ridotta
--  * cambio spalla (tasto E) con passaggio morbido
--  * supporto controller (stick destro) oltre al mouse
--  * il mouse si libera da solo con menu di Roblox, chat o pannello opzioni aperti
--  * sensibilità, FOV e asse Y invertito regolabili in ClientSettings
-- In entrambe le modalità: FOV dinamico e shake leggero.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ClientSettings = require(script.Parent.ClientSettings)

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
local shoulderCur = nil -- offset laterale attuale (si sposta piano quando cambi spalla)
local blend, blendFrom = 1, nil -- transizione quando premi Shift
local pendingYaw = nil -- direzione iniziale a inizio round
local userToggled = false
local aiming, aimAlpha = false, 0
local uiBlocked = false -- true quando un pannello del gioco ha bisogno del mouse

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
function CameraFX.SetAiming(v) aiming = v end
function CameraFX.IsAiming() return aimAlpha > 0.5 end
function CameraFX.SetUIBlocked(v) uiBlocked = v end
function CameraFX.SwapShoulder()
	ClientSettings.Set("ShoulderSide", -ClientSettings.Get("ShoulderSide"))
end

local function easeOut(t) return 1 - (1 - t) ^ 3 end

local function uiBusy()
	return uiBlocked or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil
end

-- Sensibilità effettiva (si riduce mentre il mirino è stretto)
local function sensitivity()
	local aimMul = 1 - (1 - ClientSettings.Get("AimSensitivity")) * aimAlpha
	return ClientSettings.Get("Sensitivity") * aimMul
end

local function applyLook(dx, dy)
	local inv = ClientSettings.Get("InvertY") and -1 or 1
	yaw -= dx
	pitch = math.clamp(pitch - dy * inv, C.MinPitch, C.MaxPitch)
end

-- A inizio round la camera guarda verso gli avversari (direzione decisa dal server)
player:GetAttributeChangedSignal("InMatch"):Connect(function()
	if player:GetAttribute("InMatch") then
		pendingYaw = player:GetAttribute("SpawnYaw")
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if active and input.UserInputType == Enum.UserInputType.MouseMovement and not uiBusy() then
		local sens = C.Sensitivity * gameSettings.MouseSensitivity * sensitivity()
		applyLook(input.Delta.X * sens, input.Delta.Y * sens)
	end
end)

-- Stick destro del controller (zona morta circolare)
local function gamepadLook(dt)
	for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if st.KeyCode == Enum.KeyCode.Thumbstick2 then
			local x, y = st.Position.X, st.Position.Y
			local mag = math.sqrt(x * x + y * y)
			if mag > 0.15 then
				local scale = ((mag - 0.15) / 0.85) / mag
				local rate = 2.8 * sensitivity() * dt
				applyLook(x * scale * rate, -y * scale * rate)
			end
			return
		end
	end
end

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
	local hasInput = UserInputService.MouseEnabled or UserInputService.GamepadEnabled
	local want = inMatch and locked and hasInput

	if want and not active then
		active = true
		local _, ry = hrp.CFrame:ToOrientation()
		yaw = pendingYaw or ry
		pitch = C.StartPitch
		focus = hrp.Position
		camDist = nil
		shoulderCur = nil
		hum.CameraOffset = Vector3.zero
		if userToggled then
			blendFrom, blend = camera.CFrame, 0 -- passaggio morbido dalla camera libera
		else
			blend = 1 -- inizio round: stacco netto
		end
		userToggled = false
	elseif not want and active then
		active = false
		aiming, aimAlpha = false, 0
		userToggled = false
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	if inMatch then pendingYaw = nil end

	-- Mirino stretto: scorrevole 0..1
	local aimTarget = (active and aiming and ClientSettings.Get("AimZoom") and not uiBusy()) and 1 or 0
	aimAlpha += (aimTarget - aimAlpha) * (1 - math.exp(-14 * dt))

	-- FOV dinamico (valido in entrambe le modalità)
	if inMatch then
		fovActive = true
		local v = hrp.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local targetFov = C.FOV + ClientSettings.Get("FovOffset")
			+ math.clamp(speed / Config.WalkSpeed, 0, 1.5) * 3 + kick - 14 * aimAlpha
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
	if uiBusy() then
		-- menu, chat o pannello aperti: mouse libero e camera ferma
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		if UserInputService.GamepadEnabled then gamepadLook(dt) end
	end

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

	-- Spalla: passaggio morbido quando la cambi; con il mirino stretto la camera si avvicina
	local shoulderTarget = C.Shoulder * ClientSettings.Get("ShoulderSide")
	shoulderCur = shoulderCur or shoulderTarget
	shoulderCur += (shoulderTarget - shoulderCur) * (1 - math.exp(-12 * dt))

	local head = focus + Vector3.new(0, C.Height, 0)
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local offset = rot:VectorToWorldSpace(Vector3.new(
		shoulderCur * (1 - 0.35 * aimAlpha),
		0.5,
		C.Distance * (1 - 0.25 * aimAlpha)
	))
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
