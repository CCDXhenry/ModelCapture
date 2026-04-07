--!strict
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayer = players.LocalPlayer
local lastPavePosition: Vector3? = nil
local SEA_LEVEL = 0
local isPavingMode = false
local isAwaitingRescue = false
local stationaryTime = 0
local lastStationaryPos: Vector3? = nil
local lastRefillTime = 0
-- 区域补砖（Ground/Islands）共享全局节流，避免同帧重复发送。
local lastZoneRefillTime = 0

-- 跟踪地震状态切换，用于在地震结束瞬间做运行态清理。
local lastEarthquakeActive = workspace:GetAttribute("EarthquakeActive") == true

-- Local prediction config
local LOCAL_PREDICT_TTL = GameConfig.Paving.LocalPredictTTL
local LOCAL_PREDICT_BATCH_INTERVAL = GameConfig.Paving.BatchInterval
local MAX_INTERPOLATION_STEPS = GameConfig.Paving.MaxInterpolationSteps
local LOCAL_PREDICT_SUPPORT_GRACE = 0.6
local MAX_LOCAL_PREDICT_SUPPORT_TIME = LOCAL_PREDICT_TTL + LOCAL_PREDICT_SUPPORT_GRACE
local SHOW_LOCAL_PREDICT_ATTR = "PavingShowLocalPredictBricks"
local LOCAL_PREDICT_VISIBLE_TRANSPARENCY = 0.5
local LOCAL_PREDICT_HIDDEN_TRANSPARENCY = 1
local DEBUG_AUTO_QUEUE_GATE_ATTR = "PavingDebugAutoQueueGate"

local localBrickFolder = Instance.new("Folder")
localBrickFolder.Name = "LocalPredictBricks"
localBrickFolder.Parent = workspace

local modelsFolder = replicatedStorage:WaitForChild("Models")
local bricksFolder = modelsFolder:WaitForChild("Bricks")
local brickTemplate = bricksFolder:WaitForChild("Brick1") :: Part
local GRID_SIZE = brickTemplate.Size.X

type LocalPredictEntry = {
	part: Part,
	createdAt: number,
	requested: boolean,
	resolved: boolean,
	lastRequestAt: number?,
	lastBatchId: number?,
}
type PendingBatchInfo = {
	sentAt: number,
	positions: { Vector3 },
	keys: { [string]: boolean },
}
local localBrickMap: { [string]: LocalPredictEntry } = {}
local touchConns: { [Part]: RBXScriptConnection } = {}
local localBrickPool: { Part } = {}
local pendingPaveQueue: { Vector3 } = {}
local lastBatchTime = 0
local pendingBatchMap: { [number]: PendingBatchInfo } = {}
local nextBatchId = 1
local unresolvedRequestedCount = 0
local firstBrickFallbackAt = 0
local previousFrameInSafeZone = true
local MAX_PENDING_BATCHES = GameConfig.Paving.MaxPendingBatches or 4
local BATCH_ACK_TIMEOUT = GameConfig.Paving.BatchAckTimeout or 0.9
local FIRST_BRICK_FORCE_QUEUE_COOLDOWN = GameConfig.Paving.FirstBrickForceQueueCooldown or 0.12

local function IsLocalPredictVisible(): boolean
	local attr = workspace:GetAttribute(SHOW_LOCAL_PREDICT_ATTR)
	if type(attr) == "boolean" then
		return attr
	end
	return true
end

local function GetLocalPredictTransparency(): number
	return if IsLocalPredictVisible() then LOCAL_PREDICT_VISIBLE_TRANSPARENCY else LOCAL_PREDICT_HIDDEN_TRANSPARENCY
end

local function ApplyLocalPredictDisplay(part: Part)
	part.Transparency = GetLocalPredictTransparency()
end

-- Object pool management
local function GetBrickFromPool(): Part
	local pooledBrick = table.remove(localBrickPool)
	if pooledBrick then
		ApplyLocalPredictDisplay(pooledBrick)
		pooledBrick.Parent = localBrickFolder
		return pooledBrick
	end

	local newBrick = brickTemplate:Clone()
	newBrick.Name = "LocalPredictBrick"
	newBrick.Size = brickTemplate.Size
	newBrick.Anchored = true
	newBrick.CanCollide = true
	newBrick.CanQuery = false
	ApplyLocalPredictDisplay(newBrick)
	newBrick.CastShadow = false
	newBrick:SetAttribute("IsLocal", true)
	newBrick.Parent = localBrickFolder
	return newBrick
end

workspace:GetAttributeChangedSignal(SHOW_LOCAL_PREDICT_ATTR):Connect(function()
	local transparency = GetLocalPredictTransparency()
	for _, entry in pairs(localBrickMap) do
		entry.part.Transparency = transparency
	end
	for _, pooledPart in ipairs(localBrickPool) do
		pooledPart.Transparency = transparency
	end
end)

local function ReturnBrickToPool(brick: Part)
	brick.Parent = nil
	if touchConns[brick] then
		touchConns[brick]:Disconnect()
		touchConns[brick] = nil
	end
	table.insert(localBrickPool, brick)
