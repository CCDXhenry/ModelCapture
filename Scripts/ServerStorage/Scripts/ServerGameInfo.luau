--!strict
local ServerGameInfo = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerMsg = require(serverScripts:FindFirstChild("ServerMsg"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local playerInfoMap: { [number]: GameConfig.PlayerInfo } = {}
local lastBroadcastModelYieldMap: { [number]: { [string]: number } } = {}

-- 存档或历史 bug 可能导致等级 > maxLevel；夹紧并写回，避免 abilityList 取空后回退到 1 级
type ShopLevelsClampTarget = {
	walkSpeedLevel: number,
	maxBricksLevel: number,
	rebirthLevel: number,
}

type HomeLevelClampTarget = {
	level: number,
}

local function ClampShopAndHomeLevelsFromConfig(shopInfo: ShopLevelsClampTarget, homeInfo: HomeLevelClampTarget): boolean
	local changed = false
	local walkShop = GameConfig.Shop.WalkSpeed
	if walkShop and walkShop.maxLevel > 0 then
		local v = math.clamp(math.floor(shopInfo.walkSpeedLevel + 0.5), 1, walkShop.maxLevel)
		if v ~= shopInfo.walkSpeedLevel then
			shopInfo.walkSpeedLevel = v
			changed = true
		end
	end
	local bricksShop = GameConfig.Shop.MaxBricks
	if bricksShop and bricksShop.maxLevel > 0 then
		local v = math.clamp(math.floor(shopInfo.maxBricksLevel + 0.5), 1, bricksShop.maxLevel)
		if v ~= shopInfo.maxBricksLevel then
			shopInfo.maxBricksLevel = v
			changed = true
		end
	end
	local homeShop = GameConfig.Shop.HomeLevel
	if homeShop and homeShop.maxLevel > 0 then
		local v = math.clamp(math.floor(homeInfo.level + 0.5), 1, homeShop.maxLevel)
		if v ~= homeInfo.level then
			homeInfo.level = v
			changed = true
		end
	end
	return changed
end

-- 付费 Brainrot 升级的挂起记录：按玩家缓存一次性升级信息，由收据回调消费
type PendingBrainrotPaidUpgrade = { pointIndex: number, levelAdd: number, createdAt: number }
local pendingBrainrotPaidUpgradeByUserId: { [number]: PendingBrainrotPaidUpgrade } = {}

local analyticsToolModule: any = nil
local function analyticsTool(): any
	if analyticsToolModule == nil then
		analyticsToolModule = require(serverScripts:FindFirstChild("AnalyticsTool"))
	end
	return analyticsToolModule
end

-- 与 PavingManager.legacy.luau 竖直射线参数对齐
local GROUND_RAY_ORIGIN_Y = 50
local GROUND_RAY_LENGTH = 60

local function GetWorkspaceGroundFolder(): Instance?
	return workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
end

local function IsPlayerOnWorkspaceGround(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end
	local groundFolder = GetWorkspaceGroundFolder()
	if not groundFolder then
		return false
	end
	local samplePos = rootPart.Position
	local rayOrigin = samplePos + Vector3.new(0, GROUND_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -GROUND_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { groundFolder }
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil
end

local function SyncCarriedBricksAfterMaxBricksUpgrade(player: Player)
	if IsPlayerOnWorkspaceGround(player) then
		ServerGameInfo.SetPlayerBricksToMax(player)
	else
		ServerGameInfo.UpdateInventoryBricks(player, 0)
	end
end

--初始化玩家信息
function ServerGameInfo.InitPlayerInfo(
	player: Player,
	playerSaveInfo: GameConfig.PlayerSaveInfo,
	countryRegion: string,
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	local playerInfo: GameConfig.PlayerInfo = {
		dataVersion = playerSaveInfo.dataVersion,
		firstEnterTime = playerSaveInfo.firstEnterTime,
		firstEnterVersion = playerSaveInfo.firstEnterVersion,
		gameTime = playerSaveInfo.gameTime,
		loginDays = playerSaveInfo.loginDays,
		lastOnlineDateUTC = playerSaveInfo.lastOnlineDateUTC,
		settingInfo = playerSaveInfo.settingInfo,
		ownedGamePassList = playerSaveInfo.ownedGamePassList,
		ownedShopBundleMap = playerSaveInfo.ownedShopBundleMap or {},
		playerInfoChanged = false,
		timeOfThisLogin = DateTime.now().UnixTimestamp,
		countryRegion = countryRegion,
		lastOnlineDate = DateTimeExtension.GetDate(DateTime.fromUnixTimestamp(playerSaveInfo.lastOnlineDateUTC)),
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,
		currencies = playerSaveInfo.currencies,
		inventoryInfo = playerSaveInfo.inventoryInfo,
		homeInfo = playerSaveInfo.homeInfo,
		shopInfo = playerSaveInfo.shopInfo,
		brainrotsInfo = playerSaveInfo.brainrotsInfo,
		brainrotQueue = playerSaveInfo.brainrotQueue or {},
		guideProgressInfo = playerSaveInfo.guideProgressInfo
			or {
				guideStepDoneMap = {},
				appearedGuideTypeInfo = {},
			},
		discoveredIslandIds = playerSaveInfo.discoveredIslandIds or {},
		homeSlot = "",

		-- 初始化瞬态数据
		carriedInfo = {
			bricks = 0,
		},
		lastArrivedIslandId = 1,
	}
	for ownedGamePassIndex: number, ownedGamePassId: number in playerInfo.ownedGamePassList do
		playerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	if ClampShopAndHomeLevelsFromConfig(playerInfo.shopInfo, playerInfo.homeInfo) then
		playerInfo.playerInfoChanged = true
	end
	playerInfoMap[player.UserId] = playerInfo
	player:SetAttribute("LastArrivedIslandId", playerInfo.lastArrivedIslandId)
	ServerMsg.FirePlayerInfoInit(player)

	local clientLocalPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo = {
		settingInfo = playerInfo.settingInfo,
		ownedGamePassList = playerInfo.ownedGamePassList,
		ownedShopBundleMap = playerInfo.ownedShopBundleMap,
		currencies = playerInfo.currencies,
		inventoryInfo = playerInfo.inventoryInfo,
		homeInfo = playerInfo.homeInfo,
		shopInfo = playerInfo.shopInfo,
		brainrotsInfo = playerInfo.brainrotsInfo,
		brainrotQueue = playerInfo.brainrotQueue,
		homeSlot = playerInfo.homeSlot,
		guideProgressInfo = playerInfo.guideProgressInfo,
	}
	local clientOtherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo = {
		homeSlot = playerInfo.homeSlot,
		homeInfo = playerInfo.homeInfo,
		rebirthLevel = playerInfo.shopInfo.rebirthLevel,
	}
	local clientOtherPlayerSyncInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo } = {}
	for player2Index: number, player2: Player in players:GetPlayers() do
		if player2.UserId == player.UserId then
			continue
		end
		local player2Info: GameConfig.PlayerInfo = playerInfoMap[player2.UserId]
		if player2Info == nil then
			continue
		end
		local clientOtherPlayer2SyncInfo: GameConfig.ClientOtherPlayerSyncInfo = {
			homeSlot = player2Info.homeSlot,
			homeInfo = player2Info.homeInfo,
			rebirthLevel = player2Info.shopInfo.rebirthLevel,
		}
		clientOtherPlayerSyncInfoMap[tostring(player2.UserId)] = clientOtherPlayer2SyncInfo
	end

	NetMsg.FireNotifyPlayerInfoInit(player, clientLocalPlayerSaveInfo, clientOtherPlayerSyncInfoMap, playerConfigInfo)
	NetMsg.FireNotifyPlayersOtherPlayerInfoInit(player.UserId, clientOtherPlayerSaveInfo)
	NetMsg.FireNotifyPlayerCarriedUpdate(player, playerInfo.carriedInfo)

	-- 应用行走速度
	ServerGameInfo.ApplyWalkSpeed(player)

	ServerMsg.FireLoadBackpackTools(player)

	local function OnCharacterReady(character: Model)
		task.wait(0.2)
		ServerMsg.FireLoadBackpackTools(player)
		ServerGameInfo.SetPlayerBricksToMax(player)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				local totalBricks = ServerGameInfo.GetPlayerMaxBricks(player)
				local remainingBricks = ServerGameInfo.GetPlayerCarriedBricks(player)
				local pinfo = ServerGameInfo.GetPlayerInfo(player)
				local islandId = if pinfo and pinfo.lastArrivedIslandId > 0 then pinfo.lastArrivedIslandId else 1
				analyticsTool().LogPlayerDeath(player, totalBricks, remainingBricks, islandId)
				-- 死亡后刷新：与重生/出生点对齐，避免客户端长期保留死前岛屿 id（飞行援助门槛等）
				if pinfo then
					pinfo.lastArrivedIslandId = 1
				end
				player:SetAttribute("LastArrivedIslandId", 1)
			end)
		end
	end
	player.CharacterAdded:Connect(OnCharacterReady)
	if player.Character then
		task.defer(OnCharacterReady, player.Character)
	end

	--print("[ServerGameInfo] InitPlayerInfo complete for", player.Name)
end

-- 通知玩家家园信息变更 (辅助方法)
function ServerGameInfo.NotifyPlayerHomeInfoUpdate(playerId: number)
	local playerInfo = playerInfoMap[playerId]
	if playerInfo then
		NetMsg.FireNotifyPlayerHomeInfoUpdate(playerId, playerInfo.homeSlot, playerInfo.homeInfo, playerInfo.shopInfo.rebirthLevel)
	end
end

--移除玩家信息
function ServerGameInfo.RemovePlayerInfo(player: Player)
	playerInfoMap[player.UserId] = nil
	lastBroadcastModelYieldMap[player.UserId] = nil
	--print("[ServerGameInfo] RemovePlayerInfo for", player.Name)
end

--获取玩家信息
function ServerGameInfo.GetPlayerInfo(player: Player)
	return playerInfoMap[player.UserId]
end

--创建玩家存档信息
function ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo: GameConfig.PlayerInfo): GameConfig.PlayerSaveInfo
	return {
		dataVersion = playerInfo.dataVersion,
		firstEnterTime = playerInfo.firstEnterTime,
		firstEnterVersion = playerInfo.firstEnterVersion,
		gameTime = playerInfo.gameTime,
		loginDays = playerInfo.loginDays,
		lastOnlineDateUTC = playerInfo.lastOnlineDateUTC,
		lastOnlineDate = playerInfo.lastOnlineDate,
		ownedGamePassList = playerInfo.ownedGamePassList,
		ownedShopBundleMap = playerInfo.ownedShopBundleMap,
		settingInfo = playerInfo.settingInfo,
		currencies = playerInfo.currencies,
		inventoryInfo = playerInfo.inventoryInfo,
		homeInfo = playerInfo.homeInfo,
		shopInfo = playerInfo.shopInfo,
		brainrotsInfo = playerInfo.brainrotsInfo,
		brainrotQueue = playerInfo.brainrotQueue,
		guideProgressInfo = playerInfo.guideProgressInfo,
		discoveredIslandIds = playerInfo.discoveredIslandIds,
	}
end

function ServerGameInfo.TryMarkBricksIntroGuideFinished(player: Player, maxBricksLevel: number)
	if maxBricksLevel < 2 then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	local key = GameConfig.GuideStepKey.BricksIntroFinished
	if playerInfo.guideProgressInfo.guideStepDoneMap[key] then
		return
	end
	playerInfo.guideProgressInfo.guideStepDoneMap[key] = true
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyGuideProgressInfo(player, playerInfo.guideProgressInfo)
end

--获取玩家重生倍率
function ServerGameInfo.GetRebirthMultiplier(player: Player): number
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return 1
	end
	local rebirthLevel = playerInfo.shopInfo.rebirthLevel or 0
	if rebirthLevel <= 0 then
		return 1
	end
	-- rebirthLevel 语义改为 0-based “已重生次数”，1 次重生对应 RebirthMap[1]
	local config = GameConfig.RebirthMap[rebirthLevel]
	return if config then config.collectMultiple else 1
end

--执行重生
function ServerGameInfo.ExecuteRebirth(player: Player, isPaid: boolean): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return false
	end

	local currentRebirthLevel = playerInfo.shopInfo.rebirthLevel or 0
	local nextRebirthCount = currentRebirthLevel + 1
	local nextRebirthConfig = GameConfig.RebirthMap[nextRebirthCount]
	if not nextRebirthConfig then
		print("[ServerGameInfo] ExecuteRebirth failed: max rebirth count reached for", player.Name)
		return false
	end

	-- 检查要求
	local requiredSpeedLv = nextRebirthConfig.speedLv
	local requiredBrickLv = nextRebirthConfig.brickLv

	if playerInfo.shopInfo.walkSpeedLevel < requiredSpeedLv or playerInfo.shopInfo.maxBricksLevel < requiredBrickLv then
		print("[ServerGameInfo] ExecuteRebirth failed: requirements not met for", player.Name)
		return false
	end

	local brickLevelBeforeRebirth = playerInfo.shopInfo.maxBricksLevel
	local speedLevelBeforeRebirth = playerInfo.shopInfo.walkSpeedLevel

	if not isPaid then
		-- 免费重生：重置等级
		playerInfo.shopInfo.walkSpeedLevel = 1
		playerInfo.shopInfo.maxBricksLevel = 1
		ServerGameInfo.ApplyWalkSpeed(player)
		-- 同步重置后的等级
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.WalkSpeed, 1)
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.MaxBricks, 1)
		-- 按重置后的砖块等级刷新当前砖块数量
		ServerGameInfo.SetPlayerBricksToMax(player)
	end

	-- 增加重生等级
	playerInfo.shopInfo.rebirthLevel = nextRebirthCount
	playerInfo.playerInfoChanged = true

	-- 升级重生等级后关闭减速，并刷新移速与 Speed Coil（与 PlayerSettingManager 请求关减速一致）
	if playerInfo.settingInfo.decelerationOn == true then
		ServerGameInfo.UpdateDecelerationOn(player, false)
		ServerGameInfo.ApplyWalkSpeed(player)
	end

	-- 通知客户端重生等级变更
	NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.RebirthLevel, playerInfo.shopInfo.rebirthLevel)

	--print("[ServerGameInfo] ExecuteRebirth success for", player.Name, "New Level:", playerInfo.shopInfo.rebirthLevel, "isPaid:", isPaid)
	analyticsTool().LogPlayerRebirth(
		player,
		playerInfo.shopInfo.rebirthLevel,
		brickLevelBeforeRebirth,
		speedLevelBeforeRebirth,
		if isPaid then 1 else 0
	)
	return true
