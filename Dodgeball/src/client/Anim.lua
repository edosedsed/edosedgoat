-- Animazioni procedurali (solo locali) fatte muovendo i Motor6D. Funzionano su R15.
local RunService = game:GetService("RunService")

local Anim = {}

local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(t) return 1 - (1 - t) ^ 3 end
local function easeInOut(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end

local function play(joint, duration, offsetFn)
	if joint:GetAttribute("Animating") then return end
	joint:SetAttribute("Animating", true)
	local orig = joint.C0
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / duration
		if a >= 1 or not joint.Parent then
			conn:Disconnect()
			joint.C0 = orig
			joint:SetAttribute("Animating", nil)
			return
		end
		joint.C0 = orig * offsetFn(a)
	end)
end

-- Capriola: dir = 1 in avanti, -1 all'indietro
function Anim.Roll(char, duration, dir)
	local joint = char and char:FindFirstChild("Root", true) -- R15: LowerTorso.Root
	if not joint or not joint:IsA("Motor6D") then return end
	play(joint, duration, function(a)
		return CFrame.Angles(-(dir or 1) * math.pi * 2 * easeInOut(a), 0, 0)
	end)
end

-- Lancio: carica indietro, scatto in avanti, ritorno morbido
function Anim.Swing(char)
	local joint = char and char:FindFirstChild("RightShoulder", true)
	if not joint or not joint:IsA("Motor6D") then return end
	play(joint, 0.4, function(a)
		local ang
		if a < 0.2 then
			ang = lerp(0, -1.6, easeOut(a / 0.2))
		elseif a < 0.4 then
			ang = lerp(-1.6, 2.6, (a - 0.2) / 0.2)
		else
			ang = lerp(2.6, 0, easeInOut((a - 0.4) / 0.6))
		end
		return CFrame.Angles(ang, 0, 0)
	end)
end

return Anim
