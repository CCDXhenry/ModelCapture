--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local serverScripts = ServerStorage:WaitForChild("Scripts")
local PavingEarthquakeBridge = require(serverScripts:WaitForChild("PavingEarthquakeBridge"))

local EarthquakeManager = {}

type DropKind = "FloatBlock" | "PavedBrick"
type DropState = {
	kind: DropKind,
	part: BasePart,
	baseCFrame: CFrame,
	originalCanCollide: boolean,
	originalCanQuery: boolean,
	resolveAt: number,
	id: string,
	collisionOffAt: number,
	collisionDisabled: boolean,
}

local rng = Random.new()
local SEA_LEVEL = 0

local earthquakeId = 0
local isActive = false
local earthquakeShakeActive = false
local earthquakeStartTime = 0
local earthquakeEndTime = 0
local nextEarthquakeAt = 0
local executeDropsActive = false
local executeQueue: { any } = {}
local executeQueueIndex = 0
local nextExecuteAt = 0
local markedFloatRecoverDelayMap: { [BasePart]: { min: number, max: number } } = {}
local warningIssued = false
local warningEarthquakeId = 0

local droppedStateMap: { [BasePart]: DropState } = {}

local HEARTBEAT_CONN: RBXScriptConnection? = nil
local IS_INITIALIZED = false

local function IsDebugEnabled(): boolean
	return workspace:GetAttribute("EarthquakeDebug") == true
end

local function DebugLog(...: any)
	if IsDebugEnabled() then
		print("[EarthquakeManager]", ...)
	end
end

local function SetPartGuid(part: BasePart): string
	local guid = part:GetAttribute("EarthquakeGuid")
	if type(guid) == "string" and guid ~= "" then
		return guid
	end
	local newGuid = HttpService:GenerateGUID(false)
	part:SetAttribute("EarthquakeGuid", newGuid)
	return newGuid
end

local function GetSeaLevel(): number
	local startPointFolder = workspace:FindFirstChild("StartPoint")
	local startPointModel = if startPointFolder then startPointFolder:FindFirstChild("StartPointModel") :: Model? else nil
	local startTrigger = if startPointModel then startPointModel:FindFirstChild("StartTrigger") :: Part? else nil
	local startAttachment = if startTrigger then startTrigger:FindFirstChild("Attachment") :: Attachment? else nil
	if startAttachment then
		return startAttachment.WorldPosition.Y
	end
	return 0
end

-- 实时扫描 FloatBlock，避免 Init 缓存遗漏后续生成的岛屿部件
local function CollectFloatPartsByIsland(): { [string]: { BasePart } }
	local map: { [string]: { BasePart } } = {}
	local floatFolder = workspace:FindFirstChild("FloatBlock")
	if not floatFolder then
		return map
	end
	for _, islandFolder in floatFolder:GetChildren() do
		if islandFolder:IsA("Folder") then
			local list: { BasePart } = {}
			for _, desc in islandFolder:GetDescendants() do
				if desc:IsA("BasePart") and droppedStateMap[desc] == nil and desc.Parent ~= nil then
					SetPartGuid(desc)
					table.insert(list, desc)
				end
			end
			if #list > 0 then
				map[islandFolder.Name] = list
			end
		end
	end
	return map
end