end

-- 探测配置路径
local startPointFolder = workspace:FindFirstChild("StartPoint")
local startPointModel = if startPointFolder then startPointFolder:FindFirstChild("StartPointModel") :: Model else nil
local startTrigger = if startPointModel then startPointModel:FindFirstChild("StartTrigger") :: Part else nil
local startAttachment = if startTrigger then startTrigger:FindFirstChild("Attachment") :: Attachment else nil

local startTriggerOverlapParams: OverlapParams? = nil
local function IsLocalCharacterTouchingStartTrigger(character: Model): boolean
	if not startTrigger then
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

if startAttachment then
	SEA_LEVEL = startAttachment.WorldPosition.Y
end

-- Ground：客户端请求服务端同步携带砖数（刷新 UI），与 StartTrigger 门禁/模式激活无关
local function GetGroundFolder(): Instance?
	return workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
end

local function IsLocalCarriedBricksFull(): boolean
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return false
	end

	local currentBricks = playerInfo.carriedInfo.bricks
	local maxBricksLevel = if playerInfo.shopInfo then playerInfo.shopInfo.maxBricksLevel else 1

	local maxBricks = 0
	local maxBricksConfig = GameConfig.Shop and GameConfig.Shop.MaxBricks
	if maxBricksConfig and maxBricksConfig.abilityList then
		maxBricks = maxBricksConfig.abilityList[maxBricksLevel]
			or maxBricksConfig.abilityList[maxBricksConfig.maxLevel]
			or maxBricksConfig.abilityList[1]
			or 0
	end

	return currentBricks == maxBricks
end

local function GetIslandsFolder(): Instance?
	return workspace:FindFirstChild("Islands")
end

type RefillZoneState = {
	name: string,
	folderResolver: () -> Instance?,
	touchConns: { [BasePart]: RBXScriptConnection },
	hookedFolder: Instance?,
	overlapParams: OverlapParams?,
	lastTouchRefillTime: number,
	lastPollRefillTime: number,
	wasInZoneLastFrame: boolean,
}

local refillZoneStates: { RefillZoneState } = {
	{
		name = "Ground",
		folderResolver = GetGroundFolder,
		touchConns = {},
		hookedFolder = nil,
		overlapParams = nil,
		lastTouchRefillTime = 0,
		lastPollRefillTime = 0,
		wasInZoneLastFrame = false,
	},
	{
		name = "Islands",
		folderResolver = GetIslandsFolder,
		touchConns = {},
		hookedFolder = nil,
		overlapParams = nil,
		lastTouchRefillTime = 0,
		lastPollRefillTime = 0,
		wasInZoneLastFrame = false,
	},
}

local function IsLocalCharacterOnRefillZone(character: Model, zoneState: RefillZoneState): boolean
	local folder = zoneState.folderResolver()
	if not folder then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	if not zoneState.overlapParams then
		local p = OverlapParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		zoneState.overlapParams = p
	end
	(zoneState.overlapParams :: OverlapParams).FilterDescendantsInstances = { folder }
	local boxSize = Vector3.new(2.5, 1.2, 2.5)
	local boxCFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5 - 0.3, 0)
	local overlapping = workspace:GetPartBoundsInBox(boxCFrame, boxSize, zoneState.overlapParams :: OverlapParams)
	if #overlapping > 0 then
		return true
	end

	-- 兜底：部分岛屿网格较薄/形状不规则时，盒体可能漏检，增加向下射线判定（长度与服务端补砖校验一致）。
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { folder }
	local rayOrigin = root.Position + Vector3.new(0, 4, 0)
	local rayLen = math.max(12, GameConfig.Paving.RefillSurfaceRayLength or 80)
	local rayDirection = Vector3.new(0, -rayLen, 0)
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil
end

local function IsRefillDebugEnabled(): boolean
	return workspace:GetAttribute("PavingDebugRefillTrigger") == true
end

-- Touch/Poll/进入区域共享入口，统一做满砖检查与节流。
local function TryRequestRefill(reason: string, zoneState: RefillZoneState, now: number): boolean
	if IsLocalCarriedBricksFull() then
		return false
	end

	local touchCooldown = GameConfig.Paving.GroundTouchRefillCooldown
	local globalCooldown = touchCooldown
	if now - lastZoneRefillTime < globalCooldown then
		return false
	end

	if reason == "poll" then
		local pollInterval = math.max(GameConfig.Paving.GroundPollRefillInterval or 2, 1.5)
		if now - zoneState.lastPollRefillTime < pollInterval then
			return false
		end
		zoneState.lastPollRefillTime = now
	else
		if now - zoneState.lastTouchRefillTime < touchCooldown then
			return false
		end
		zoneState.lastTouchRefillTime = now
	end

	lastZoneRefillTime = now
	NetMsg.FireRequestStartPaving()
	if IsRefillDebugEnabled() then
		print(string.format("[PavingClient][Refill] reason=%s zone=%s", reason, zoneState.name))
	end
	return true
end