end

--增加玩家游戏时间
function ServerGameInfo.AddPlayerGameTime(player: Player, addGameTime: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		--warn("[ServerGameInfo] AddPlayerGameTime failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.gameTime += addGameTime
	playerInfo.playerInfoChanged = true
end

--改变玩家登录天数
function ServerGameInfo.ChangePlayerLoginDays(player: Player, loginDays: number, lastOnlineDate: DateTimeExtension.DateTimeTable)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		--warn("[ServerGameInfo] ChangePlayerLoginDays failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.loginDays = loginDays
	--print("[ServerGameInfo] ChangePlayerLoginDays for", player.Name, "to", loginDays)
	playerInfo.lastOnlineDate = lastOnlineDate
	playerInfo.lastOnlineDateUTC = DateTime.fromUniversalTime(lastOnlineDate.Year, lastOnlineDate.Month, lastOnlineDate.Day).UnixTimestamp
	playerInfo.playerInfoChanged = true
end

--设置玩家通行证为已获得
function ServerGameInfo.SetPlayerGamePassAcquired(player: Player, gamePassId: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] SetPlayerGamePassAcquired failed: playerInfo not found for", player.Name)
		return
	end
	if playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	--print("[ServerGameInfo] SetPlayerGamePassAcquired for", player.Name, "id", gamePassId)
	table.insert(playerInfo.ownedGamePassList, gamePassId)
	playerInfo.ownedGamePassMap[gamePassId] = true
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyPlayerAcquiredGamePass(player, gamePassId)
end

--更新玩家家园展示位模型信息
function ServerGameInfo.UpdatePlayerPlacedModel(player: Player, pointIndex: number, modelInfo: GameConfig.ModelInfo)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdatePlayerPlacedModel failed: playerInfo not found for", player.Name)
		return
	end

	-- Mark guide progress when transitioning from "no brainrot on home" to "has brainrot on home".
	local hadBrainrotBefore = false
	for _, placedModel in pairs(playerInfo.homeInfo.placedModels) do
		if placedModel ~= nil then
			local placedAny = placedModel :: any
			local configId = placedAny.configId :: number?
			if configId ~= nil and GameConfig.BrainrotIdMap[configId] ~= nil then
				hadBrainrotBefore = true
				break
			end
		end
	end

	local modelInfoAny = modelInfo :: any
	local isBrainrotAfter = false
	if modelInfoAny ~= nil then
		local configId = modelInfoAny.configId :: number?
		isBrainrotAfter = configId ~= nil and GameConfig.BrainrotIdMap[configId] ~= nil
	end

	playerInfo.homeInfo.placedModels[tostring(pointIndex)] = modelInfo
	if modelInfoAny then
		if modelInfoAny.unclaimedYield == nil then
			modelInfoAny.unclaimedYield = 0
		end
		-- 新放置的展台模型：从当前时刻开始计累积时长（用于 model_collect_cash duration_sec）
		if modelInfoAny.yieldAccrueStartUnix == nil then
			local legacySec = modelInfoAny.yieldAccruedSeconds
			if typeof(legacySec) == "number" and legacySec > 0 then
				modelInfoAny.yieldAccrueStartUnix = DateTime.now().UnixTimestamp - math.floor(legacySec)
			else
				modelInfoAny.yieldAccrueStartUnix = DateTime.now().UnixTimestamp
			end
		end
	end

	if not hadBrainrotBefore and isBrainrotAfter then
		local key = GameConfig.GuideStepKey.BrainrotPlaceFinished
		if not playerInfo.guideProgressInfo.guideStepDoneMap[key] then
			playerInfo.guideProgressInfo.guideStepDoneMap[key] = true
			playerInfo.playerInfoChanged = true
			NetMsg.FireNotifyGuideProgressInfo(player, playerInfo.guideProgressInfo)
		end
	end

	playerInfo.playerInfoChanged = true

	-- 通知客户端更新 (封装在数据层)
	NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, playerInfo.homeInfo)

	--print("[ServerGameInfo] UpdatePlayerPlacedModel and notified for", player.Name, "at point", pointIndex)
end

--设置玩家家园槽位
function ServerGameInfo.SetPlayerHomeSlot(player: Player, slotName: string)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] SetPlayerHomeSlot failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.homeSlot = slotName
	playerInfo.playerInfoChanged = true

	--槽位变更也需要通知客户端家园数据
	NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, playerInfo.homeInfo)
	--print("[ServerGameInfo] SetPlayerHomeSlot for", player.Name, "to", slotName)
