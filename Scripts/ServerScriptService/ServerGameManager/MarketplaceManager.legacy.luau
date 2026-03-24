--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")

local function OnPromptGamePassPurchaseFinished(player: Instance, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	if not player:IsA("Player") then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassId)
	AnalyticsTool.AddPassPurchaseEvent(player, gamePassId, GameConfig.GamePassPrice[gamePassId])
end

--处理购买商品收据
local function ProcessReceipt(receiptInfo: GameConfig.ReceiptInfo): Enum.ProductPurchaseDecision
	local player: Player? = players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == GameConfig.Paving.DeathRescueProductId then
		NetMsg.FireNotifyRescueStart(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

marketplaceService.PromptGamePassPurchaseFinished:Connect(OnPromptGamePassPurchaseFinished)
marketplaceService.ProcessReceipt = ProcessReceipt