local function ShuffleList<T>(list: { T })
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function PickRandomSubset<T>(sourceList: { T }, count: number): { T }
	if count <= 0 or #sourceList <= 0 then
		return {}
	end
	local clone = table.clone(sourceList)
	ShuffleList(clone)
	local result = {} :: { T }
	for i = 1, math.min(count, #clone) do
		table.insert(result, clone[i])
	end
	return result
end

local function CreateDropPayload(part: BasePart, baseCFrame: CFrame, kind: DropKind): any
	return {
		id = SetPartGuid(part),
		part = part,
		baseCFrame = baseCFrame,
		fallToY = SEA_LEVEL - (GameConfig.Earthquake.FallOffsetY or 3.5),
		kind = kind,
	}
end

local function DropPart(part: BasePart, kind: DropKind, now: number, floatRecoverDelayMin: number?, floatRecoverDelayMax: number?): any?
	if droppedStateMap[part] ~= nil then
		return nil
	end

	-- 清除“标记颜色&抖动”状态：进入真正掉落流程后由客户端下落/断裂效果接管
	part:SetAttribute("EarthquakeMarkedForDrop", nil)
	part:SetAttribute("EarthquakeMarkedKind", nil)

	local baseCFrame = part.CFrame
	local resolveAt: number
	if kind == "FloatBlock" then
		local recoverDelayMin = floatRecoverDelayMin or 2.5
		local recoverDelayMax = floatRecoverDelayMax or 4.5
		resolveAt = now + rng:NextNumber(recoverDelayMin, recoverDelayMax)
	else
		resolveAt = now + (GameConfig.Earthquake.PavedBrickDestroyDelayAfterDrop or 1.15)
	end

	local preFall = GameConfig.Earthquake.PreFallIntenseDuration
	local fallDur = GameConfig.Earthquake.FallDuration
	local collisionOffAt = now + preFall + fallDur

	droppedStateMap[part] = {
		kind = kind,
		part = part,
		baseCFrame = baseCFrame,
		originalCanCollide = part.CanCollide,
		originalCanQuery = part.CanQuery,
		resolveAt = resolveAt,
		id = SetPartGuid(part),
		collisionOffAt = collisionOffAt,
		collisionDisabled = false,
	}

	part:SetAttribute("EarthquakeDropped", true)
	part:SetAttribute("EarthquakeDropKind", kind)
	part:SetAttribute("EarthquakeDroppedAt", now)

	if kind == "PavedBrick" then
		PavingEarthquakeBridge.OnEarthquakeDropBrick(part :: Part)
	end

	return CreateDropPayload(part, baseCFrame, kind)
end

local function BroadcastDrop(earthquakeIdValue: number, judgeIndexValue: number, floatList: { any }, pavedList: { any })
	NetMsg.FireNotifyEarthquakeJudgeDrop(earthquakeIdValue, judgeIndexValue, floatList, pavedList)
end

local function BroadcastRecover(earthquakeIdValue: number, floatList: { any }, pavedList: { any })
	NetMsg.FireNotifyEarthquakeRecover(earthquakeIdValue, floatList, pavedList)
end

local function BuildDroppedSnapshotPayload(): ({ any }, { any })
	local droppedFloat = {} :: { any }
	local droppedPaved = {} :: { any }
	for part, dropState in pairs(droppedStateMap) do
		if part.Parent == nil then
			continue
		end
		local payload = CreateDropPayload(part, dropState.baseCFrame, dropState.kind)
		if dropState.kind == "FloatBlock" then
			table.insert(droppedFloat, payload)
		else
			table.insert(droppedPaved, payload)
		end
	end
	return droppedFloat, droppedPaved
end

local function ProcessDropCollisionOff(now: number)
	local toRemove: { BasePart } = {}
	local toStrip: { BasePart } = {}
	for part, dropState in pairs(droppedStateMap) do
		if dropState.collisionDisabled then
			continue
		end
		if part.Parent == nil then
			table.insert(toRemove, part)
			continue
		end
		if now >= dropState.collisionOffAt then
			table.insert(toStrip, part)
		end
	end
	for _, part in ipairs(toRemove) do
		droppedStateMap[part] = nil
	end
	for _, part in ipairs(toStrip) do
		local dropState = droppedStateMap[part]
		if dropState and not dropState.collisionDisabled and part.Parent ~= nil then
			part.CanCollide = false
			part.CanQuery = false
			dropState.collisionDisabled = true
		end
	end
end

local function ProcessDropResolutions(now: number)
	local recoverFloat = {} :: { any }
	local toResolve: { BasePart } = {}
	for part, dropState in pairs(droppedStateMap) do
		if now >= dropState.resolveAt then
			table.insert(toResolve, part)
		end
	end
	for _, part in ipairs(toResolve) do
		local dropState = droppedStateMap[part]
		if dropState == nil then
			continue
		end
		if dropState.kind == "FloatBlock" then
			if part.Parent ~= nil then
				part:SetAttribute("EarthquakeDropped", false)
				part:SetAttribute("EarthquakeDropKind", nil)
				part:SetAttribute("EarthquakeDroppedAt", nil)
				part.CanCollide = dropState.originalCanCollide
				part.CanQuery = dropState.originalCanQuery
				table.insert(recoverFloat, CreateDropPayload(part, dropState.baseCFrame, "FloatBlock"))
			end
			droppedStateMap[part] = nil
		else
			PavingEarthquakeBridge.ReleasePavedBrickAfterEarthquake(part :: Part)
			droppedStateMap[part] = nil
		end
	end

	if #recoverFloat > 0 then
		BroadcastRecover(earthquakeId, recoverFloat, {})
	end
end

local function ParseIslandIdFromName(islandFolderName: string): number
	local id = tonumber(islandFolderName:match("^Island(%d+)$"))
	return if id then id else 1
end

local function ScheduleNextEarthquake(now: number)
	local minGap = GameConfig.Earthquake.IntervalMin
	local maxGap = GameConfig.Earthquake.IntervalMax
	local cooldownAfterEnd = GameConfig.Earthquake.CooldownAfterEnd or 0
	local gap = rng:NextNumber(minGap, maxGap) + cooldownAfterEnd
	nextEarthquakeAt = now + gap
	workspace:SetAttribute("EarthquakeNextAt", nextEarthquakeAt)
	warningIssued = false
end

local function StartEarthquake(now: number)
	warningIssued = false
	earthquakeId += 1
	isActive = true
	earthquakeShakeActive = true
	executeDropsActive = false
	table.clear(executeQueue)
	executeQueueIndex = 0
	nextExecuteAt = 0
	for part in pairs(markedFloatRecoverDelayMap) do
		markedFloatRecoverDelayMap[part] = nil
	end
	earthquakeStartTime = now
	earthquakeEndTime = now + GameConfig.Earthquake.Duration
	workspace:SetAttribute("EarthquakeId", earthquakeId)
	workspace:SetAttribute("EarthquakeActive", true)
	workspace:SetAttribute("EarthquakeStartAt", earthquakeStartTime)
	workspace:SetAttribute("EarthquakeEndAt", earthquakeEndTime)

	-- 允许地震期间新铺的砖也进入“标记->结束后掉落”流程
	workspace:SetAttribute("EarthquakeDropExecutionActive", false)
	workspace:SetAttribute("EarthquakeMarkPavingActive", true)

	-- 1) 标记 FloatBlock：地震开始时直接抽取一次
	local partsByIsland = CollectFloatPartsByIsland()
	for islandName, floatParts in pairs(partsByIsland) do
		local islandId = ParseIslandIdFromName(islandName)
		local islandCfg = GameConfig.IslandEarthquakeConfigMap[islandId]
		if islandCfg then
			local dropCount = math.clamp(islandCfg.floatBlockDropCountJudge or 0, 0, #floatParts)
			local targets = PickRandomSubset(floatParts, dropCount)
			for _, part in ipairs(targets) do
				if part.Parent ~= nil then
					part:SetAttribute("EarthquakeMarkedForDrop", true)
					part:SetAttribute("EarthquakeMarkedKind", "FloatBlock")
					markedFloatRecoverDelayMap[part] = {
						min = islandCfg.DropRecoverDelayMin,
						max = islandCfg.DropRecoverDelayMax,
					}
				end
			end
		end
	end

	-- 2) 标记已经铺好的 PavedBrick：地震开始时全标记
	local pavedFolder = workspace:FindFirstChild("PavedBricks") :: Folder?
	if pavedFolder and pavedFolder:IsA("Folder") then
		for _, child in ipairs(pavedFolder:GetChildren()) do
			if child:IsA("BasePart") then
				-- 若该砖仍处于上一轮掉落中，则跳过避免重复标记
				if child:GetAttribute("EarthquakeDropped") ~= true then
					child:SetAttribute("EarthquakeMarkedForDrop", true)
					child:SetAttribute("EarthquakeMarkedKind", "PavedBrick")
				end
			end
		end
	end

	NetMsg.FireNotifyEarthquakeState(earthquakeId, true, GameConfig.Earthquake.Duration, 1)
	DebugLog("Earthquake start id=", earthquakeId, "duration=", GameConfig.Earthquake.Duration)
