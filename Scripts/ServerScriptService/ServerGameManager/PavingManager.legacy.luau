--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")

type BrickData = {
	Owner: Player,
	ExpireTime: number,
	IsGhost: boolean,
}
type PavingBatchRejectInfo = {
	index: number,
	reason: string,
}

local activeBricks: { [Part]: BrickData } = {}
local activeBricksGrid: { [string]: Part } = {} -- O(1) 空间网格字典
local playerLastBatchTimeMap: { [number]: number } = {}
local playerInFlightBatchMap: { [number]: number } = {}
local metrics = {
	totalBatches = 0,
	totalAccepted = 0,
	totalRejected = 0,
	totalBackpressureRejected = 0,
	totalContentionRejected = 0,
	totalAckLatencyMs = 0,
	totalAckCount = 0,
}
local METRIC_PREFIX = "PavingMetric_"

local GHOST_DURATION = 1.5 -- 幽灵状态持续时间

local modelsFolder = replicatedStorage:WaitForChild("Models")
local bricksFolder = modelsFolder:WaitForChild("Bricks")
local brickTemplate = bricksFolder:WaitForChild("Brick1") :: Part

local function UpdateBrickVisual(part: Part, isGhost: boolean)
	if isGhost then
		part.BrickColor = BrickColor.new("Neon orange") -- 使用橙色区分
		--part.Material = Enum.Material.Neon
		part.Transparency = 0.5
		part:SetAttribute("IsGhost", true)
	else
		part.Color = brickTemplate.Color
		--part.Material = brickTemplate.Material
		part.Transparency = brickTemplate.Transparency
		part:SetAttribute("IsGhost", false)
	end
end

local function GetPosKey(pos: Vector3)
	return string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z)
end

local function UpdateMetricAttributes()
	workspace:SetAttribute(METRIC_PREFIX .. "TotalBatches", metrics.totalBatches)
	workspace:SetAttribute(METRIC_PREFIX .. "TotalAccepted", metrics.totalAccepted)
	workspace:SetAttribute(METRIC_PREFIX .. "TotalRejected", metrics.totalRejected)
	workspace:SetAttribute(METRIC_PREFIX .. "TotalBackpressureRejected", metrics.totalBackpressureRejected)
	workspace:SetAttribute(METRIC_PREFIX .. "TotalContentionRejected", metrics.totalContentionRejected)
	local avgLatencyMs = if metrics.totalAckCount > 0 then metrics.totalAckLatencyMs / metrics.totalAckCount else 0
	workspace:SetAttribute(METRIC_PREFIX .. "AvgAckLatencyMs", avgLatencyMs)
end

local brickPool: { Part } = {}
local SEA_LEVEL = 0
local lastEarthquakeActive = workspace:GetAttribute("EarthquakeActive") == true
local playerLastPlacedBrickMap: { [number]: Part } = {}

-- 动态获取海平面高度 (与客户端逻辑对齐)
local startPointFolder = workspace:FindFirstChild("StartPoint")
local startPointModel = if startPointFolder then startPointFolder:FindFirstChild("StartPointModel") :: Model else nil
local startTrigger = if startPointModel then startPointModel:FindFirstChild("StartTrigger") :: Part else nil
local startAttachment = if startTrigger then startTrigger:FindFirstChild("Attachment") :: Attachment else nil

if startAttachment then
	SEA_LEVEL = startAttachment.WorldPosition.Y
end

local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
if not pavedBricksFolder then
	pavedBricksFolder = Instance.new("Folder")
	pavedBricksFolder.Name = "PavedBricks"
	pavedBricksFolder.Parent = workspace
end

-- 调试：workspace:SetAttribute("PavingDebugFloatBlockRays", true) 显示 FloatBlock 四角竖直射线的命中情况
local DEBUG_FLOATBLOCK_RAYS_ATTR = "PavingDebugFloatBlockRays"
local FLOATBLOCK_RAY_ORIGIN_Y = 50
local FLOATBLOCK_RAY_LENGTH = 60
local DEBUG_RAY_LIFETIME = 4

local function GetOrCreateDebugRaysFolder(): Folder
	local existing = workspace:FindFirstChild("PavingDebugFloatBlockRays")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "PavingDebugFloatBlockRays"
	folder.Parent = workspace
	return folder
end

