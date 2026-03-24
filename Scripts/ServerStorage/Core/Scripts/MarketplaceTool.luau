--!strict
local MarketplaceTool = {}

local AttemptLimit: number = 5
local RetryDelay: number = 1

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")

--玩家是否拥有通行证
function MarketplaceTool.SafeUserOwnsGamePass(player: Player, gamePassId: number): (boolean, any)
	return RetryAsync(function()
		return marketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end, AttemptLimit, RetryDelay)
end

return MarketplaceTool