end

local function TickEarthquake(now: number)
	if isActive then
		-- 地震抖动结束：开始执行掉落（含随机间隙顺序）
		if earthquakeShakeActive and now >= earthquakeEndTime then
			earthquakeShakeActive = false
			workspace:SetAttribute("EarthquakeActive", false)
			workspace:SetAttribute("EarthquakeRescuePaving", false)
			workspace:SetAttribute("EarthquakeMarkPavingActive", false)
			workspace:SetAttribute("EarthquakeDropExecutionActive", true)
			NetMsg.FireNotifyEarthquakeState(earthquakeId, false, 0, 0)

			-- 构建执行队列：已标记 FloatBlock + 全服已标记 PavedBrick
			table.clear(executeQueue)
			executeQueueIndex = 1

			-- FloatBlock（起始时抽取并存储 recover delay）
			for part, recoverDelay in pairs(markedFloatRecoverDelayMap) do
				if part.Parent ~= nil and part:GetAttribute("EarthquakeMarkedForDrop") == true then
					table.insert(executeQueue, {
						kind = "FloatBlock" :: DropKind,
						part = part,
						recoverDelayMin = recoverDelay.min,
						recoverDelayMax = recoverDelay.max,
					})
				end
			end
			-- 防止“标记->掉落队列”重复执行
			for k in pairs(markedFloatRecoverDelayMap) do
				markedFloatRecoverDelayMap[k] = nil
			end

			-- PavedBrick（地震期间新铺的砖也会被 PavingManager 打标）
			local pavedFolder = workspace:FindFirstChild("PavedBricks") :: Folder?
			if pavedFolder and pavedFolder:IsA("Folder") then
				for _, child in ipairs(pavedFolder:GetChildren()) do
					if child:IsA("BasePart") then
						if child:GetAttribute("EarthquakeMarkedForDrop") == true and child:GetAttribute("EarthquakeMarkedKind") == "PavedBrick" then
							table.insert(executeQueue, {
								kind = "PavedBrick" :: DropKind,
								part = child,
							})
						end
					end
				end
			end

			-- 保留随机顺序，但执行时机改为“固定总时窗内全部完成”
			ShuffleList(executeQueue)
			nextExecuteAt = now
			executeDropsActive = true
		end

		-- 执行队列（1秒内全部执行完成，不再为每个块引入随机间隙）
		if executeDropsActive then
			local totalCount = math.max(1, #executeQueue)
			local windowSeconds = math.max(0.05, GameConfig.Earthquake.DropExecuteWindowSeconds or 1.0)
			local perDropInterval = windowSeconds / totalCount
			local droppedFloatBatch = {} :: { any }
			local droppedPavedBatch = {} :: { any }
			local batchJudgeIndex = executeQueueIndex
			while executeQueueIndex <= #executeQueue and now >= nextExecuteAt do
				local entry = executeQueue[executeQueueIndex]
				local part = entry.part :: BasePart
				local kind = entry.kind :: DropKind

				local payload
				if kind == "FloatBlock" then
					payload = DropPart(part, "FloatBlock", now, entry.recoverDelayMin, entry.recoverDelayMax)
					if payload ~= nil then
						table.insert(droppedFloatBatch, payload)
					end
				else
					payload = DropPart(part, "PavedBrick", now)
					if payload ~= nil then
						table.insert(droppedPavedBatch, payload)
					end
				end

				batchJudgeIndex = executeQueueIndex
				executeQueueIndex += 1
				if executeQueueIndex <= #executeQueue then
					nextExecuteAt += perDropInterval
				end
			end
			if #droppedFloatBatch > 0 or #droppedPavedBatch > 0 then
				BroadcastDrop(earthquakeId, batchJudgeIndex, droppedFloatBatch, droppedPavedBatch)
			end

			if executeQueueIndex > #executeQueue then
				executeDropsActive = false
				isActive = false
				workspace:SetAttribute("EarthquakeDropExecutionActive", false)
				ScheduleNextEarthquake(now)
			end
		end
		return
	end

	if #Players:GetPlayers() < (GameConfig.Earthquake.MinPlayersToTrigger or 1) then
		return
	end
	local warningLead = GameConfig.Earthquake.WarningSeconds or 5
	if not warningIssued and now >= nextEarthquakeAt - warningLead and now < nextEarthquakeAt then
		warningIssued = true
		warningEarthquakeId = earthquakeId + 1
		workspace:SetAttribute("EarthquakeRescuePaving", true)
		NetMsg.FireNotifyEarthquakeWarning(warningEarthquakeId, math.max(1, math.ceil(nextEarthquakeAt - now)))
		DebugLog("Earthquake warning id=", warningEarthquakeId, "seconds=", math.ceil(nextEarthquakeAt - now))
	end
	if now >= nextEarthquakeAt then
		StartEarthquake(now)
	end
end

local function SyncEarthquakeStateForPlayer(player: Player)
	local nowClock = os.clock()
	if isActive then
		if earthquakeShakeActive then
			local durationLeft = math.max(0, earthquakeEndTime - nowClock)
			NetMsg.FireNotifyEarthquakeStateToPlayer(player, earthquakeId, true, durationLeft, 1)
		else
			NetMsg.FireNotifyEarthquakeStateToPlayer(player, earthquakeId, false, 0, 0)
		end

		local droppedFloat, droppedPaved = BuildDroppedSnapshotPayload()
		if #droppedFloat > 0 or #droppedPaved > 0 then
			NetMsg.FireNotifyEarthquakeJudgeDropToPlayer(player, earthquakeId, 0, droppedFloat, droppedPaved)
		end
		DebugLog("Synced earthquake state for player", player.Name, "dropFloat=", #droppedFloat, "dropPaved=", #droppedPaved)
	elseif warningIssued and nowClock < nextEarthquakeAt then
		NetMsg.FireNotifyEarthquakeWarningToPlayer(player, warningEarthquakeId, math.max(1, math.ceil(nextEarthquakeAt - nowClock)))
	end
end

local function OnHeartbeat()
	local now = os.clock()
	ProcessDropCollisionOff(now)
	ProcessDropResolutions(now)
	TickEarthquake(now)
end

function EarthquakeManager.Init()
	if IS_INITIALIZED then
		return
	end
	IS_INITIALIZED = true
	SEA_LEVEL = GetSeaLevel()
	ScheduleNextEarthquake(os.clock())
	workspace:SetAttribute("EarthquakeActive", false)
	workspace:SetAttribute("EarthquakeRescuePaving", false)
	workspace:SetAttribute("EarthquakeMarkPavingActive", false)
	workspace:SetAttribute("EarthquakeDropExecutionActive", false)
	workspace:SetAttribute("EarthquakeDebug", false)
	if HEARTBEAT_CONN == nil then
		HEARTBEAT_CONN = RunService.Heartbeat:Connect(OnHeartbeat)
	end
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			SyncEarthquakeStateForPlayer(player)
		end)
	end)
	DebugLog("Initialized. seaLevel=", SEA_LEVEL)
end

return EarthquakeManager
