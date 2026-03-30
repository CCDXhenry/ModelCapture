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
local earthquakeStartTime = 0
local earthquakeEndTime = 0
local nextEarthquakeAt = 0
local judgeIndex = 0
local judgeCountMax = 0
local nextJudgeAt = 0
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

local function GetIslandFolderCenter(islandFolder: Folder): Vector3?
	local sum = Vector3.zero
	local n = 0
	for _, desc in islandFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			sum += desc.Position
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return sum / n
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

local function CollectPavedBricks(): { BasePart }
	local result = {} :: { BasePart }
	local folder = workspace:FindFirstChild("PavedBricks")
	if not folder then
		return result
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and droppedStateMap[child] == nil then
			if child:GetAttribute("IsGhost") ~= true then
				SetPartGuid(child)
				table.insert(result, child)
			end
		end
	end
	return result
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

local function ExecuteJudge(now: number, judgeIndexValue: number)
	local floatFolder = workspace:FindFirstChild("FloatBlock") :: Folder?
	local partsByIsland = CollectFloatPartsByIsland()

	-- 预计算岛屿中心，用于 PavedBrick 归属
	local islandEntries = {} :: { { islandId: number, center: Vector3 } }
	if floatFolder then
		for _, islandFolder in ipairs(floatFolder:GetChildren()) do
			if islandFolder:IsA("Folder") then
				local center = GetIslandFolderCenter(islandFolder :: Folder)
				if center then
					local name = islandFolder.Name
					table.insert(islandEntries, { islandId = ParseIslandIdFromName(name), center = center })
				end
			end
		end
	end

	local droppedFloatPayload = {} :: { any }
	local droppedPavedPayload = {} :: { any }

	-- 1) FloatBlock：每个岛按自己的 judgeCount 触发，掉落数量固定
	for islandName, floatParts in pairs(partsByIsland) do
		local islandId = ParseIslandIdFromName(islandName)
		local islandCfg = GameConfig.IslandEarthquakeConfigMap[islandId]
		if islandCfg and judgeIndexValue <= math.max(1, islandCfg.judgeCount) then
			local dropCount = math.clamp(islandCfg.floatBlockDropCountJudge, 0, #floatParts)
			local targets = PickRandomSubset(floatParts, dropCount)

			for _, part in ipairs(targets) do
				local payload = DropPart(part, "FloatBlock", now, islandCfg.DropRecoverDelayMin, islandCfg.DropRecoverDelayMax)
				if payload ~= nil then
					table.insert(droppedFloatPayload, payload)
				end
			end
		end
	end

	-- 2) PavedBrick：按最近岛屿中心归属后，再用岛屿配置独立判定
	local availablePaved = CollectPavedBricks()
	if #availablePaved > 0 then
		-- 兜底：无法推导岛屿中心时，退化为按 islandId=1 的配置掉落
		if #islandEntries == 0 then
			local islandCfg = GameConfig.IslandEarthquakeConfigMap[1]
			if islandCfg and judgeIndexValue <= math.max(1, islandCfg.judgeCount) then
				local dropCount = math.clamp(islandCfg.pavedBrickDropCountJudge, 0, #availablePaved)
				local targets = PickRandomSubset(availablePaved, dropCount)
				for _, part in ipairs(targets) do
					local payload = DropPart(part, "PavedBrick", now)
					if payload ~= nil then
						table.insert(droppedPavedPayload, payload)
					end
				end
			end
		else
			local pavedByIslandId = {} :: { [number]: { BasePart } }
			for _, part in ipairs(availablePaved) do
				local pos = part.Position
				local bestId: number? = nil
				local bestD2 = math.huge
				for _, entry in ipairs(islandEntries) do
					local d2 = (pos - entry.center).Magnitude ^ 2
					if d2 < bestD2 then
						bestD2 = d2
						bestId = entry.islandId
					end
				end
				if bestId ~= nil then
					pavedByIslandId[bestId] = pavedByIslandId[bestId] or {}
					table.insert(pavedByIslandId[bestId], part)
				end
			end

			for islandId, list in pairs(pavedByIslandId) do
				local islandCfg = GameConfig.IslandEarthquakeConfigMap[islandId]
				if islandCfg and judgeIndexValue <= math.max(1, islandCfg.judgeCount) then
					local dropCount = math.clamp(islandCfg.pavedBrickDropCountJudge, 0, #list)
					local targets = PickRandomSubset(list, dropCount)
					for _, part in ipairs(targets) do
						local payload = DropPart(part, "PavedBrick", now)
						if payload ~= nil then
							table.insert(droppedPavedPayload, payload)
						end
					end
				end
			end
		end
	end

	if #droppedFloatPayload > 0 or #droppedPavedPayload > 0 then
		BroadcastDrop(earthquakeId, judgeIndexValue, droppedFloatPayload, droppedPavedPayload)
	end

	DebugLog(
		"Judge",
		judgeIndexValue,
		"dropFloat=",
		#droppedFloatPayload,
		"dropPaved=",
		#droppedPavedPayload
	)
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
	earthquakeStartTime = now
	earthquakeEndTime = now + GameConfig.Earthquake.Duration
	judgeIndex = 0

	judgeCountMax = 1
	for _, islandCfg in pairs(GameConfig.IslandEarthquakeConfigMap) do
		judgeCountMax = math.max(judgeCountMax, math.max(1, islandCfg.judgeCount))
	end
	local judgeSpan = GameConfig.Earthquake.Duration / math.max(1, judgeCountMax)
	nextJudgeAt = now + judgeSpan

	workspace:SetAttribute("EarthquakeId", earthquakeId)
	workspace:SetAttribute("EarthquakeActive", true)
	workspace:SetAttribute("EarthquakeStartAt", earthquakeStartTime)
	workspace:SetAttribute("EarthquakeEndAt", earthquakeEndTime)
	NetMsg.FireNotifyEarthquakeState(earthquakeId, true, GameConfig.Earthquake.Duration, judgeCountMax)
	DebugLog("Earthquake start id=", earthquakeId, "duration=", GameConfig.Earthquake.Duration, "judgeCount=", judgeCountMax)
end

local function EndEarthquake(now: number)
	if not isActive then
		return
	end
	isActive = false
	workspace:SetAttribute("EarthquakeActive", false)
	workspace:SetAttribute("EarthquakeRescuePaving", false)
	NetMsg.FireNotifyEarthquakeState(earthquakeId, false, 0, 0)
	DebugLog("Earthquake end id=", earthquakeId)
	ScheduleNextEarthquake(now)
end

local function TickEarthquake(now: number)
	if isActive then
		local judgeSpan = GameConfig.Earthquake.Duration / math.max(1, judgeCountMax)
		while judgeIndex < judgeCountMax and now >= nextJudgeAt do
			judgeIndex += 1
			ExecuteJudge(now, judgeIndex)
			nextJudgeAt += judgeSpan
		end
		if now >= earthquakeEndTime then
			EndEarthquake(now)
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
		local durationLeft = math.max(0, earthquakeEndTime - nowClock)
		NetMsg.FireNotifyEarthquakeStateToPlayer(player, earthquakeId, true, durationLeft, math.max(1, judgeCountMax))
		local droppedFloat, droppedPaved = BuildDroppedSnapshotPayload()
		if #droppedFloat > 0 or #droppedPaved > 0 then
			NetMsg.FireNotifyEarthquakeJudgeDropToPlayer(player, earthquakeId, judgeIndex, droppedFloat, droppedPaved)
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
