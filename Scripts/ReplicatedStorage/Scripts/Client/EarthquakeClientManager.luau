--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local EarthquakeClientManager = {}

type DropKind = "FloatBlock" | "PavedBrick"

type DropAnimState = {
	part: BasePart,
	baseCFrame: CFrame,
	fallToY: number,
	phase: string,
	phaseStartAt: number,
	fromCFrame: CFrame,
	toCFrame: CFrame,
	dropKind: DropKind,
}

local localPlayer = Players.LocalPlayer
local earthquakeActive = false
local warningUiToken = 0
local earthquakeActiveUiToken = 0

local trackedPartMap: { [BasePart]: CFrame } = {}
local droppedAnimMap: { [BasePart]: DropAnimState } = {}
local markedBrickColorValue = BrickColor.new(GameConfig.Earthquake.MarkedBrickColor :: any)

type MarkedVisualState = {
	baseCFrame: CFrame,
	originalBrickColor: BrickColor,
	originalMaterial: Enum.Material,
	originalTransparency: number,
}

local markedPartMap: { [BasePart]: MarkedVisualState } = {}
local lastMarkedRefreshAt = 0

local MARKED_PARTS_REFRESH_INTERVAL = 0.2

local function GetMarkedTransparencyForKind(kind: unknown): number
	local raw: number
	if kind == "PavedBrick" then
		raw = GameConfig.Earthquake.MarkedPavedBrickTransparency or 0
	else
		raw = GameConfig.Earthquake.MarkedFloatBlockTransparency or 0
	end
	return math.clamp(raw, 0, 1)
end

local floatFolder: Folder? = nil
local islandsFolder: Folder? = nil
local _pavedBricksFolder: Folder? = nil

local function GetHumanoid(): Humanoid?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function ApplyEarthquakeCameraShake(now: number)
	local humanoid = GetHumanoid()
	if not humanoid then
		return
	end
	local amp = GameConfig.Earthquake.ScreenShakeAmplitude
	local freq = GameConfig.Earthquake.ScreenShakeFrequency
	local t = now * freq
	local ox = math.sin(t * 1.1) * amp
	local oy = math.cos(t * 0.9) * amp * 0.4
	local oz = math.sin(t * 0.8) * amp * 0.3
	humanoid.CameraOffset = Vector3.new(ox, oy, oz)
end

local function GetRotationOnly(cframe: CFrame): CFrame
	return cframe - cframe.Position
end

local function BuildTargetCFrame(baseCFrame: CFrame, yValue: number): CFrame
	local pos = baseCFrame.Position
	return CFrame.new(pos.X, yValue, pos.Z) * GetRotationOnly(baseCFrame)
end

local function TrackPart(part: BasePart)
	if not part:IsDescendantOf(workspace) then
		return
	end
	if not part.Anchored then
		return
	end
	trackedPartMap[part] = part.CFrame
end

local function ApplyMarkedVisual(part: BasePart)
	-- 只做“外观标记”：不影响物理碰撞（全部是纯表现/断裂在客户端完成）
	local state = markedPartMap[part]
	if state == nil then
		markedPartMap[part] = {
			baseCFrame = part.CFrame,
			originalBrickColor = part.BrickColor,
			originalMaterial = part.Material,
			originalTransparency = part.Transparency,
		}
	end

	part.BrickColor = markedBrickColorValue
	part.Transparency = GetMarkedTransparencyForKind(part:GetAttribute("EarthquakeMarkedKind"))
end

local function TryMarkPart(part: Instance)
	if not part or not part:IsA("BasePart") then
		return
	end
	local basePart = part :: BasePart
	if basePart:GetAttribute("EarthquakeMarkedForDrop") ~= true then
		return
	end
	ApplyMarkedVisual(basePart)
end

