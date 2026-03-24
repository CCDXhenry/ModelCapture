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
local GRID_SIZE = GameConfig.Paving.BrickSize.X or 4
local SEA_LEVEL = 0
local isPavingMode = false
local isAwaitingRescue = false
local stationaryTime = 0
local lastStationaryPos: Vector3? = nil
local lastRefillTime = 0

-- Local prediction config
local LOCAL_PREDICT_TTL = GameConfig.Paving.LocalPredictTTL
local LOCAL_PREDICT_BATCH_INTERVAL = GameConfig.Paving.BatchInterval
local MAX_INTERPOLATION_STEPS = GameConfig.Paving.MaxInterpolationSteps

local localBrickFolder = Instance.new("Folder")
localBrickFolder.Name = "LocalPredictBricks"
localBrickFolder.Parent = workspace

type LocalPredictEntry = {
	part: Part,
	createdAt: number,
	requested: boolean,
}
local localBrickMap: { [string]: LocalPredictEntry } = {}
local touchConns: { [Part]: RBXScriptConnection } = {}
local localBrickPool: { Part } = {}
local pendingPaveQueue: { Vector3 } = {}
local lastBatchTime = 0

-- Object pool management
local function GetBrickFromPool(): Part?
	local brick = table.remove(localBrickPool)
	if brick then
		brick.Transparency = 0.5
		brick.Parent = localBrickFolder
		return brick
	end

	brick = Instance.new("Part")
	if not brick then
		return nil
	end
	brick.Name = "LocalPredictBrick"
	brick.Size = Vector3.new(GRID_SIZE, 1, GRID_SIZE)
	brick.Anchored = true
	brick.CanCollide = true
	brick.CanQuery = false
	brick.Transparency = 1
	brick.Color = Color3.fromRGB(255, 255, 0)
	brick.Material = Enum.Material.Neon
	brick.CastShadow = false
	brick:SetAttribute("IsLocal", true)
	brick.Parent = localBrickFolder
	return brick
end

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

if startAttachment then
	SEA_LEVEL = startAttachment.WorldPosition.Y
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

-- Efficient removal
local function RemoveLocalBrickEntry(key: string)
	local entry = localBrickMap[key]
	if entry then
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
	print("[PavingClient] Cleared all local prediction bricks and queue")
end

local function RequestPlaceBrick(targetPos: Vector3)
	local now = os.clock()
	local key = GetPosKey(targetPos)
	if localBrickMap[key] then
		return
	end

	-- 2. Create local prediction
	local brick: Part? = GetBrickFromPool()
	if not brick then
		return
	end
	brick.Position = targetPos

	localBrickMap[key] = {
		part = brick,
		createdAt = now,
		requested = false,
	}

	local character = localPlayer.Character
	local function triggerPave()
		local entry = localBrickMap[key]
		if entry and not entry.requested then
			entry.requested = true
			table.insert(pendingPaveQueue, targetPos)
		end
	end

	touchConns[brick] = brick.Touched:Connect(function(otherPart)
		if character and otherPart:IsDescendantOf(character) then
			triggerPave()
		end
	end)

	if character then
		local overlapParts = workspace:GetPartBoundsInBox(brick.CFrame, brick.Size)
		for _, part in overlapParts do
			if part:IsDescendantOf(character) then
				triggerPave()
				break
			end
		end
	end
end

-- Check if brick exists (excluding local predictions)
local function CheckBrickExists(targetPos: Vector3, character: Model): boolean
	local checkOrigin = targetPos + Vector3.new(0, 5, 0)
	local checkDir = Vector3.new(0, -10, 0)
	local checkParams = RaycastParams.new()
	checkParams.FilterType = Enum.RaycastFilterType.Include
	local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
	checkParams.FilterDescendantsInstances = { pavedBricksFolder }

	local checkResult = workspace:Raycast(checkOrigin, checkDir, checkParams)
	if checkResult and checkResult.Instance and checkResult.Position.Y >= SEA_LEVEL - 0.5 then
		-- 如果检测到的是幽灵砖块 (即将消失)，则视作不存在，从而触发填实逻辑
		if checkResult.Instance:GetAttribute("IsGhost") == true then
			return false
		end
		return true
	end
	return false
