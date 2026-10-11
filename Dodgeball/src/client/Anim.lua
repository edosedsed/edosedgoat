-- Animazioni procedurali (solo locali) fatte muovendo i Motor6D. Funzionano su R15.
-- Ogni animazione usa un solo orologio (os.clock) quindi dura uguale a qualsiasi FPS.
-- Una nuova animazione sullo stesso giunto sostituisce quella in corso e ripristina prima il giunto.
local RunService = game:GetService("RunService")

local Anim = {}

local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(t) return 1 - (1 - t) ^ 3 end
local function easeInOut(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end

local running = {} -- [Motor6D] = funzione che ferma l'animazione in corso su quel giunto

-- tracks: { { joint = Motor6D, fn = function(t) -> CFrame (offset applicato a C0) } }
-- onTick(t) viene chiamata a ogni frame, dopo aver applicato la posa. Ritorna la funzione di stop.
local function animate(tracks, duration, onTick)
	for _, tr in tracks do
		local prev = running[tr.joint]
		if prev then prev() end
		tr.orig = tr.joint.C0
	end

	local conn
	local finished = false
	local function finish()
		if finished then return end
		finished = true
		if conn then conn:Disconnect() end
		for _, tr in tracks do
			if tr.joint.Parent then tr.joint.C0 = tr.orig end
			if running[tr.joint] == finish then running[tr.joint] = nil end
		end
	end
	for _, tr in tracks do running[tr.joint] = finish end

	local t0 = os.clock()
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		for _, tr in tracks do
			if not tr.joint.Parent then
				finish()
				return
			end
			tr.joint.C0 = tr.orig * tr.fn(math.min(t, duration))
		end
		if onTick then onTick(t) end
		if t >= duration then finish() end
	end)
	return finish
end

-- Capriola: dir = 1 in avanti, -1 all'indietro
function Anim.Roll(char, duration, dir)
	local joint = char and char:FindFirstChild("Root", true) -- R15: LowerTorso.Root
	if not joint or not joint:IsA("Motor6D") then return end
	animate({
		{
			joint = joint,
			fn = function(t)
				return CFrame.Angles(-(dir or 1) * math.pi * 2 * easeInOut(t / duration), 0, 0)
			end,
		},
	}, duration)
end

-- Curve del lancio. Tutte le posizioni sono continue e con velocità continua tra le fasi:
--   anticipazione (carica indietro) -> frustata (la velocità massima cade ESATTAMENTE al rilascio)
--   -> follow-through (il braccio finisce il gesto) -> ritorno morbido.
-- Ritorna: durata totale, funzione del braccio (radianti), funzione del busto (radianti).
function Anim.SwingCurves(releaseTime)
	local windup = releaseTime * 0.55 -- anticipazione più lenta della frustata: lo scatto resta il momento più veloce
	local whip = 2 * (releaseTime - windup) -- easeInOut: velocità massima a metà frustata = rilascio
	local whipEnd = windup + whip
	local hold = 0.04
	local back = 0.24
	local total = whipEnd + hold + back

	local function profile(rest, windupPose, endPose)
		return function(t)
			if t < windup then
				return lerp(rest, windupPose, easeInOut(t / windup))
			elseif t < whipEnd then
				return lerp(windupPose, endPose, easeInOut((t - windup) / whip))
			elseif t < whipEnd + hold then
				return endPose
			else
				return lerp(endPose, rest, easeInOut(math.min(1, (t - whipEnd - hold) / back)))
			end
		end
	end

	return total, profile(0, -1.5, 2.6), profile(0, -0.3, 0.22)
end

-- Lancio: il braccio (e un leggero giro del busto) fanno anticipazione, frustata e follow-through.
-- onRelease() viene chiamata UNA volta, nel frame in cui il braccio è alla massima velocità
-- (se il personaggio non ha le giunture R15 parte comunque dopo releaseTime secondi).
-- Ritorna { Cancel = function } : annulla animazione e rilascio (es. se schivi a metà lancio).
function Anim.Swing(char, releaseTime, onRelease)
	releaseTime = releaseTime or 0.14
	local cancelled, released = false, false
	local function fire()
		if released or cancelled then return end
		released = true
		if onRelease then onRelease() end
	end

	local arm = char and char:FindFirstChild("RightShoulder", true)
	local waist = char and char:FindFirstChild("Waist", true)
	if not arm or not arm:IsA("Motor6D") then
		task.delay(releaseTime, fire)
		return {
			Cancel = function() cancelled = true end,
		}
	end

	local total, armAngle, waistAngle = Anim.SwingCurves(releaseTime)
	local tracks = {
		{ joint = arm, fn = function(t) return CFrame.Angles(armAngle(t), 0, 0) end },
	}
	if waist and waist:IsA("Motor6D") then
		table.insert(tracks, { joint = waist, fn = function(t) return CFrame.Angles(0, waistAngle(t), 0) end })
	end

	local stop = animate(tracks, total, function(t)
		if t >= releaseTime then fire() end
	end)
	return {
		Cancel = function()
			cancelled = true
			stop()
		end,
	}
end

-- Presa: le braccia si alzano in avanti e restano così per tutta la finestra di presa (hold secondi), poi tornano giù.
-- Ritorna { Cancel = function }.
function Anim.Catch(char, hold)
	hold = math.max(hold or 0.45, 0.15)
	local up, back = 0.1, 0.22
	local function pose(t) -- 0 = riposo, 1 = braccia alzate
		if t < up then
			return easeOut(t / up)
		elseif t < hold then
			return 1
		end
		return 1 - easeInOut(math.min(1, (t - hold) / back))
	end

	local tracks = {}
	for _, name in { "RightShoulder", "LeftShoulder" } do
		local joint = char and char:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			table.insert(tracks, {
				joint = joint,
				fn = function(t) return CFrame.Angles(1.4 * pose(t), 0, 0) end,
			})
		end
	end
	if #tracks == 0 then
		return { Cancel = function() end }
	end
	return { Cancel = animate(tracks, hold + back) }
end

return Anim