local function HookZonePartForUiTouch(part: BasePart, zoneState: RefillZoneState)
	if zoneState.touchConns[part] then
		return
	end
	zoneState.touchConns[part] = part.Touched:Connect(function(otherPart)
		local char = localPlayer.Character
		if not char or not otherPart:IsDescendantOf(char) then
			return
		end
		TryRequestRefill("touch", zoneState, os.clock())
	end)
	part.Destroying:Connect(function()
		local c = zoneState.touchConns[part]
		if c then
			c:Disconnect()
			zoneState.touchConns[part] = nil
		end
	end)
end

local function TryHookZoneFolderForUiSync(zoneState: RefillZoneState)
	local folder = zoneState.folderResolver()
	if not folder or zoneState.hookedFolder == folder then
		return
	end
	zoneState.hookedFolder = folder
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			HookZonePartForUiTouch(desc :: BasePart, zoneState)
		end
	end
	folder.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			HookZonePartForUiTouch(desc :: BasePart, zoneState)
		end
	end)
	folder.Destroying:Connect(function()
		if zoneState.hookedFolder == folder then
			zoneState.hookedFolder = nil
		end
	end)
end

local function TryHookAllRefillZonesForUiSync()
	for _, zoneState in ipairs(refillZoneStates) do
		TryHookZoneFolderForUiSync(zoneState)
	end
end

local function ResetRefillZoneRuntimeState()
	for _, zoneState in ipairs(refillZoneStates) do
		zoneState.wasInZoneLastFrame = false
	end
	lastZoneRefillTime = 0
end

local function GetSnappedPosition(pos: Vector3)
	local x = math.floor(pos.X / GRID_SIZE + 0.5) * GRID_SIZE
	local z = math.floor(pos.Z / GRID_SIZE + 0.5) * GRID_SIZE
	return Vector3.new(x, SEA_LEVEL, z)
end

local function GetPosKey(pos: Vector3)
	return string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z)
end

local function GetCurrentWalkSpeed(): number
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if playerInfo and playerInfo.shopInfo then
		local level = playerInfo.shopInfo.walkSpeedLevel or 1
		local speedList = GameConfig.Shop.WalkSpeed.abilityList
		return speedList[level] or 16
	end
	return 16
end

local function GetEquippedToolName(character: Model?): string?
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			return child.Name
		end
	end
	return nil
end

local function IsHoldingExtraJumpCoil(character: Model?): boolean
	local toolName = GetEquippedToolName(character)
	if not toolName then
		return false
	end
	local coilData = GameConfig.CoilNameMap[toolName]
	if not coilData then
		return false
	end
	return (coilData.extraJumps or 0) > 0
end

-- Efficient removal
local function RemoveLocalBrickEntry(key: string)
	local entry = localBrickMap[key]
	if entry then
		if entry.requested and not entry.resolved then
			unresolvedRequestedCount = math.max(unresolvedRequestedCount - 1, 0)
		end
		if entry.part then
			ReturnBrickToPool(entry.part)
		end
		localBrickMap[key] = nil
	end
end

local function ClearLocalBricks()
	if not next(localBrickMap) then
		return
	end
	for key, entry in pairs(localBrickMap) do
		if entry.part then
			ReturnBrickToPool(entry.part)
		end
	end
	table.clear(localBrickMap)
	table.clear(pendingPaveQueue)
	table.clear(pendingBatchMap)
	unresolvedRequestedCount = 0
	print("[PavingClient] Cleared all local prediction bricks and queue")
end

local function ResetPavingRuntimeState()
	lastPavePosition = nil
	stationaryTime = 0
	lastStationaryPos = nil
	lastBatchTime = 0
	firstBrickFallbackAt = 0
	previousFrameInSafeZone = true
	table.clear(pendingPaveQueue)
end

-- Check if brick exists (excluding local predictions)
local function CheckBrickExists(targetPos: Vector3): boolean
	local checkOrigin = targetPos + Vector3.new(0, 5, 0)
	local checkDir = Vector3.new(0, -10, 0)
	local checkParams = RaycastParams.new()
	checkParams.FilterType = Enum.RaycastFilterType.Include
	local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
	checkParams.FilterDescendantsInstances = { pavedBricksFolder }

	local checkResult = workspace:Raycast(checkOrigin, checkDir, checkParams)
	if checkResult and checkResult.Instance and checkResult.Position.Y >= SEA_LEVEL - 0.5 then
		if checkResult.Instance:GetAttribute("IsGhost") == true then
			return false
		end
		if checkResult.Instance:GetAttribute("EarthquakeDropped") == true then
			return false
		end
		return true
	end
	return false
end

local FLOATBLOCK_RAY_ORIGIN_Y = 50
local FLOATBLOCK_RAY_LENGTH = 60

local function RaycastFloatBlockAtPoint(pos: Vector3): RaycastResult?
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if not floatBlockFolder then
		return nil
	end
	local rayOrigin = pos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floatBlockFolder }
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

-- FloatBlock：单点竖直射线；四角全命中才视为整块在禁区（与服务端一致）
local function IsPointOverFloatBlock(pos: Vector3): boolean
	return RaycastFloatBlockAtPoint(pos) ~= nil
