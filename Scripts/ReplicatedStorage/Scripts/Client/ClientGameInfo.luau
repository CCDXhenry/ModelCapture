--!strict
local ClientGameInfo = {}
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo?
local otherPlayerInfoMap: { [number]: GameConfig.ClientOtherPlayerInfo } = {}

--初始化玩家信息
function ClientGameInfo.InitPlayerInfo(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	--初始化自己的玩家信息
	localPlayerInfo = {
		settingInfo = localPlayerSaveInfo.settingInfo,
		ownedGamePassList = localPlayerSaveInfo.ownedGamePassList,
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,

		currencies = localPlayerSaveInfo.currencies,
		inventoryInfo = localPlayerSaveInfo.inventoryInfo,
		homeInfo = localPlayerSaveInfo.homeInfo,
		shopInfo = localPlayerSaveInfo.shopInfo,
		brainrotsInfo = localPlayerSaveInfo.brainrotsInfo,
		brainrotQueue = localPlayerSaveInfo.brainrotQueue or {},
		homeSlot = localPlayerSaveInfo.homeSlot,

		-- 初始化瞬态信息
		carriedInfo = {
			bricks = 0,
		},
	}
	if localPlayerInfo == nil then
		return
	end
	for ownedGamePassIndex: number, ownedGamePassId: number in localPlayerInfo.ownedGamePassList do
		localPlayerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	--初始化其他玩家的玩家信息
	for otherPlayerIdKey: string, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo in otherPlayerSaveInfoMap do
		local otherPlayerId: number? = tonumber(otherPlayerIdKey)
		if otherPlayerId == nil then
			continue
		end
		local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {
			homeSlot = otherPlayerSaveInfo.homeSlot,
			homeInfo = otherPlayerSaveInfo.homeInfo,
			rebirthLevel = otherPlayerSaveInfo.rebirthLevel,
		}
		otherPlayerInfoMap[otherPlayerId] = otherPlayerInfo
	end
	--发送消息
	ClientMsg.FireLocalPlayerInfoInit()
	--print("[ClientGameInfo] InitPlayerInfo complete")
end

--初始化其他玩家信息
function ClientGameInfo.InitOtherPlayerInfo(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {
		homeSlot = otherPlayerSaveInfo.homeSlot,
		homeInfo = otherPlayerSaveInfo.homeInfo,
		rebirthLevel = otherPlayerSaveInfo.rebirthLevel,
	}
	otherPlayerInfoMap[playerId] = otherPlayerInfo
	ClientMsg.FireOtherPlayerInfoInit(playerId)
	print("[ClientGameInfo] InitOtherPlayerInfo for playerId", playerId)
end

--获取自己的玩家信息
function ClientGameInfo.GetLocalPlayerInfo(): GameConfig.ClientLocalPlayerInfo?
	return localPlayerInfo
end

--获取其他玩家的玩家信息
function ClientGameInfo.GetOtherPlayerInfo(playerId: number): GameConfig.ClientOtherPlayerInfo?
	if otherPlayerInfoMap == nil then
		return nil
	end
	return otherPlayerInfoMap[playerId]
end

--更新库存信息
function ClientGameInfo.UpdateInventory(inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	if localPlayerInfo then
		localPlayerInfo.inventoryInfo = inventoryInfo
		ClientMsg.FireLocalPlayerInventoryUpdate(inventoryInfo)
		print("[ClientGameInfo] Inventory updated and signal fired")
	end
end

--更新货币数量
function ClientGameInfo.UpdateCurrency(currencyType: number, totalAmount: number, lastChange: number, reason: number)
	if localPlayerInfo == nil then
		return
	end

	local currencyKey: string = tostring(currencyType)
	localPlayerInfo.currencies[currencyKey] = totalAmount
	print("[ClientGameInfo] UpdateCurrency type", currencyType, "total", totalAmount, "change", lastChange, "reason", reason)

	--如果是增加且金额大于0，弹出获得提示
	if lastChange > 0 then
		local rewardInfo: GameConfig.RewardInfo = {
			rewardType = GameConfig.RewardType.Currency,
			rewardId = currencyType,
			rewardCount = lastChange,
			rewardSource = reason,
		}
		ClientMsg.FireShowAddRewardsTip({ rewardInfo })
	end

	--通知界面刷新
	ClientMsg.FireLocalPlayerCurrencyUpdate()
end

--更新搬运信息
function ClientGameInfo.UpdateCarriedInfo(carriedInfo: GameConfig.PlayerCarriedInfo)
	if localPlayerInfo then
		localPlayerInfo.carriedInfo = carriedInfo
		ClientMsg.FireLocalPlayerCarriedUpdate(carriedInfo)
		--print("[ClientGameInfo] Carried update received and signal fired:", carriedInfo.bricks)
	end
end

--更新收益信息
function ClientGameInfo.UpdateAllPlayersModelYields(allYields: { [string]: { [string]: number } })
	for playerIdStr, yields in pairs(allYields) do
		local playerId = tonumber(playerIdStr)
		if not playerId then
			continue
		end

		local pInfo = if playerId == game.Players.LocalPlayer.UserId then localPlayerInfo else otherPlayerInfoMap[playerId]

		if pInfo and pInfo.homeInfo and pInfo.homeInfo.placedModels then
			for pointIndexStr, amount in pairs(yields) do
				local model = pInfo.homeInfo.placedModels[pointIndexStr]
				if model then
					model.unclaimedYield = amount
				end
			end
		end
	end
	ClientMsg.FireAllPlayersModelYieldsUpdate(allYields)
	print("[ClientGameInfo] All players model yields updated and signal fired")
end

--更新自己或其他玩家的房屋信息
function ClientGameInfo.UpdatePlayerHomeInfo(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	if localPlayerInfo ~= nil and playerId == game.Players.LocalPlayer.UserId then
		localPlayerInfo.homeSlot = homeSlot
		localPlayerInfo.homeInfo = homeInfo
		print("[ClientGameInfo] UpdatePlayerHomeInfo for LocalPlayer")
	elseif otherPlayerInfoMap[playerId] ~= nil then
		otherPlayerInfoMap[playerId].homeSlot = homeSlot
		otherPlayerInfoMap[playerId].homeInfo = homeInfo
		otherPlayerInfoMap[playerId].rebirthLevel = rebirthLevel
		print("[ClientGameInfo] UpdatePlayerHomeInfo for OtherPlayer", playerId)
	end
	ClientMsg.FirePlayerHomeInfoUpdate(playerId, homeSlot, homeInfo, rebirthLevel)
end

--自己获得了通行证
function ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId: number)
	if localPlayerInfo == nil or localPlayerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	table.insert(localPlayerInfo.ownedGamePassList, gamePassId)
	localPlayerInfo.ownedGamePassMap[gamePassId] = true
	ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId)
	print("[ClientGameInfo] SetLocalPlayerGamePassAcquired", gamePassId)
end

--更新技能等级
function ClientGameInfo.UpdateSkillLevel(skillType: number, level: number)
	if localPlayerInfo == nil then
		return
	end

	if skillType == GameConfig.SkillType.WalkSpeed then
		localPlayerInfo.shopInfo.walkSpeedLevel = level
	elseif skillType == GameConfig.SkillType.MaxBricks then
		localPlayerInfo.shopInfo.maxBricksLevel = level
	elseif skillType == GameConfig.SkillType.RebirthLevel then
		localPlayerInfo.shopInfo.rebirthLevel = level
	end

	print("[ClientGameInfo] UpdateSkillLevel", skillType, level)
	ClientMsg.FireLocalPlayerSkillLevelUpdate(skillType, level)
end

-- 更新无障碍信息
function ClientGameInfo.UpdateBrainrotQueue(queue: { GameConfig.BrainrotQueueItem })
	if localPlayerInfo then
		localPlayerInfo.brainrotQueue = queue
		ClientMsg.FireBrainrotQueueUpdate(queue)
		print("[ClientGameInfo] BrainrotQueue updated, count:", #queue)
	end
end

-- 获取当前 Brainrot 背包队列
function ClientGameInfo.GetBrainrotQueue(): { GameConfig.BrainrotQueueItem }
	if localPlayerInfo then
		return localPlayerInfo.brainrotQueue
	end
	return {}
end

-- 移除其他玩家信息 (当玩家离开时)
function ClientGameInfo.RemoveOtherPlayer(playerId: number)
	otherPlayerInfoMap[playerId] = nil
	print("[ClientGameInfo] RemoveOtherPlayer for playerId", playerId)
end

return ClientGameInfo