end

--更新玩家货币
function ServerGameInfo.UpdatePlayerCurrency(player: Player, currencyType: number, addAmount: number, reason: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local currencyKey: string = tostring(currencyType)
	local currentAmount: number = playerInfo.currencies[currencyKey] or 0
	local newAmount: number = math.max(0, currentAmount + addAmount)
	playerInfo.currencies[currencyKey] = newAmount
	playerInfo.playerInfoChanged = true

	--通知客户端
	NetMsg.FireNotifyPlayerCurrencyUpdate(player, currencyType, newAmount, addAmount, reason)
end

--更新/设置玩家家园模型未领取收益
function ServerGameInfo.UpdateModelUnclaimedYield(player: Player, pointIndex: number, amount: number, isSet: boolean?)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateModelUnclaimedYield failed: playerInfo not found for", player.Name)
		return
	end
	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if model == nil then
		return
	end

	if isSet then
		model.unclaimedYield = amount
	else
		model.unclaimedYield = (model.unclaimedYield or 0) + amount
		local modelAny = model :: any
		-- 旧存档仅有 yieldAccruedSeconds、无 yieldAccrueStartUnix 时，在首次加收益时补起点
		if modelAny.yieldAccrueStartUnix == nil then
			local legacySec = modelAny.yieldAccruedSeconds
			if typeof(legacySec) == "number" and legacySec > 0 then
				modelAny.yieldAccrueStartUnix = DateTime.now().UnixTimestamp - math.floor(legacySec)
			else
				modelAny.yieldAccrueStartUnix = DateTime.now().UnixTimestamp
			end
		end
	end
	playerInfo.playerInfoChanged = true
end

-- 广播所有玩家所有活跃模型的收益更新 (深度聚合优化版，全服单次广播)
function ServerGameInfo.BroadcastAllPlayersModelYields()
	local allYields: { [string]: { [string]: number } } = {}

	for userId, playerInfo in pairs(playerInfoMap) do
		local oldSnapshot = lastBroadcastModelYieldMap[userId] or {}
		local newSnapshot: { [string]: number } = {}
		local playerYields: { [string]: number } = {}
		local hasDelta = false
		for pointIndexStr, model in pairs(playerInfo.homeInfo.placedModels) do
			local amount = model.unclaimedYield or 0
			if amount > 0 then
				newSnapshot[pointIndexStr] = amount
				if oldSnapshot[pointIndexStr] ~= amount then
					playerYields[pointIndexStr] = amount
					hasDelta = true
				end
			end
		end

		for pointIndexStr, oldAmount in pairs(oldSnapshot) do
			if newSnapshot[pointIndexStr] == nil and oldAmount > 0 then
				playerYields[pointIndexStr] = 0
				hasDelta = true
			end
		end

		lastBroadcastModelYieldMap[userId] = newSnapshot
		if hasDelta then
			allYields[tostring(userId)] = playerYields
		end
	end

	for userId in pairs(lastBroadcastModelYieldMap) do
		if playerInfoMap[userId] == nil then
			lastBroadcastModelYieldMap[userId] = nil
		end
	end

	if next(allYields) then
		NetMsg.FireNotifyAllPlayersModelYields(allYields)
	end
end

-- 广播家园同步更新 (全量同步，用于模型变动等)
function ServerGameInfo.NotifyHomeYieldUpdate(player: Player)
	ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
end

-- 领取指定模型的收益
function ServerGameInfo.ClaimModelYield(player: Player, targetPlayerId: number, pointIndex: number)
	local targetPlayer = players:GetPlayerByUserId(targetPlayerId)
	if not targetPlayer then
		return
	end

	local targetInfo = playerInfoMap[targetPlayerId]
	if not targetInfo then
		return
	end

	local model = targetInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model or not model.unclaimedYield or model.unclaimedYield <= 0 then
		return
	end

	local modelAny = model :: any
	local nowUnix = DateTime.now().UnixTimestamp
	local startUnix: number? = modelAny.yieldAccrueStartUnix
	if startUnix == nil then
		local legacySec = modelAny.yieldAccruedSeconds
		if typeof(legacySec) == "number" and legacySec > 0 then
			startUnix = nowUnix - math.floor(legacySec)
		else
			startUnix = nowUnix
		end
	end
	local durationSec = math.max(0, math.floor(nowUnix - (startUnix :: number)))
	local amount = model.unclaimedYield
	local configId = model.configId
	local level = model.level
	model.unclaimedYield = 0
	modelAny.yieldAccrueStartUnix = nowUnix
	modelAny.yieldAccruedSeconds = nil
	targetInfo.playerInfoChanged = true

	-- 给当前触摸者（player）增加货币
	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, amount, GameConfig.ItemCountChangeReason.GainFromClaimModelYield)

	analyticsTool().LogModelCollectCash(player, configId, level, durationSec, amount)

	-- 通知双方客户端家园信息更新
	ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
	if player.UserId ~= targetPlayerId then
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(targetPlayerId)
	end

	--print("[ServerGameInfo] Player", player.Name, "claimed", amount, "yield from model at point", pointIndex, "owned by", targetPlayer.Name)
