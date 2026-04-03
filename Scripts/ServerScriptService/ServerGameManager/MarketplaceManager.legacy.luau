--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")

-- 付费随机策略拒付：运行时引擎有 PurchaseDenied 则使用；否则 typings/旧版无此枚举项，回退 NotProcessedYet。
local function getPolicyDeniedPurchaseDecision(): Enum.ProductPurchaseDecision
	local productPurchaseDecisionAny: any = Enum.ProductPurchaseDecision
	if productPurchaseDecisionAny.PurchaseDenied ~= nil then
		return productPurchaseDecisionAny.PurchaseDenied :: Enum.ProductPurchaseDecision
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function GrantShopBundleReward(
	player: Player,
	reward: GameConfig.RewardInfo,
	grantTipKey: string?,
	grantExpectedCount: number?,
	shopBundleId: number?,
	purchaseProductId: number?
)
	if reward.rewardType == GameConfig.RewardType.Currency then
		ServerGameInfo.UpdatePlayerCurrency(
			player,
			GameConfig.CurrencyType.Coin,
			reward.rewardCount,
			GameConfig.ItemCountChangeReason.GainFromPurchase
		)
		return
	end

	local rewardCount = reward.rewardCount or 1
	if rewardCount <= 0 then
		return
	end

	if reward.rewardType == GameConfig.RewardType.Brainrot then
		local config = GameConfig.BrainrotIdMap[reward.rewardId]
		if config then
			for _ = 1, rewardCount do
				BrainrotQueueManager.AddItem(
					player,
					reward.rewardId,
					config.quality,
					reward.rewardLv or 1,
					false,
					GameConfig.ItemType.Brainrot,
					false, -- 非岛屿流程：允许突破队列上限
					grantTipKey,
					grantExpectedCount,
					shopBundleId,
					GameConfig.ModelGetSource.Shop,
					purchaseProductId or 0
				)
			end
		end
		return
	end

	if reward.rewardType == GameConfig.RewardType.Coil then
		local config = GameConfig.CoilIdMap[reward.rewardId]
		if config then
			for _ = 1, rewardCount do
				BrainrotQueueManager.AddItem(
					player,
					reward.rewardId,
					config.quality,
					reward.rewardLv or 1,
					false,
					GameConfig.ItemType.Coil,
					false, -- 非岛屿流程：允许突破队列上限
					grantTipKey,
					grantExpectedCount,
					shopBundleId,
					nil,
					nil
				)
			end
		end
		return
	end

	if reward.rewardType == GameConfig.RewardType.LittleElfChest then
		local config = GameConfig.LittleElfChestIdMap[reward.rewardId]
		if config then
			for _ = 1, rewardCount do
				BrainrotQueueManager.AddItem(
					player,
					reward.rewardId,
					config.quality,
					reward.rewardLv or 1,
					false,
					GameConfig.ItemType.LittleElfChest,
					false, -- 非岛屿流程：允许突破队列上限
					grantTipKey,
					grantExpectedCount,
					shopBundleId,
					nil,
					nil
				)
			end
		end
		return
	end
end

local function GrantShopBundleByProductId(player: Player, receiptInfo: GameConfig.ReceiptInfo): (boolean, boolean, boolean)
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return false, false, false
	end
	for _, bundleId in ipairs(GameConfig.ShopBundleList) do
		local bundleData = GameConfig.ShopBundleById[bundleId]
		if bundleData then
			local productIndex: number? = nil
			if bundleData.config.productId1 == productId then
				productIndex = 1
			elseif bundleData.config.productId2 == productId then
				productIndex = 2
			elseif bundleData.config.productId3 == productId then
				productIndex = 3
			end
			if productIndex == nil then
				continue
			end
			local shopBundleId = bundleData.config.id
			if bundleData.config.arePaidRandomItemsRestricted ~= 0 and playerInfo.playerConfigInfo.arePaidRandomItemsRestricted then
				return false, false, true
			end
			if bundleData.config.canRepurchased == 0 and playerInfo.ownedShopBundleMap[shopBundleId] == true then
				return false, true, false
			end
			local function getGrantTipKey(reward: GameConfig.RewardInfo): string
				return `shopgrant_{purchaseId}_{shopBundleId}_{reward.rewardType}_{reward.rewardId}`
			end
			for _, reward in ipairs(bundleData.rewards) do
				if (reward.productIndex or 1) == productIndex then
					GrantShopBundleReward(
						player,
						reward,
						getGrantTipKey(reward),
						reward.rewardCount,
						shopBundleId,
						productId
					)
				end
			end
			playerInfo.ownedShopBundleMap[shopBundleId] = true
			playerInfo.playerInfoChanged = true
			return true, false, false
		end
	end
	return false, false, false
end

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
	elseif receiptInfo.ProductId == GameConfig.Paving.RebirthProductId then
		local success = ServerGameInfo.ExecuteRebirth(player, true)
		return if success then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	elseif receiptInfo.ProductId == GameConfig.ShopPaid.WalkSpeed10ProductId then
		ServerGameInfo.UpgradeAbilityPaid(player, "WalkSpeed", 10)
		AnalyticsTool.AddProductPurchaseEvent(player, receiptInfo)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif receiptInfo.ProductId == GameConfig.ShopPaid.MaxBricks10ProductId then
		ServerGameInfo.UpgradeAbilityPaid(player, "MaxBricks", 10)
		AnalyticsTool.AddProductPurchaseEvent(player, receiptInfo)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		local ok, denied, policyDenied = GrantShopBundleByProductId(player, receiptInfo)
		if ok then
			AnalyticsTool.AddProductPurchaseEvent(player, receiptInfo)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if policyDenied then
			return getPolicyDeniedPurchaseDecision()
		end
		if denied then
			-- 使用 NotProcessedYet 表示“不处理”，
			-- 同时由 GrantShopBundleByProductId 内的 owned 判断保证不会再次发放奖励。
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

marketplaceService.PromptGamePassPurchaseFinished:Connect(OnPromptGamePassPurchaseFinished)
marketplaceService.ProcessReceipt = ProcessReceipt
