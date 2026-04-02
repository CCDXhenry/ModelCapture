--!strict
local _players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))

local islandsFolder = workspace:WaitForChild("Islands")
local homesFolder = workspace:WaitForChild("PlayersHome")

local _actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local _actualChests = replicatedStorage:WaitForChild("Models"):WaitForChild("LittleElfChests")
local BrainrotCarryingManager = require(serverScripts:FindFirstChild("BrainrotCarryingManager"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))

local BrainrotIslandManager = {}
local rng = Random.new()
local SpawnFacingRandomOffsetMaxDeg = 360

-- =========================================================
-- Brainrot 独立倒计时（按 BrainrotUID 管理）
-- 倒计时结束：该 uid 对应的 brainrot 实体销毁，并在其所属岛屿补刷一个新 IslandBrainrot
-- =========================================================
local BrainrotRefreshCountdownSeconds = GameConfig.BrainrotRefreshCountdownSeconds or 23
local BrainrotTimerTickSeconds = 1 -- 每秒递减一次
local brainrotTimerStates: { [string]: {
	remainingSeconds: number,
	paused: boolean,
	homeIslandName: string,
	currentInstance: BasePart?,
} } = {}

local TerminateAndRespawnBrainrot: (uid: string) -> () = function(_uid: string)
	-- no-op: 会在模块执行到后面被覆盖
end

function BrainrotIslandManager.PauseBrainrotTimer(uid: string, instance: Instance?)
	if not uid then
		return
	end

	local targetPart: BasePart? = if instance and instance:IsA("BasePart") then instance :: BasePart else nil
	local state = brainrotTimerStates[uid]

	if not state then
		local remaining = if targetPart then (tonumber(targetPart:GetAttribute("BrainrotTimerRemainingSeconds")) or BrainrotRefreshCountdownSeconds) else BrainrotRefreshCountdownSeconds
		local homeIslandName = if targetPart then ((targetPart:GetAttribute("HomeIslandName") :: string?) or "") else ""

		state = {
			remainingSeconds = remaining,
			paused = true,
			homeIslandName = homeIslandName,
			currentInstance = targetPart,
		}
		brainrotTimerStates[uid] = state
	end

	state.paused = true
	if targetPart then
		state.currentInstance = targetPart
	end

	local target = state.currentInstance
	if target and target.Parent then
		target:SetAttribute("BrainrotTimerPaused", true)
		target:SetAttribute("BrainrotTimerRemainingSeconds", state.remainingSeconds)
	end
end

function BrainrotIslandManager.ResumeBrainrotTimer(uid: string, instance: Instance?)
	if not uid then
		return
	end

	local targetPart: BasePart? = if instance and instance:IsA("BasePart") then instance :: BasePart else nil
	local state = brainrotTimerStates[uid]

	if not state then
		local remaining = if targetPart then (tonumber(targetPart:GetAttribute("BrainrotTimerRemainingSeconds")) or BrainrotRefreshCountdownSeconds) else BrainrotRefreshCountdownSeconds
		local homeIslandName = if targetPart then ((targetPart:GetAttribute("HomeIslandName") :: string?) or "") else ""

		state = {
			remainingSeconds = remaining,
			paused = false,
			homeIslandName = homeIslandName,
			currentInstance = targetPart,
		}
		brainrotTimerStates[uid] = state
	end

	state.paused = false
	if targetPart then
		state.currentInstance = targetPart
	end

	local target = state.currentInstance
	if target and target.Parent then
		target:SetAttribute("BrainrotTimerPaused", false)
		target:SetAttribute("BrainrotTimerRemainingSeconds", state.remainingSeconds)
	end
end

-- Forward declaration
local StartCarryingBrainrot
local SetupBrainrotInteraction
local ConvertCarryingToQueue -- 向前声明