end

--升级模型
function ServerGameInfo.UpgradePlacedModel(player: Player, pointIndex: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpgradePlacedModel failed: playerInfo not found for", player.Name)
		return
	end
	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if model then
		model.level += 1
		playerInfo.playerInfoChanged = true
		NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, playerInfo.homeInfo)
		--print("[ServerGameInfo] UpgradePlacedModel for", player.Name, "at point", pointIndex, "to level", model.level)
	end
end

-- 一次性将展台模型等级提升指定层数（不扣币，供付费路径使用）
function ServerGameInfo.UpgradePlacedModelByLevelAdd(player: Player, pointIndex: number, levelAdd: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpgradePlacedModelByLevelAdd failed: playerInfo not found for", player.Name)
		return
	end

	if levelAdd <= 0 then
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn("[ServerGameInfo] UpgradePlacedModelByLevelAdd failed: no model at point", pointIndex)
		return
	end

	model.level += levelAdd
	playerInfo.playerInfoChanged = true

	NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, playerInfo.homeInfo)

	-- 记录一次最终等级的升级埋点
	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if brainrotData then
		analyticsTool().LogModelUpgrade(player, model.configId, model.level)
	end

	print(
		"[ServerGameInfo] UpgradePlacedModelByLevelAdd for",
		player.Name,
		"at point",
		pointIndex,
		"levelAdd",
		levelAdd,
		"to level",
		model.level
	)
