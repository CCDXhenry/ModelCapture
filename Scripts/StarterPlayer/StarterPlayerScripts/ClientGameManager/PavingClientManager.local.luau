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
local ClientGroundZoneState = require(clientScripts:FindFirstChild("ClientGroundZoneState"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayer = players.LocalPlayer
local lastPavePosition: Vector3? = nil
local SEA_LEVEL = 0
local isPavingMode = false
local isAwaitingRescue = false
local stationaryTime = 0
local lastStationaryPos: Vector3? = nil
local lastRefillTime = 0
-- 区域补砖（Ground）共享全局节流，避免同帧重复发送。
local lastZoneRefillTime = 0
local EARTHQUAKE_POST_UNLOCK_PHASE_ATTR = "EarthquakePostQuakeUnlockPhase"
local PLAYER_POST_UNLOCKED_ATTR = "PavingPostQuakeUnlocked"

-- 跟踪地震状态切换，用于在地震结束瞬间做运行态清理。
local lastEarthquakeActive = workspace:GetAttribute("EarthquakeActive") == true

-- Local prediction config
local LOCAL_PREDICT_TTL = GameConfig.Paving.LocalPredictTTL
local LOCAL_PREDICT_BATCH_INTERVAL = GameConfig.Paving.BatchInterval
local function GetEffectiveMaxPendingBatches(): number
	local base = GameConfig.Paving.MaxPendingBatches or 4
	return math.max(base, GameConfig.Paving.MaxPendingBatchesDuringEarthquake or 8)
end

local function GetEffectiveBatchInterval(): number
	local q = GameConfig.Paving.BatchIntervalDuringEarthquake
	if type(q) == "number" and q > 0 then
		return q
	end
	return LOCAL_PREDICT_BATCH_INTERVAL
end

local MAX_INTERPOLATION_STEPS = GameConfig.Paving.MaxInterpolationSteps
local LOCAL_PREDICT_SUPPORT_GRACE = 0.6
local MAX_LOCAL_PREDICT_SUPPORT_TIME = LOCAL_PREDICT_TTL + LOCAL_PREDICT_SUPPORT_GRACE
local SHOW_LOCAL_PREDICT_ATTR = "PavingShowLocalPredictBricks"
local LOCAL_PREDICT_VISIBLE_TRANSPARENCY = 0.5
local LOCAL_PREDICT_HIDDEN_TRANSPARENCY = 1
local NON_EARTHQUAKE_LOCAL_PREDICT_TRANSPARENCY = 0
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
	isTouchOnly: boolean, -- 仅触碰触发的路径砖（多段跳弹簧），初始隐藏，触碰后才激活显示
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
local previousFrameOnOtherPlayerPavedBrick = false
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
	if not IsLocalPredictVisible() then
		return LOCAL_PREDICT_HIDDEN_TRANSPARENCY
	end
	-- 非地震时本地预测砖改为即时实心显示；地震标记期沿用原有透明度表现。
	if workspace:GetAttribute("EarthquakeMarkPavingActive") == true then
		return LOCAL_PREDICT_VISIBLE_TRANSPARENCY
	end
	return NON_EARTHQUAKE_LOCAL_PREDICT_TRANSPARENCY
end

local function ApplyLocalPredictDisplay(part: Part)
	part.Transparency = GetLocalPredictTransparency()
	part.Color = brickTemplate.Color
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

local FALL_SAFE_PIT_FOLDER_NAME = "FallSafePit"
local function GetFallSafePitFolder(): Instance?
	return workspace:FindFirstChild(FALL_SAFE_PIT_FOLDER_NAME)
end

local fallSafePitOverlapParams: OverlapParams? = nil
local function IsLocalCharacterOnFallSafePit(character: Model?): boolean
	if not character then
		return false
	end
	local folder = GetFallSafePitFolder()
	if not folder then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	if not fallSafePitOverlapParams then
		local p = OverlapParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		fallSafePitOverlapParams = p
	end
	(fallSafePitOverlapParams :: OverlapParams).FilterDescendantsInstances = { folder }
	local boxSize = Vector3.new(2.8, 3, 2.8)
	local boxCFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5 - 0.25, 0)
	local overlapping = workspace:GetPartBoundsInBox(boxCFrame, boxSize, fallSafePitOverlapParams :: OverlapParams)
	return #overlapping > 0
end

local function GetCharacterFeetWorldY(character: Model?): number?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	return root.Position.Y - root.Size.Y * 0.5
end

local function IsLocalCharacterBelowSeaPavingPlane(character: Model?): boolean
	local feetY = GetCharacterFeetWorldY(character)
	if feetY == nil then
		return false
	end
	local delta = GameConfig.Paving.NoPaveWhenFeetBelowSeaStuds
	if type(delta) ~= "number" or delta <= 0 then
		return false
	end
	return feetY < SEA_LEVEL - delta
end

-- FallSafePit 重叠或脚底明显低于海平面铺砖平面（坑底 Start 台子常在 FallSafePit 外）
local function ShouldBlockSeaLevelPaving(character: Model?): boolean
	return IsLocalCharacterOnFallSafePit(character) or IsLocalCharacterBelowSeaPavingPlane(character)
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

	-- 兜底：部分地面网格较薄/形状不规则时，盒体可能漏检，增加向下射线判定（长度与服务端补砖校验一致）。
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

local function DiscardPavingInterpolationAnchor()
	lastPavePosition = nil
	stationaryTime = 0
	lastStationaryPos = nil
end

local function ResetPavingRuntimeState()
	DiscardPavingInterpolationAnchor()
	lastBatchTime = 0
	firstBrickFallbackAt = 0
	previousFrameInSafeZone = true
	previousFrameOnOtherPlayerPavedBrick = false
	table.clear(pendingPaveQueue)
end

local function ClearLocalBricks()
	if next(localBrickMap) then
		for _, entry in pairs(localBrickMap) do
			if entry.part then
				ReturnBrickToPool(entry.part)
			end
		end
		table.clear(localBrickMap)
		print("[PavingClient] Cleared all local prediction bricks and queue")
	end
	table.clear(pendingPaveQueue)
	table.clear(pendingBatchMap)
	unresolvedRequestedCount = 0
	-- 丢弃插值锚点，避免无砖/清预测后 lastPavePosition 仍指向旧海面，补砖时与 Start 等位置拉直线。
	ResetPavingRuntimeState()
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

-- 低配：脚下命中他人已铺实体砖（非幽灵/已掉落），用于继承插值锚点。
local function GetOtherPlayerPavedBrickUnderCharacter(rootWorldPos: Vector3): BasePart?
	local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
	if not pavedBricksFolder then
		return nil
	end
	local checkOrigin = rootWorldPos + Vector3.new(0, 5, 0)
	local checkDir = Vector3.new(0, -10, 0)
	local checkParams = RaycastParams.new()
	checkParams.FilterType = Enum.RaycastFilterType.Include
	checkParams.FilterDescendantsInstances = { pavedBricksFolder }
	local checkResult = workspace:Raycast(checkOrigin, checkDir, checkParams)
	if not checkResult or not checkResult.Instance:IsA("BasePart") then
		return nil
	end
	local part = checkResult.Instance
	if checkResult.Position.Y < SEA_LEVEL - 0.5 then
		return nil
	end
	if part:GetAttribute("IsGhost") == true then
		return nil
	end
	if part:GetAttribute("EarthquakeDropped") == true then
		return nil
	end
	local ownerId = part:GetAttribute("PavingOwnerUserId")
	if type(ownerId) ~= "number" or ownerId == localPlayer.UserId then
		return nil
	end
	return part
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

-- 仅用于「无铺砖能力」上下文：海平面以下坑底（FallSafePit）不计入 HasSolidGroundAt，单独向下长射线探测。
local FALLSAFE_PIT_RAY_ORIGIN_OFFSET_Y = 50
local FALLSAFE_PIT_RAY_LENGTH = 120

local function HasFallSafePitSupportAt(worldPos: Vector3): boolean
	local folder = GetFallSafePitFolder()
	if not folder then
		return false
	end
	local origin = Vector3.new(worldPos.X, worldPos.Y + FALLSAFE_PIT_RAY_ORIGIN_OFFSET_Y, worldPos.Z)
	local direction = Vector3.new(0, -FALLSAFE_PIT_RAY_LENGTH, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local result = workspace:Raycast(origin, direction, params)
	return result ~= nil and result.Instance ~= nil
end

local function SendAllPendingPaveBatches()
	local paveCarriedInfo = ClientGameInfo.GetLocalPlayerInfo()
	local paveCarriedBricks = if paveCarriedInfo then paveCarriedInfo.carriedInfo.bricks else 0
	if paveCarriedBricks <= 0 then
		table.clear(pendingPaveQueue)
		return
	end
	if ShouldBlockSeaLevelPaving(localPlayer.Character) then
		table.clear(pendingPaveQueue)
		return
	end
	if #pendingPaveQueue <= 0 then
		return
	end
	local pendingCount = 0
	for _ in pairs(pendingBatchMap) do
		pendingCount += 1
	end
	local maxPending = GetEffectiveMaxPendingBatches()
	if pendingCount >= maxPending then
		return
	end
	local maxBatchSize = GameConfig.Paving.MaxBatchSize
	local queueIndex = 1
	local originalCount = #pendingPaveQueue
	while queueIndex <= originalCount and pendingCount < maxPending do
		local endIndex = math.min(queueIndex + maxBatchSize - 1, originalCount)
		local batchChunk = table.move(pendingPaveQueue, queueIndex, endIndex, 1, {})
		local batchId = nextBatchId
		nextBatchId += 1
		local keys: { [string]: boolean } = {}
		local localSentAt = os.clock()
		local serverTimeAtSend = workspace:GetServerTimeNow()
		for _, pos in ipairs(batchChunk) do
			local key = GetPosKey(pos)
			keys[key] = true
			local entry = localBrickMap[key]
			if entry then
				entry.lastRequestAt = localSentAt
				entry.lastBatchId = batchId
			end
		end
		pendingBatchMap[batchId] = {
			sentAt = localSentAt,
			positions = batchChunk,
			keys = keys,
		}
		
		local isEarthquakeMarkActive = workspace:GetAttribute("EarthquakeMarkPavingActive") == true
		NetMsg.FireRequestPlaceBrickBatch(batchChunk, batchId, serverTimeAtSend, isEarthquakeMarkActive)
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

local function TrySendPendingImmediatelyForNonEarthquake()
	if #pendingPaveQueue <= 0 then
		return
	end
	local now = os.clock()
	-- 统一策略：新砖入队后更积极地尝试立刻发包，减少等待下一拍 Heartbeat 的体感延迟。
	if now - lastBatchTime < 0.015 then
		return
	end
	SendAllPendingPaveBatches()
	lastBatchTime = now
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

-- 玩家脚下安全区：单点竖直射线（与服务端 IsPlayerInPavingSafeZone 对齐）；预测落点仍用整块 footprint。
local function IsPlayerFeetInClientSafeZone(snappedFeetPos: Vector3): boolean
	return IsPointOverSafeZone(snappedFeetPos)
end

local function IsLocalPlayerPostQuakePavingLocked(): boolean
	if workspace:GetAttribute(EARTHQUAKE_POST_UNLOCK_PHASE_ATTR) ~= true then
		return false
	end
	if localPlayer:GetAttribute(PLAYER_POST_UNLOCKED_ATTR) == true then
		return false
	end
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart == nil then
		return true
	end
	local snappedFeetPos = GetSnappedPosition(rootPart.Position)
	return not IsPlayerFeetInClientSafeZone(snappedFeetPos)
end

local function HasPavingAbility(): boolean
	if IsLocalPlayerPostQuakePavingLocked() then
		return false
	end
	local info = ClientGameInfo.GetLocalPlayerInfo()
	local bricks = if info then info.carriedInfo.bricks else 0
	return bricks > 0
end

-- 有铺砖能力时与 HasSolidGroundAt 完全一致（不含 FallSafePit）；无铺砖能力时才合并坑底命中，避免干扰海平面正常铺砖判定。
local function HasEffectiveGroundAt(samplePos: Vector3): boolean
	local base = HasSolidGroundAt(samplePos)
	if HasPavingAbility() then
		return base
	end
	return base or HasFallSafePitSupportAt(samplePos)
end

-- 有铺砖能力时路径补全：格点须在海面列上有常规支撑，或水平方向仍贴近当前脚步格（允许海面延伸铺桥）。
local function InterpolationCellAllowedOnSeaGrid(cellPos: Vector3, feetGridPos: Vector3): boolean
	if HasSolidGroundAt(cellPos) then
		return true
	end
	local horiz = (Vector3.new(cellPos.X, 0, cellPos.Z) - Vector3.new(feetGridPos.X, 0, feetGridPos.Z)).Magnitude
	local maxSteps = math.max(MAX_INTERPOLATION_STEPS, GameConfig.Paving.MaxInterpolationStepsAtHighSpeed or MAX_INTERPOLATION_STEPS)
	return horiz <= GRID_SIZE * (maxSteps + 2)
end

-- 沿 moveDir 从脚下对齐格向前逐格扫描，返回第一块满足 4b 条件的可铺格（与服务端整块禁铺边界对齐）。
local function FindFirstPaveCellAlongMove(
	originSnapped: Vector3,
	moveDir: Vector3,
	feetGridPos: Vector3,
	maxSteps: number
): Vector3?
	local horizMove = Vector3.new(moveDir.X, 0, moveDir.Z)
	if horizMove.Magnitude < 1e-4 then
		return nil
	end
	local unitDir = horizMove.Unit
	for k = 1, maxSteps do
		local cell = GetSnappedPosition(originSnapped + unitDir * (k * GRID_SIZE))
		if
			InterpolationCellAllowedOnSeaGrid(cell, feetGridPos)
			and not IsEntireBrickFootprintOverSafeZone(cell)
			and not IsFloatBlockBlockingPaving(cell)
			and not CheckBrickExists(cell)
		then
			return cell
		end
	end
	return nil
end

-- requireTouchTrigger：多段跳弹簧，仅触碰/重叠预测砖入队。
-- 非多段跳：水平逻辑产生的预测砖仅在“铺砖门禁安全区”外自动入队；触碰预测砖始终可入队（防掉落）。
local function RequestPlaceBrick(targetPos: Vector3, requireTouchTrigger: boolean, forceQueue: boolean?)
	if IsLocalPlayerPostQuakePavingLocked() then
		return
	end
	if ShouldBlockSeaLevelPaving(localPlayer.Character) then
		return
	end
	local placeInfo = ClientGameInfo.GetLocalPlayerInfo()
	local carriedForPlace = if placeInfo then placeInfo.carriedInfo.bricks else 0
	if carriedForPlace <= 0 then
		return
	end
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
			TrySendPendingImmediatelyForNonEarthquake()
		end
		return
	end

	local brick = GetBrickFromPool()
	brick.Position = targetPos

	-- requireTouchTrigger 且非 forceQueue 的路径砖：初始隐藏，等触碰后才显示（与地震路径砖行为一致）
	local isTouchOnly = requireTouchTrigger and (forceQueue ~= true)
	if isTouchOnly then
		brick.Transparency = LOCAL_PREDICT_HIDDEN_TRANSPARENCY
		brick.Color = brickTemplate.Color
	else
		ApplyLocalPredictDisplay(brick)
	end

	localBrickMap[key] = {
		part = brick,
		createdAt = now,
		requested = false,
		resolved = false,
		isTouchOnly = isTouchOnly,
	}

	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart

	local inPavingGateSafeZone = IsEntireBrickFootprintOverPavingGateSafeZone(targetPos)

	local function triggerPave()
		local triggerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not triggerInfo or triggerInfo.carriedInfo.bricks <= 0 then
			return
		end
		local entry = localBrickMap[key]
		if entry and not entry.requested then
			-- 触碰激活时立刻显示路径砖，与 feetGuard forceQueue 路径的即时可见保持一致
			if entry.isTouchOnly then
				ApplyLocalPredictDisplay(entry.part)
			end
			entry.requested = true
			entry.resolved = false
			unresolvedRequestedCount += 1
			table.insert(pendingPaveQueue, targetPos)
			TrySendPendingImmediatelyForNonEarthquake()
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

	local inGroundRefillZoneThisFrame = false
	if character and rootPart and humanoid and humanoid.Health > 0 then
		for _, zoneState in ipairs(refillZoneStates) do
			if zoneState.name == "Ground" then
				inGroundRefillZoneThisFrame = IsLocalCharacterOnRefillZone(character, zoneState)
				break
			end
		end
	end
	ClientGroundZoneState.SetLocalInGroundRefillZone(inGroundRefillZoneThisFrame)

	-- 1. Hard cleanup conditions (Death/Falling/Invalid state)
	local now = os.clock()
	local pos = if rootPart then rootPart.Position else nil
	local onOtherPlayerPavedBrickThisFrame = false
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
			print("[PavingClient] Mode reset due to death/falling")
		end
		ClearLocalBricks()
		return
	end

	-- 2. Mode Activation Check (Start Trigger or Safe Zone)
	if pos and character then
		local inStartRange = IsLocalCharacterTouchingStartTrigger(character)
		local inSafeZone = false
		if not inStartRange then
			inSafeZone = IsPlayerFeetInClientSafeZone(GetSnappedPosition(pos))
		end

		-- Ground 补砖区：坑底等区域与安全区射线可能不同步，仅「经过」安全区跳跃时易漏激活铺砖模式。
		if inStartRange or inSafeZone or inGroundRefillZoneThisFrame then
			if not isPavingMode then
				isPavingMode = true
				--print("[PavingClient] Mode activated")

				-- 【新增】：如果有惯性方向，额外在前方一格预铺一块
				local activationInfo = ClientGameInfo.GetLocalPlayerInfo()
				local activationBricks = if activationInfo then activationInfo.carriedInfo.bricks else 0
				local velocity = rootPart.AssemblyLinearVelocity
				-- 纯安全区激活不预铺前方格；起点触发仍预铺（出海惯性）。
				if activationBricks > 0 and velocity.Magnitude > 1 and (inStartRange or not inSafeZone) then
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

	-- Ground：统一补砖触发，Touch 优先，轮询兜底。
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
	local currentFrameInSafeZone = IsPlayerFeetInClientSafeZone(feetPosForState)
	if currentFrameInSafeZone then
		lastPavePosition = nil
	end
	local inPostQuakeUnlockPhase = workspace:GetAttribute(EARTHQUAKE_POST_UNLOCK_PHASE_ATTR) == true
	local unlockedAfterQuake = localPlayer:GetAttribute(PLAYER_POST_UNLOCKED_ATTR) == true
	-- 失去铺砖能力（没砖或震后未解锁等）即丢弃插值锚点，避免恢复能力后从陈旧 lastPavePosition 拉直线。
	if not HasPavingAbility() then
		DiscardPavingInterpolationAnchor()
	end
	local wasOnOtherPlayerPavedBrick = previousFrameOnOtherPlayerPavedBrick
	local otherPlayerPavedBrickUnderFeet: BasePart? = nil
	if not currentFrameInSafeZone and HasPavingAbility() and pos then
		otherPlayerPavedBrickUnderFeet = GetOtherPlayerPavedBrickUnderCharacter(pos)
	end
	onOtherPlayerPavedBrickThisFrame = otherPlayerPavedBrickUnderFeet ~= nil
	if inPostQuakeUnlockPhase and not unlockedAfterQuake and not currentFrameInSafeZone then
		table.clear(pendingPaveQueue)
		if isOutOfBricks then
			ClearLocalBricks()
		end
		previousFrameOnOtherPlayerPavedBrick = if currentFrameInSafeZone then false else onOtherPlayerPavedBrickThisFrame
		previousFrameInSafeZone = currentFrameInSafeZone
		return
	end

	local blockSeaLevelPave = ShouldBlockSeaLevelPaving(character)
	if blockSeaLevelPave then
		ClearLocalBricks()
	end

	if not isOutOfBricks and not blockSeaLevelPave then
		-- 4a. Feet Guard: 检测脚下是否有有效地面，无地面时立即铺砖
		local feetPos = feetPosForState
		local feetFloatBlock = GetFloatBlockAtPoint(feetPos)
		local onDangerousFloatBlock = false
		if feetFloatBlock ~= nil then
			onDangerousFloatBlock = feetFloatBlock:GetAttribute("EarthquakeMarkedForDrop") == true
				or feetFloatBlock:GetAttribute("EarthquakeDropped") == true
		end
		local noGroundUnderFeet = not HasEffectiveGroundAt(pos)
		local allowEmergencyPaving = onDangerousFloatBlock and serverBricks > 0
		if noGroundUnderFeet then
			-- 脚下投影仍在安全区内（Ground/Islands/Home/安全 Float）时跳过：服务端必然拒绝且无铺砖意义。
			-- HasSolidGroundAt 使用短射线（±5），玩家跳高后会漏判；currentFrameInSafeZone 为脚下格单点竖直长射线（与服务端一致）。
			-- 多段跳弹簧（requireTouchTrigger）依赖 Touch/overlap 机制落点后再铺；
			-- 仅地震紧急兜座（allowEmergencyPaving）保留 forceQueue 保护。
			local forceQueueNow = allowEmergencyPaving or not requireTouchTrigger
			if not currentFrameInSafeZone and not CheckBrickExists(feetPos) and (allowEmergencyPaving or not IsFloatBlockBlockingPaving(feetPos)) then
				-- 空中脚下无地时，强制请求脚下砖，避免跳跃与安全区边缘漏首块/尾块
				RequestPlaceBrick(feetPos, requireTouchTrigger, if forceQueueNow then true else nil)
				FlushPendingPaveQueue()
			end
		end
		-- 从安全区跃迁到海面且脚下无地时，强制首格入队并立刻同步，避免首块漏铺
		-- 多段跳弹簧时同样不强制 forceQueue，让 Touch/overlap 接管。
		if previousFrameInSafeZone and not currentFrameInSafeZone and (now - firstBrickFallbackAt) >= FIRST_BRICK_FORCE_QUEUE_COOLDOWN then
			if noGroundUnderFeet then
				firstBrickFallbackAt = now
				local forceQueueFirst = not requireTouchTrigger
				RequestPlaceBrick(feetPos, requireTouchTrigger, if forceQueueFirst then true else nil)
				FlushPendingPaveQueue()
			end
		end

		-- 4b. Paving logic calculation (基于物理惯性的方向预判)
		-- 脚下仍在安全区内时不做前瞻/静止自动铺砖，避免边界外无效预测砖。
		if not currentFrameInSafeZone then
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
			-- 出站接榫：有速度且锚点空时从脚下格开始插值，配合扫描首格贴安全区外沿。
			if not isStationary and previousFrameInSafeZone and not currentFrameInSafeZone and lastPavePosition == nil then
				lastPavePosition = feetPosForState
			end
			-- 踩在他人已铺砖上：用脚下砖格作锚点（仅首踩或锚点空时写入，避免每帧打断插值链）。
			if otherPlayerPavedBrickUnderFeet and (lastPavePosition == nil or not wasOnOtherPlayerPavedBrick) then
				lastPavePosition = GetSnappedPosition(otherPlayerPavedBrickUnderFeet.Position)
			end
			local playerWalkSpeed = GetCurrentWalkSpeed()
			local lookaheadFactor = math.clamp(speed / math.max(1, playerWalkSpeed), 1.0, GameConfig.Paving.HighSpeedLookaheadMaxFactor or 2.2)
			local targetPos = if isStationary then GetSnappedPosition(pos) else GetSnappedPosition(pos + moveDir * (GRID_SIZE * lookaheadFactor))
			-- 出站首帧：用沿前进方向第一块可铺格覆盖远 lookahead，避免与安全区边缘留缝。
			if not isStationary and previousFrameInSafeZone and not currentFrameInSafeZone then
				local scanMaxSteps = math.clamp(math.ceil(lookaheadFactor) + 4, 8, 16)
				local scanPos = FindFirstPaveCellAlongMove(feetPosForState, moveDir, feetPosForState, scanMaxSteps)
				if scanPos ~= nil then
					targetPos = scanPos
				end
			end

			-- [优化] Stationary renewal (防止原地发呆无限扣砖)
			local RENEWAL_INTERVAL = GameConfig.Paving.StationaryRenewalInterval or 0.2
			if isStationary then
				if lastStationaryPos and (targetPos - lastStationaryPos).Magnitude < 0.1 then
					stationaryTime += dt
					if stationaryTime >= RENEWAL_INTERVAL then
						stationaryTime = 0
						-- 加上射线检测与安全区检测
						if
							InterpolationCellAllowedOnSeaGrid(targetPos, feetPosForState)
							and not IsEntireBrickFootprintOverSafeZone(targetPos)
							and not IsFloatBlockBlockingPaving(targetPos)
							and not CheckBrickExists(targetPos)
						then
							RequestPlaceBrick(targetPos, requireTouchTrigger)
							FlushPendingPaveQueue()
						end
					end
				else
					lastStationaryPos = targetPos
					stationaryTime = 0
					-- [顺发] 当检测到刚停下时，立即尝试续期一次，不再等待计时器
					if
						InterpolationCellAllowedOnSeaGrid(targetPos, feetPosForState)
						and not IsEntireBrickFootprintOverSafeZone(targetPos)
						and not IsFloatBlockBlockingPaving(targetPos)
						and not CheckBrickExists(targetPos)
					then
						RequestPlaceBrick(targetPos, requireTouchTrigger)
						FlushPendingPaveQueue()
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
							InterpolationCellAllowedOnSeaGrid(interimPos, feetPosForState)
							and not IsEntireBrickFootprintOverSafeZone(interimPos)
							and not IsFloatBlockBlockingPaving(interimPos)
							and not CheckBrickExists(interimPos)
						then
							RequestPlaceBrick(interimPos, requireTouchTrigger)
						end
						lastPavePosition = interimPos
					end
					FlushPendingPaveQueue()
				else
					if
						InterpolationCellAllowedOnSeaGrid(targetPos, feetPosForState)
						and not IsEntireBrickFootprintOverSafeZone(targetPos)
						and not IsFloatBlockBlockingPaving(targetPos)
						and not CheckBrickExists(targetPos)
					then
						lastPavePosition = targetPos
						RequestPlaceBrick(targetPos, requireTouchTrigger)
						FlushPendingPaveQueue()
					else
						lastPavePosition = targetPos
					end
				end
			else
				if
					InterpolationCellAllowedOnSeaGrid(targetPos, feetPosForState)
					and not IsEntireBrickFootprintOverSafeZone(targetPos)
					and not IsFloatBlockBlockingPaving(targetPos)
					and not CheckBrickExists(targetPos)
				then
					lastPavePosition = targetPos
					RequestPlaceBrick(targetPos, requireTouchTrigger)
					FlushPendingPaveQueue()
				end
			end
		end
	else
		-- 无砖：清除全部本地预测与待发批，避免补砖后 5b 把踩在脚下的未请求砖入队打成实体砖。
		ClearLocalBricks()
	end
	if currentFrameInSafeZone then
		lastPavePosition = nil
	end
	previousFrameOnOtherPlayerPavedBrick = if currentFrameInSafeZone then false else onOtherPlayerPavedBrickThisFrame
	previousFrameInSafeZone = currentFrameInSafeZone

	-- [优化] Batch transmission (防止卡顿导致包过大被服务器拒收)
	if #pendingPaveQueue > 0 and (now - lastBatchTime >= GetEffectiveBatchInterval()) then
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

	-- 5b. Per-frame overlap re-check：对未发送到服务端的本地预测砖做每帧重叠检测。
	-- 地震时 feetGuard 高频触发 forceQueue 跳过 Touch 等待；非地震时仅靠 Touched 事件，
	-- 多段跳等场景下 Touched 延迟高/不可靠。此处统一补偿：检测到角色重叠时立即 triggerPave+flush。
	if character and isPavingMode and not isOutOfBricks and not blockSeaLevelPave then
		local overlapCheckParams = OverlapParams.new()
		overlapCheckParams.FilterType = Enum.RaycastFilterType.Include
		overlapCheckParams.FilterDescendantsInstances = { character }
		local needFlush = false
		for key, entry in pairs(localBrickMap) do
			if entry.requested then
				continue
			end
			local brickPart = entry.part
			local expandedSize = brickPart.Size + Vector3.new(0, 3, 0)
			local overlapping = workspace:GetPartBoundsInBox(brickPart.CFrame, expandedSize, overlapCheckParams)
			if #overlapping > 0 then
				-- 触碰触发的隐藏路径砖，重叠检测到时也立刻显示（补偿 Touch 事件延迟）
				if entry.isTouchOnly then
					ApplyLocalPredictDisplay(entry.part)
				end
				entry.requested = true
				entry.resolved = false
				entry.lastRequestAt = now
				unresolvedRequestedCount += 1
				table.insert(pendingPaveQueue, brickPart.Position)
				needFlush = true
			end
		end
		if needFlush then
			FlushPendingPaveQueue()
		end
	end

	-- 6. Efficient TTL Cleanup (Safe pairs iteration)
	for key, entry in pairs(localBrickMap) do
		local aliveTime = now - entry.createdAt
		if aliveTime >= LOCAL_PREDICT_TTL then
			local waitingServerAck = entry.requested and not entry.resolved and (entry.lastRequestAt ~= nil)
			local keepForAck = waitingServerAck and (now - (entry.lastRequestAt :: number)) <= BATCH_ACK_TIMEOUT
			local standingSupport = not isOutOfBricks
				and aliveTime < MAX_LOCAL_PREDICT_SUPPORT_TIME
				and IsCharacterStandingOnLocalBrick(entry.part, character)
			local shouldKeepForSupport = keepForAck or standingSupport
			if shouldKeepForSupport then
				continue
			end
			RemoveLocalBrickEntry(key)
		end
	end

	-- 7. Full client marking system (Independent of Server)
	local isEarthquakeMarkActive = workspace:GetAttribute("EarthquakeMarkPavingActive") == true
	
	if isEarthquakeMarkActive then
		local markedBrickColor = BrickColor.new(GameConfig.Earthquake.MarkedBrickColor)
		local markedTransparency = GameConfig.Earthquake.MarkedPavedBrickTransparency or 0
		local predictTransparency = GetLocalPredictTransparency()
		
		-- Locally predicted bricks
		for _, entry in pairs(localBrickMap) do
			if entry.requested then
				entry.part.BrickColor = markedBrickColor
				entry.part.Transparency = markedTransparency
			else
				entry.part.Color = brickTemplate.Color
				entry.part.Transparency = predictTransparency
			end
		end
		
		-- Server generated real PavedBricks
		local folder = workspace:FindFirstChild("PavedBricks")
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") then
					local ownerId = child:GetAttribute("PavingOwnerUserId")
					if type(ownerId) == "number" then
						local currentIsMarked = child:GetAttribute("ClientVisualMarked") == true
						if not currentIsMarked then
							child.BrickColor = markedBrickColor
							child.Transparency = markedTransparency
							child:SetAttribute("ClientVisualMarked", true)
						end
					end
				end
			end
		end
	else
		-- 非地震时按 requested/isTouchOnly 三状态刷新，与地震时每帧写入的"强制渲染"保持一致。
		-- requested=true（已入队）→ 实心显示；isTouchOnly=true（路径砖未触碰）→ 保持隐藏；其余 → 按配置透明度显示
		local predictTransparency = GetLocalPredictTransparency()
		for _, entry in pairs(localBrickMap) do
			if entry.requested then
				-- 已入队的砖：实心显示
				entry.part.Color = brickTemplate.Color
				entry.part.Transparency = 0
			elseif entry.isTouchOnly then
				-- 未触碰的路径砖：保持隐藏，等待触碰激活
				entry.part.Transparency = LOCAL_PREDICT_HIDDEN_TRANSPARENCY
			else
				-- 普通移动砖（非弹簧 forceQueue 等）：按当前配置的透明度显示
				entry.part.Color = brickTemplate.Color
				entry.part.Transparency = predictTransparency
			end
		end
	end
end

runService.Heartbeat:Connect(OnHeartbeat)

-- 搬运数由服务端权威同步；若仅依赖 Heartbeat 读 carriedInfo，会比网络包晚一帧以上，
-- 仍会用「旧砖数」RequestPlaceBrick / 堆积待发批。此处与同步同帧清空预测与队列。
ClientMsg.ConnectLocalPlayerCarriedUpdate(function(carriedInfo: GameConfig.PlayerCarriedInfo)
	if carriedInfo.bricks <= 0 then
		ClearLocalBricks()
	end
end)

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
	ResetRefillZoneRuntimeState()
	isPavingMode = false
	isAwaitingRescue = false
	ClearLocalBricks()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		isPavingMode = false
		isAwaitingRescue = false
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
	ClearLocalBricks()
end)

-- Sync with server bricks
local function HookPavedBricksFolder(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if not child:IsA("BasePart") then
			return
		end
		local key = GetPosKey(child.Position)
		local entry = localBrickMap[key]
		if entry then
			-- 先标记已确认，再延迟一帧移除本地预测砖。
			-- 避免服务端砖复制到客户端渲染完成前出现「两砖皆无」的 1 帧空白闪烁。
			if entry.requested and not entry.resolved then
				entry.resolved = true
				unresolvedRequestedCount = math.max(unresolvedRequestedCount - 1, 0)
			end
			task.defer(function()
				RemoveLocalBrickEntry(key)
			end)
		end
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
	if child.Name == "Ground" or child.Name == "ground" then
		TryHookAllRefillZonesForUiSync()
	end
end)
TryHookAllRefillZonesForUiSync()