local function RefreshMarkedParts()
	if floatFolder then
		for _, desc in ipairs(floatFolder:GetDescendants()) do
			if desc:IsA("BasePart") then
				TryMarkPart(desc)
			end
		end
	end
	if _pavedBricksFolder then
		for _, child in ipairs(_pavedBricksFolder:GetChildren()) do
			TryMarkPart(child)
		end
	end
end

-- 地震摇晃结束、掉落动画尚未开始时：去掉水平抖动（复位 CFrame）；仍带掉落标记的块保持标记色，避免先闪回本体色再等掉落包重新上色。
local function RestoreAllMarkedPhaseVisuals()
	local snapshot: { [BasePart]: MarkedVisualState } = {}
	for part, state in pairs(markedPartMap) do
		snapshot[part] = state
	end
	for part, state in pairs(snapshot) do
		if part.Parent ~= nil then
			part.CFrame = state.baseCFrame
			if part:GetAttribute("EarthquakeMarkedForDrop") == true then
				local kind = part:GetAttribute("EarthquakeMarkedKind")
				part.BrickColor = markedBrickColorValue
				part.Transparency = GetMarkedTransparencyForKind(kind)
			else
				part.BrickColor = state.originalBrickColor
				part.Material = state.originalMaterial
				part.Transparency = state.originalTransparency
			end
		end
		markedPartMap[part] = nil
	end
end

local function UpdateMarkedJitter(now: number)
	if not earthquakeActive then
		return
	end
	local floatAmp = GameConfig.Earthquake.MarkedShakeAmplitude or 0.6
	local floatFreq = GameConfig.Earthquake.MarkedShakeFrequency or 10
	local pavedAmp = GameConfig.Earthquake.MarkedPavedShakeAmplitude or 0.22
	local pavedFreq = GameConfig.Earthquake.MarkedPavedShakeFrequency or 6.5

	for part, state in pairs(markedPartMap) do
		if part.Parent == nil then
			markedPartMap[part] = nil
			continue
		end

		-- 若已经开始掉落动画，则不再对“已掉落物”做额外抖动，避免干扰 CFrame
		if droppedAnimMap[part] ~= nil then
			continue
		end

		-- 标记属性仍存在才抖动；服务器在真正掉落前会清除标记属性
		if part:GetAttribute("EarthquakeMarkedForDrop") ~= true then
			-- 被服务端取消标记且并未进入掉落动画：恢复正常外观（用于“保留的最后一块砖”）。
			part.BrickColor = state.originalBrickColor
			part.Material = state.originalMaterial
			part.Transparency = state.originalTransparency
			markedPartMap[part] = nil
			continue
		end

		local kind = part:GetAttribute("EarthquakeMarkedKind")
		local amp = if kind == "PavedBrick" then pavedAmp else floatAmp
		local freq = if kind == "PavedBrick" then pavedFreq else floatFreq

		-- 服务器可能会把砖转成幽灵态并改材质，所以这里持续保持标记的深褐色外观
		part.BrickColor = markedBrickColorValue
		part.Transparency = GetMarkedTransparencyForKind(kind)

		-- 计算抖动 seed：优先使用 EarthquakeGuid，兜底用位置，避免 forward 引用导致静态分析报错
		local guid = part:GetAttribute("EarthquakeGuid")
		local seed: number
		if type(guid) == "string" then
			local hash = 0
			for i = 1, math.min(8, #guid) do
				hash += string.byte(guid, i)
			end
			seed = hash * 0.1
		else
			local p = part.Position
			local q = math.floor(p.X * 10) + math.floor(p.Y * 10) * 3 + math.floor(p.Z * 10) * 7
			seed = q * 0.01
		end
		local dx = math.sin((now + seed) * freq) * amp
		local dz = math.cos((now + seed * 0.73) * freq) * amp
		part.CFrame = state.baseCFrame * CFrame.new(dx, 0, dz)
	end
end

local function UntrackPart(part: BasePart)
	trackedPartMap[part] = nil
	droppedAnimMap[part] = nil
end

local function TrackDescendantParts(root: Instance)
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			TrackPart(desc)
		end
	end
end

-- 铺砖 Part 的地震标记依赖复制属性；ChildAdded 时属性可能尚未到达，需监听变化以免依赖 0.2s 全量补扫。
local pavedBrickEarthquakeHooked: { [BasePart]: true } = {}

local function HookPavedBrickEarthquakeReplication(part: BasePart)
	if pavedBrickEarthquakeHooked[part] then
		return
	end
	pavedBrickEarthquakeHooked[part] = true
	part:GetAttributeChangedSignal("EarthquakeMarkedForDrop"):Connect(function()
		TryMarkPart(part)
	end)
	part:GetAttributeChangedSignal("EarthquakeMarkedKind"):Connect(function()
		TryMarkPart(part)
	end)
end

local function OnPavedBrickAdded(child: Instance)
	if child:IsA("BasePart") then
		local brick = child :: BasePart
		HookPavedBrickEarthquakeReplication(brick)
		TrackPart(brick)
		TryMarkPart(brick)
	end
end

local function HookPavedBricksFolder(folder: Folder)
	_pavedBricksFolder = folder
	for _, child in ipairs(folder:GetChildren()) do
		OnPavedBrickAdded(child)
	end
	folder.ChildAdded:Connect(OnPavedBrickAdded)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			pavedBrickEarthquakeHooked[child :: BasePart] = nil
			UntrackPart(child)
		end
	end)