end

local function GetFloatBlockAtPoint(pos: Vector3): BasePart?
	local result = RaycastFloatBlockAtPoint(pos)
	if result and result.Instance and result.Instance:IsA("BasePart") then
		return result.Instance
	end
	return nil
end

local function IsEntireBrickFootprintOverFloatBlock(center: Vector3): boolean
	local size = brickTemplate.Size
	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	local y = center.Y
	local corners = {
		Vector3.new(center.X - hx, y, center.Z - hz),
		Vector3.new(center.X + hx, y, center.Z - hz),
		Vector3.new(center.X - hx, y, center.Z + hz),
		Vector3.new(center.X + hx, y, center.Z + hz),
	}
	for _, p in corners do
		if not IsPointOverFloatBlock(p) then
			return false
		end
	end
	return true
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

local function IsPointOverSafeZone(pos: Vector3): boolean
	local filterInstances = GetSafeZoneFilterInstances()
	local rayOrigin = pos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	if #filterInstances > 0 then
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = filterInstances
		if workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil then
			return true
		end
	end

	local floatHit = RaycastFloatBlockAtPoint(pos)
	if
		floatHit
		and floatHit.Instance
		and floatHit.Instance:GetAttribute("EarthquakeMarkedForDrop") ~= true
		and floatHit.Instance:GetAttribute("EarthquakeDropped") ~= true
	then
		return true
	end

	return false
end

-- 铺砖自动入队专用安全区判定：仅 Ground/Islands/PlayersHome 计入，不包含 FloatBlock。
local function IsPointOverPavingGateSafeZone(pos: Vector3): boolean
	local filterInstances = GetSafeZoneFilterInstances()
	if #filterInstances == 0 then
		return false
	end
	local rayOrigin = pos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = filterInstances
	return workspace:Raycast(rayOrigin, rayDirection, raycastParams) ~= nil
end

local function IsEntireBrickFootprintOverPavingGateSafeZone(center: Vector3): boolean
	local size = brickTemplate.Size
	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	local y = center.Y
	local corners = {
		Vector3.new(center.X - hx, y, center.Z - hz),
		Vector3.new(center.X + hx, y, center.Z - hz),
		Vector3.new(center.X - hx, y, center.Z + hz),
		Vector3.new(center.X + hx, y, center.Z + hz),
	}
	for _, p in corners do
		if not IsPointOverPavingGateSafeZone(p) then
			return false
		end
	end
	return true
end

local function IsDebugAutoQueueEnabled(): boolean
	return workspace:GetAttribute(DEBUG_AUTO_QUEUE_GATE_ATTR) == true
end

local function DebugAutoQueueDecision(
	stage: string,
	targetPos: Vector3,
	rootPart: BasePart?,
	requireTouchTrigger: boolean,
	forceQueue: boolean?,
	inPavingGateSafeZone: boolean
)
	if not IsDebugAutoQueueEnabled() then
		return
	end
	local distanceToTarget = -1
	if rootPart then
		distanceToTarget = (targetPos - rootPart.Position).Magnitude
	end
	print(
		string.format(
			"[PavingClient][AutoQueue] stage=%s force=%s touchOnly=%s inGateSafeZone=%s target=(%.1f,%.1f,%.1f) dist=%.2f",
			stage,
			tostring(forceQueue == true),
			tostring(requireTouchTrigger),
			tostring(inPavingGateSafeZone),
			targetPos.X,
			targetPos.Y,
			targetPos.Z,
			distanceToTarget
		)
	)
end

-- 与服务端一致：预警～地震结束期间允许在 FloatBlock 上铺砖
local function IsFloatBlockBlockingPaving(center: Vector3): boolean
	if workspace:GetAttribute("EarthquakeRescuePaving") == true then
		return false
	end
	return IsEntireBrickFootprintOverFloatBlock(center)
end

local function HasSolidGroundAt(samplePos: Vector3): boolean
	local key = GetPosKey(GetSnappedPosition(samplePos))
	if localBrickMap[key] then
		return true
	end

	local rayOrigin = samplePos + Vector3.new(0, 5, 0)
	local rayDir = Vector3.new(0, -10, 0)

	local groundFilterInstances = GetSafeZoneFilterInstances()
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
	local filterList: { Instance } = {}
	for _, inst in groundFilterInstances do
		table.insert(filterList, inst)
	end
	if floatBlockFolder then
		table.insert(filterList, floatBlockFolder)
	end
	if pavedBricksFolder then
		table.insert(filterList, pavedBricksFolder)
	end
	if #filterList == 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(rayOrigin, rayDir, params)
	if result and result.Instance and result.Position.Y >= SEA_LEVEL - 1 then
		if result.Instance:GetAttribute("EarthquakeDropped") == true then
			return false
		end
		return true
	end
	return false
end

