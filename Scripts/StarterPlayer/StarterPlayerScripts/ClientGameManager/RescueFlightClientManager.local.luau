--!strict
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local localPlayer = players.LocalPlayer
local lastTouchedIsland: Instance? = nil

-- 从水平参考点向上偏移后向下打射线，得到直立 HRP CFrame（脚大致在地表上）
local RAYCAST_ABOVE_STUDS = 200
local RAYCAST_DOWN_STUDS = 600
local SURFACE_BIAS_ALONG_NORMAL = 0.25
local PIVOT_FALLBACK_EXTRA_Y = 15

runService.Heartbeat:Connect(function()
	local character = localPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then return end

	local rayOrigin = rootPart.Position
	local rayDirection = Vector3.new(0, -10, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local islandsFolder = workspace:FindFirstChild("Islands")
	if islandsFolder then
		params.FilterDescendantsInstances = { islandsFolder }
		local result = workspace:Raycast(rayOrigin, rayDirection, params)
		if result and result.Instance then
			local island = result.Instance
			while island and island.Parent ~= islandsFolder and island.Parent ~= game do
				island = island.Parent :: any
			end
			if island and island.Parent == islandsFolder then
				lastTouchedIsland = island
			end
		end
	end
end)

local function FindNearestIsland(startPos: Vector3): Instance?
	local islandsFolder = workspace:FindFirstChild("Islands")
	if not islandsFolder then return nil end

	local nearestIsland: Instance? = nil
	local minDistance = math.huge

	for _, island in pairs(islandsFolder:GetChildren()) do
		local pos = Vector3.zero
		if island:IsA("Model") and island.PrimaryPart then
			pos = island.PrimaryPart.Position
		elseif island:IsA("Model") then
			pos = island:GetPivot().Position
		elseif island:IsA("BasePart") then
			pos = island.Position
		end

		local dist = (pos - startPos).Magnitude
		if dist < minDistance then
			minDistance = dist
			nearestIsland = island
		end
	end

	return nearestIsland
end

local function AttachWings(character: Model): Part?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then return nil end

	local wings = Instance.new("Part")
	wings.Name = "TemporaryWings"
	wings.Size = Vector3.new(4, 1, 1)
	wings.Color = Color3.fromRGB(255, 255, 255)
	wings.Material = Enum.Material.Neon
	wings.CanCollide = false
	wings.Massless = true
	wings.CFrame = (torso :: BasePart).CFrame * CFrame.new(0, 0.5, 1)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso :: BasePart
	weld.Part1 = wings
	weld.Parent = wings

	wings.Parent = character
	return wings
end

local function GroundHrpCFrameFromHorizontalRef(
	character: Model,
	horizontalRef: Vector3
): CFrame?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not rootPart or not humanoid then
		return nil
	end

	local origin = Vector3.new(horizontalRef.X, horizontalRef.Y + RAYCAST_ABOVE_STUDS, horizontalRef.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local hit = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_DOWN_STUDS, 0), params)
	if not hit then
		return nil
	end

	local ground = hit.Position + hit.Normal * SURFACE_BIAS_ALONG_NORMAL
	local yOff = rootPart.Size.Y * 0.5 + humanoid.HipHeight
	local pos = ground + Vector3.new(0, yOff, 0)
	return CFrame.new(pos)
end

local function ResolveRescueLandCFrame(targetIsland: Instance?, character: Model): CFrame
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not rootPart or not humanoid then
		return CFrame.new()
	end

	if not targetIsland then
		return rootPart.CFrame
	end

	local tp = targetIsland:FindFirstChild("TeleportPoint")
	if tp then
		local spawnLoc = tp:FindFirstChild("SpawnLocation")
		if spawnLoc and spawnLoc:IsA("SpawnLocation") then
			local spawnPart = spawnLoc :: BasePart
			local ref = spawnPart.CFrame * CFrame.new(0, 3, 0)
			local cf = GroundHrpCFrameFromHorizontalRef(character, ref.Position)
			if cf then
				return cf
			end
		end

		local ring = tp:FindFirstChild("Ring")
		if ring and ring:IsA("BasePart") then
			local ringPart = ring :: BasePart
			local refPos = ringPart.Position + Vector3.new(0, 8, 0)
			local cf = GroundHrpCFrameFromHorizontalRef(character, refPos)
			if cf then
				return cf
			end
		end
	end

	local pivotPos: Vector3
	if targetIsland:IsA("Model") then
		pivotPos = targetIsland:GetPivot().Position
	elseif targetIsland:IsA("BasePart") then
		pivotPos = targetIsland.Position
	else
		pivotPos = rootPart.Position
	end

	local cf = GroundHrpCFrameFromHorizontalRef(character, pivotPos + Vector3.new(0, 20, 0))
	if cf then
		return cf
	end

	local yOff = rootPart.Size.Y * 0.5 + humanoid.HipHeight + PIVOT_FALLBACK_EXTRA_Y
	return CFrame.new(pivotPos + Vector3.new(0, yOff, 0))
end

local function OnRescueStart()
	local character = localPlayer.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if not rootPart or not humanoid then return end

	rootPart.Anchored = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	local wings = AttachWings(character)

	local startPos = rootPart.Position
	local highCFrame = rootPart.CFrame + Vector3.new(0, 100, 0)

	local flyUpInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local flyUpTween = tweenService:Create(rootPart, flyUpInfo, { CFrame = highCFrame })

	flyUpTween:Play()
	flyUpTween.Completed:Wait()

	local targetIsland = lastTouchedIsland or FindNearestIsland(startPos)
	local landCFrame = ResolveRescueLandCFrame(targetIsland, character)
	local landPos = landCFrame.Position

	-- Phase 2：水平移动到目标落点正上方（高度保持升空终点，Tween）；不做竖直下落 Tween
	local highPos = rootPart.Position
	local targetAbovePos = Vector3.new(landPos.X, highPos.Y, landPos.Z)
	local horizontalDelta = targetAbovePos - highPos
	local distance = horizontalDelta.Magnitude
	if distance > 0.5 then
		local speed = 120
		local flyTime = math.max(distance / speed, 0.12)
		local lookCFrame = CFrame.lookAt(highPos, targetAbovePos)
		rootPart.CFrame = CFrame.new(highPos) * lookCFrame.Rotation
		local targetCFrame = CFrame.new(targetAbovePos) * lookCFrame.Rotation
		local glideInfo = TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local glideTween = tweenService:Create(rootPart, glideInfo, { CFrame = targetCFrame })
		glideTween:Play()
		glideTween.Completed:Wait()
	else
		rootPart.CFrame = CFrame.new(targetAbovePos)
	end

	if wings then
		wings:Destroy()
	end

	-- 目标正上方解锚，由物理自由落体到底（无下落 Tween）
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	rootPart.Anchored = false
	humanoid.PlatformStand = false
end

NetMsg.ConnectNotifyRescueStart(OnRescueStart)
