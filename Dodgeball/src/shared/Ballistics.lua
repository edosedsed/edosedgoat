-- Calcolo puro (nessuna dipendenza da Roblox) della traiettoria con gravità costante.
local Ballistics = {}

-- Angolo di elevazione (radianti) con cui lanciare a velocità v per passare dal punto a distanza orizzontale x e dislivello y,
-- con accelerazione di gravità g. Se il punto è fuori portata, ritorna l'angolo di massima gittata.
function Ballistics.LaunchElevation(g, v, x, y)
	local v2 = v * v
	local disc = v2 * v2 - g * (g * x * x + 2 * y * v2)
	local tanT = (v2 - math.sqrt(math.max(disc, 0))) / (g * x)
	return math.atan(tanT)
end

-- Quanto bisogna alzare la mira (radianti) rispetto alla linea di vista per compensare la caduta.
-- amount: 0..1 (quanta compensazione applicare), maxRaise: limite di sicurezza (radianti).
function Ballistics.Raise(g, v, dist, sinElev, amount, maxRaise)
	local x = dist * math.sqrt(math.max(0, 1 - sinElev * sinElev))
	local y = dist * sinElev
	if amount <= 0 or x < 3 or g <= 0 then return 0 end
	local los = math.atan2(y, x)
	local want = Ballistics.LaunchElevation(g, v, x, y)
	return math.clamp((want - los) * amount, 0, maxRaise)
end

return Ballistics
