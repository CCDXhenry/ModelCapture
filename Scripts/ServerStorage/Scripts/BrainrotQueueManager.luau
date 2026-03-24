--!strict
local BrainrotQueueManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local MaxCapacity = GameConfig.BrainrotQueue.MaxCapacity
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))

local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local actualChests = replicatedStorage:WaitForChild("Models"):WaitForChild("LittleElfChests")
local actualCoils = replicatedStorage:WaitForChild("Tools")

-- 提示冷却逻辑
local FullTipCooldown: number = 5
local playerLastFullTipTime: { [Player]: number } = {}

-- 生成 Tool 并放入玩家 Backpack
local function CreateToolForItem(player: Player, item: GameConfig.BrainrotQueueItem): Tool?
	local itemType = item.itemType or GameConfig.ItemType.Brainrot
	local config: any
	if itemType == GameConfig.ItemType.Brainrot then
		config = GameConfig.BrainrotIdMap[item.configId]
	elseif itemType == GameConfig.ItemType.Coil then
		config = GameConfig.CoilIdMap[item.configId]
	elseif itemType == GameConfig.ItemType.LittleElfChest then
		config = GameConfig.LittleElfChestIdMap[item.configId]
	end

	if not config then
		warn("[BrainrotQueueManager] CreateToolForItem: no config for itemType", itemType, "configId", item.configId)
		return nil
	end

	local tool
	if itemType == GameConfig.ItemType.Brainrot then
		tool = Instance.new("Tool")
		tool.Name = config.name_t or ("Brainrot_" .. item.configId)
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		tool:SetAttribute("ItemType", itemType)
		tool:SetAttribute("BrainrotUID", item.uid)
		tool:SetAttribute("ConfigId", item.configId)
		tool:SetAttribute("Quality", item.quality)
		tool:SetAttribute("Level", item.level)

		-- 创建 Handle
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Anchored = false
		handle.CanCollide = false
		handle.Transparency = 1
		handle.Massless = true
		handle.Parent = tool

		-- Clone 视觉模型到 Tool
		local sourceModel = actualModels:FindFirstChild(config.resourceName)
		if sourceModel and sourceModel:IsA("Model") then
			local visualModel = sourceModel:Clone()
			visualModel.Name = "VisualModel"
			local rootPart = visualModel.PrimaryPart or visualModel:FindFirstChild("RootPart") or visualModel:FindFirstChildWhichIsA("BasePart")
			if rootPart and rootPart:IsA("BasePart") then
				local targetRoot = rootPart :: BasePart
				for _, part in ipairs(visualModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = false
						part.Anchored = false
						part.Massless = true
						part.CanQuery = false
						part.CanTouch = false
					end
				end
				visualModel:PivotTo(handle.CFrame)
				visualModel.Parent = tool

				local motor = Instance.new("Motor6D")
				motor.Name = "VisualMotor"
				motor.Part0 = handle
				motor.Part1 = targetRoot
				motor.C0 = CFrame.new()
				motor.C1 = targetRoot.CFrame:ToObjectSpace(handle.CFrame)
				motor.Parent = handle
			else
				visualModel.Parent = tool
			end
		end
	elseif itemType == GameConfig.ItemType.Coil then
		local sourceModel = actualCoils:FindFirstChild(config.modelRes)
		if sourceModel and sourceModel:IsA("Tool") then
			tool = sourceModel:Clone()
			tool.CanBeDropped = false
			tool:SetAttribute("ItemType", itemType)
			tool:SetAttribute("BrainrotUID", item.uid)
			tool:SetAttribute("ConfigId", item.configId)
			tool:SetAttribute("Quality", item.quality)
			tool:SetAttribute("Level", item.level)
		else
			warn("[BrainrotQueueManager] Coil Tool not found in ReplicatedStorage.Tools:", config.modelRes)
			return nil
		end
	elseif itemType == GameConfig.ItemType.LittleElfChest then
		local sourceModel = actualChests:FindFirstChild(config.resourceName)
		if sourceModel and sourceModel:IsA("Model") then
			tool = Instance.new("Tool")
			tool.Name = config.name_t or ("Chest_" .. item.configId)
			tool.RequiresHandle = true
			tool.CanBeDropped = false
			tool:SetAttribute("ItemType", itemType)
			tool:SetAttribute("BrainrotUID", item.uid)
			tool:SetAttribute("ConfigId", item.configId)
			tool:SetAttribute("Quality", item.quality)
			tool:SetAttribute("Level", item.level)

			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Anchored = false
			handle.CanCollide = false
			handle.Transparency = 1
			handle.Massless = true
			handle.Parent = tool

			local visualModel = sourceModel:Clone()
			visualModel.Name = "VisualModel"
			local root = visualModel.PrimaryPart or visualModel:FindFirstChild("RootPart") or visualModel:FindFirstChildWhichIsA("BasePart")
			if root and root:IsA("BasePart") then
				for _, part in ipairs(visualModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = false
						part.Anchored = false
						part.Massless = true
						part.CanQuery = false
						part.CanTouch = false
					end
				end
				visualModel:PivotTo(handle.CFrame)
				visualModel.Parent = tool

				local motor = Instance.new("Motor6D")
				motor.Name = "VisualMotor"
				motor.Part0 = handle
				motor.Part1 = root
				motor.Parent = handle
			else
				visualModel.Parent = tool
			end
		else
			warn("[BrainrotQueueManager] Chest Model not found in LittleElfChests:", config.resourceName)
			return nil
		end
	end

	if tool then
		tool.Parent = player.Backpack
		print("[BrainrotQueueManager] Created Tool for uid:", item.uid, "name:", tool.Name)
	end
	return tool
end

-- 生成唯一 UID
local function GenerateUID(): string
	return "bq_" .. tostring(math.floor(os.clock() * 100000)) .. "_" .. tostring(math.random(10000, 99999))
end

-- 通知客户端队列变化
local function NotifyQueueUpdate(player: Player, queue: { GameConfig.BrainrotQueueItem })
	NetMsg.FireNotifyBrainrotQueueUpdate(player, queue)
end

-- 向玩家背包队列添加一个 Brainrot/Coil
function BrainrotQueueManager.AddItem(player: Player, configId: number, quality: number, level: number, equipImmediately: boolean?, itemType: number?): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[BrainrotQueueManager] AddItem failed: playerInfo not found for", player.Name)
		return false
	end

	if #playerInfo.brainrotQueue >= MaxCapacity then
		-- 提示玩家背包已满 (增加 5 秒间隔限制)
		local now = os.clock()
		local lastTip = playerLastFullTipTime[player] or 0
		if now - lastTip >= FullTipCooldown then
			playerLastFullTipTime[player] = now
			NetMsg.FireNotifyShowGameTip(player, GameTexts.BackpackFull.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.BackpackFull.key)
		end
		return false
	end

	local item: GameConfig.BrainrotQueueItem = {
		uid = GenerateUID(),
		itemType = itemType or GameConfig.ItemType.Brainrot,
		configId = configId,
		quality = quality,
		level = level,
	}

	table.insert(playerInfo.brainrotQueue, item)
	playerInfo.playerInfoChanged = true

	-- 创建对应的 Tool 并放入玩家 Backpack
	task.defer(function()
		local tool = CreateToolForItem(player, item)
		if equipImmediately and tool then
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:EquipTool(tool)
			end
		end
	end)

	print("[BrainrotQueueManager] AddItem for", player.Name, "configId:", configId, "uid:", item.uid, "total:", #playerInfo.brainrotQueue)
	NotifyQueueUpdate(player, playerInfo.brainrotQueue)
	return true
end

-- 从玩家背包队列移除指定 uid 的 Brainrot
function BrainrotQueueManager.RemoveItem(player: Player, uid: string): boolean
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[BrainrotQueueManager] RemoveItem failed: playerInfo not found for", player.Name)
		return false
	end

	local removedIndex: number? = nil
	for i, item in ipairs(playerInfo.brainrotQueue) do
		if item.uid == uid then
			removedIndex = i
			break
		end
	end

	if removedIndex then
		table.remove(playerInfo.brainrotQueue, removedIndex)
		playerInfo.playerInfoChanged = true
		print("[BrainrotQueueManager] RemoveItem for", player.Name, "uid:", uid, "remaining:", #playerInfo.brainrotQueue)
		NotifyQueueUpdate(player, playerInfo.brainrotQueue)
		return true
	else
		warn("[BrainrotQueueManager] RemoveItem failed: uid not found", uid, "for", player.Name)
		return false
	end
end

-- 移除队列中指定索引的 Brainrot（按数字键消耗时使用）
function BrainrotQueueManager.RemoveItemByIndex(player: Player, index: number): GameConfig.BrainrotQueueItem?
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		warn("[BrainrotQueueManager] RemoveItemByIndex failed: playerInfo not found for", player.Name)
		return nil
	end

	local item = playerInfo.brainrotQueue[index]
	if not item then
		warn("[BrainrotQueueManager] RemoveItemByIndex failed: no item at index", index, "for", player.Name)
		return nil
	end

	table.remove(playerInfo.brainrotQueue, index)
	playerInfo.playerInfoChanged = true
	print("[BrainrotQueueManager] RemoveItemByIndex for", player.Name, "index:", index, "remaining:", #playerInfo.brainrotQueue)
	NotifyQueueUpdate(player, playerInfo.brainrotQueue)
	return item
end

-- 获取玩家当前背包队列（只读引用）
function BrainrotQueueManager.GetQueue(player: Player): { GameConfig.BrainrotQueueItem }?
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return nil
	end
	return playerInfo.brainrotQueue
end

-- 玩家上线时，根据存档数据恢复所有 Tool
function BrainrotQueueManager.LoadPlayerQueue(player: Player)
	local queue = BrainrotQueueManager.GetQueue(player)
	if queue then
		for _, item in ipairs(queue) do
			CreateToolForItem(player, item)
		end
	end
end

-- 玩家开启宝箱
function BrainrotQueueManager.OpenChest(player: Player, uid: string)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then return end

	-- 1. 验证宝箱是否存在
	local chestItem: GameConfig.BrainrotQueueItem? = nil
	local itemIndex: number? = nil
	for i, item in ipairs(playerInfo.brainrotQueue) do
		if item.uid == uid and item.itemType == GameConfig.ItemType.LittleElfChest then
			chestItem = item
			itemIndex = i
			break
		end
	end

	if not chestItem or not itemIndex then
		warn("[BrainrotQueueManager] OpenChest failed: chest uid not found", uid)
		return
	end

	local chestConfig = GameConfig.LittleElfChestIdMap[chestItem.configId]
	if not chestConfig then return end

	-- 2. 随机获得掉落
	local rewardPool = chestConfig.rewardPool
	if not rewardPool or #rewardPool == 0 then
		warn("[BrainrotQueueManager] OpenChest error: rewardPool is empty for chest", chestItem.configId)
		return
	end

	local randomBrainrotId = rewardPool[math.random(1, #rewardPool)]
	local brainrotConfig = GameConfig.BrainrotIdMap[randomBrainrotId]
	if not brainrotConfig then
		warn("[BrainrotQueueManager] OpenChest error: random brainrot config not found", randomBrainrotId)
		return
	end

	-- 3. 移除宝箱，添加新宠物
	-- 先移除 Tool
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("BrainrotUID") == uid then
				child:Destroy()
			end
		end
	end
	for _, child in ipairs(player.Backpack:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") == uid then
			child:Destroy()
		end
	end

	-- 更新数据
	table.remove(playerInfo.brainrotQueue, itemIndex)
	playerInfo.playerInfoChanged = true

	-- 添加新宠物
	BrainrotQueueManager.AddItem(player, brainrotConfig.id, brainrotConfig.quality, 1, true, GameConfig.ItemType.Brainrot)

	-- 提示
	NetMsg.FireNotifyShowGameTip(player, GameTexts.ReceivedReward.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.ReceivedReward.key, {brainrotConfig.name_t})
end

-- 模块初始化 (服务端监听)
task.defer(function()
	NetMsg.ConnectRequestOpenChest(BrainrotQueueManager.OpenChest)
end)

return BrainrotQueueManager