local function SendAllPendingPaveBatches()
	if #pendingPaveQueue <= 0 then
		return
	end
	local pendingCount = 0
	for _ in pairs(pendingBatchMap) do
		pendingCount += 1
	end
	if pendingCount >= MAX_PENDING_BATCHES then
		return
	end
	local maxBatchSize = GameConfig.Paving.MaxBatchSize
	local queueIndex = 1
	local originalCount = #pendingPaveQueue
	while queueIndex <= originalCount and pendingCount < MAX_PENDING_BATCHES do
		local endIndex = math.min(queueIndex + maxBatchSize - 1, originalCount)
		local batchChunk = table.move(pendingPaveQueue, queueIndex, endIndex, 1, {})
		local batchId = nextBatchId
		nextBatchId += 1
		local keys: { [string]: boolean } = {}
		local sentAt = os.clock()
		for _, pos in ipairs(batchChunk) do
			local key = GetPosKey(pos)
			keys[key] = true
			local entry = localBrickMap[key]
			if entry then
				entry.lastRequestAt = sentAt
				entry.lastBatchId = batchId
			end
		end
		pendingBatchMap[batchId] = {
			sentAt = sentAt,
			positions = batchChunk,
			keys = keys,
		}
		NetMsg.FireRequestPlaceBrickBatch(batchChunk, batchId, sentAt)
		pendingCount += 1
		queueIndex = endIndex + 1
	end
	if queueIndex > 1 then
		local remain = if queueIndex <= originalCount then table.move(pendingPaveQueue, queueIndex, originalCount, 1, {}) else {}
		table.clear(pendingPaveQueue)
		for _, pos in ipairs(remain) do
			table.insert(pendingPaveQueue, pos)
		end
	end
end

local function FlushPendingPaveQueue()
	if #pendingPaveQueue <= 0 then
		return
	end
	SendAllPendingPaveBatches()
	lastBatchTime = os.clock()
end

local function IsCharacterStandingOnLocalBrick(brick: Part, character: Model?): boolean
	if not character then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { character }
	local expandedSize = brick.Size + Vector3.new(0, 3, 0)
	local overlapParts = workspace:GetPartBoundsInBox(brick.CFrame, expandedSize, overlapParams)
	return #overlapParts > 0
end

local function IsEntireBrickFootprintOverSafeZone(center: Vector3): boolean
	local size = brickTemplate.Size
	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	local y = center.Y
	local corners = {
		Vector3.new(center.X - hx, y, center.Z - hz),
		Vector3.new(center.X + hx, y, center.Z - hz),
		Vector3.new(center.X - hx, y, center.Z + hz),
		Vector3.new(center.X + hx, y, center.Z + hz),
	}
	for _, p in corners do
		if not IsPointOverSafeZone(p) then
			return false
		end
	end
	return true
end

-- requireTouchTrigger：多段跳弹簧，仅触碰/重叠预测砖入队。
-- 非多段跳：水平逻辑产生的预测砖仅在“铺砖门禁安全区”外自动入队；触碰预测砖始终可入队（防掉落）。
local function RequestPlaceBrick(targetPos: Vector3, requireTouchTrigger: boolean, forceQueue: boolean?)
	local now = os.clock()
	local key = GetPosKey(targetPos)
	local existed = localBrickMap[key]
	if existed then
		if forceQueue == true and ((not existed.requested) or existed.resolved) then
			existed.requested = true
			existed.resolved = false
			existed.lastRequestAt = now
			unresolvedRequestedCount += 1
			table.insert(pendingPaveQueue, targetPos)
		end
		return
	end

	local brick = GetBrickFromPool()
	brick.Position = targetPos

	localBrickMap[key] = {
		part = brick,
		createdAt = now,
		requested = false,
		resolved = false,
	}

	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart

	local inPavingGateSafeZone = IsEntireBrickFootprintOverPavingGateSafeZone(targetPos)

	local function triggerPave()
		local entry = localBrickMap[key]
		if entry and not entry.requested then
			entry.requested = true
			entry.resolved = false
			unresolvedRequestedCount += 1
			table.insert(pendingPaveQueue, targetPos)
		end
	end

	local function hookTouchAndOverlapAlways()
		touchConns[brick] = brick.Touched:Connect(function(otherPart)
			if character and otherPart:IsDescendantOf(character) then
				triggerPave()
			end
		end)

		if character and not inPavingGateSafeZone then
			local overlapParts = workspace:GetPartBoundsInBox(brick.CFrame, brick.Size)
			for _, part in overlapParts do
				if part:IsDescendantOf(character) then
					triggerPave()
					break
				end
			end
		end
	end

	if requireTouchTrigger then
		hookTouchAndOverlapAlways()
		if forceQueue == true then
			DebugAutoQueueDecision("touchOnly_force", targetPos, rootPart, requireTouchTrigger, forceQueue, inPavingGateSafeZone)
			triggerPave()
		end
		return
	end

	hookTouchAndOverlapAlways()
	if forceQueue == true or not inPavingGateSafeZone then
		DebugAutoQueueDecision("auto_or_force", targetPos, rootPart, requireTouchTrigger, forceQueue, inPavingGateSafeZone)
		triggerPave()
	else
		DebugAutoQueueDecision("blocked_by_gate_safe_zone", targetPos, rootPart, requireTouchTrigger, forceQueue, inPavingGateSafeZone)
	end