end

-- 标记一次待处理的付费 Brainrot 升级（由 HomeManager 写入，由收据回调消费）
function ServerGameInfo.SetPendingBrainrotPaidUpgrade(player: Player, pointIndex: number, levelAdd: number)
	local userId = player.UserId
	if levelAdd <= 0 then
		levelAdd = 1
	end

	pendingBrainrotPaidUpgradeByUserId[userId] = {
		pointIndex = pointIndex,
		levelAdd = levelAdd,
		createdAt = os.clock(),
	}

	print(
		"[ServerGameInfo] SetPendingBrainrotPaidUpgrade for",
		player.Name,
		"pointIndex",
		pointIndex,
		"levelAdd",
		levelAdd
	)
end

-- 在收据回调中尝试消费付费 Brainrot 升级挂起记录
function ServerGameInfo.TryConsumeBrainrotPaidUpgrade(player: Player): boolean
	local userId = player.UserId
	local pending = pendingBrainrotPaidUpgradeByUserId[userId]
	if not pending then
		return false
	end

	-- 简单过期校验，防止极端情况下长时间挂起
	if os.clock() - pending.createdAt > 300 then
		warn("[ServerGameInfo] PendingBrainrotPaidUpgrade expired for userId", userId)
		pendingBrainrotPaidUpgradeByUserId[userId] = nil
		return false
	end

	-- 消费并清理
	pendingBrainrotPaidUpgradeByUserId[userId] = nil
	ServerGameInfo.UpgradePlacedModelByLevelAdd(player, pending.pointIndex, pending.levelAdd)
	return true
