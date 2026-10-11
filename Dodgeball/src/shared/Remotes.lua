-- Il server crea i RemoteEvent, il client li aspetta. Si usa con require() da entrambi.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Throw", "Catch", "Dodge", "DodgeFX", "State", "Eliminated", "HitMarker", "Notice" }

local folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local remotes = {}
for _, name in NAMES do
	remotes[name] = folder:WaitForChild(name)
end
return remotes