local function CreateDebugRaySegment(from: Vector3, to: Vector3, color: Color3, parent: Instance)
	local dist = (to - from).Magnitude
	if dist < 0.01 then
		return
	end
	local mid = from:Lerp(to, 0.5)
	local p = Instance.new("Part")
	p.Name = "FloatBlockRay"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.12, 0.12, dist)
	p.CFrame = CFrame.new(mid, to)
	p.Parent = parent
	game:GetService("Debris"):AddItem(p, DEBUG_RAY_LIFETIME)
end

local function GetBrickFromPool(): Part
	local brick = table.remove(brickPool)
	if not brick then
		local newPart = brickTemplate:Clone()
		newPart:SetAttribute("IsLocal", false)
		newPart.Anchored = true
		newPart.CanCollide = true
		newPart.Size = brickTemplate.Size

		newPart.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character then
				return
			end
			local hitPlayer = players:GetPlayerFromCharacter(character :: Model)
			if not hitPlayer then
				return
			end

			local data = activeBricks[newPart]
			if data and data.Owner ~= hitPlayer then
				local now = os.clock()

				-- Debounce check
				local lastPenalty = (newPart:GetAttribute("LastPenaltyTime") :: any) or 0
				if now - lastPenalty < 0.5 then
					return
				end
				newPart:SetAttribute("LastPenaltyTime", now)

				-- 只有非幽灵砖块才会被踩踏扣时间
				if not data.IsGhost then
					local remaining = data.ExpireTime - now
					if remaining > 0 then
						data.ExpireTime = now + math.max(GameConfig.Paving.MinCollapseTime, remaining - GameConfig.Paving.SteppedPenalty)
						newPart.BrickColor = BrickColor.new("Bright red") -- 变红提示即将进入进入幽灵态
					end
				end
			end
		end)
		brick = newPart
	end

	local part = brick :: Part
	-- 对象池复用兜底：确保每次取出的砖都有可站立的物理属性。
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CastShadow = false --性能优化
	return part
end

-- 辅助函数：归还砖块到对象池（安全版本：防止误删替代砖块的网格条目）
local function ReturnBrickToPool(brick: Part)
	local key = GetPosKey(brick.Position)
	if activeBricksGrid[key] == brick then
		activeBricksGrid[key] = nil
	end
	local ownerUserId = brick:GetAttribute("PavingOwnerUserId")
	if type(ownerUserId) == "number" and playerLastPlacedBrickMap[ownerUserId] == brick then
		playerLastPlacedBrickMap[ownerUserId] = nil
	end
	activeBricks[brick] = nil
	brick.Parent = nil
	-- 防止地震掉落流程将碰撞关闭后带入对象池，影响后续新铺砖可站立性。
	brick.Anchored = true
	brick.CanCollide = true
	brick.CanQuery = true
	brick:SetAttribute("IsGhost", nil)
	brick:SetAttribute("EarthquakeDropped", nil)
	brick:SetAttribute("EarthquakeMarkedForDrop", nil)
	brick:SetAttribute("EarthquakeMarkedKind", nil)
	brick:SetAttribute("PavingOwnerUserId", nil)
	table.insert(brickPool, brick)
end

-- FloatBlock：单点竖直射线（与砖块水平尺寸组合为「整块 footprint 才禁铺」）
local function RaycastFloatBlockAtPoint(samplePos: Vector3): RaycastResult?
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if not floatBlockFolder then
		return nil
	end

	local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floatBlockFolder }

	return workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

local function IsPointOverFloatBlock(pos: Vector3): boolean
	return RaycastFloatBlockAtPoint(pos) ~= nil
end

local function GetSafeZoneFilterInstances(): { Instance }
	local filterInstances = {}
	local groundFolder = workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
	local islandsFolder = workspace:FindFirstChild("Islands")
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if groundFolder then
		table.insert(filterInstances, groundFolder)
	end
	if islandsFolder then
		table.insert(filterInstances, islandsFolder)
	end
	if homesFolder then
		table.insert(filterInstances, homesFolder)
	end
	return filterInstances
end

local function IsPointOverSafeZone(samplePos: Vector3): boolean
	local filterInstances = GetSafeZoneFilterInstances()
	if #filterInstances <= 0 then
		return false
	end
	local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = filterInstances
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil
end