end

local function StartDropAnim(part: BasePart, baseCFrame: CFrame, fallToY: number, dropKind: DropKind)
	local fallTargetCFrame = BuildTargetCFrame(baseCFrame, fallToY)
	droppedAnimMap[part] = {
		part = part,
		baseCFrame = baseCFrame,
		fallToY = fallToY,
		phase = "intense",
		phaseStartAt = os.clock(),
		fromCFrame = baseCFrame,
		toCFrame = fallTargetCFrame,
		dropKind = dropKind,
	}
end

local function StartRecoverAnim(part: BasePart, baseCFrame: CFrame)
	local anim = droppedAnimMap[part]
	if anim == nil then
		-- 容错：客户端尚未收到该 part 的掉落消息时，直接执行回浮动画。
		local current = part.CFrame
		droppedAnimMap[part] = {
			part = part,
			baseCFrame = baseCFrame,
			fallToY = current.Position.Y,
			phase = "rise",
			phaseStartAt = os.clock(),
			fromCFrame = current,
			toCFrame = baseCFrame,
			dropKind = "FloatBlock",
		}
		return
	end
	anim.baseCFrame = baseCFrame
	anim.phase = "rise"
	anim.phaseStartAt = os.clock()
	anim.fromCFrame = part.CFrame
	anim.toCFrame = baseCFrame
end