end

-- 商店与减速设置下的基准行走速度（不含线圈加成）
function ServerGameInfo.GetResolvedShopWalkSpeed(player: Player): number?
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return nil
	end
	local walkSpeedLevel = playerInfo.shopInfo.walkSpeedLevel
	local isDecelerationOn = playerInfo.settingInfo.decelerationOn == true
	local config = GameConfig.Shop.WalkSpeed
	local targetLevel = if isDecelerationOn then 1 else walkSpeedLevel
	return config.abilityList[targetLevel] or config.abilityList[config.maxLevel] or config.abilityList[1]
end

--应用行走速度比例到角色
function ServerGameInfo.ApplyWalkSpeed(player: Player)
	if ServerGameInfo.GetPlayerInfo(player) == nil then
		return
	end
	local character = player.Character
	if character then
		local CoilManager = require(serverScripts:FindFirstChild("CoilManager") :: ModuleScript)
		CoilManager.SyncHumanoidCoilLocomotion(player)
	end
end

--设置减速状态
function ServerGameInfo.UpdateDecelerationOn(player: Player, decelerationOn: boolean)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateDecelerationOn failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.settingInfo.decelerationOn = decelerationOn
	playerInfo.playerInfoChanged = true
	--print("[ServerGameInfo] UpdateDecelerationOn for", player.Name, "to", decelerationOn)
end

--更新行走速度等级
function ServerGameInfo.UpdateWalkSpeedLevel(player: Player, levelAdd: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateWalkSpeedLevel failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.shopInfo.walkSpeedLevel += levelAdd
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.WalkSpeed, playerInfo.shopInfo.walkSpeedLevel)
	--print("[ServerGameInfo] UpdateWalkSpeedLevel for", player.Name, "by", levelAdd, "total", playerInfo.shopInfo.walkSpeedLevel)
end

--更新最大砖头等级
function ServerGameInfo.UpdateMaxBricksLevel(player: Player, levelAdd: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateMaxBricksLevel failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.shopInfo.maxBricksLevel += levelAdd
	playerInfo.playerInfoChanged = true

	-- 通知客户端技能等级变更
	NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.MaxBricks, playerInfo.shopInfo.maxBricksLevel)
	-- 同时更新持久化部分 ( inventoryInfo ) -> 保持兼容性或根据需求移除，既然提到弃用则主要同步技能等级
	NetMsg.FireNotifyPlayerInventoryUpdate(player, playerInfo.inventoryInfo)

	ServerGameInfo.TryMarkBricksIntroGuideFinished(player, playerInfo.shopInfo.maxBricksLevel)
	SyncCarriedBricksAfterMaxBricksUpgrade(player)
	print("[ServerGameInfo] UpdateMaxBricksLevel for", player.Name, "by", levelAdd, "total", playerInfo.shopInfo.maxBricksLevel)
end