local function _GetSnappedPositionForPaving(pos: Vector3): Vector3
	local grid = brickTemplate.Size.X
	local x = math.floor(pos.X / grid + 0.5) * grid
	local z = math.floor(pos.Z / grid + 0.5) * grid
	return Vector3.new(x, SEA_LEVEL, z)
end

-- 与客户端门禁对齐：Ground/Islands/Home，或「未标记且未掉落」的 Float
local function IsPointOverPavingSafeZone(samplePos: Vector3): boolean
	local filterInstances = GetSafeZoneFilterInstances()
	local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)

	if #filterInstances > 0 then
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = filterInstances
		if workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil then
			return true
		end
	end

	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if floatBlockFolder then
		local fp = RaycastParams.new()
		fp.FilterType = Enum.RaycastFilterType.Include
		fp.FilterDescendantsInstances = { floatBlockFolder }
		local r = workspace:Raycast(rayOrigin, rayDirection, fp)
		if r and r.Instance and r.Instance:IsA("BasePart") then
			local inst = r.Instance
			if inst:GetAttribute("EarthquakeMarkedForDrop") ~= true and inst:GetAttribute("EarthquakeDropped") ~= true then
				return true
			end
		end
	end

	return false
end

local function GetBrickFootprintCornerPositions(center: Vector3): { Vector3 }
	local size = brickTemplate.Size
	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	local y = center.Y
	return {
		Vector3.new(center.X - hx, y, center.Z - hz),
		Vector3.new(center.X + hx, y, center.Z - hz),
		Vector3.new(center.X - hx, y, center.Z + hz),
		Vector3.new(center.X + hx, y, center.Z + hz),
	}
end

local function _IsEntireBrickFootprintOverPavingSafeZone(center: Vector3): boolean
	for _, p in GetBrickFootprintCornerPositions(center) do
		if not IsPointOverPavingSafeZone(p) then
			return false
		end
	end
	return true
end

local function IsEntireBrickFootprintOverFloatBlock(center: Vector3): boolean
	for _, p in GetBrickFootprintCornerPositions(center) do
		if not IsPointOverFloatBlock(p) then
			return false
		end
	end
	return true
end

local function IsDangerousFloatBlock(part: BasePart?): boolean
	return part ~= nil and (part:GetAttribute("EarthquakeMarkedForDrop") == true or part:GetAttribute("EarthquakeDropped") == true)
end

local function IsPlayerOnDangerousFloatBlock(rootPos: Vector3): boolean
	local hit = RaycastFloatBlockAtPoint(rootPos)
	if hit == nil then
		return false
	end
	local inst = hit.Instance
	if not inst:IsA("BasePart") then
		return false
	end
	return IsDangerousFloatBlock(inst)
end

local function IsEntireBrickFootprintOverSafeZone(center: Vector3): boolean
	for _, p in GetBrickFootprintCornerPositions(center) do
		if not IsPointOverSafeZone(p) then
			return false
		end
	end
	return true
end

-- 可视化：从 samplePos 向上偏移处向下打射线；绿色=命中 FloatBlock，红色=未命中（线段画满射程）
local function VisualizeFloatBlockRaysForBrickCenter(center: Vector3)
	local folder = GetOrCreateDebugRaysFolder()
	local hitColor = Color3.fromRGB(80, 255, 120)
	local missColor = Color3.fromRGB(255, 80, 80)
	for _, samplePos in GetBrickFootprintCornerPositions(center) do
		local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
		local rayEnd = rayOrigin + Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
		local result = RaycastFloatBlockAtPoint(samplePos)
		if result then
			CreateDebugRaySegment(rayOrigin, result.Position, hitColor, folder)
		else
			CreateDebugRaySegment(rayOrigin, rayEnd, missColor, folder)
		end
	end
end

