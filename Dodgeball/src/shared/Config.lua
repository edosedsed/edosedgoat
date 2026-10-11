-- Tutte le impostazioni del gioco in un posto solo.
return {
	MinPlayers = 1, -- giocatori che devono entrare nel cerchio perché il round parta (metti 2+ per la versione finale)
	IntermissionTime = 20, -- secondi di pre-lobby prima di ogni round
	RoundTime = 120,
	EndedTime = 6,

	Teams = {
		{ Name = "Rossi", Color = Color3.fromRGB(226, 92, 92) },
		{ Name = "Blu", Color = Color3.fromRGB(84, 138, 222) },
	},

	Arena = { Length = 90, Width = 50, WallHeight = 30 },
	LobbyPosition = Vector3.new(0, 0, 200),

	-- Cerchio d'ingresso nella pre-lobby: ci cammini dentro e vieni teletrasportato in campo
	Portal = {
		Offset = Vector3.new(0, 0, -22), -- posizione rispetto al centro della lobby
		Radius = 5,
		OpenColor = Color3.fromRGB(128, 168, 142),
		ClosedColor = Color3.fromRGB(176, 180, 192),
	},

	-- Personaggio
	WalkSpeed = 15, -- più lento (16 è il default di Roblox)
	JumpHeight = 6.5,
	TurnSpeed = 18, -- quanto velocemente il personaggio ruota verso la mira
	Accel = 8, -- più basso = partenza più morbida
	Decel = 10, -- più basso = si ferma più lentamente (effetto "scivolata")

	-- Camera / Shift Lock
	ShiftLockDefault = true, -- true = camera da spalla con mouse bloccato (Shift per sbloccare)
	Camera = {
		FOV = 70,
		Distance = 11,
		Shoulder = 2.6,
		Height = 1.2,
		Sensitivity = 0.0028,
		StartPitch = -0.12, -- parte leggermente dall'alto per vedere il campo
		MinPitch = -1.0, -- guardare in basso
		MaxPitch = 0.75, -- guardare in alto
	},

	-- Palla
	BallCount = 6,
	BallSize = 2.4,
	BallSpeed = 95,
	BallGravityScale = 0.3,
	BallLifetime = 4,
	ThrowCooldown = 0.5,
	ThrowRelease = 0.12, -- secondi dal clic al rilascio (sincronizza la palla con il braccio; 0 = istantaneo)
	AimAssistAngle = 7,
	AimAssistStrength = 0.6,
	AimAssistRange = 120,
	BallIdleGravityScale = 1, -- gravità della palla a terra/ferma (1 = normale: si ferma e "dorme", meno fisica e rete; metti 0.3 per il vecchio effetto galleggiante)
	BallHitRadius = 2.2, -- raggio orizzontale (studs) del rilevamento colpi lungo la traiettoria
	BallHitHeight = 3.2, -- tolleranza verticale (studs) rispetto al centro del giocatore
	MaxThrowTargetDistance = 600, -- bersaglio inviato dal client oltre questa distanza viene ignorato
	SpentTime = 0.4, -- secondi in cui una palla che ha colpito non è raccoglibile

	-- Palle speciali. Ogni tipo può cambiare: Speed (moltiplicatore di BallSpeed), GravityScale, Density, Elasticity,
	-- Bounces (rimbalzi extra su muri/terra prima di fermarsi), Curve (curvatura laterale), Score (punti di una colpita),
	-- MaxPerRound (massimo per round), Weight (probabilità relativa) e Color (colore a terra e scia).
	-- Il tipo è anche nell'attributo "Kind" della palla: il client può usarlo per effetti, suoni e particelle.
	BallKindOrder = { "Normal", "Fast", "Heavy", "Bouncy", "Curve", "Golden" },
	BallKinds = {
		Normal = { Weight = 60 },
		Fast = { Weight = 14, Speed = 1.45, GravityScale = 0.15, Color = Color3.fromRGB(80, 200, 255) },
		Heavy = { Weight = 12, Speed = 0.8, GravityScale = 0.6, Density = 2.5, Color = Color3.fromRGB(90, 92, 112) },
		Bouncy = { Weight = 12, Bounces = 3, Elasticity = 1, Color = Color3.fromRGB(110, 215, 120) },
		Curve = { Weight = 10, Curve = 14, Color = Color3.fromRGB(190, 120, 240) },
		Golden = { Weight = 3, MaxPerRound = 1, Speed = 1.15, Score = 3, Color = Color3.fromRGB(255, 215, 60) },
	},

	-- Punti di squadra (servono come spareggio a fine tempo e nella morte improvvisa)
	Score = { Hit = 1, Catch = 1 },

	-- Fine partita
	SuddenDeathTime = 30, -- se a fine tempo i vivi sono pari: vince chi elimina per primo (poi spareggio a punti)
	StallTime = 35, -- secondi senza colpi né prese: la partita viene accorciata
	StallCountdown = 15, -- secondi che restano dopo l'avviso di stallo

	-- Presa
	CatchWindow = 0.45,
	CatchCooldown = 2.5,

	-- Schivata
	DodgeSpeed = 56,
	DodgeDuration = 0.3,
	DodgeInvuln = 0.42,
	DodgeCooldown = 1.5,

	-- Anti-spam sui RemoteEvent: intervallo minimo (secondi) tra due richieste accettate dallo stesso giocatore
	RemoteMinInterval = { Throw = 0.15, Catch = 0.2, Dodge = 0.25 },
}