local function HashNumberFromPart(part: BasePart): number
	local guid = part:GetAttribute("EarthquakeGuid")
	if type(guid) ~= "string" then
		-- 若没有 guid（例如仅在“标记阶段”被通知），用位置做一个可重复的 seed
		local p = part.Position
		local seed = math.floor(p.X * 10) + math.floor(p.Y * 10) * 3 + math.floor(p.Z * 10) * 7
		return seed * 0.01
	end
	local hash = 0
	for i = 1, math.min(8, #guid) do
		hash += string.byte(guid, i)
	end
	return hash * 0.1
end

local function UpdateDropAnimations(now: number)
	local intenseAmplitude = GameConfig.Earthquake.IntenseShakeAmplitude
	local intenseFrequency = GameConfig.Earthquake.IntenseShakeFrequency
	local intenseDuration = GameConfig.Earthquake.PreFallIntenseDuration
	local fallDuration = GameConfig.Earthquake.FallDuration
	local riseDuration = GameConfig.Earthquake.RiseDuration

	for part, anim in pairs(droppedAnimMap) do
		if part.Parent == nil then
			droppedAnimMap[part] = nil
			continue
		end

		local elapsed = now - anim.phaseStartAt
		if anim.phase == "intense" then
			local seed = HashNumberFromPart(part)
			local dx = math.sin((now + seed) * intenseFrequency) * intenseAmplitude
			local dz = math.cos((now + seed * 0.73) * intenseFrequency) * intenseAmplitude
			part.CFrame = anim.baseCFrame * CFrame.new(dx, 0, dz)
			if elapsed >= intenseDuration then
				anim.phase = "fall"
				anim.phaseStartAt = now
				anim.fromCFrame = part.CFrame
				anim.toCFrame = BuildTargetCFrame(anim.baseCFrame, anim.fallToY)
			end
		elseif anim.phase == "fall" then
			local alpha = math.clamp(elapsed / math.max(0.01, fallDuration), 0, 1)
			part.CFrame = anim.fromCFrame:Lerp(anim.toCFrame, alpha)
			if alpha >= 1 then
				anim.phase = "fallen"
				anim.phaseStartAt = now
			end
		elseif anim.phase == "fallen" then
			-- 不再对锚固块做水平位移，避免与服务器碰撞不同步导致穿模
			local fallenBase = BuildTargetCFrame(anim.baseCFrame, anim.fallToY)
			part.CFrame = fallenBase
			if anim.dropKind == "PavedBrick" then
				continue
			end
		elseif anim.phase == "rise" then
			local alpha = math.clamp(elapsed / math.max(0.01, riseDuration), 0, 1)
			part.CFrame = anim.fromCFrame:Lerp(anim.toCFrame, alpha)
			if alpha >= 1 then
				part.CFrame = anim.baseCFrame
				trackedPartMap[part] = anim.baseCFrame
				droppedAnimMap[part] = nil
			end
		end
	end
end

local function OnRenderStep()
	local now = os.clock()
	if earthquakeActive then
		ApplyEarthquakeCameraShake(now)
		-- 降低补扫频率，避免每帧遍历目录导致客户端输入延迟。
		if now - lastMarkedRefreshAt >= MARKED_PARTS_REFRESH_INTERVAL then
			lastMarkedRefreshAt = now
			RefreshMarkedParts()
		end
	else
		local humanoid = GetHumanoid()
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
		for part, baseCFrame in pairs(trackedPartMap) do
			if part.Parent == nil then
				trackedPartMap[part] = nil
			elseif droppedAnimMap[part] == nil then
				part.CFrame = baseCFrame
			end
		end
	end
	UpdateDropAnimations(now)
	UpdateMarkedJitter(now)
end

local function HandleDropEntry(entry: any)
	if type(entry) ~= "table" then
		return
	end
	local part = entry.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	local dropKind: DropKind = if entry.kind == "PavedBrick" then "PavedBrick" else "FloatBlock"
	local baseCFrame = entry.baseCFrame
	if typeof(baseCFrame) ~= "CFrame" then
		baseCFrame = part.CFrame
	end
	local fallToY = entry.fallToY
	if type(fallToY) ~= "number" then
		fallToY = baseCFrame.Position.Y - 4
	end

	-- 掉落开始：触发纯表现断裂，并确保可视上是标记色
	if dropKind == "FloatBlock" and markedPartMap[part] == nil then
		-- 若玩家在掉落阶段才加入，之前的“标记阶段外观”可能没来得及记录原始外观
		markedPartMap[part] = {
			baseCFrame = part.CFrame,
			originalBrickColor = part.BrickColor,
			originalMaterial = part.Material,
			originalTransparency = part.Transparency,
		}
	end
	part.BrickColor = BrickColor.new(GameConfig.Earthquake.MarkedBrickColor :: any)
	part.Transparency = GetMarkedTransparencyForKind(dropKind)
	--part.Material = Enum.Material.SmoothPlastic

	-- PavedBrick 掉落后会被服务器回收/移除；不需要等待“回浮”
	if dropKind == "PavedBrick" then
		markedPartMap[part] = nil
	end

	trackedPartMap[part] = baseCFrame
	StartDropAnim(part, baseCFrame, fallToY, dropKind)
end

local function HandleRecoverEntry(entry: any)
	if type(entry) ~= "table" then
		return
	end
	if entry.kind == "PavedBrick" then
		return
	end
	local part = entry.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	local baseCFrame = entry.baseCFrame
	if typeof(baseCFrame) ~= "CFrame" then
		baseCFrame = trackedPartMap[part] or part.CFrame
	end

	-- 回浮结束：恢复掉落前的原始外观
	local markedState = markedPartMap[part]
	if markedState ~= nil then
		part.BrickColor = markedState.originalBrickColor
		part.Material = markedState.originalMaterial
		part.Transparency = markedState.originalTransparency
		markedPartMap[part] = nil
	end

	StartRecoverAnim(part, baseCFrame)
end

function EarthquakeClientManager.Init()
	islandsFolder = workspace:FindFirstChild("Islands") :: Folder?
	floatFolder = workspace:FindFirstChild("FloatBlock") :: Folder?

	if islandsFolder then
		TrackDescendantParts(islandsFolder)
		islandsFolder.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				TrackPart(desc)
			end
		end)
	end
	if floatFolder then
		TrackDescendantParts(floatFolder)
		floatFolder.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				TrackPart(desc)
				TryMarkPart(desc)
			end
		end)
	end

	local existedPaved = workspace:FindFirstChild("PavedBricks")
	if existedPaved and existedPaved:IsA("Folder") then
		HookPavedBricksFolder(existedPaved)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "PavedBricks" and child:IsA("Folder") then
			HookPavedBricksFolder(child :: Folder)
		end
	end)

	NetMsg.ConnectNotifyEarthquakeWarning(function(earthquakeId: number, secondsUntilStart: number)
		warningUiToken += 1
		local token = warningUiToken
		task.spawn(function()
			local n = math.max(0, math.floor(secondsUntilStart))
			while n > 0 do
				if token ~= warningUiToken then
					return
				end
				ClientMsg.FireEarthquakeUiUpdate("warning", n)
				task.wait(1)
				n -= 1
			end
		end)
	end)

	NetMsg.ConnectNotifyEarthquakeState(function(earthquakeId: number, isStart: boolean, duration: number, _judgeCount: number)
		earthquakeActive = isStart
		if isStart then
			RefreshMarkedParts()
			warningUiToken += 1
			earthquakeActiveUiToken += 1
			local token = earthquakeActiveUiToken
			local endAt = os.clock() + math.max(0, duration)
			task.spawn(function()
				while true do
					if token ~= earthquakeActiveUiToken then
						return
					end
					local remaining = math.max(0, math.ceil(endAt - os.clock()))
					ClientMsg.FireEarthquakeUiUpdate("active", remaining)
					if remaining <= 0 then
						return
					end
					task.wait(1)
				end
			end)
		else
			RestoreAllMarkedPhaseVisuals()
			earthquakeActiveUiToken += 1
			ClientMsg.FireEarthquakeUiUpdate("hide", nil)
		end
	end)

	NetMsg.ConnectNotifyEarthquakeJudgeDrop(function(earthquakeId: number, _judgeIndex: number, droppedFloatBlocks: { any }, droppedPavedBricks: { any })
		for _, entry in ipairs(droppedFloatBlocks) do
			HandleDropEntry(entry)
		end
		for _, entry in ipairs(droppedPavedBricks) do
			HandleDropEntry(entry)
		end
	end)

	NetMsg.ConnectNotifyEarthquakeRecover(function(earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any })
		for _, entry in ipairs(recoverFloatBlocks) do
			HandleRecoverEntry(entry)
		end
	end)

	RunService.RenderStepped:Connect(OnRenderStep)
end

return EarthquakeClientManager