local function OnRequestPlaceBrickBatch(player: Player, positions: any, batchId: number?, clientSentAt: number?)
	local rejectReason = GameConfig.PavingRejectReason
	local acceptedIndexes: { number } = {}
	local rejectedList: { PavingBatchRejectInfo } = {}
	local function AddRejected(index: number, reason: string)
		table.insert(rejectedList, {
			index = index,
			reason = reason,
		})
	end

	local playerId = player.UserId
	local requestBatchId = if typeof(batchId) == "number" then batchId else 0
	local now = os.clock()
	local maxPending = math.max(1, GameConfig.Paving.MaxPendingBatches or 4)
	local inFlightCount = playerInFlightBatchMap[playerId] or 0
	if inFlightCount >= maxPending then
		metrics.totalBatches += 1
		metrics.totalRejected += 1
		metrics.totalBackpressureRejected += 1
		UpdateMetricAttributes()
		NetMsg.FireNotifyPlaceBrickBatchResult(
			player,
			requestBatchId,
			acceptedIndexes,
			{ { index = 1, reason = rejectReason.ServerBackpressure } },
			ServerGameInfo.GetPlayerCarriedBricks(player),
			now
		)
		return
	end

	playerLastBatchTimeMap[playerId] = now
	playerInFlightBatchMap[playerId] = inFlightCount + 1
	metrics.totalBatches += 1

	if type(positions) ~= "table" then
		AddRejected(1, rejectReason.InvalidPayload)
		metrics.totalRejected += 1
		NetMsg.FireNotifyPlaceBrickBatchResult(player, requestBatchId, acceptedIndexes, rejectedList, ServerGameInfo.GetPlayerCarriedBricks(player), now)
		playerInFlightBatchMap[playerId] = math.max((playerInFlightBatchMap[playerId] or 1) - 1, 0)
		UpdateMetricAttributes()
		return
	end
	if #positions > GameConfig.Paving.MaxBatchSize then
		warn("[PavingManager] Player", player.Name, "sent too many bricks in one batch:", #positions)
		AddRejected(1, rejectReason.BatchTooLarge)
		metrics.totalRejected += 1
		NetMsg.FireNotifyPlaceBrickBatchResult(player, requestBatchId, acceptedIndexes, rejectedList, ServerGameInfo.GetPlayerCarriedBricks(player), now)
		playerInFlightBatchMap[playerId] = math.max((playerInFlightBatchMap[playerId] or 1) - 1, 0)
		UpdateMetricAttributes()
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player) :: any
	if playerInfo == nil then
		AddRejected(1, rejectReason.InvalidPayload)
		metrics.totalRejected += 1
		NetMsg.FireNotifyPlaceBrickBatchResult(player, requestBatchId, acceptedIndexes, rejectedList, ServerGameInfo.GetPlayerCarriedBricks(player), now)
		playerInFlightBatchMap[playerId] = math.max((playerInFlightBatchMap[playerId] or 1) - 1, 0)
		UpdateMetricAttributes()
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		AddRejected(1, rejectReason.InvalidPayload)
		metrics.totalRejected += 1
		NetMsg.FireNotifyPlaceBrickBatchResult(player, requestBatchId, acceptedIndexes, rejectedList, ServerGameInfo.GetPlayerCarriedBricks(player), now)
		playerInFlightBatchMap[playerId] = math.max((playerInFlightBatchMap[playerId] or 1) - 1, 0)
		UpdateMetricAttributes()
		return
	end

	local showFloatBlockRays = workspace:GetAttribute(DEBUG_FLOATBLOCK_RAYS_ATTR) == true
	local consumedBricks = 0
	local remainingBricks = playerInfo.carriedInfo.bricks
	local playerOnDangerousFloatBlock = IsPlayerOnDangerousFloatBlock(rootPart.Position)
	-- 续期窗口采用“双阈值”：比例阈值 + 绝对秒数上限，避免回踩旧路时大面积过早续期。
	local stationaryRenewalThresholdByRatio = GameConfig.Paving.BaseCollapseTime * GameConfig.Paving.StationaryRenewalThreshold
	local stationaryRenewalMaxRemainingTime = GameConfig.Paving.StationaryRenewalMaxRemainingTime or 1
	local stationaryRenewalRemainingThreshold = math.min(stationaryRenewalThresholdByRatio, stationaryRenewalMaxRemainingTime)

	for index, position in ipairs(positions) do
		if typeof(position) ~= "Vector3" then
			AddRejected(index, rejectReason.NotVector3)
			metrics.totalRejected += 1
			continue
		end

		-- [优化] 瞬间查找取代遍历 (O(1) 复杂度)
		-- 放在禁铺判定之前：已有砖续命/续期不应被 FloatBlock/SafeZone 禁铺规则误拦截。
		local key = GetPosKey(position)
		local existingBrick = activeBricksGrid[key]

		if existingBrick then
			local data = activeBricks[existingBrick]
			if data and data.Owner == player then
				local remainingTime = data.ExpireTime - now
				if remainingBricks <= 0 then
					-- 无砖时不再做“续命延寿”；是否可站立只取决于砖是否已消失。
					table.insert(acceptedIndexes, index)
					continue
				end
				-- 如果是幽灵砖，无视续期阈值直接填实
				-- 如果是非幽灵砖，则走常规续期逻辑
				if data.IsGhost then
					data.IsGhost = false
					data.ExpireTime = now + GameConfig.Paving.BaseCollapseTime
					UpdateBrickVisual(existingBrick, false)
					consumedBricks += 1
					remainingBricks -= 1
					table.insert(acceptedIndexes, index)
				else
					-- 防止网络延迟导致的短时间内重复续期扣砖
					if remainingTime < stationaryRenewalRemainingThreshold then
						data.ExpireTime = now + GameConfig.Paving.BaseCollapseTime
						UpdateBrickVisual(existingBrick, false)
						consumedBricks += 1
						remainingBricks -= 1
						table.insert(acceptedIndexes, index)
					else
						table.insert(acceptedIndexes, index)
					end
				end
			elseif data and data.Owner ~= player then
				AddRejected(index, rejectReason.OccupiedByOther)
				metrics.totalRejected += 1
				metrics.totalContentionRejected += 1
			else
				table.insert(acceptedIndexes, index)
			end
			-- 如果已经有砖了，跳过生成步骤
			continue
		end

		if showFloatBlockRays then
			VisualizeFloatBlockRaysForBrickCenter(position)
		end

		-- 若整块砖 footprint 完全位于安全区（Ground/Islands/PlayersHome），则禁铺
		if IsEntireBrickFootprintOverSafeZone(position) then
			AddRejected(index, rejectReason.SafeZoneBlocked)
			metrics.totalRejected += 1
			continue
		end

		-- 仅当砖块底面四角均落在 FloatBlock 上方时才禁铺（预警～地震结束期间允许在 FloatBlock 上铺砖自救）
		if workspace:GetAttribute("EarthquakeRescuePaving") ~= true and IsEntireBrickFootprintOverFloatBlock(position) then
			-- 紧急自救：玩家当前脚下是“危险浮块”且仍有砖时，允许补脚下砖避免直接掉落。
			local allowEmergencyPaving = remainingBricks > 0 and playerOnDangerousFloatBlock
			if not allowEmergencyPaving then
				AddRejected(index, rejectReason.FloatBlockBlocked)
				metrics.totalRejected += 1
				continue
			end
		end

		-- 1. Anti-cheat: Height check (使用动态 SEA_LEVEL)
		if math.abs(position.Y - SEA_LEVEL) > 2 then
			AddRejected(index, rejectReason.HeightMismatch)
			metrics.totalRejected += 1
			continue
		end

		-- 2. Anti-cheat: Distance check（水平 XZ；砖位 Y 固定为海平面，全 3D 会在跳跃时误拒）
		local horizDelta = Vector3.new(position.X - rootPart.Position.X, 0, position.Z - rootPart.Position.Z)
		if horizDelta.Magnitude > GameConfig.Paving.PavingDistanceLimit then
			AddRejected(index, rejectReason.DistanceLimit)
			metrics.totalRejected += 1
			continue
		end

		-- 3. Inventory check（仅在“无现存砖可续命”时限制）
		if remainingBricks <= 0 then
			AddRejected(index, rejectReason.OutOfBricks)
			metrics.totalRejected += 1
			continue
		end

		-- 5. Deduct and Place
		consumedBricks += 1
		remainingBricks -= 1

		local brick = GetBrickFromPool()
		brick.Position = position
		UpdateBrickVisual(brick, false)
		brick:SetAttribute("PavingOwnerUserId", player.UserId)
		if workspace:GetAttribute("EarthquakeMarkPavingActive") == true then
			local previousLastBrick = playerLastPlacedBrickMap[player.UserId]
			if previousLastBrick and previousLastBrick.Parent ~= nil and previousLastBrick:GetAttribute("EarthquakeDropped") ~= true then
				previousLastBrick:SetAttribute("EarthquakeMarkedForDrop", true)
				previousLastBrick:SetAttribute("EarthquakeMarkedKind", "PavedBrick")
			end
			-- 地震期间“当前最后一块砖”保持正常铺砖外观，不参与地震标记动画。
			brick:SetAttribute("EarthquakeMarkedForDrop", nil)
			brick:SetAttribute("EarthquakeMarkedKind", nil)
			playerLastPlacedBrickMap[player.UserId] = brick
		end
		brick.Parent = pavedBricksFolder

		-- 存入空间哈希字典
		activeBricksGrid[key] = brick

		activeBricks[brick] = {
			Owner = player,
			ExpireTime = now + GameConfig.Paving.BaseCollapseTime,
			IsGhost = false,
		}
		table.insert(acceptedIndexes, index)
	end

	if consumedBricks > 0 then
		ServerGameInfo.UpdateInventoryBricks(player, -consumedBricks, nil, true)
	end
	NetMsg.FireNotifyPlayerCarriedUpdate(player, playerInfo.carriedInfo)
	NetMsg.FireNotifyPlaceBrickBatchResult(
		player,
		requestBatchId,
		acceptedIndexes,
		rejectedList,
		playerInfo.carriedInfo.bricks,
		now
	)

	if typeof(clientSentAt) == "number" then
		local latencyMs = math.max(0, (now - clientSentAt) * 1000)
		metrics.totalAckLatencyMs += latencyMs
		metrics.totalAckCount += 1
	end
	metrics.totalAccepted += #acceptedIndexes
	playerInFlightBatchMap[playerId] = math.max((playerInFlightBatchMap[playerId] or 1) - 1, 0)
	UpdateMetricAttributes()
