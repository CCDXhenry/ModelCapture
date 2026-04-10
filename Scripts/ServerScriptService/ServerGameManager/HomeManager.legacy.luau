--!strict
local serverStorage = game:GetService("ServerStorage")
local HomeManager = {}
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local HomeManagerModule = require(serverScripts:FindFirstChild("HomeManager"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local runService = game:GetService("RunService")
local players = game:GetService("Players")

local homesFolder = workspace:FindFirstChild("PlayersHome") or Instance.new("Folder")
homesFolder.Name = "PlayersHome"
if homesFolder.Parent ~= workspace then
	homesFolder.Parent = workspace
end

local availableSlots = {}
local yieldUpdateAccumulator = 0
local yieldBroadcastAccumulator = 0
local islandDiscoverAccumulator = 0
local basePlotsCount = 0

local YIELD_UPDATE_INTERVAL = 1
local YIELD_BROADCAST_INTERVAL = 1

-- Initialize available slots from PlayersHome
local function InitSlots()
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			table.insert(availableSlots, child.Name)

			if basePlotsCount == 0 then
				local lv1 = child:FindFirstChild("Lv1")
				if lv1 then
					local count = 0
					for _, sub in ipairs(lv1:GetChildren()) do
						if sub.Name:match("^PlaceModel%d+$") then
							count += 1
						end
					end
					basePlotsCount = count
				end
			end
		end
	end
	table.sort(availableSlots)
	print("[HomeManager] Initialized with", #availableSlots, "slots. Base plots per floor:", basePlotsCount)
end

-- local function BroadcastHomeUpdate(player: Player) ... removed as logic is now in ServerGameInfo

local function SetupPlayerRespawn(player: Player, slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if slotModel then
		local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
		if teleportPoint then
			local spawnLocation: SpawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation
			player.RespawnLocation = spawnLocation
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					task.defer(function()
						hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
					end)
				end
			end
		end
	end

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if hrp and slotModel then
			local teleportPoint = slotModel:FindFirstChild("TeleportPoint")
			if teleportPoint then
				local spawnLocation: SpawnLocation = teleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation
				task.defer(function()
					hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
				end)
			end
		end
	end)

	-- 动态结构同步 & 初始绑定 (表现层已移至客户端)
	-- 服务器不再处理物理部件的生成或触摸绑定
end

local function OnPlayerAdded(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		--warn("[HomeManager] OnPlayerAdded failed: playerInfo not found for", player.Name, "- deferring until it exists.")
		task.spawn(function()
			while not playerInfo and player.Parent do
				task.wait(0.5)
				playerInfo = ServerGameInfo.GetPlayerInfo(player)
			end
			if playerInfo then
				OnPlayerAdded(player)
			end
		end)
		return
	end

	if #availableSlots == 0 then
		player:Kick("Server is full, no home slots available.")
		return
	end

	local slotName = availableSlots[1]
	table.remove(availableSlots, 1)

	-- 使用封装的方法设置槽位，会自动通知客户端
	ServerGameInfo.SetPlayerHomeSlot(player, slotName)

	SetupPlayerRespawn(player, slotName)
	print("[HomeManager] Assigned slot", slotName, "to", player.Name)
end

local function OnRequestPlaceHomeModel(player: Player, instanceId: string, pointIndex: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[HomeManager] OnRequestPlaceHomeModel failed: playerInfo not found for", player.Name)
		return
	end

	local maxPoints = playerInfo.homeInfo.level * (if basePlotsCount > 0 then basePlotsCount else 6)
	if pointIndex < 1 or pointIndex > maxPoints then
		warn("[HomeManager] OnRequestPlaceHomeModel failed: invalid pointIndex", pointIndex, "maxPoints for level", playerInfo.homeInfo.level, "is", maxPoints)
		return
	end
	if playerInfo.homeInfo.placedModels[tostring(pointIndex)] ~= nil then
		warn("[HomeManager] OnRequestPlaceHomeModel failed: pointIndex occupied", pointIndex)
		return
	end

	local modelIndex: number? = nil
	local targetModel: GameConfig.ModelInfo? = nil
	for i, model in ipairs(playerInfo.inventoryInfo.models) do
		if model.instanceId == instanceId then
			targetModel = model
			modelIndex = i
			break
		end
	end

	if targetModel and modelIndex then
		if not GameConfig.BrainrotIdMap[targetModel.configId] then
			warn(
				"[HomeManager] OnRequestPlaceHomeModel rejected: configId is not Brainrot for",
				player.Name,
				"configId",
				targetModel.configId
			)
			return
		end

		table.remove(playerInfo.inventoryInfo.models, modelIndex)

		-- 使用封装的方法更新放置模型，会自动通知客户端
		ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, targetModel)

		AnalyticsTool.LogModelPlace(player, targetModel.configId, targetModel.level)

		print("[HomeManager] Player", player.Name, "placed model", instanceId, "at point", pointIndex)
	else
		warn("[HomeManager] OnRequestPlaceHomeModel failed: targetModel not in inventory", instanceId)
	end
end

local function OnRequestUpgradeModel(player: Player, pointIndex: number, levelAdd: number?, isPaidIntent: boolean?)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[HomeManager] OnRequestUpgradeModel failed: playerInfo not found for", player.Name)
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn("[HomeManager] OnRequestUpgradeModel failed: no model at point", pointIndex)
		return
	end
	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		warn("[HomeManager] OnRequestUpgradeModel failed: brainrotData not found for configId", model.configId)
		return
	end

	local cost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, model.level)
	local currentGold = playerInfo.currencies["1"] or 0

	-- 付费意图：记录 pending，由收据回调处理真正升级
	if isPaidIntent == true then
		if currentGold >= cost then
			-- 理论上客户端应只在金币不足时走付费逻辑，这里做一层保护：金币足够则直接按普通升级处理
		else
			ServerGameInfo.SetPendingBrainrotPaidUpgrade(player, pointIndex, levelAdd or 3)
			print("[HomeManager] Recorded pending paid brainrot upgrade for", player.Name, "at point", pointIndex, "levelAdd", levelAdd or 3)
			return
		end
	end

	if currentGold >= cost then
		local configIdBefore = model.configId
		-- 统一管理金币消耗
		ServerGameInfo.UpdatePlayerCurrency(
			player,
			GameConfig.CurrencyType.Coin,
			-cost,
			GameConfig.ItemCountChangeReason.SpendOnUpgradeBrainrot
		)

		-- 统一管理模型升级，会自动通知客户端
		ServerGameInfo.UpgradePlacedModel(player, pointIndex)

		local modelAfter = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
		if modelAfter then
			AnalyticsTool.LogModelUpgrade(player, configIdBefore, modelAfter.level)
		end

		print("[HomeManager] Player", player.Name, "upgraded model at point", pointIndex, "to level", model.level)
	else
		warn("[HomeManager] OnRequestUpgradeModel failed: insufficient currency for", player.Name)
	end
end

local function OnRequestSellModel(player: Player, pointIndex: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[HomeManager] OnRequestSellModel failed: playerInfo not found for", player.Name)
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn("[HomeManager] OnRequestSellModel failed: no model at point", pointIndex)
		return
	end

	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		warn("[HomeManager] OnRequestSellModel failed: brainrotData not found for configId", model.configId)
		return
	end

	local returnVal = GameConfig.GetBrainrotSellPrice(brainrotData.baseAbility, model.level)
	local sellConfigId = model.configId
	local sellLevel = model.level

	-- 增加金币
	ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, returnVal, GameConfig.ItemCountChangeReason.GainFromSellModel)

	-- 移除模型 (设置为 nil)
	ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, nil :: any)

	AnalyticsTool.LogModelSell(player, 1, returnVal, { sellConfigId }, { sellLevel })

	print("[HomeManager] Player", player.Name, "sold model at point", pointIndex, "for", returnVal)
end

function HomeManager.RestoreHomeModel(player: Player, brainrot: Instance)
	local fromHomeSlot = brainrot:GetAttribute("FromHomeSlot")
	local fromPointIndex = brainrot:GetAttribute("FromPointIndex") :: number
	local originalDataJson = brainrot:GetAttribute("OriginalData")

	if not fromHomeSlot or not fromPointIndex or not originalDataJson then
		brainrot:Destroy()
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo or playerInfo.homeSlot ~= fromHomeSlot then
		brainrot:Destroy()
		return
	end

	local HttpService = game:GetService("HttpService")
	local ok, originalData = pcall(function()
		return HttpService:JSONDecode(originalDataJson)
	end)

	if ok and originalData then
		-- 恢复到展台
		ServerGameInfo.UpdatePlayerPlacedModel(player, fromPointIndex, originalData)
		print("[HomeManager] Restored brainrot to slot", fromHomeSlot, "point", fromPointIndex)
	end

	brainrot:Destroy()
end

local function OnRequestPickupHomeModel(player: Player, pointIndex: number)
	HomeManagerModule.OnRequestPickupHomeModel(player, pointIndex)
end

local function OnRequestClaimYield(player: Player, targetPlayerId: number, pointIndex: number)
	-- 现在通过远程请求进行验证并领取
	ServerGameInfo.ClaimModelYield(player, targetPlayerId, pointIndex)
end

local function OnHeartbeat(dt: number)
	yieldUpdateAccumulator += dt
	yieldBroadcastAccumulator += dt
	islandDiscoverAccumulator += dt

	-- 表现层全在客户端，不再需要在 Heartbeat 中同步结构
	if yieldUpdateAccumulator >= YIELD_UPDATE_INTERVAL then
		yieldUpdateAccumulator -= YIELD_UPDATE_INTERVAL
		for _, player in ipairs(players:GetPlayers()) do
			local playerInfo = ServerGameInfo.GetPlayerInfo(player)
			if playerInfo then
				for pointIndexStr, model in pairs(playerInfo.homeInfo.placedModels) do
					local brainrotData = GameConfig.BrainrotIdMap[model.configId]
					if brainrotData then
						local baseYield = GameConfig.GetBrainrotAbility(brainrotData.baseAbility, model.level)
						local multiplier = ServerGameInfo.GetRebirthMultiplier(player)
						local yield = math.ceil(baseYield * multiplier)
						if yield > 0 then
							local pointIndex = tonumber(pointIndexStr)
							if pointIndex then
								ServerGameInfo.UpdateModelUnclaimedYield(player, pointIndex, yield)
							end
						end
					end
				end
			end
		end
	end

	if yieldBroadcastAccumulator >= YIELD_BROADCAST_INTERVAL then
		yieldBroadcastAccumulator -= YIELD_BROADCAST_INTERVAL
		ServerGameInfo.BroadcastAllPlayersModelYields()
	end

	if islandDiscoverAccumulator >= 3 then
		islandDiscoverAccumulator -= 3
		for _, plr in ipairs(players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local islandId = ServerGameInfo.GetIslandIdAtPosition(hrp.Position)
				if islandId > 0 then
					local pinfo = ServerGameInfo.GetPlayerInfo(plr)
					if pinfo and pinfo.lastArrivedIslandId ~= islandId then
						pinfo.lastArrivedIslandId = islandId
						plr:SetAttribute("LastArrivedIslandId", islandId)
					end
				end
				ServerGameInfo.TryMarkIslandDiscovered(plr, islandId)
			end
		end
	end
end

local function OnPlayerRemoving(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo and playerInfo.homeSlot and playerInfo.homeSlot ~= "" then
		-- Return slot
		table.insert(availableSlots, playerInfo.homeSlot)
		table.sort(availableSlots)
		print("[HomeManager] Player", player.Name, "left. Returned slot", playerInfo.homeSlot)

		-- Clear their home info visually on clients by broadcasting an empty home
		NetMsg.FireNotifyPlayerHomeInfoUpdate(player.UserId, playerInfo.homeSlot, {
			level = 1,
			placedModels = {},
			unclaimedYield = 0,
		})
	end
end

InitSlots()

players.PlayerAdded:Connect(OnPlayerAdded)
players.PlayerRemoving:Connect(OnPlayerRemoving)
runService.Heartbeat:Connect(OnHeartbeat)

NetMsg.ConnectRequestPlaceHomeModel(OnRequestPlaceHomeModel)
NetMsg.ConnectRequestUpgradeModel(OnRequestUpgradeModel)
NetMsg.ConnectRequestSellModel(OnRequestSellModel)
NetMsg.ConnectRequestClaimYield(OnRequestClaimYield)
NetMsg.ConnectRequestPickupHomeModel(OnRequestPickupHomeModel)

-- 重生请求处理
NetMsg.ConnectRequestRebirth(function(player: Player)
	ServerGameInfo.ExecuteRebirth(player, false)
end)

NetMsg.ConnectRequestPaidRebirth(function(player: Player)
	-- 获取重生等级并检查要求 (虽然 Purchase 也会检查，但这里可以先做一次检查)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then return end
	
	local currentRebirthLevel = playerInfo.shopInfo.rebirthLevel or 0
	local nextRebirthCount = currentRebirthLevel + 1
	local nextRebirthConfig = GameConfig.RebirthMap[nextRebirthCount]
	if not nextRebirthConfig then return end
	
	if playerInfo.shopInfo.walkSpeedLevel >= nextRebirthConfig.speedLv and playerInfo.shopInfo.maxBricksLevel >= nextRebirthConfig.brickLv then
		-- 弹出付费提示
		game:GetService("MarketplaceService"):PromptProductPurchase(player, GameConfig.Paving.RebirthProductId)
	end
end)

return HomeManager