end

local function OnHeartbeat(dt: number)
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid

	-- 1. Hard cleanup conditions (Death/Falling/Invalid state)
	local now = os.clock()
	local pos = if rootPart then rootPart.Position else nil
	local requireTouchTrigger = IsHoldingExtraJumpCoil(character)
	local earthquakeActiveNow = workspace:GetAttribute("EarthquakeActive") == true
	if lastEarthquakeActive and not earthquakeActiveNow then
		-- 地震结束后不再因“当前不在安全区”强制关闭铺砖模式。
		-- 是否可落砖继续由后续位置合法性与服务端校验控制。
	end
	lastEarthquakeActive = earthquakeActiveNow
	-- 调整死亡判定阈值：使用统一配置
	local isFallingIntoSea = pos and pos.Y < SEA_LEVEL + GameConfig.Paving.DeathThreshold
	local isDeadOrFalling = not rootPart or not humanoid or isFallingIntoSea or (humanoid and humanoid.Health <= 0)

	if isAwaitingRescue then
		if pos and pos.Y >= SEA_LEVEL + GameConfig.Paving.DeathThreshold then
			isAwaitingRescue = false
		end
		return
	end

	if isDeadOrFalling then
		-- 如果是落水且还没死，尝试开启救援流程
		if isFallingIntoSea and humanoid and humanoid.Health > 0 and not isAwaitingRescue then
			isAwaitingRescue = true
			rootPart.Anchored = true
			humanoid.PlatformStand = true
			ClientMsg.FireShowRescuePopup()
			return
		end

		if isPavingMode then
			isPavingMode = false
			ResetPavingRuntimeState()
			print("[PavingClient] Mode reset due to death/falling")
		end
		ClearLocalBricks()
		ResetPavingRuntimeState()
		return
	end

	-- 2. Mode Activation Check (Start Trigger or Safe Zone)
	if pos and character then
		local inStartRange = IsLocalCharacterTouchingStartTrigger(character)
		local inSafeZone = false
		if not inStartRange then
			inSafeZone = IsEntireBrickFootprintOverSafeZone(GetSnappedPosition(pos))
		end

		if inStartRange or inSafeZone then
			if not isPavingMode then
				isPavingMode = true
				--print("[PavingClient] Mode activated")

				-- 【新增】：如果有惯性方向，额外在前方一格预铺一块
				local velocity = rootPart.AssemblyLinearVelocity
				if velocity.Magnitude > 1 then
					local horizUnit = Vector3.new(velocity.X, 0, velocity.Z).Unit
					local forwardSnapped = GetSnappedPosition(pos + horizUnit * GRID_SIZE)
					RequestPlaceBrick(forwardSnapped, requireTouchTrigger)
				end

				lastBatchTime = 0
			end

			if inStartRange then
				local refillCooldown = GameConfig.Paving.StartTriggerRefillCooldown or 0.35
				if now - lastRefillTime > refillCooldown then
					NetMsg.FireRequestStartPaving()
					lastRefillTime = now
				end
			end
		end
	end

	-- Ground / Islands：统一补砖触发，Touch 优先，轮询兜底。
	if character and rootPart and humanoid and humanoid.Health > 0 then
		local pollInterval = math.max(GameConfig.Paving.GroundPollRefillInterval or 2, 1.5)
		for _, zoneState in ipairs(refillZoneStates) do
			local inZone = IsLocalCharacterOnRefillZone(character, zoneState)
			if inZone and not zoneState.wasInZoneLastFrame then
				-- 进入补砖区时立刻尝试，减少仅靠触碰导致的漏补。
				TryRequestRefill("enter", zoneState, now)
			end
			if inZone and now - zoneState.lastPollRefillTime >= pollInterval then
				TryRequestRefill("poll", zoneState, now)
			end
			zoneState.wasInZoneLastFrame = inZone
		end
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()

	-- 4. Execution Guard (If still not in paving mode, stop here)
	if not isPavingMode or not pos or not rootPart or not humanoid then
		return
	end

	if rootPart.Anchored then
		return
	end

	local serverBricks = if playerInfo then playerInfo.carriedInfo.bricks else 0
	local isOutOfBricks = serverBricks <= 0
	local feetPosForState = GetSnappedPosition(pos)
	local currentFrameInSafeZone = IsEntireBrickFootprintOverSafeZone(feetPosForState)

	if not isOutOfBricks then
		-- 4a. Feet Guard: 检测脚下是否有有效地面，无地面时立即铺砖
		local feetPos = feetPosForState
		local feetFloatBlock = GetFloatBlockAtPoint(feetPos)
		local onDangerousFloatBlock = false
		if feetFloatBlock ~= nil then
			onDangerousFloatBlock = feetFloatBlock:GetAttribute("EarthquakeMarkedForDrop") == true
				or feetFloatBlock:GetAttribute("EarthquakeDropped") == true
		end
		local noGroundUnderFeet = not HasSolidGroundAt(pos)
		local allowEmergencyPaving = onDangerousFloatBlock and serverBricks > 0
		if noGroundUnderFeet then
			if not CheckBrickExists(feetPos) and (allowEmergencyPaving or not IsFloatBlockBlockingPaving(feetPos)) then
				-- 空中脚下无地时，强制请求脚下砖，避免跳跃与安全区边缘漏首块/尾块
				RequestPlaceBrick(feetPos, requireTouchTrigger, true)
				FlushPendingPaveQueue()
			end
		end
		-- 从安全区跃迁到海面且脚下无地时，强制首格入队并立刻同步，避免首块漏铺
		if previousFrameInSafeZone and not currentFrameInSafeZone and (now - firstBrickFallbackAt) >= FIRST_BRICK_FORCE_QUEUE_COOLDOWN then
			if noGroundUnderFeet then
				firstBrickFallbackAt = now
				RequestPlaceBrick(feetPos, requireTouchTrigger, true)
				FlushPendingPaveQueue()
			end
		end

		-- 4b. Paving logic calculation (基于物理惯性的方向预判)
		local velocity = rootPart.AssemblyLinearVelocity
		local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = horizontalVelocity.Magnitude

		-- 核心修改：优先使用实际物理运动方向
		local moveDir: Vector3
		if speed > 0.5 then
			moveDir = horizontalVelocity.Unit -- 有惯性速度时，严格按照飞行的物理方向铺砖
		elseif humanoid.MoveDirection.Magnitude > 0.1 then
			moveDir = humanoid.MoveDirection -- 刚起步速度还不够时，使用按键方向
		else
			-- 完全静止时，使用玩家的面朝方向（过滤掉Y轴）
			local lookVec = rootPart.CFrame.LookVector
			moveDir = Vector3.new(lookVec.X, 0, lookVec.Z).Unit
		end

		local isStationary = speed < 0.1
		local playerWalkSpeed = GetCurrentWalkSpeed()
		local lookaheadFactor = math.clamp(speed / math.max(1, playerWalkSpeed), 1.0, GameConfig.Paving.HighSpeedLookaheadMaxFactor or 2.2)
		local targetPos = if isStationary then GetSnappedPosition(pos) else GetSnappedPosition(pos + moveDir * (GRID_SIZE * lookaheadFactor))

		-- [优化] Stationary renewal (防止原地发呆无限扣砖)
		local RENEWAL_INTERVAL = GameConfig.Paving.StationaryRenewalInterval or 0.2
		if isStationary then
			if lastStationaryPos and (targetPos - lastStationaryPos).Magnitude < 0.1 then
				stationaryTime += dt
				if stationaryTime >= RENEWAL_INTERVAL then
					stationaryTime = 0
					-- 加上射线检测与安全区检测
					if not IsEntireBrickFootprintOverSafeZone(targetPos) and not IsFloatBlockBlockingPaving(targetPos) and not CheckBrickExists(targetPos) then
						RequestPlaceBrick(targetPos, requireTouchTrigger)
					end
				end
			else
				lastStationaryPos = targetPos
				stationaryTime = 0
				-- [顺发] 当检测到刚停下时，立即尝试续期一次，不再等待计时器
				if not IsEntireBrickFootprintOverSafeZone(targetPos) and not IsFloatBlockBlockingPaving(targetPos) and not CheckBrickExists(targetPos) then
					RequestPlaceBrick(targetPos, requireTouchTrigger)
				end
			end
		else
			stationaryTime = 0
			lastStationaryPos = nil
		end

		-- Movement paving with interpolation
		if lastPavePosition then
			local diff = targetPos - lastPavePosition
			local dist = diff.Magnitude

			if dist < GRID_SIZE * 0.75 then
			-- No action
			elseif dist > GRID_SIZE * 1.05 then
				local dynamicMaxSteps = MAX_INTERPOLATION_STEPS
				if speed > playerWalkSpeed * 1.25 then
					dynamicMaxSteps = GameConfig.Paving.MaxInterpolationStepsAtHighSpeed or dynamicMaxSteps
				end
				local stepCount = math.clamp(math.floor(dist / GRID_SIZE), 1, dynamicMaxSteps)
				local unitDir = diff.Unit
				local startPos = lastPavePosition
				for i = 1, stepCount do
					local interimPos = GetSnappedPosition(startPos + unitDir * (i * GRID_SIZE))
					if
						not IsEntireBrickFootprintOverSafeZone(interimPos)
						and not IsFloatBlockBlockingPaving(interimPos)
						and not CheckBrickExists(interimPos)
					then
						RequestPlaceBrick(interimPos, requireTouchTrigger)
					end
					lastPavePosition = interimPos
				end
			else
				if not IsEntireBrickFootprintOverSafeZone(targetPos) and not IsFloatBlockBlockingPaving(targetPos) and not CheckBrickExists(targetPos) then
					lastPavePosition = targetPos
					RequestPlaceBrick(targetPos, requireTouchTrigger)
				else
					lastPavePosition = targetPos
				end
			end
		else
			if not IsEntireBrickFootprintOverSafeZone(targetPos) and not IsFloatBlockBlockingPaving(targetPos) and not CheckBrickExists(targetPos) then
				lastPavePosition = targetPos
				RequestPlaceBrick(targetPos, requireTouchTrigger)
			end
		end
	else
		-- 无砖时不再发送续砖请求；是否可站立由砖本身是否已消失决定。
	end
	previousFrameInSafeZone = currentFrameInSafeZone

	-- [优化] Batch transmission (防止卡顿导致包过大被服务器拒收)
	if #pendingPaveQueue > 0 and (now - lastBatchTime >= LOCAL_PREDICT_BATCH_INTERVAL) then
		SendAllPendingPaveBatches()
		lastBatchTime = now
	end
	for batchId, info in pairs(pendingBatchMap) do
		if (now - info.sentAt) > BATCH_ACK_TIMEOUT then
			for key in pairs(info.keys) do
				local entry = localBrickMap[key]
				if entry and entry.lastBatchId == batchId and not entry.resolved then
					RemoveLocalBrickEntry(key)
				end
			end
			pendingBatchMap[batchId] = nil
		end
	end

	-- 6. Efficient TTL Cleanup (Safe pairs iteration)
	for key, entry in pairs(localBrickMap) do
		local aliveTime = now - entry.createdAt
		if aliveTime >= LOCAL_PREDICT_TTL then
			local waitingServerAck = entry.requested and not entry.resolved and (entry.lastRequestAt ~= nil)
			local keepForAck = waitingServerAck and (now - (entry.lastRequestAt :: number)) <= BATCH_ACK_TIMEOUT
			local shouldKeepForSupport = keepForAck or (aliveTime < MAX_LOCAL_PREDICT_SUPPORT_TIME and IsCharacterStandingOnLocalBrick(entry.part, character))
			if shouldKeepForSupport then
				continue
			end
			RemoveLocalBrickEntry(key)
		end
	end
