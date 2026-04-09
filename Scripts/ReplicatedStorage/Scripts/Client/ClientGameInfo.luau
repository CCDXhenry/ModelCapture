--!strict
local ClientGameInfo = {}
local players: Players = game:GetService("Players")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo?
local otherPlayerInfoMap: { [number]: GameConfig.ClientOtherPlayerInfo } = {}

-- 用于“新增 uid 才显示获得奖励提示”的增量判定
-- 避免玩家重新进游戏时把旧队列也触发提示。
local seenQueueUidSet: { [string]: boolean } = {}
local triggeredGrantTipKeySet: { [string]: boolean } = {}

--初始化玩家信息
function ClientGameInfo.InitPlayerInfo(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	--初始化自己的玩家信息
	local guideProgressInfo = localPlayerSaveInfo.guideProgressInfo
	if guideProgressInfo == nil then
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
		}
	end
	localPlayerInfo = {
		settingInfo = localPlayerSaveInfo.settingInfo,
		ownedGamePassList = localPlayerSaveInfo.ownedGamePassList,
		ownedShopBundleMap = localPlayerSaveInfo.ownedShopBundleMap or {},
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,

		currencies = localPlayerSaveInfo.currencies,
		inventoryInfo = localPlayerSaveInfo.inventoryInfo,
		homeInfo = localPlayerSaveInfo.homeInfo,
		shopInfo = localPlayerSaveInfo.shopInfo,
		brainrotsInfo = localPlayerSaveInfo.brainrotsInfo,
		brainrotQueue = localPlayerSaveInfo.brainrotQueue or {},
		homeSlot = localPlayerSaveInfo.homeSlot,
		guideProgressInfo = guideProgressInfo,
		currentGuideType = GameConfig.GuideType.None,

		-- 初始化瞬态信息
		carriedInfo = {
			bricks = 0,
		},
	}
	if localPlayerInfo == nil then
		return
	end

	-- 初始化“已存在 uid”集合：首次 UpdateBrainrotQueue 时不触发提示
	local initialQueue = localPlayerSaveInfo.brainrotQueue or {}
	for _, item in ipairs(initialQueue) do
		seenQueueUidSet[item.uid] = true
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

-- 家园展台收益数字 UI：最多每秒刷新一次，减轻 ClientGameManager 侧 NetMsg 回调压力；数据仍每包合并。
local HOME_YIELD_UI_MIN_INTERVAL = 1.0
local lastYieldUiFireClock = -math.huge
local yieldUiThrottleSeq = 0

local function buildAllPlayersModelYieldsSnapshot(): { [string]: { [string]: number } }
	local snapshot: { [string]: { [string]: number } } = {}
	local function addPlayerYields(playerId: number, pInfo: GameConfig.ClientLocalPlayerInfo | GameConfig.ClientOtherPlayerInfo)
		if not pInfo.homeInfo or not pInfo.homeInfo.placedModels then
			return
		end
		local yieldsForPlayer: { [string]: number } = {}
		for pointIndexStr, model in pairs(pInfo.homeInfo.placedModels) do
			if model then
				local m = model :: any
				yieldsForPlayer[pointIndexStr] = if type(m.unclaimedYield) == "number" then m.unclaimedYield else 0
			end
		end
		if next(yieldsForPlayer) ~= nil then
			snapshot[tostring(playerId)] = yieldsForPlayer
		end
	end
	if localPlayerInfo then
		addPlayerYields(players.LocalPlayer.UserId, localPlayerInfo)
	end
	for otherPlayerId, otherInfo in pairs(otherPlayerInfoMap) do
		addPlayerYields(otherPlayerId, otherInfo)
	end
	return snapshot
end

local function fireYieldUiFromSnapshot()
	ClientMsg.FireAllPlayersModelYieldsUpdate(buildAllPlayersModelYieldsSnapshot())
	lastYieldUiFireClock = os.clock()
end

--更新收益信息
function ClientGameInfo.UpdateAllPlayersModelYields(allYields: { [string]: { [string]: number } })
	for playerIdStr, yields in pairs(allYields) do
		local playerId = tonumber(playerIdStr)
		if not playerId then
			continue
		end

		local pInfo = if playerId == players.LocalPlayer.UserId then localPlayerInfo else otherPlayerInfoMap[playerId]

		if pInfo and pInfo.homeInfo and pInfo.homeInfo.placedModels then
			for pointIndexStr, amount in pairs(yields) do
				local model = pInfo.homeInfo.placedModels[pointIndexStr]
				if model then
					model.unclaimedYield = amount
				end
			end
		end
	end

	local now = os.clock()
	if now - lastYieldUiFireClock >= HOME_YIELD_UI_MIN_INTERVAL then
		yieldUiThrottleSeq += 1
		fireYieldUiFromSnapshot()
	else
		yieldUiThrottleSeq += 1
		local seq = yieldUiThrottleSeq
		task.delay(HOME_YIELD_UI_MIN_INTERVAL - (now - lastYieldUiFireClock), function()
			if seq ~= yieldUiThrottleSeq then
				return
			end
			fireYieldUiFromSnapshot()
		end)
	end
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
		-- rebirthLevel 可能因旧路径缺参而为 nil，避免把已有缓存覆盖为空
		if rebirthLevel ~= nil then
			otherPlayerInfoMap[playerId].rebirthLevel = rebirthLevel
		end
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
		localPlayerInfo.settingInfo.decelerationOn = false
	end

	print("[ClientGameInfo] UpdateSkillLevel", skillType, level)
	ClientMsg.FireLocalPlayerSkillLevelUpdate(skillType, level)
