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

local playerInfoMap: { [number]: GameConfig.PlayerInfo } = {}

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
		homeSlot = "",

		-- 初始化瞬态数据
		carriedInfo = {
			bricks = 0,
		},
	}
	for ownedGamePassIndex: number, ownedGamePassId: number in playerInfo.ownedGamePassList do
		playerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	playerInfoMap[player.UserId] = playerInfo
	ServerMsg.FirePlayerInfoInit(player)

	local clientLocalPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo = {
		settingInfo = playerInfo.settingInfo,
		ownedGamePassList = playerInfo.ownedGamePassList,
		currencies = playerInfo.currencies,
		inventoryInfo = playerInfo.inventoryInfo,
		homeInfo = playerInfo.homeInfo,
		shopInfo = playerInfo.shopInfo,
		brainrotsInfo = playerInfo.brainrotsInfo,
		brainrotQueue = playerInfo.brainrotQueue,
		homeSlot = playerInfo.homeSlot,
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

	-- 应用行走速度
	ServerGameInfo.ApplyWalkSpeed(player)

	ServerMsg.FireLoadBackpackTools(player)

	player.CharacterAdded:Connect(function(character)
		task.wait(0.2)
		ServerMsg.FireLoadBackpackTools(player)
	end)

	print("[ServerGameInfo] InitPlayerInfo complete for", player.Name)
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
	print("[ServerGameInfo] RemovePlayerInfo for", player.Name)
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
		settingInfo = playerInfo.settingInfo,
		currencies = playerInfo.currencies,
		inventoryInfo = playerInfo.inventoryInfo,
		homeInfo = playerInfo.homeInfo,
		shopInfo = playerInfo.shopInfo,
		brainrotsInfo = playerInfo.brainrotsInfo,
		brainrotQueue = playerInfo.brainrotQueue,
	}
end

--获取玩家重生倍率
function ServerGameInfo.GetRebirthMultiplier(player: Player): number
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return 1
	end
	local rebirthLevel = playerInfo.shopInfo.rebirthLevel or 1
	if rebirthLevel <= 1 then
		return 1
	end
	local config = GameConfig.RebirthMap[rebirthLevel - 1]
	return if config then config.collectMultiple else 1
end

--执行重生
function ServerGameInfo.ExecuteRebirth(player: Player, isPaid: boolean): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return false
	end

	local currentRebirthLevel = playerInfo.shopInfo.rebirthLevel or 1
	local nextRebirthConfig = GameConfig.RebirthMap[currentRebirthLevel]
	if not nextRebirthConfig then
		print("[ServerGameInfo] ExecuteRebirth failed: max rebirth level reached for", player.Name)
		return false
	end

	-- 检查要求
	local requiredSpeedLv = nextRebirthConfig.speedLv
	local requiredBrickLv = nextRebirthConfig.brickLv

	if playerInfo.shopInfo.walkSpeedLevel < requiredSpeedLv or playerInfo.shopInfo.maxBricksLevel < requiredBrickLv then
		print("[ServerGameInfo] ExecuteRebirth failed: requirements not met for", player.Name)
		return false
	end

	if not isPaid then
		-- 免费重生：重置等级
		playerInfo.shopInfo.walkSpeedLevel = 1
		playerInfo.shopInfo.maxBricksLevel = 1
		ServerGameInfo.ApplyWalkSpeed(player)
		-- 同步重置后的等级
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.WalkSpeed, 1)
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.MaxBricks, 1)
		-- 还要同步搬运信息（可能因为容量变了需要同步）
		ServerGameInfo.UpdateInventoryBricks(player, 0)
	end

	-- 增加重生等级
	playerInfo.shopInfo.rebirthLevel = currentRebirthLevel + 1
	playerInfo.playerInfoChanged = true

	-- 通知客户端重生等级变更
	NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.RebirthLevel, playerInfo.shopInfo.rebirthLevel)

	print("[ServerGameInfo] ExecuteRebirth success for", player.Name, "New Level:", playerInfo.shopInfo.rebirthLevel, "isPaid:", isPaid)
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
	print("[ServerGameInfo] ChangePlayerLoginDays for", player.Name, "to", loginDays)
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
	print("[ServerGameInfo] SetPlayerGamePassAcquired for", player.Name, "id", gamePassId)
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
	playerInfo.homeInfo.placedModels[tostring(pointIndex)] = modelInfo
	if modelInfo and modelInfo.unclaimedYield == nil then
		modelInfo.unclaimedYield = 0
	end
	playerInfo.playerInfoChanged = true

	-- 通知客户端更新 (封装在数据层)
	NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, playerInfo.homeInfo)

	print("[ServerGameInfo] UpdatePlayerPlacedModel and notified for", player.Name, "at point", pointIndex)
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
	print("[ServerGameInfo] SetPlayerHomeSlot for", player.Name, "to", slotName)
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
	end
	playerInfo.playerInfoChanged = true
