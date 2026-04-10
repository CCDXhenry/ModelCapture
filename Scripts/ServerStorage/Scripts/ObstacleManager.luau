--!strict
local ObstacleManager = {}

local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")
local tweenService: TweenService = game:GetService("TweenService")
local workspace: Workspace = game:GetService("Workspace")

local OBSTACLE_FOLDER_NAME = "Obstacle"
local OBSTACLE_FOLDER_WAIT_SECONDS = 5
local ISLAND_NAME_PATTERN = "^Island%d+$"
local FULL_CYCLE_DURATION_SECONDS = 4
local TOUCH_KILL_DEBOUNCE_SECONDS = 0.35
local MOVE_TWEEN_EASING_STYLE = Enum.EasingStyle.Linear
local MOVE_TWEEN_EASING_DIRECTION = Enum.EasingDirection.In

local ATTR_DURATION = "Duration"
local ATTR_DWELL_TIME = "DwellTime"
local ATTR_MOVE_MODEL = "MoveModel"
local ATTR_MIN_SCALE = "MinScale"
local ATTR_MAX_SCALE = "MaxScale"
local ATTR_SCALE_TIME = "ScaleTime"

local MOVE_MODEL_PING_PONG = 1
local MOVE_MODEL_LOOP = 2

local DEFAULT_DWELL_TIME_SECONDS = 0
local DEFAULT_MIN_SCALE = 1
local DEFAULT_SCALE_TIME_WHEN_ATTR_MISSING_SECONDS = 1
local SCALE_EQUALITY_EPSILON = 1e-5
local MIN_VALID_SCALE = 1e-3

local lastKillClockByUserId: { [number]: number } = {}
local isInitialized = false

type ObstacleMotionConfig = {
	minScale: Vector3,
	maxScale: Vector3,
	scaleTime: Vector3,
	needsScaleAnimation: boolean,
}

type WaypointConfig = {
	worldPosition: Vector3,
	durationToNext: number,
	dwellSeconds: number,
}

type ScaleAnimationEntry = {
	part: BasePart,
	baseSize: Vector3,
	minScale: Vector3,
	maxScale: Vector3,
	scaleTime: Vector3,
}

local scaleAnimationEntries: { ScaleAnimationEntry } = {}
local scaleHeartbeatConnection: RBXScriptConnection? = nil

local function easeInOutQuad(t: number): number
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - ((-2 * t + 2) ^ 2) / 2
end

local function axisOscMultiplier(minC: number, maxC: number, timeC: number, clock: number): number
	local period = 2 * timeC
	local u = (clock % period) / period * 2
	local w = if u <= 1 then u else 2 - u
	local e = easeInOutQuad(w)
	return minC + (maxC - minC) * e
end

local function composeSizeComponents(
	baseSize: Vector3,
	minS: Vector3,
	maxS: Vector3,
	scaleTime: Vector3,
	clock: number
): Vector3
	local function comp(baseComp: number, minC: number, maxC: number, timeC: number): number
		if math.abs(maxC - minC) <= SCALE_EQUALITY_EPSILON then
			return baseComp
		end
		if timeC <= 0 then
			return baseComp * minC
		end
		return baseComp * axisOscMultiplier(minC, maxC, timeC, clock)
	end
	return Vector3.new(
		comp(baseSize.X, minS.X, maxS.X, scaleTime.X),
		comp(baseSize.Y, minS.Y, maxS.Y, scaleTime.Y),
		comp(baseSize.Z, minS.Z, maxS.Z, scaleTime.Z)
	)
end

local function composeStaticSizeForNonAnimatedAxes(baseSize: Vector3, minS: Vector3, maxS: Vector3, scaleTime: Vector3): Vector3
	local function comp(baseComp: number, minC: number, maxC: number, timeC: number): number
		if math.abs(maxC - minC) <= SCALE_EQUALITY_EPSILON then
			return baseComp
		end
		if timeC <= 0 then
			return baseComp * minC
		end
		return baseComp
	end
	return Vector3.new(
		comp(baseSize.X, minS.X, maxS.X, scaleTime.X),
		comp(baseSize.Y, minS.Y, maxS.Y, scaleTime.Y),
		comp(baseSize.Z, minS.Z, maxS.Z, scaleTime.Z)
	)