--统一处理属性升级
function ServerGameInfo.UpgradeAbility(player: Player, abilityName: string, levelAdd: number?): boolean
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return false
	end

	local shopData: any = GameConfig.Shop[abilityName]
	if shopData == nil then
		return false
	end

	local currentLevel: number = 0
	if abilityName == "WalkSpeed" then
		currentLevel = playerInfo.shopInfo.walkSpeedLevel
	elseif abilityName == "MaxBricks" then
		currentLevel = playerInfo.shopInfo.maxBricksLevel
	elseif abilityName == "HomeLevel" then
		currentLevel = playerInfo.homeInfo.level
	end

	local addLevels: number = levelAdd or 1
	local totalCost: number = 0
	local nextLevel: number = currentLevel

	for i = 1, addLevels do
		local upgradeCost: number? = shopData.upgradeCostList[nextLevel]
		if upgradeCost == nil then
			print("[ServerGameInfo] UpgradeAbility failed: Max level reached for", abilityName, "at", nextLevel)
			return false
		end
		totalCost += upgradeCost
		nextLevel += 1
	end

	local currencyType = GameConfig.CurrencyType.Coin
	local currencyKey = tostring(currencyType)
	local currentCurrency = playerInfo.currencies[currencyKey] or 0

	if currentCurrency < totalCost then
		print("[ServerGameInfo] UpgradeAbility failed: Not enough currency for", abilityName)
		return false
	end

	-- 扣除费用
	local reason = if abilityName == "WalkSpeed"
		then GameConfig.ItemCountChangeReason.SpendOnUpgradeWalkSpeed
		elseif abilityName == "MaxBricks" then GameConfig.ItemCountChangeReason.SpendOnUpgradeMaxBricks
		else GameConfig.ItemCountChangeReason.SpendOnUpgradeHome
	ServerGameInfo.UpdatePlayerCurrency(player, currencyType, -totalCost, reason)

	-- 更新等级
	if abilityName == "WalkSpeed" then
		playerInfo.shopInfo.walkSpeedLevel = nextLevel
		-- 应用效果
		ServerGameInfo.ApplyWalkSpeed(player)
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.WalkSpeed, nextLevel)
	elseif abilityName == "MaxBricks" then
		playerInfo.shopInfo.maxBricksLevel = nextLevel
		-- 通知客户端技能等级变更
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.MaxBricks, nextLevel)
		-- 在 Ground 上则补满背负砖，否则仅触发携带态同步
		SyncCarriedBricksAfterMaxBricksUpgrade(player)
		ServerGameInfo.TryMarkBricksIntroGuideFinished(player, nextLevel)
	elseif abilityName == "HomeLevel" then
		playerInfo.homeInfo.level = nextLevel
		-- 家园等级变更通知
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
		-- 同时通知技能等级变更，方便统一 UI 处理
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.HomeLevel, nextLevel)
	end

	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpgradeAbility for", player.Name, "ability", abilityName, "to level", nextLevel)
	if abilityName == "HomeLevel" then
		analyticsTool().LogBaseUpgrade(player, nextLevel)
	elseif abilityName == "MaxBricks" then
		local upgradeType = if addLevels >= 10 then 2 else 1
		analyticsTool().LogPlayerUpgrade(player, upgradeType, nextLevel)
	elseif abilityName == "WalkSpeed" then
		local upgradeType = if addLevels >= 10 then 4 else 3
		analyticsTool().LogPlayerUpgrade(player, upgradeType, nextLevel)
	end
	return true
end

-- 付费升级：不扣除金币，仅校验 upgradeCostList 是否还能继续升级，并尽可能升级到上限
function ServerGameInfo.UpgradeAbilityPaid(player: Player, abilityName: string, levelAdd: number?): boolean
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return false
	end

	local shopData: any = GameConfig.Shop[abilityName]
	if shopData == nil then
		return false
	end

	local currentLevel: number
	if abilityName == "WalkSpeed" then
		currentLevel = playerInfo.shopInfo.walkSpeedLevel
	elseif abilityName == "MaxBricks" then
		currentLevel = playerInfo.shopInfo.maxBricksLevel
	elseif abilityName == "HomeLevel" then
		currentLevel = playerInfo.homeInfo.level
	else
		return false
	end

	local addLevels: number = levelAdd or 1
	local nextLevel = currentLevel
	local upgradedCount = 0

	for _ = 1, addLevels do
		-- upgradeCostList[nextLevel] 存在代表：从 nextLevel 升到 nextLevel + 1 可行
		local upgradeCost = shopData.upgradeCostList[nextLevel]
		if upgradeCost == nil then
			break
		end
		nextLevel += 1
		upgradedCount += 1
	end

	if upgradedCount <= 0 then
		return false
	end

	if abilityName == "WalkSpeed" then
		playerInfo.shopInfo.walkSpeedLevel = nextLevel
		ServerGameInfo.ApplyWalkSpeed(player)
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.WalkSpeed, nextLevel)
	elseif abilityName == "MaxBricks" then
		playerInfo.shopInfo.maxBricksLevel = nextLevel
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.MaxBricks, nextLevel)
		SyncCarriedBricksAfterMaxBricksUpgrade(player)
		ServerGameInfo.TryMarkBricksIntroGuideFinished(player, nextLevel)
	elseif abilityName == "HomeLevel" then
		playerInfo.homeInfo.level = nextLevel
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.HomeLevel, nextLevel)
	end

	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpgradeAbilityPaid for", player.Name, "ability", abilityName, "to level", nextLevel)
	if abilityName == "HomeLevel" then
		analyticsTool().LogBaseUpgrade(player, nextLevel)
	elseif abilityName == "MaxBricks" then
		local upgradeType = if upgradedCount >= 10 then 2 else 1
		analyticsTool().LogPlayerUpgrade(player, upgradeType, nextLevel)
	elseif abilityName == "WalkSpeed" then
		local upgradeType = if upgradedCount >= 10 then 4 else 3
		analyticsTool().LogPlayerUpgrade(player, upgradeType, nextLevel)
	end
	return true