end

runService.Heartbeat:Connect(OnHeartbeat)

local function MarkEntryResolved(entry: LocalPredictEntry)
	if entry.requested and not entry.resolved then
		entry.resolved = true
		unresolvedRequestedCount = math.max(unresolvedRequestedCount - 1, 0)
	end
end

NetMsg.ConnectNotifyPlaceBrickBatchResult(
	function(batchId: number, acceptedIndexes: { number }, rejectedList: { { index: number, reason: string } }, serverBricks: number, serverNow: number)
		local batchInfo = pendingBatchMap[batchId]
		if not batchInfo then
			return
		end

		for _, acceptedIndex in ipairs(acceptedIndexes) do
			local pos = batchInfo.positions[acceptedIndex]
			if pos then
				local key = GetPosKey(pos)
				local entry = localBrickMap[key]
				if entry then
					MarkEntryResolved(entry)
				end
			end
		end

		for _, rejected in ipairs(rejectedList) do
			local pos = batchInfo.positions[rejected.index]
			if pos then
				local key = GetPosKey(pos)
				RemoveLocalBrickEntry(key)
			end
		end

		pendingBatchMap[batchId] = nil
		workspace:SetAttribute("PavingLastBatchAckServerTime", serverNow)
		workspace:SetAttribute("PavingLastServerBricks", serverBricks)
	end
)