end

local startTriggerOverlapParams: OverlapParams? = nil
local function _IsPlayerOverlappingStartTrigger(player: Player): boolean
	if not startTrigger or not startTrigger:IsA("BasePart") then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	if not startTriggerOverlapParams then
		local p = OverlapParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		startTriggerOverlapParams = p
	end
	(startTriggerOverlapParams :: OverlapParams).FilterDescendantsInstances = { character }
	local overlapping = workspace:GetPartBoundsInBox(startTrigger.CFrame, startTrigger.Size, startTriggerOverlapParams :: OverlapParams)
	return #overlapping > 0
end

local characterRefillOverlapParams: OverlapParams? = nil
-- 返回脚下探测命中的 BasePart（盒体重叠优先，否则向下射线），用于区域判定与岛屿命名。
local function GetCharacterRefillSurfaceHit(player: Player, folder: Instance): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	if not characterRefillOverlapParams then
		local p = OverlapParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		characterRefillOverlapParams = p
	end
	(characterRefillOverlapParams :: OverlapParams).FilterDescendantsInstances = { folder }
	local boxSize = Vector3.new(2.5, 1.2, 2.5)
	local boxCFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5 - 0.3, 0)
	local overlapping = workspace:GetPartBoundsInBox(boxCFrame, boxSize, characterRefillOverlapParams :: OverlapParams)
	for _, inst in overlapping do
		if inst:IsA("BasePart") then
			return inst
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { folder }
	local rayOrigin = root.Position + Vector3.new(0, 4, 0)
	local rayLen = math.max(12, GameConfig.Paving.RefillSurfaceRayLength or 80)
	local rayDirection = Vector3.new(0, -rayLen, 0)
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local hit = rayResult and rayResult.Instance
	if hit and hit:IsA("BasePart") then
		return hit
	end
	return nil