end

--更新家园等级
function ServerGameInfo.UpdateHomeLevel(player: Player, levelAdd: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateHomeLevel failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.homeInfo.level += levelAdd
	playerInfo.playerInfoChanged = true

	--家园等级变更通知
	ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
	print("[ServerGameInfo] UpdateHomeLevel for", player.Name, "by", levelAdd, "total", playerInfo.homeInfo.level)
end

--更新搬运中的砖头数量 (瞬态)
function ServerGameInfo.UpdateInventoryBricks(player: Player, amount: number, isSet: boolean?, suppressNotify: boolean?)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateInventoryBricks failed: playerInfo not found for", player.Name)
		return
	end

	if isSet then
		playerInfo.carriedInfo.bricks = amount
	else
		playerInfo.carriedInfo.bricks += amount
	end

	-- 同步瞬态信息到客户端
	if suppressNotify ~= true then
		NetMsg.FireNotifyPlayerCarriedUpdate(player, playerInfo.carriedInfo)
	end
end

function ServerGameInfo.GetPlayerCarriedBricks(player: Player): number
	local playerInfo: GameConfig.PlayerInfo? = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return 0
	end
	return playerInfo.carriedInfo.bricks
end

--获取玩家最大砖头数量
function ServerGameInfo.GetPlayerMaxBricks(player: Player): number
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	local config = GameConfig.Shop.MaxBricks
	if playerInfo == nil then
		return config.abilityList[config.maxLevel] or config.abilityList[1]
	end
	return config.abilityList[playerInfo.shopInfo.maxBricksLevel] or config.abilityList[config.maxLevel] or config.abilityList[1]
end

--将玩家砖头补满 (瞬态)
function ServerGameInfo.SetPlayerBricksToMax(player: Player)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return
	end
	local maxBricks = ServerGameInfo.GetPlayerMaxBricks(player)
	playerInfo.carriedInfo.bricks = maxBricks

	-- 同步瞬态层
	NetMsg.FireNotifyPlayerCarriedUpdate(player, playerInfo.carriedInfo)

	--print("[ServerGameInfo] SetPlayerBricksToMax for", player.Name, "to", maxBricks)
end

--添加模型到库存
function ServerGameInfo.AddModelToInventory(player: Player, modelInfo: GameConfig.ModelInfo)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] AddModelToInventory failed: playerInfo not found for", player.Name)
		return
	end
	table.insert(playerInfo.inventoryInfo.models, modelInfo)
	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] AddModelToInventory for", player.Name, "instanceId", modelInfo.instanceId)

	-- 同步库存变更
	NetMsg.FireNotifyPlayerInventoryUpdate(player, playerInfo.inventoryInfo)
end

--设置背景音乐音量
function ServerGameInfo.UpdateBGMVolume(player: Player, volume: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateBGMVolume failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.settingInfo.bgmVolume = volume
	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpdateBGMVolume for", player.Name, "to", volume)
end

--设置音效音量
function ServerGameInfo.UpdateSoundEffectVolume(player: Player, volume: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateSoundEffectVolume failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.settingInfo.soundEffectVolume = volume
	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpdateSoundEffectVolume for", player.Name, "to", volume)
end

--设置震动状态
function ServerGameInfo.UpdateVibrationOn(player: Player, vibrationOn: boolean)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		warn("[ServerGameInfo] UpdateVibrationOn failed: playerInfo not found for", player.Name)
		return
	end
	playerInfo.settingInfo.vibrationOn = vibrationOn
	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpdateVibrationOn for", player.Name, "to", vibrationOn)
end

function ServerGameInfo.GetIslandIdAtPosition(worldPosition: Vector3): number
	local islandsFolder = workspace:FindFirstChild("Islands")
	if not islandsFolder then
		return 0
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { islandsFolder }
	local origin = worldPosition + Vector3.new(0, 12, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
	if not result then
		return 0
	end
	local inst = result.Instance
	local island: Instance? = inst
	while island and island.Parent ~= islandsFolder and island.Parent ~= game do
		island = island.Parent
	end
	if not island or island.Parent ~= islandsFolder then
		return 0
	end
	local id = tonumber(string.match(island.Name, "^Island(%d+)$"))
	return if id then id else 0
end

function ServerGameInfo.TryMarkIslandDiscovered(player: Player, islandId: number)
	if islandId <= 0 then
		return
	end
	local playerInfo = playerInfoMap[player.UserId]
	if not playerInfo then
		return
	end
	local discoveredMap: { [string]: boolean } = playerInfo.discoveredIslandIds or {}
	playerInfo.discoveredIslandIds = discoveredMap
	local key = tostring(islandId)
	if discoveredMap[key] then
		return
	end
	discoveredMap[key] = true
	playerInfo.playerInfoChanged = true
	analyticsTool().LogIslandDiscover(player, islandId)
end

return ServerGameInfo