end

-- Area check helper
local function IsInFloatBlockZone(targetPos: Vector3): boolean
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if not floatBlockFolder then
		return false
	end

	local rayOrigin = targetPos + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -60, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floatBlockFolder }

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	return result ~= nil
end

local function IsAtSafeZone(targetPos: Vector3): boolean
	local groundFolder = workspace:FindFirstChild("Ground")
	local islandsFolder = workspace:FindFirstChild("Islands")
	local homesFolder = workspace:FindFirstChild("PlayersHome")

	local rayOrigin = targetPos + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -60, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local filterInstances = {}
	if groundFolder then
		table.insert(filterInstances, groundFolder)
	end
	if islandsFolder then
		table.insert(filterInstances, islandsFolder)
	end
	if homesFolder then
		table.insert(filterInstances, homesFolder)
	end

	if #filterInstances > 0 then
		raycastParams.FilterDescendantsInstances = filterInstances
		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		return result ~= nil
	end
	return false
end

local function OnHeartbeat(dt: number)
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid

	-- 1. Hard cleanup conditions (Death/Falling/Invalid state)
	local now = os.clock()
	local pos = if rootPart then rootPart.Position else nil
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
			lastPavePosition = nil
			print("[PavingClient] Mode reset due to death/falling")
		end
		ClearLocalBricks()
		return
	end

	-- 2. Mode Activation Check (Start Trigger)
	-- This must be checked regardless of isPavingMode to allow activation
	if startTrigger and pos then
		local distX = math.abs(pos.X - startTrigger.Position.X)
		if distX < GameConfig.Paving.StartActivationRange then
			if not isPavingMode then
				isPavingMode = true
				print("[PavingClient] Mode activated")

				-- -- 【新增】：激活瞬间，强制在玩家当前脚底“打桩”，防止初始掉落
				-- local currentSnapped = GetSnappedPosition(pos)
				-- RequestPlaceBrick(currentSnapped)
				-- lastPavePosition = currentSnapped

				-- 【新增】：如果有惯性方向，额外在前方一格预铺一块
				local velocity = rootPart.AssemblyLinearVelocity
				if velocity.Magnitude > 1 then
					local horizUnit = Vector3.new(velocity.X, 0, velocity.Z).Unit
					local forwardSnapped = GetSnappedPosition(pos + horizUnit * GRID_SIZE)
					RequestPlaceBrick(forwardSnapped)
				end

				-- 【新增】：强制重置发送计时器，让接下来的 batch 逻辑在当前帧立刻发送给服务端
				lastBatchTime = 0
			end

			if now - lastRefillTime > 2 then
				NetMsg.FireRequestStartPaving()
				lastRefillTime = now
			end
		end
	end

	-- 3. Soft Deactivation (ONLY for hard failures or running out of bricks)
	-- Removed Safe Zone auto-exit to allow paving from islands into the sea.
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	local isOutOfBricks = playerInfo ~= nil and playerInfo.carriedInfo.bricks <= 0

	if isPavingMode and isOutOfBricks then
		isPavingMode = false
		lastPavePosition = nil
		ClearLocalBricks()
		--print("[PavingClient] Mode exited (Out of bricks)")
		return
	end

	-- 4. Execution Guard (If still not in paving mode, stop here)
	if not isPavingMode or not pos or not rootPart or not humanoid then
		return
	end

	-- 3. Inventory check (Double check for execution)
	if playerInfo == nil or playerInfo.carriedInfo.bricks <= 0 then
		return
	end

	-- 4. Paving logic calculation (修改：基于物理惯性的方向预判)
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
	local lookaheadFactor = if isStationary then 0.5 else math.clamp(speed / playerWalkSpeed, 1.0, 1.5)
	local targetPos = GetSnappedPosition(pos + moveDir * (GRID_SIZE * lookaheadFactor))

	-- [优化] Stationary renewal (防止原地发呆无限扣砖)
	local RENEWAL_INTERVAL = GameConfig.Paving.StationaryRenewalInterval or 0.2
	if isStationary then
		if lastStationaryPos and (targetPos - lastStationaryPos).Magnitude < 0.1 then
			stationaryTime += dt
			if stationaryTime >= RENEWAL_INTERVAL then
				stationaryTime = 0
				-- 加上射线检测与安全区检测
				if not IsAtSafeZone(targetPos) and not IsInFloatBlockZone(targetPos) and not CheckBrickExists(targetPos, character) then
					RequestPlaceBrick(targetPos)
				end
			end
		else
			lastStationaryPos = targetPos
			stationaryTime = 0
			-- [顺发] 当检测到刚停下时，立即尝试续期一次，不再等待计时器
			if not IsAtSafeZone(targetPos) and not IsInFloatBlockZone(targetPos) and not CheckBrickExists(targetPos, character) then
				RequestPlaceBrick(targetPos)
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

		if dist < GRID_SIZE * 0.9 then
			-- No action
		elseif dist > GRID_SIZE * 1.1 then
			local stepCount = math.clamp(math.floor(dist / GRID_SIZE), 1, MAX_INTERPOLATION_STEPS)
			local unitDir = diff.Unit
			local startPos = lastPavePosition
			for i = 1, stepCount do
				local interimPos = GetSnappedPosition(startPos + unitDir * (i * GRID_SIZE))
				if not IsAtSafeZone(interimPos) and not IsInFloatBlockZone(interimPos) and not CheckBrickExists(interimPos, character) then
					RequestPlaceBrick(interimPos)
				end
				lastPavePosition = interimPos
			end
		else
			if not IsAtSafeZone(targetPos) and not IsInFloatBlockZone(targetPos) and not CheckBrickExists(targetPos, character) then
				lastPavePosition = targetPos
				RequestPlaceBrick(targetPos)
			else
				lastPavePosition = targetPos
			end
		end
	else
		if not IsAtSafeZone(targetPos) and not IsInFloatBlockZone(targetPos) and not CheckBrickExists(targetPos, character) then
			lastPavePosition = targetPos
			RequestPlaceBrick(targetPos)
		end
	end

	-- [优化] Batch transmission (防止卡顿导致包过大被服务器拒收)
	if #pendingPaveQueue > 0 and (now - lastBatchTime >= LOCAL_PREDICT_BATCH_INTERVAL) then
		local maxBatchSize = GameConfig.Paving.MaxBatchSize
		-- 把积压的请求拆分成多个安全的包
		for i = 1, #pendingPaveQueue, maxBatchSize do
			local batchChunk = table.move(pendingPaveQueue, i, math.min(i + maxBatchSize - 1, #pendingPaveQueue), 1, {})
			NetMsg.FireRequestPlaceBrickBatch(batchChunk)
		end

		table.clear(pendingPaveQueue)
		lastBatchTime = now
	end

	-- 6. Efficient TTL Cleanup (Safe pairs iteration)
	for key, entry in pairs(localBrickMap) do
		if (now - entry.createdAt) >= LOCAL_PREDICT_TTL then
			RemoveLocalBrickEntry(key)
		end
	end
end

runService.Heartbeat:Connect(OnHeartbeat)

-- Character management
local function OnCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		isPavingMode = false
		isAwaitingRescue = false
		lastPavePosition = nil
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
			if root then root.Anchored = false end
			if hum then 
				hum.PlatformStand = false 
				hum.Health = 0 -- Kill immediately to prevent re-trigger on the next frame
			end
			-- Let the next heartbeat clean up
		end
	end
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
end)