end

-- Islands 下用于日志展示的名称：取命中部件在 Islands 下的第一层祖先（通常为单岛 Model/Folder 名）。
local function GetIslandSubRootNameForLog(hit: BasePart, islandsFolder: Instance): string
	local current: Instance? = hit
	while current and current ~= islandsFolder do
		if current.Parent == islandsFolder then
			return current.Name
		end
		current = current.Parent
	end
	return islandsFolder.Name
end

-- 补砖合法区域（与客户端 Ground/Islands/起点 对齐）；用于校验 Remote 与日志地点名
local function ResolveRefillLocation(player: Player): string?
	if _IsPlayerOverlappingStartTrigger(player) then
		return "起点"
	end
	local groundFolder = workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
	if groundFolder and GetCharacterRefillSurfaceHit(player, groundFolder) ~= nil then
		return "Ground"
	end
	local islandsFolder = workspace:FindFirstChild("Islands")
	if islandsFolder then
		local islandHit = GetCharacterRefillSurfaceHit(player, islandsFolder)
		if islandHit then
			local subName = GetIslandSubRootNameForLog(islandHit, islandsFolder)
			return "岛屿:" .. subName
		end
	end
	return nil
end

local function OnHeartbeat(deltaTime: number)
	local now = os.clock()
	for brick, data in pairs(activeBricks) do
		if now >= data.ExpireTime then
			if not data.IsGhost then
				-- 转变为幽灵状态
				data.IsGhost = true
				data.ExpireTime = now + GHOST_DURATION
				UpdateBrickVisual(brick, true)
			else
				-- 幽灵状态也到期，彻底移除（寿命到期的砖在地震期间也按原逻辑正常结束）
				ReturnBrickToPool(brick)
			end
		end
	end
