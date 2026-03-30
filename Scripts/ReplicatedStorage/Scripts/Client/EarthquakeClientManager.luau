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
local currentEarthquakeId = 0
local warningUiToken = 0
local earthquakeActiveUiToken = 0

local trackedPartMap: { [BasePart]: CFrame } = {}
local droppedAnimMap: { [BasePart]: DropAnimState } = {}

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

local function OnPavedBrickAdded(child: Instance)
	if child:IsA("BasePart") then
		TrackPart(child)
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
		return 0
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
		currentEarthquakeId = earthquakeId
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
		currentEarthquakeId = earthquakeId
		earthquakeActive = isStart
		if isStart then
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
			earthquakeActiveUiToken += 1
			ClientMsg.FireEarthquakeUiUpdate("hide", nil)
		end
	end)

	NetMsg.ConnectNotifyEarthquakeJudgeDrop(function(earthquakeId: number, _judgeIndex: number, droppedFloatBlocks: { any }, droppedPavedBricks: { any })
		if currentEarthquakeId ~= 0 and earthquakeId ~= currentEarthquakeId then
			return
		end
		for _, entry in ipairs(droppedFloatBlocks) do
			HandleDropEntry(entry)
		end
		for _, entry in ipairs(droppedPavedBricks) do
			HandleDropEntry(entry)
		end
	end)

	NetMsg.ConnectNotifyEarthquakeRecover(function(earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any })
		if currentEarthquakeId ~= 0 and earthquakeId ~= currentEarthquakeId then
			return
		end
		for _, entry in ipairs(recoverFloatBlocks) do
			HandleRecoverEntry(entry)
		end
	end)

	RunService.RenderStepped:Connect(OnRenderStep)
end

return EarthquakeClientManager