-- 1. 岛屿传送逻辑
local function SetupIslandTeleport(island: Instance)
	local teleportPoint = island:FindFirstChild("TeleportPoint")
	if not teleportPoint or not teleportPoint:IsA("Model") then
		return
	end

	local ring = teleportPoint:FindFirstChild("Ring")
	if not ring or not ring:IsA("MeshPart") then
		return
	end

	local proximityPromptAttachment = ring:FindFirstChild("ProximityPromptAttachment")
	if not proximityPromptAttachment or not proximityPromptAttachment:IsA("Attachment") then
		return
	end

	local proximityPrompt = proximityPromptAttachment:FindFirstChild("ProximityPrompt")
	if not proximityPrompt or not proximityPrompt:IsA("ProximityPrompt") then
		return
	end

	proximityPrompt.Triggered:Connect(function(player)
		local playerInfo = ServerGameInfo.GetPlayerInfo(player)
		if playerInfo and playerInfo.homeSlot ~= "" and homesFolder then
			local homeModel = homesFolder:FindFirstChild(playerInfo.homeSlot)
			if homeModel then
				local homeTeleportPoint = homeModel:FindFirstChild("TeleportPoint")
				if homeTeleportPoint then
					local spawnLocation = homeTeleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation
					local character = player.Character
					if character then
						local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp then
							hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
							ConvertCarryingToQueue(player)
						end
					end
				end
			end
		end
	end)
end

function ConvertCarryingToQueue(player: Player)
	-- 防止“死亡瞬间/倒地后”仍触发地面 Touched 导致把携带态错误入队。
	-- 携带态只在玩家存活时允许转换为背包队列。
	if player:GetAttribute("BrainrotDeathGuard") == true then
		return
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if humanoid then
			-- Health<=0 或状态为 Dead 都视为已死亡/死亡中，直接拒绝入队转换。
			if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
				return
			end
		end
	end

	local carryingBrainrot = BrainrotCarryingManager.GetCarryingBrainrot(player)
	if not carryingBrainrot then
		return
	end

	local configId = tonumber(carryingBrainrot:GetAttribute("ConfigId"))
	local quality = tonumber(carryingBrainrot:GetAttribute("Quality")) or 1
	local level = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
	local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
	local itemType = carryingBrainrot:GetAttribute("ItemType") :: number?

	if configId and uid then
		local resolvedItemType = itemType or GameConfig.ItemType.Brainrot
		local success = BrainrotQueueManager.AddItem(
			player,
			configId,
			quality,
			level,
			true,
			itemType,
			true,
			nil,
			nil,
			nil,
			if resolvedItemType == GameConfig.ItemType.Brainrot then GameConfig.ModelGetSource.Island else nil,
			if resolvedItemType == GameConfig.ItemType.Brainrot then 0 else nil
		)
		if success then
			-- 把携带 brainrot 移出岛面（放回队列）时：终止该 uid 倒计时并立即补刷
			if itemType == GameConfig.ItemType.Brainrot then
				TerminateAndRespawnBrainrot(uid)
			end
			BrainrotCarryingManager.StopCarrying(player)
		else
			--warn("[BrainrotIslandManager] Ground conversion failed: Backpack full for", player.Name)
		end
	end
end

function StartCarryingBrainrot(player: Player, randomBrainrot: Instance)
	local configId = tonumber(randomBrainrot:GetAttribute("ConfigId"))

	if configId then
		local level = tonumber(randomBrainrot:GetAttribute("Level")) or 1
		local itemType = (randomBrainrot:GetAttribute("ItemType") :: number?) or GameConfig.ItemType.Brainrot
		local carry = BrainrotCarryingManager.StartCarrying(player, randomBrainrot)
		if carry then
			if itemType == GameConfig.ItemType.Brainrot or itemType == GameConfig.ItemType.LittleElfChest then
				AnalyticsTool.LogModelPickUp(player, configId, level, itemType)
			end
			randomBrainrot:Destroy()
		end
	end
end