end

local function OnRequestStartPaving(player: Player)
	local location = ResolveRefillLocation(player)
	if location == nil then
		--warn("[PavingManager] 拒绝补砖: 未在合法区域", player.Name)
		return
	end
	local before = ServerGameInfo.GetPlayerCarriedBricks(player)
	local maxBricks = ServerGameInfo.GetPlayerMaxBricks(player)
	if before >= maxBricks then
		print("[PavingManager] 补砖", player.Name, "携带砖已满 地点", location, "当前", before)
		return
	end
	ServerGameInfo.SetPlayerBricksToMax(player)
	local added = maxBricks - before
	print("[PavingManager] 补砖", player.Name, "增加砖块", added, "地点", location)
end

workspace:GetAttributeChangedSignal("EarthquakeActive"):Connect(function()
	local earthquakeActiveNow = workspace:GetAttribute("EarthquakeActive") == true
	if not lastEarthquakeActive and earthquakeActiveNow then
		table.clear(playerLastPlacedBrickMap)
	end
	lastEarthquakeActive = earthquakeActiveNow
end)

NetMsg.ConnectRequestStartPaving(OnRequestStartPaving)
NetMsg.ConnectRequestPlaceBrickBatch(OnRequestPlaceBrickBatch)
runService.Heartbeat:Connect(OnHeartbeat)

local function OnEarthquakeDropBrick(brick: Part)
	local key = GetPosKey(brick.Position)
	if activeBricksGrid[key] == brick then
		activeBricksGrid[key] = nil
	end
	local ownerUserId = brick:GetAttribute("PavingOwnerUserId")
	if type(ownerUserId) == "number" and playerLastPlacedBrickMap[ownerUserId] == brick then
		playerLastPlacedBrickMap[ownerUserId] = nil
	end
	activeBricks[brick] = nil
end

local function ReleaseBrickAfterEarthquake(brick: Part)
	ReturnBrickToPool(brick)
end

local function RefreshProtectedPavedBrickAfterEarthquake(brick: Part)
	local data = activeBricks[brick]
	if data == nil then
		return
	end
	data.IsGhost = false
	data.ExpireTime = os.clock() + GameConfig.Paving.BaseCollapseTime
	UpdateBrickVisual(brick, false)
end

local function GetEarthquakeProtectedPavedBricks(): { [Part]: true }
	local result: { [Part]: true } = {}
	for _, brick in pairs(playerLastPlacedBrickMap) do
		if brick.Parent ~= nil then
			result[brick] = true
		end
	end
	return result
end

local PavingEarthquakeBridge = require(serverScripts:WaitForChild("PavingEarthquakeBridge")) :: any
PavingEarthquakeBridge.RegisterReleasePavedBrickAfterEarthquake(ReleaseBrickAfterEarthquake)
PavingEarthquakeBridge.RegisterOnEarthquakeDropBrick(OnEarthquakeDropBrick)
PavingEarthquakeBridge.RegisterGetEarthquakeProtectedPavedBricks(GetEarthquakeProtectedPavedBricks)
PavingEarthquakeBridge.RegisterRefreshProtectedPavedBrickAfterEarthquake(RefreshProtectedPavedBrickAfterEarthquake)

players.PlayerRemoving:Connect(function(player)
	playerLastBatchTimeMap[player.UserId] = nil
	playerInFlightBatchMap[player.UserId] = nil
	playerLastPlacedBrickMap[player.UserId] = nil
end)