end

local function sizesRoughlyEqual(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < SCALE_EQUALITY_EPSILON
end

local function ReadNonNegativeNumberAttribute(part: Instance, attrName: string, defaultValue: number): number
	local raw = part:GetAttribute(attrName)
	if type(raw) ~= "number" then
		return defaultValue
	end
	if raw ~= raw or raw < 0 then
		return defaultValue
	end
	return raw
end

-- Per-waypoint Duration: missing/invalid/negative → default; explicit 0 = instant leg (allowed).
local function ReadWaypointDurationSeconds(att: Attachment): number
	local raw = att:GetAttribute(ATTR_DURATION)
	if raw == nil then
		return FULL_CYCLE_DURATION_SECONDS
	end
	if type(raw) ~= "number" or raw ~= raw then
		return FULL_CYCLE_DURATION_SECONDS
	end
	if raw < 0 then
		return FULL_CYCLE_DURATION_SECONDS
	end
	return raw
end

local function ReadMoveModel(part: BasePart): number
	local raw = part:GetAttribute(ATTR_MOVE_MODEL)
	if raw == nil then
		return MOVE_MODEL_LOOP
	end
	if type(raw) ~= "number" or raw ~= raw then
		warn("[ObstacleManager] MoveModel invalid on", part:GetFullName(), "— using loop (2).")
		return MOVE_MODEL_LOOP
	end
	local r = math.floor(raw + 0)
	if r == MOVE_MODEL_PING_PONG or r == MOVE_MODEL_LOOP then
		return r
	end
	warn("[ObstacleManager] MoveModel must be 1 or 2 on", part:GetFullName(), "— using loop (2).")
	return MOVE_MODEL_LOOP
end

local function CollectOrderedWaypoints(part: BasePart): { WaypointConfig }?
	type IndexedAtt = { index: number, att: Attachment }
	local indexed: { IndexedAtt } = {}

	for _, child in part:GetChildren() do
		if child:IsA("Attachment") then
			local nStr = string.match(child.Name, "^Attachment(%d+)$")
			if nStr ~= nil then
				local idx = tonumber(nStr)
				if idx ~= nil and idx == idx and idx > 0 then
					table.insert(indexed, { index = idx, att = child })
				end
			end
		end
	end

	if #indexed < 2 then
		return nil
	end

	table.sort(indexed, function(a: IndexedAtt, b: IndexedAtt): boolean
		return a.index < b.index
	end)

	local waypoints: { WaypointConfig } = {}
	for _, entry in indexed do
		table.insert(waypoints, {
			worldPosition = entry.att.WorldPosition,
			durationToNext = ReadWaypointDurationSeconds(entry.att),
			dwellSeconds = ReadNonNegativeNumberAttribute(entry.att, ATTR_DWELL_TIME, DEFAULT_DWELL_TIME_SECONDS),
		})
	end
	return waypoints
end

local function ReadVector3Attribute(part: Instance, attrName: string, defaultVec: Vector3): Vector3
	local raw = part:GetAttribute(attrName)
	if typeof(raw) == "Vector3" then
		return raw :: Vector3
	end
	if type(raw) == "number" and raw == raw then
		return Vector3.one * raw
	end
	return defaultVec
end

local function SanitizeMinMaxScaleVector(v: Vector3, label: string, partFullName: string): Vector3
	local function f(c: number, axis: string): number
		if c ~= c or c <= 0 then
			warn("[ObstacleManager]", label, "invalid component", axis, "on", partFullName, "— using 1.")
			return DEFAULT_MIN_SCALE
		end
		return math.max(c, MIN_VALID_SCALE)
	end
	return Vector3.new(f(v.X, "X"), f(v.Y, "Y"), f(v.Z, "Z"))
end

local function SwapMinMaxPerAxisIfNeeded(minS: Vector3, maxS: Vector3, partFullName: string): (Vector3, Vector3)
	local x1, x2 = minS.X, maxS.X
	local y1, y2 = minS.Y, maxS.Y
	local z1, z2 = minS.Z, maxS.Z
	if x1 > x2 then
		warn("[ObstacleManager] MinScale.X > MaxScale.X on", partFullName, "— swapping.")
		x1, x2 = x2, x1
	end
	if y1 > y2 then
		warn("[ObstacleManager] MinScale.Y > MaxScale.Y on", partFullName, "— swapping.")
		y1, y2 = y2, y1
	end
	if z1 > z2 then
		warn("[ObstacleManager] MinScale.Z > MaxScale.Z on", partFullName, "— swapping.")
		z1, z2 = z2, z1
	end
	return Vector3.new(x1, y1, z1), Vector3.new(x2, y2, z2)
end

local function SanitizeScaleTimeComponent(c: number, axis: string, partFullName: string): number
	if c ~= c then
		return 0
	end
	if c < 0 then
		warn("[ObstacleManager] ScaleTime.", axis, "negative on", partFullName, "— using 0.")
		return 0
	end
	return c
end

local function AnyAxisWantsRange(minS: Vector3, maxS: Vector3): boolean
	return math.abs(maxS.X - minS.X) > SCALE_EQUALITY_EPSILON
		or math.abs(maxS.Y - minS.Y) > SCALE_EQUALITY_EPSILON
		or math.abs(maxS.Z - minS.Z) > SCALE_EQUALITY_EPSILON
end

local function ComputeNeedsScaleAnimation(minS: Vector3, maxS: Vector3, scaleTime: Vector3): boolean
	local function axisWants(minC: number, maxC: number, timeC: number): boolean
		return math.abs(maxC - minC) > SCALE_EQUALITY_EPSILON and timeC > 0
	end
	return axisWants(minS.X, maxS.X, scaleTime.X)
		or axisWants(minS.Y, maxS.Y, scaleTime.Y)
		or axisWants(minS.Z, maxS.Z, scaleTime.Z)
end

local function ParseScaleTimeVector(part: BasePart, anyAxisRange: boolean): Vector3
	local raw = part:GetAttribute(ATTR_SCALE_TIME)
	local partFullName = part:GetFullName()

	if raw == nil then
		if anyAxisRange then
			warn(
				"[ObstacleManager] ScaleTime attribute missing on",
				partFullName,
				"— using",
				tostring(DEFAULT_SCALE_TIME_WHEN_ATTR_MISSING_SECONDS),
				"s per axis (min→max leg)."
			)
			return Vector3.one * DEFAULT_SCALE_TIME_WHEN_ATTR_MISSING_SECONDS
		end
		return Vector3.one
	end

	local v: Vector3
	if typeof(raw) == "Vector3" then
		v = raw :: Vector3
	elseif type(raw) == "number" and raw == raw then
		v = Vector3.one * raw
	else
		if anyAxisRange then
			warn("[ObstacleManager] ScaleTime invalid type on", partFullName, "— using default per-axis time.")
			return Vector3.one * DEFAULT_SCALE_TIME_WHEN_ATTR_MISSING_SECONDS
		end
		return Vector3.one
	end

	return Vector3.new(
		SanitizeScaleTimeComponent(v.X, "X", partFullName),
		SanitizeScaleTimeComponent(v.Y, "Y", partFullName),
		SanitizeScaleTimeComponent(v.Z, "Z", partFullName)
	)
end

local function BuildObstacleMotionConfig(part: BasePart): ObstacleMotionConfig
	local minRaw = ReadVector3Attribute(part, ATTR_MIN_SCALE, Vector3.one)
	local maxRaw = ReadVector3Attribute(part, ATTR_MAX_SCALE, Vector3.one)
	local partFullName = part:GetFullName()
	local minScale = SanitizeMinMaxScaleVector(minRaw, "MinScale", partFullName)
	local maxScale = SanitizeMinMaxScaleVector(maxRaw, "MaxScale", partFullName)
	minScale, maxScale = SwapMinMaxPerAxisIfNeeded(minScale, maxScale, partFullName)

	local anyAxisRange = AnyAxisWantsRange(minScale, maxScale)
	local scaleTime = ParseScaleTimeVector(part, anyAxisRange)
	local needsScaleAnimation = ComputeNeedsScaleAnimation(minScale, maxScale, scaleTime)

	return {
		minScale = minScale,
		maxScale = maxScale,
		scaleTime = scaleTime,
		needsScaleAnimation = needsScaleAnimation,
	}
end

local function removeScaleEntriesForPart(target: BasePart)
	for i = #scaleAnimationEntries, 1, -1 do
		if scaleAnimationEntries[i].part == target then
			table.remove(scaleAnimationEntries, i)
		end
	end
end

local function ensureScaleHeartbeat()
	if scaleHeartbeatConnection ~= nil then
		return
	end
	scaleHeartbeatConnection = runService.Heartbeat:Connect(function()
		local clock = os.clock()
		for i = #scaleAnimationEntries, 1, -1 do
			local entry = scaleAnimationEntries[i]
			local p = entry.part
			if not p.Parent then
				table.remove(scaleAnimationEntries, i)
				continue
			end
			p.Size = composeSizeComponents(entry.baseSize, entry.minScale, entry.maxScale, entry.scaleTime, clock)
		end
	end)
end

local function registerScaleAnimationEntry(part: BasePart, baseSize: Vector3, config: ObstacleMotionConfig)
	local entry: ScaleAnimationEntry = {
		part = part,
		baseSize = baseSize,
		minScale = config.minScale,
		maxScale = config.maxScale,
		scaleTime = config.scaleTime,
	}
	table.insert(scaleAnimationEntries, entry)
	part.Destroying:Once(function()
		removeScaleEntriesForPart(part)
	end)
	ensureScaleHeartbeat()
end

local function applyOneTimeScaleWhenNoHeartbeat(part: BasePart, baseSize: Vector3, config: ObstacleMotionConfig)
	local nextSize = composeStaticSizeForNonAnimatedAxes(baseSize, config.minScale, config.maxScale, config.scaleTime)
	if not sizesRoughlyEqual(nextSize, baseSize) then
		part.Size = nextSize
	end
end

local function computeNextIndexPingPong(i: number, n: number, step: number): (number, number)
	local nextIndex = i + step
	if nextIndex > n then
		return n - 1, -1
	end
	if nextIndex < 1 then
		return 2, 1
	end
	return nextIndex, step
end

local function RunMultiWaypointLoop(part: BasePart, waypoints: { WaypointConfig }, rotation: CFrame, moveModel: number)
	local n = #waypoints
	if n < 2 then
		return
	end

	local i = 1
	local step = 1

	while part.Parent do
		part.CFrame = CFrame.new(waypoints[i].worldPosition) * rotation

		local dwell = waypoints[i].dwellSeconds
		if dwell > 0 then
			local t0 = os.clock()
			while part.Parent and os.clock() - t0 < dwell do
				task.wait()
			end
		end

		if not part.Parent then
			break
		end

		local nextIndex: number
		if moveModel == MOVE_MODEL_LOOP then
			nextIndex = (i % n) + 1
		else
			local newStep: number
			nextIndex, newStep = computeNextIndexPingPong(i, n, step)
			step = newStep
		end

		local legDuration = waypoints[i].durationToNext
		local nextCFrame = CFrame.new(waypoints[nextIndex].worldPosition) * rotation

		if legDuration > 0 then
			local moveTween = tweenService:Create(
				part,
				TweenInfo.new(legDuration, MOVE_TWEEN_EASING_STYLE, MOVE_TWEEN_EASING_DIRECTION, 0, false, 0),
				{ CFrame = nextCFrame }
			)
			local finished = false
			local conn = moveTween.Completed:Connect(function()
				finished = true
			end)
			moveTween:Play()
			while not finished and part.Parent do
				task.wait()
			end
			conn:Disconnect()
			moveTween:Cancel()
		else
			part.CFrame = nextCFrame
		end

		if not part.Parent then
			break
		end

		i = nextIndex
	end
end

local function StartObstacleMotionAndScale(part: BasePart, waypoints: { WaypointConfig }?, moveModel: number?)
	local config = BuildObstacleMotionConfig(part)
	local baseSize = part.Size
	local rotation = part.CFrame.Rotation

	if config.needsScaleAnimation then
		registerScaleAnimationEntry(part, baseSize, config)
		part.Size = composeSizeComponents(baseSize, config.minScale, config.maxScale, config.scaleTime, os.clock())
	else
		applyOneTimeScaleWhenNoHeartbeat(part, baseSize, config)
	end

	if waypoints ~= nil and #waypoints >= 2 then
		part.CFrame = CFrame.new(waypoints[1].worldPosition) * rotation
		local model = if moveModel ~= nil then moveModel else MOVE_MODEL_LOOP
		task.spawn(function()
			RunMultiWaypointLoop(part, waypoints, rotation, model)
		end)
	end
end

local function OnObstacleTouched(_obstaclePart: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return
	end
	local player = players:GetPlayerFromCharacter(character)
	if player == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	if humanoid.Health <= 0 then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return
	end

	local now = os.clock()
	local last = lastKillClockByUserId[player.UserId]
	if last ~= nil and now - last < TOUCH_KILL_DEBOUNCE_SECONDS then
		return
	end
	lastKillClockByUserId[player.UserId] = now
	humanoid.Health = 0
end

local function ScanObstacleFolder(obstacleFolder: Instance)
	table.clear(scaleAnimationEntries)
	local validObstacleCount = 0

	for _, island in obstacleFolder:GetChildren() do
		if not (island:IsA("Folder") or island:IsA("Model")) then
			continue
		end
		if string.match(island.Name, ISLAND_NAME_PATTERN) == nil then
			continue
		end

		for _, obstaclePart in island:GetChildren() do
			if not obstaclePart:IsA("BasePart") then
				continue
			end

			local waypoints = CollectOrderedWaypoints(obstaclePart)
			if waypoints == nil then
				warn(
					"[ObstacleManager] Need at least two Attachment1, Attachment2, … under",
					obstaclePart:GetFullName(),
					"— motion disabled; scale/touch only."
				)
			end

			validObstacleCount += 1

			obstaclePart.Touched:Connect(function(hit: BasePart)
				OnObstacleTouched(obstaclePart, hit)
			end)

			local moveModel = if waypoints ~= nil then ReadMoveModel(obstaclePart) else nil
			StartObstacleMotionAndScale(obstaclePart, waypoints, moveModel)
		end
	end

	if validObstacleCount == 0 then
		warn("[ObstacleManager] No valid obstacles under", obstacleFolder:GetFullName())
	end
end

function ObstacleManager.Init()
	if isInitialized then
		return
	end

	local obstacleFolder = workspace:WaitForChild(OBSTACLE_FOLDER_NAME, OBSTACLE_FOLDER_WAIT_SECONDS)
	if obstacleFolder == nil then
		warn("[ObstacleManager] Workspace." .. OBSTACLE_FOLDER_NAME .. " not found within " .. tostring(OBSTACLE_FOLDER_WAIT_SECONDS) .. "s; skipping.")
		return
	end

	isInitialized = true
	ScanObstacleFolder(obstacleFolder)

	players.PlayerRemoving:Connect(function(player: Player)
		lastKillClockByUserId[player.UserId] = nil
	end)
end

return ObstacleManager