function SetupBrainrotInteraction(randomBrainrot: Instance, island: Instance, spawnPos: Vector3, sizeY: number)
	local interactionTarget: BasePart? = if randomBrainrot:IsA("BasePart") then randomBrainrot :: any else nil

	if not interactionTarget then
		return
	end

	local attachment = interactionTarget:FindFirstChild("InteractionAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		if attachment then
			attachment.Name = "InteractionAttachment"
			attachment.Position = Vector3.new(0, 2, 0)
			attachment.Parent = interactionTarget
		end
	end

	local attachmentObj = attachment :: Attachment
	local prompt: ProximityPrompt = attachmentObj:FindFirstChild("ProximityPrompt") :: ProximityPrompt

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		if prompt then
			local itemType = randomBrainrot:GetAttribute("ItemType") or 1
			local configId: number? = randomBrainrot:GetAttribute("ConfigId") :: number?
			local level = randomBrainrot:GetAttribute("Level") or 1
			local config: any = nil
			if itemType == 3 then
				config = if configId then GameConfig.LittleElfChestIdMap[configId] else nil
			else
				config = if configId then GameConfig.BrainrotIdMap[configId] else nil
			end

			local name = if config then config.name_t else randomBrainrot.Name
			prompt.ActionText = GameTexts.PickUpBrainrot.source
			local levelStr = if itemType == GameConfig.ItemType.LittleElfChest then "???" else tostring(level)
			prompt.ObjectText = `{name}(等级{levelStr})`
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 10
			prompt.Enabled = true
			prompt.Parent = attachment
		end
	end

	-- island/rebirthLimit are static for this interaction, so precompute once.
	local islandId = tonumber(island.Name:match("^Island(%d+)$")) or 1
	local islandConfig = GameConfig.IslandConfigMap[islandId]
	local islandRebirthCount = islandConfig and islandConfig.rebirthCount or 0

	prompt.Triggered:Connect(function(player)
		local playerInfo = ServerGameInfo.GetPlayerInfo(player)
		local playerRebirthCount = if playerInfo then (playerInfo.shopInfo.rebirthLevel or 0) else 0
		if playerRebirthCount < islandRebirthCount then
			NetMsg.FireNotifyShowGameTip(
				player,
				GameTexts.InsufficientRebirthCount.source,
				GameConfig.GameTipTweenType.FlyUp,
				GameTexts.InsufficientRebirthCount.key,
				{ tostring(islandRebirthCount) }
			)
			return
		end

		-- 拾取 brainrot 时暂停该 uid 倒计时
		local itemType = randomBrainrot:GetAttribute("ItemType") :: number?
		if itemType == GameConfig.ItemType.Brainrot then
			local uid = randomBrainrot:GetAttribute("BrainrotUID") :: string?
			if uid then
				BrainrotIslandManager.PauseBrainrotTimer(uid, randomBrainrot)
			end
		end

		StartCarryingBrainrot(player, randomBrainrot)
	end)
end

local function GetIslandId(islandName: string): number
	return tonumber(islandName:match("^Island(%d+)$")) or 1
end

type IslandSpawnerEntry = { id: number, weight: number, itemType: number, itemId: number }
type IslandBoundsData = {
	center: Vector3,
	halfX: number,
	halfY: number,
	halfZ: number,
}

local SpawnSamplingConfig = {
	BoundsPadding = 3,
	MinCellSize = 6,
	MaxCellSize = 16,
	CellCountMultiple = 2,
	MinSpacing = 6,
	MaxSpacing = 14,
	PreferredSpacingScale = 0.8,
	AttemptsPerSpawn = 20,
	FallbackSampleCount = 20,
	RaycastStartOffset = 80,
	RaycastDistance = 180,
}

local function PickWeightedFromIslandPool(pool: { IslandSpawnerEntry }, wantChest: boolean): IslandSpawnerEntry?
	local totalWeight = 0
	for _, entry in ipairs(pool) do
		local isChestEntry = entry.itemType == GameConfig.ItemType.LittleElfChest
		if isChestEntry == wantChest then
			totalWeight += entry.weight or 0
		end
	end
	if totalWeight <= 0 then
		return nil
	end
	local rnd = math.random(1, totalWeight)
	local currentWeight = 0
	for _, entry in ipairs(pool) do
		local isChestEntry = entry.itemType == GameConfig.ItemType.LittleElfChest
		if isChestEntry == wantChest then
			currentWeight += entry.weight or 0
			if rnd <= currentWeight then
				return entry
			end
		end
	end
	return nil
end

local function GetIslandBoundsData(island: Instance): IslandBoundsData?
	if island:IsA("Model") then
		local cf, size = island:GetBoundingBox()
		return {
			center = cf.Position,
			halfX = math.max(size.X * 0.5 - SpawnSamplingConfig.BoundsPadding, SpawnSamplingConfig.MinCellSize),
			halfY = math.max(size.Y * 0.5, 4),
			halfZ = math.max(size.Z * 0.5 - SpawnSamplingConfig.BoundsPadding, SpawnSamplingConfig.MinCellSize),
		}
	elseif island:IsA("BasePart") then
		return {
			center = island.Position,
			halfX = math.max(island.Size.X * 0.5 - SpawnSamplingConfig.BoundsPadding, SpawnSamplingConfig.MinCellSize),
			halfY = math.max(island.Size.Y * 0.5, 4),
			halfZ = math.max(island.Size.Z * 0.5 - SpawnSamplingConfig.BoundsPadding, SpawnSamplingConfig.MinCellSize),
		}
	end
	return nil
end

local function CollectIslandSpawnPositions(island: Instance): { Vector3 }
	local positionList = {} :: { Vector3 }
	for _, child in ipairs(island:GetChildren()) do
		if (child.Name == "IslandBrainrot" or child.Name == "IslandChest") and child:IsA("BasePart") then
			table.insert(positionList, child.Position)
		end
	end
	return positionList
end

local function GetTargetSpawnCount(islandId: number): number
	local islandConfig = GameConfig.IslandConfigMap[islandId]
	if not islandConfig then
		return 4
	end
	local brainrotCount = islandConfig.brainrotGenerateCount or 0
	local chestCount = islandConfig.littleElfChestGenerateCount or 0
	return math.max(brainrotCount + chestCount, 4)
end

local function BuildIslandGrid(boundsData: IslandBoundsData, targetCount: number): (number, number, number)
	local width = boundsData.halfX * 2
	local depth = boundsData.halfZ * 2
	local area = math.max(width * depth, 1)
	local expectedCellCount = math.max(targetCount * SpawnSamplingConfig.CellCountMultiple, 4)
	local targetCellSize = math.sqrt(area / expectedCellCount)
	local cellSize = math.clamp(targetCellSize, SpawnSamplingConfig.MinCellSize, SpawnSamplingConfig.MaxCellSize)
	local cellCountX = math.max(1, math.floor(width / cellSize))
	local cellCountZ = math.max(1, math.floor(depth / cellSize))
	return cellSize, cellCountX, cellCountZ
end

local function PositionToGridIndex(
	pos: Vector3,
	boundsData: IslandBoundsData,
	cellSize: number,
	cellCountX: number,
	cellCountZ: number
): (number, number)
	local minX = boundsData.center.X - boundsData.halfX
	local minZ = boundsData.center.Z - boundsData.halfZ
	local cellX = math.floor((pos.X - minX) / cellSize) + 1
	local cellZ = math.floor((pos.Z - minZ) / cellSize) + 1
	return math.clamp(cellX, 1, cellCountX), math.clamp(cellZ, 1, cellCountZ)
end

local function PickLeastOccupiedCell(
	existingPositions: { Vector3 },
	boundsData: IslandBoundsData,
	cellSize: number,
	cellCountX: number,
	cellCountZ: number
): (number, number)
	local occupancyMap = {} :: { [number]: number }
	for _, pos in ipairs(existingPositions) do
		local cellX, cellZ = PositionToGridIndex(pos, boundsData, cellSize, cellCountX, cellCountZ)
		local idx = (cellZ - 1) * cellCountX + cellX
		occupancyMap[idx] = (occupancyMap[idx] or 0) + 1
	end

	local candidateList = {} :: { { x: number, z: number } }
	local minOccupancy = math.huge
	for z = 1, cellCountZ do
		for x = 1, cellCountX do
			local idx = (z - 1) * cellCountX + x
			local count = occupancyMap[idx] or 0
			if count < minOccupancy then
				minOccupancy = count
				table.clear(candidateList)
				table.insert(candidateList, { x = x, z = z })
			elseif count == minOccupancy then
				table.insert(candidateList, { x = x, z = z })
			end
		end
	end

	if #candidateList == 0 then
		return 1, 1
	end
	local pick = candidateList[rng:NextInteger(1, #candidateList)]
	return pick.x, pick.z
end

local function BuildCandidateXZInCell(
	boundsData: IslandBoundsData,
	cellX: number,
	cellZ: number,
	cellSize: number
): Vector3
	local minX = boundsData.center.X - boundsData.halfX
	local minZ = boundsData.center.Z - boundsData.halfZ
	local x0 = minX + (cellX - 1) * cellSize
	local z0 = minZ + (cellZ - 1) * cellSize
	local x = x0 + rng:NextNumber() * cellSize
	local z = z0 + rng:NextNumber() * cellSize
	return Vector3.new(
		math.clamp(x, minX, boundsData.center.X + boundsData.halfX),
		boundsData.center.Y,
		math.clamp(z, minZ, boundsData.center.Z + boundsData.halfZ)
	)
end

local function RaycastIslandGround(island: Instance, boundsData: IslandBoundsData, candidateXZ: Vector3): Vector3?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { island }
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local rayOrigin = Vector3.new(
		candidateXZ.X,
		boundsData.center.Y + boundsData.halfY + SpawnSamplingConfig.RaycastStartOffset,
		candidateXZ.Z
	)
	local rayDirection = Vector3.new(0, -SpawnSamplingConfig.RaycastDistance, 0)
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end
	return nil
end

local function ComputeMinSpacing(boundsData: IslandBoundsData, targetCount: number): number
	local area = math.max(boundsData.halfX * 2 * boundsData.halfZ * 2, 1)
	local avgArea = area / math.max(targetCount, 1)
	local preferredSpacing = math.sqrt(avgArea) * SpawnSamplingConfig.PreferredSpacingScale
	return math.clamp(preferredSpacing, SpawnSamplingConfig.MinSpacing, SpawnSamplingConfig.MaxSpacing)
end

local function GetNearestDistanceSquared(candidatePos: Vector3, existingPositions: { Vector3 }): number
	if #existingPositions == 0 then
		return math.huge
	end
	local nearestDistanceSq = math.huge
	for _, pos in ipairs(existingPositions) do
		local distanceSq = (Vector3.new(candidatePos.X, 0, candidatePos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude ^ 2
		if distanceSq < nearestDistanceSq then
			nearestDistanceSq = distanceSq
		end
	end
	return nearestDistanceSq
end

local function PickSpawnPositionWithSpacing(island: Instance, islandId: number): Vector3
	local boundsData = GetIslandBoundsData(island)
	if not boundsData then
		local basePos = if island:IsA("BasePart") then island.Position else Vector3.zero
		return basePos + Vector3.new(0, 5, 0)
	end

	local targetCount = GetTargetSpawnCount(islandId)
	local existingPositions = CollectIslandSpawnPositions(island)
	local cellSize, cellCountX, cellCountZ = BuildIslandGrid(boundsData, targetCount)
	local minSpacing = ComputeMinSpacing(boundsData, targetCount)
	local minSpacingSq = minSpacing * minSpacing

	for _ = 1, SpawnSamplingConfig.AttemptsPerSpawn do
		local cellX, cellZ = PickLeastOccupiedCell(existingPositions, boundsData, cellSize, cellCountX, cellCountZ)
		local candidateXZ = BuildCandidateXZInCell(boundsData, cellX, cellZ, cellSize)
		local groundedPos = RaycastIslandGround(island, boundsData, candidateXZ)
		if groundedPos then
			local nearestDistanceSq = GetNearestDistanceSquared(groundedPos, existingPositions)
			if nearestDistanceSq >= minSpacingSq then
				return groundedPos
			end
		end
	end

	-- 回退策略：在全岛候选中选择“离现有刷怪点最远”的位置。
	local bestPos: Vector3? = nil
	local bestScore = -1
	for _ = 1, SpawnSamplingConfig.FallbackSampleCount do
		local candidateXZ = Vector3.new(
			boundsData.center.X + rng:NextNumber(-boundsData.halfX, boundsData.halfX),
			boundsData.center.Y,
			boundsData.center.Z + rng:NextNumber(-boundsData.halfZ, boundsData.halfZ)
		)
		local groundedPos = RaycastIslandGround(island, boundsData, candidateXZ)
		if groundedPos then
			local nearestDistanceSq = GetNearestDistanceSquared(groundedPos, existingPositions)
			if nearestDistanceSq > bestScore then
				bestScore = nearestDistanceSq
				bestPos = groundedPos
			end
		end
	end

	if bestPos then
		return bestPos
	end
	return boundsData.center + Vector3.new(0, 5, 0)
end

local function SpawnOneBrainrotInternal(island: Instance, isChest: boolean): BasePart?
	local islandId = GetIslandId(island.Name)
	local islandConfig = GameConfig.IslandConfigMap[islandId]
	if not islandConfig then
		return nil
	end

	local config: any = nil
	local itemType = GameConfig.ItemType.Brainrot

	local pool = GameConfig.IslandSpawnerMap[islandId]
	local entry = pool and PickWeightedFromIslandPool(pool, isChest) or nil
	if entry then
		itemType = entry.itemType
		local configId = entry.itemId
		if itemType == GameConfig.ItemType.LittleElfChest then
			config = GameConfig.LittleElfChestIdMap[configId]
		elseif itemType == GameConfig.ItemType.Brainrot then
			config = GameConfig.BrainrotIdMap[configId]
		elseif itemType == GameConfig.ItemType.Coil then
			config = GameConfig.CoilIdMap[configId]
		end
	end

	if not config then
		return nil
	end

	local randomBrainrot = Instance.new("Part")
	randomBrainrot.Size = Vector3.new(1, 1, 1)
	randomBrainrot.Transparency = 1
	randomBrainrot.CanCollide = false
	randomBrainrot.Anchored = true
	randomBrainrot.Name = if itemType == GameConfig.ItemType.LittleElfChest then "IslandChest" else "IslandBrainrot"

	randomBrainrot:SetAttribute("ConfigId", config.id)
	randomBrainrot:SetAttribute("ItemType", itemType)
	randomBrainrot:SetAttribute("Quality", config.quality or 1)
	
	local minLv = islandConfig.itemMinLv or 1
	local maxLv = islandConfig.itemMaxLv or 10
	local level = rng:NextInteger(minLv, maxLv)
	randomBrainrot:SetAttribute("Level", level)
	randomBrainrot:SetAttribute("HomeIslandName", island.Name)

	-- 为 IslandBrainrot 设置独立倒计时（宝箱不需要倒计时）
	if itemType == GameConfig.ItemType.Brainrot then
		local uid = HttpService:GenerateGUID(false)
		randomBrainrot:SetAttribute("BrainrotUID", uid)
		randomBrainrot:SetAttribute("BrainrotTimerRemainingSeconds", BrainrotRefreshCountdownSeconds)
		randomBrainrot:SetAttribute("BrainrotTimerPaused", false)
		brainrotTimerStates[uid] = {
			remainingSeconds = BrainrotRefreshCountdownSeconds,
			paused = false,
			homeIslandName = island.Name,
			currentInstance = randomBrainrot,
		}
	end

	local spawnPos = PickSpawnPositionWithSpacing(island, islandId)
	local randomFacingOffsetDeg = rng:NextNumber(-SpawnFacingRandomOffsetMaxDeg, SpawnFacingRandomOffsetMaxDeg)
	local spawnFacingCFrame = CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(randomFacingOffsetDeg), 0)

	local sizeY = 0
	randomBrainrot.CFrame = spawnFacingCFrame

	randomBrainrot:SetAttribute("SpawnPos", spawnPos)
	randomBrainrot:SetAttribute("SpawnSizeY", sizeY)

	randomBrainrot.Parent = island
	SetupBrainrotInteraction(randomBrainrot, island, spawnPos, sizeY)
	return randomBrainrot
end

-- 倒计时结束/移出岛面时：终止该 uid 的倒计时并立刻在 home 岛补一个新 brainrot
TerminateAndRespawnBrainrot = function(uid: string)
	if not uid then
		return
	end

	local state = brainrotTimerStates[uid]
	if not state then
		return
	end

	local homeIslandName = state.homeIslandName
	brainrotTimerStates[uid] = nil

	local targetIsland = if homeIslandName ~= "" then islandsFolder:FindFirstChild(homeIslandName) else nil
	if targetIsland then
		SpawnOneBrainrotInternal(targetIsland, false)
	end
end

-- 4. 业务逻辑封装
local function SpawnBrainrotsOnIsland(island: Instance)
	local islandId = GetIslandId(island.Name)
	local islandConfig = GameConfig.IslandConfigMap[islandId]
	if not islandConfig then return end

	local brainrotCount = islandConfig.brainrotGenerateCount or 3
	local chestCount = islandConfig.littleElfChestGenerateCount or 1

	for i = 1, brainrotCount do
		SpawnOneBrainrotInternal(island, false)
	end
	for i = 1, chestCount do
		SpawnOneBrainrotInternal(island, true)
	end
end

local function GetActiveBrainrot(player: Player): Instance?
	local character = player.Character
	if not character then
		return nil
	end

	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying and carrying:GetAttribute("BrainrotUID") then
		if carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return carrying
		end
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool:GetAttribute("BrainrotUID") then
		if equippedTool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return equippedTool
		end
	end

	return nil
end

local function OnRequestPlaceCarryingBrainrot(player: Player, pointIndex: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local carryingBrainrot = GetActiveBrainrot(player)
	if carryingBrainrot then
		local configId = carryingBrainrot:GetAttribute("ConfigId")
		local quality = carryingBrainrot:GetAttribute("Quality") or 2

		if configId then
			local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
			if not uid then
				return
			end

			local itemType = carryingBrainrot:GetAttribute("ItemType") :: number?
			if itemType ~= GameConfig.ItemType.Brainrot then
				warn(
					"[BrainrotIslandManager] OnRequestPlaceCarryingBrainrot rejected: itemType is not Brainrot for",
					player.Name,
					"itemType",
					itemType
				)
				return
			end

			if carryingBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, uid) then
					return
				end
			else
				if not carryingBrainrot.Parent then
					return
				end
			end

			if itemType == GameConfig.ItemType.Brainrot then
				-- 把携带 brainrot 移出岛面（放回家园/展台）时：终止倒计时并立即补刷
				TerminateAndRespawnBrainrot(uid)
			end

			local qualityCfg = GameConfig.BrainrotQualityConfig[quality :: number]
			local defaultQualityCfg = GameConfig.BrainrotQualityConfig[1]
			local rarity: GameConfig.ModelRarity = (if qualityCfg then qualityCfg.rarity else if defaultQualityCfg then defaultQualityCfg.rarity else "Common") :: any
			local placedLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1

			ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, {
				instanceId = "brainrot_" .. tostring(math.floor(os.clock() * 1000)),
				configId = tonumber(configId) or 1,
				level = placedLevel,
				rarity = rarity,
			})

			AnalyticsTool.LogModelPlace(player, tonumber(configId) or 1, placedLevel)

			carryingBrainrot:Destroy()
		end
	end
end

local function OnRequestSellCarryingBrainrot(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	local carryingBrainrot = GetActiveBrainrot(player)
	if carryingBrainrot then
		local configId = carryingBrainrot:GetAttribute("ConfigId")
		if configId then
			local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
			if not uid then
				return
			end

			local itemType = carryingBrainrot:GetAttribute("ItemType") :: number?

			if carryingBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, uid) then
					return
				end
			else
				if not carryingBrainrot.Parent then
					return
				end
			end

			if itemType == GameConfig.ItemType.Brainrot then
				-- 出售时把携带 brainrot 移出岛面：终止倒计时并立即补刷
				TerminateAndRespawnBrainrot(uid)
			end

			local brainrotConfig = GameConfig.BrainrotIdMap[tonumber(configId) or 0]
			if brainrotConfig then
				local currentLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
				local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotConfig.baseAbility, currentLevel)

				ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, sellPrice, GameConfig.ItemCountChangeReason.GainFromSellModel)
				AnalyticsTool.LogModelSell(player, 1, sellPrice, { tonumber(configId) or 0 }, { currentLevel })
				carryingBrainrot:Destroy()

				print("[BrainrotIslandManager] Player", player.Name, "sold tool brainrot for", sellPrice)
			end
		end
	end
end

local function StartSpawnLoop()
	task.spawn(function()
		while true do
			task.wait(10)
			if not islandsFolder then
				continue
			end

			for _, island in ipairs(islandsFolder:GetChildren()) do
				if island.Name:match("^Island%d+$") then
					local islandId = GetIslandId(island.Name)
					local islandConfig = GameConfig.IslandConfigMap[islandId]
					if not islandConfig then continue end

					-- brainrot 不再使用 10 秒补刷；由独立倒计时负责销毁与随机补刷
					local targetChestCount = islandConfig.littleElfChestGenerateCount or 1

					local currentChestCount = 0
					for _, child in ipairs(island:GetChildren()) do
						if child.Name == "IslandChest" then
							currentChestCount += 1
						end
					end

					if currentChestCount < targetChestCount then
						local toSpawn = targetChestCount - currentChestCount
						for i = 1, toSpawn do
							SpawnOneBrainrotInternal(island, true)
						end
					end
				end
			end
		end
	end)
end

local function StartBrainrotTimerTickLoop()
	task.spawn(function()
		while true do
			task.wait(BrainrotTimerTickSeconds)
			for uid, state in pairs(brainrotTimerStates) do
				if state and not state.paused then
					state.remainingSeconds = math.max(state.remainingSeconds - BrainrotTimerTickSeconds, 0)

					local inst = state.currentInstance
					if inst and inst.Parent then
						inst:SetAttribute("BrainrotTimerRemainingSeconds", state.remainingSeconds)
					end

					if state.remainingSeconds <= 0 then
						local homeIslandName = state.homeIslandName
						brainrotTimerStates[uid] = nil

						if inst and inst.Parent then
							inst:Destroy()
						end

						local targetIsland = if homeIslandName ~= "" then islandsFolder:FindFirstChild(homeIslandName) else nil
						if targetIsland then
							SpawnOneBrainrotInternal(targetIsland, false)
						end
					end
				end
			end
		end
	end)
end

local function SetupGroundTrigger()
	local groundFolder = workspace:FindFirstChild("Ground")
	if not groundFolder then
		return
	end

	local function OnTouched(hit)
		local char = hit.Parent
		if not char then
			return
		end
		local player = _players:GetPlayerFromCharacter(char)
		if player then
			local now = os.clock()
			local lastTouch = player:GetAttribute("LastGroundTouch") or 0
			if now - lastTouch > 0.5 then
				player:SetAttribute("LastGroundTouch", now)
				ConvertCarryingToQueue(player)
			end
		end
	end

	if groundFolder:IsA("BasePart") then
		groundFolder.Touched:Connect(OnTouched)
	end
	for _, ground in ipairs(groundFolder:GetDescendants()) do
		if ground:IsA("BasePart") then
			ground.Touched:Connect(OnTouched)
		end
	end
end

function BrainrotIslandManager.Init()
	SetupGroundTrigger()

	-- 死亡清理：如果玩家在“携带态 brainrot（CarryingBrainrot）”还没转换成背包 Tool 前死亡，
	-- 需要把该 uid 的倒计时态清理并立即在岛上补刷，避免重生后从 brainrotQueue 生成 Tool。
	local function BindPlayerDeathHandler(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			-- 给 ConvertCarryingToQueue 的防护属性一个确定的初始值
			player:SetAttribute("BrainrotDeathGuard", false)

			local humanoid = character:WaitForChild("Humanoid", 2) :: Humanoid?
			if not humanoid then
				return
			end

			humanoid.Died:Connect(function()
				player:SetAttribute("BrainrotDeathGuard", true)

				local carryingBrainrot = character:FindFirstChild("CarryingBrainrot")
				if not carryingBrainrot then
					return
				end

				local itemType = carryingBrainrot:GetAttribute("ItemType") :: number?
				if itemType ~= GameConfig.ItemType.Brainrot then
					return
				end

				local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
				if uid then
					TerminateAndRespawnBrainrot(uid)
				end

				-- 清理携带物，避免死亡后仍触发一些交互/触碰逻辑。
				if carryingBrainrot.Parent then
					carryingBrainrot:Destroy()
				end
			end)
		end)
	end

	for _, player in ipairs(_players:GetPlayers()) do
		BindPlayerDeathHandler(player)
	end
	_players.PlayerAdded:Connect(BindPlayerDeathHandler)

	if not islandsFolder then
		return
	end

	for _, island in ipairs(islandsFolder:GetChildren()) do
		if island.Name:match("^Island%d+$") then
			SetupIslandTeleport(island)
			SpawnBrainrotsOnIsland(island)
		end
	end
	islandsFolder.ChildAdded:Connect(function(child)
		if child.Name:match("^Island%d+$") then
			SetupIslandTeleport(child)
			SpawnBrainrotsOnIsland(child)
		end
	end)

	NetMsg.ConnectRequestPlaceCarryingBrainrot(OnRequestPlaceCarryingBrainrot)
	NetMsg.ConnectRequestSellCarryingBrainrot(OnRequestSellCarryingBrainrot)

	StartBrainrotTimerTickLoop()
	StartSpawnLoop()
end

function BrainrotIslandManager.StartCarryingBrainrot(player: Player, brainrot: Instance)
	StartCarryingBrainrot(player, brainrot)
end

BrainrotIslandManager.SetupBrainrotInteraction = SetupBrainrotInteraction

-- 注入引用给携带管理器，避免携带管理器在运行时再 require 引发循环依赖
local carryingManagerAny = BrainrotCarryingManager :: any
if carryingManagerAny.SetBrainrotIslandManager then
	carryingManagerAny.SetBrainrotIslandManager(BrainrotIslandManager)
end

return BrainrotIslandManager
