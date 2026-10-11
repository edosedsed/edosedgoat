-- Impostazioni locali del giocatore (valgono per la sessione) e piccoli dati condivisi dal client.
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local ClientSettings = {}

ClientSettings.Values = {
	Sensitivity = 1, -- moltiplicatore della sensibilità del mouse / stick
	AimSensitivity = 0.6, -- moltiplicatore extra mentre tieni il mirino stretto (clic destro)
	FovOffset = 0, -- gradi aggiunti al FOV di Config.Camera.FOV
	InvertY = false,
	ShoulderSide = 1, -- 1 = camera sulla spalla destra, -1 = sinistra
	AimZoom = true, -- clic destro = mirino stretto
	DangerWarning = true, -- freccia quando una palla nemica sta per colpirti
}

-- { minimo, massimo, passo }
ClientSettings.Limits = {
	Sensitivity = { 0.3, 2.5, 0.1 },
	AimSensitivity = { 0.2, 1, 0.1 },
	FovOffset = { -10, 25, 5 },
}

ClientSettings.Changed = Instance.new("BindableEvent") -- Fire(key, value)

function ClientSettings.Get(key)
	return ClientSettings.Values[key]
end

function ClientSettings.Set(key, value)
	local lim = ClientSettings.Limits[key]
	if lim then
		value = math.floor(math.clamp(value, lim[1], lim[2]) * 100 + 0.5) / 100
	end
	if ClientSettings.Values[key] == value then return end
	ClientSettings.Values[key] = value
	ClientSettings.Changed:Fire(key, value)
end

function ClientSettings.Step(key, direction)
	local lim = ClientSettings.Limits[key]
	if lim then
		ClientSettings.Set(key, ClientSettings.Values[key] + direction * lim[3])
	end
end

-- Suoni: inserisci qui i tuoi asset (es. "rbxassetid://123456789"). Vuoto = nessun suono.
ClientSettings.Sounds = {
	Throw = "",
	Catch = "",
	Dodge = "",
	Pickup = "",
	Hit = "", -- quando colpisci o afferri
	Impact = "", -- una palla lanciata tocca terra o un muro vicino a te (mancato)
	Eliminated = "",
}

function ClientSettings.PlaySound(name)
	local id = ClientSettings.Sounds[name]
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.6
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

-- Nomi e descrizioni dei tipi di palla (usati da HUD e BallFX)
ClientSettings.KindInfo = {
	Normal = { Name = "Normale", Text = "Palla standard" },
	Fast = { Name = "Veloce", Text = "Più veloce e tesa" },
	Heavy = { Name = "Pesante", Text = "Lenta, cade di più" },
	Bouncy = { Name = "Rimbalzante", Text = "Rimbalza sui muri" },
	Curve = { Name = "A curva", Text = "Curva di lato" },
	Golden = { Name = "Dorata", Text = "Vale più punti" },
}

return ClientSettings