-- Character management
local function OnCharacterAdded(character: Model)
	ResetPavingRuntimeState()
	ResetRefillZoneRuntimeState()
	isPavingMode = false
	isAwaitingRescue = false
	ClearLocalBricks()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		isPavingMode = false
		isAwaitingRescue = false
		ResetPavingRuntimeState()
		ClearLocalBricks()
	end)
end
if localPlayer.Character then
	OnCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(OnCharacterAdded)

ClientMsg.ConnectResumeFalling(function()
	if isAwaitingRescue then
		isAwaitingRescue = false
		local character = localPlayer.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
			local hum = character:FindFirstChild("Humanoid") :: Humanoid
			if root then
				root.Anchored = false
			end
			if hum then
				hum.PlatformStand = false
				hum.Health = 0 -- Kill immediately to prevent re-trigger on the next frame
			end
			-- Let the next heartbeat clean up
		end
	end
	ResetPavingRuntimeState()
	ClearLocalBricks()
end)

-- Sync with server bricks
local function HookPavedBricksFolder(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if not child:IsA("BasePart") then
			return
		end
		local key = GetPosKey(child.Position)
		RemoveLocalBrickEntry(key) -- Use linear search lookup for server sync
	end)
end

local function TryHookPavedBricksFolder()
	local folder = workspace:FindFirstChild("PavedBricks")
	if folder then
		HookPavedBricksFolder(folder)
	end
end

TryHookPavedBricksFolder()
workspace.ChildAdded:Connect(function(child)
	if child.Name == "PavedBricks" then
		HookPavedBricksFolder(child)
	end
	if child.Name == "Ground" or child.Name == "ground" or child.Name == "Islands" then
		TryHookAllRefillZonesForUiSync()
	end
end)
TryHookAllRefillZonesForUiSync()
