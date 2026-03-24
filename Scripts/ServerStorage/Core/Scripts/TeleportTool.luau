--!strict
local TeleportTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local teleportService: TeleportService = game:GetService("TeleportService")
local players: Players = game:GetService("Players")

local AttemptLimit: number = 5
local RetryDelay: number = 1
local FloodDelay: number = 15

local teleportingPlayers: { [number]: boolean } = {}

function TeleportTool.IsPlayerTeleporting(playerId: number): boolean
	return teleportingPlayers[playerId]
end

function TeleportTool.SafeTeleport(placeId: number, players: { Instance }, teleportOptions: Instance?): (boolean, any)
	for playerIndex: number, player: Instance in players do
		if player:IsA("Player") then
			teleportingPlayers[player.UserId] = true
		end
	end
	return RetryAsync(function()
		return teleportService:TeleportAsync(placeId, players, teleportOptions)
	end, AttemptLimit, RetryDelay)
end

local function HandleFailedTeleport(
	player: Player,
	teleportResult: Enum.TeleportResult,
	errorMessage: string,
	targetPlaceId: number,
	teleportOptions: Instance?
)
	if teleportResult == Enum.TeleportResult.Flooded then
		task.wait(FloodDelay)
	elseif teleportResult == Enum.TeleportResult.Failure then
		task.wait(RetryDelay)
	else
		teleportingPlayers[player.UserId] = nil
		error(("Invalid teleport [%s]: %s"):format(teleportResult.Name, errorMessage))
	end
	TeleportTool.SafeTeleport(targetPlaceId, { player }, teleportOptions)
end

local function OnPlayerRemoving(player: Player)
	teleportingPlayers[player.UserId] = nil
end

teleportService.TeleportInitFailed:Connect(HandleFailedTeleport)
players.PlayerRemoving:Connect(OnPlayerRemoving)

return TeleportTool