end

-- 更新无障碍信息
function ClientGameInfo.UpdateBrainrotQueue(queue: { GameConfig.BrainrotQueueItem })
	if localPlayerInfo then
		-- 1) 统计每个 grantTipKey 对应的“总数”和“新增 uid 数”
		local groupInfoByTipKey:
			{ [string]: {
				expectedCount: number,
				itemType: number,
				configId: number,
				shopBundleId: number?,
				totalCount: number,
				newCount: number,
			} } = {}

		for _, item in ipairs(queue) do
			local tipKey = item.grantTipKey
			if tipKey ~= nil then
				local g = groupInfoByTipKey[tipKey]
				if g == nil then
					g = {
						expectedCount = item.grantExpectedCount or 0,
						itemType = item.itemType or GameConfig.ItemType.Brainrot,
						configId = item.configId,
						shopBundleId = item.grantShopBundleId,
						totalCount = 0,
						newCount = 0,
					}
					groupInfoByTipKey[tipKey] = g
				end

				g.totalCount += 1
				if not seenQueueUidSet[item.uid] then
					g.newCount += 1
				end
			end
		end

		-- 2) 更新本地队列状态并广播
		localPlayerInfo.brainrotQueue = queue
		ClientMsg.FireBrainrotQueueUpdate(queue)

		-- 3) 触发“获得奖励提示”（只对“新增 uid”触发）
		for tipKey, g in pairs(groupInfoByTipKey) do
			if not triggeredGrantTipKeySet[tipKey]
				and g.expectedCount > 0
				and g.totalCount >= g.expectedCount
				and g.newCount > 0
			then
				local rewardType: number?
				if g.itemType == GameConfig.ItemType.Brainrot then
					rewardType = GameConfig.RewardType.Brainrot
				elseif g.itemType == GameConfig.ItemType.Coil then
					rewardType = GameConfig.RewardType.Coil
				elseif g.itemType == GameConfig.ItemType.LittleElfChest then
					rewardType = GameConfig.RewardType.LittleElfChest
				end

				if rewardType ~= nil then
					local rewardInfo: GameConfig.RewardInfo = {
						rewardType = rewardType,
						rewardId = g.configId,
						rewardCount = g.expectedCount,
					}
					ClientMsg.FireShowAddRewardsTip({ rewardInfo })
					triggeredGrantTipKeySet[tipKey] = true

					-- 更新本地“已购”状态：用于商店界面立刻展示不可复购遮罩
					if g.shopBundleId ~= nil then
						localPlayerInfo.ownedShopBundleMap[g.shopBundleId] = true
					end
				end
			end
		end

		-- 4) 将队列 uid 记为已见，确保后续增量判定正确
		for _, item in ipairs(queue) do
			seenQueueUidSet[item.uid] = true
		end

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

function ClientGameInfo.GetCurrentGuideType(): number
	if localPlayerInfo == nil then
		return GameConfig.GuideType.None
	end
	return localPlayerInfo.currentGuideType
end

function ClientGameInfo.SetCurrentGuideType(guideType: number)
	if localPlayerInfo == nil then
		return
	end
	if localPlayerInfo.currentGuideType == guideType then
		return
	end
	localPlayerInfo.currentGuideType = guideType
	ClientMsg.FireCurrentGuideTypeChanged()
end

function ClientGameInfo.UpdateGuideProgressInfo(guideProgressInfo: GameConfig.GuideProgressSaveInfo)
	if localPlayerInfo == nil then
		return
	end
	localPlayerInfo.guideProgressInfo = guideProgressInfo
	ClientMsg.FireCurrentGuideTypeChanged()
end

-- 移除其他玩家信息 (当玩家离开时)
function ClientGameInfo.RemoveOtherPlayer(playerId: number)
	otherPlayerInfoMap[playerId] = nil
	print("[ClientGameInfo] RemoveOtherPlayer for playerId", playerId)
end

return ClientGameInfo