end

-- 广播所有玩家所有活跃模型的收益更新 (深度聚合优化版，全服单次广播)
function ServerGameInfo.BroadcastAllPlayersModelYields()
	local allYields: { [string]: { [string]: number } } = {}

	for userId, playerInfo in pairs(playerInfoMap) do
		local playerYields: { [string]: number } = {}
		local hasYield = false
		for pointIndexStr, model in pairs(playerInfo.homeInfo.placedModels) do
			if model.unclaimedYield and model.unclaimedYield > 0 then
				playerYields[pointIndexStr] = model.unclaimedYield
				hasYield = true
			end
		end

		if hasYield then
			allYields[tostring(userId)] = playerYields
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

	local amount = model.unclaimedYield
	model.unclaimedYield = 0
	targetInfo.playerInfoChanged = true

	-- 给当前触摸者（player）增加货币
	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, amount, GameConfig.ItemCountChangeReason.GainFromClaimModelYield)

	-- 通知双方客户端家园信息更新
	ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
	if player.UserId ~= targetPlayerId then
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(targetPlayerId)
	end

	print("[ServerGameInfo] Player", player.Name, "claimed", amount, "yield from model at point", pointIndex, "owned by", targetPlayer.Name)
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
		print("[ServerGameInfo] UpgradePlacedModel for", player.Name, "at point", pointIndex, "to level", model.level)
	end
end

--应用行走速度比例到角色
function ServerGameInfo.ApplyWalkSpeed(player: Player)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local walkSpeedLevel = playerInfo.shopInfo.walkSpeedLevel
	local config = GameConfig.Shop.WalkSpeed
	local targetSpeed = config.abilityList[walkSpeedLevel] or config.abilityList[1]

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = targetSpeed
		end
	end
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
	print("[ServerGameInfo] UpdateWalkSpeedLevel for", player.Name, "by", levelAdd, "total", playerInfo.shopInfo.walkSpeedLevel)
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
		-- 通知客户端库存变更
		ServerGameInfo.UpdateInventoryBricks(player, 0) -- 虽然是0，但能触发一次状态同步
	elseif abilityName == "HomeLevel" then
		playerInfo.homeInfo.level = nextLevel
		-- 家园等级变更通知
		ServerGameInfo.NotifyPlayerHomeInfoUpdate(player.UserId)
		-- 同时通知技能等级变更，方便统一 UI 处理
		NetMsg.FireNotifyPlayerSkillLevelUpdate(player, GameConfig.SkillType.HomeLevel, nextLevel)
	end

	playerInfo.playerInfoChanged = true
	print("[ServerGameInfo] UpgradeAbility for", player.Name, "ability", abilityName, "to level", nextLevel)
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
function ServerGameInfo.UpdateInventoryBricks(player: Player, amount: number, isSet: boolean?)
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
	NetMsg.FireNotifyPlayerCarriedUpdate(player, playerInfo.carriedInfo)
end

--获取玩家最大砖头数量
function ServerGameInfo.GetPlayerMaxBricks(player: Player): number
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	local config = GameConfig.Shop.MaxBricks
	if playerInfo == nil then
		return config.abilityList[1]
	end
	return config.abilityList[playerInfo.shopInfo.maxBricksLevel] or config.abilityList[1]
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

	print("[ServerGameInfo] SetPlayerBricksToMax for", player.Name, "to", maxBricks)
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

return ServerGameInfo
