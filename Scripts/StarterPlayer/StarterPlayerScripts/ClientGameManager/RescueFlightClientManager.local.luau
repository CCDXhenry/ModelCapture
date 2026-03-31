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
		params.FilterDescendantsInstances = {islandsFolder}
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

local function OnRescueStart()
	local character = localPlayer.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if not rootPart or not humanoid then return end

	-- Ensure anchored
	rootPart.Anchored = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	
	-- Attach simple wings mask
	local wings = AttachWings(character)
	
	-- Phase 1: Fly Up
	local startPos = rootPart.Position
	local highCFrame = rootPart.CFrame + Vector3.new(0, 100, 0)
	
	local flyUpInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local flyUpTween = tweenService:Create(rootPart, flyUpInfo, {CFrame = highCFrame})
	
	flyUpTween:Play()
	flyUpTween.Completed:Wait()
	
	-- Phase 2: Fly to Nearest Island
	local targetIsland = lastTouchedIsland or FindNearestIsland(startPos)
	local islandPos = rootPart.Position -- fallback
	if targetIsland then
		islandPos = Vector3.zero
		if targetIsland:IsA("Model") then
			islandPos = targetIsland:GetPivot().Position + Vector3.new(0, 3, 0)
		elseif targetIsland:IsA("BasePart") then
			islandPos = targetIsland.Position + Vector3.new(0, 3, 0)
		end
		
		-- Calculate fly time based on distance (Increasing overall speed)
		local highPos = highCFrame.Position
		local distance = (Vector3.new(islandPos.X, highPos.Y, islandPos.Z) - highPos).Magnitude
		local speed = 120 -- Studs per second (Previously 50)
		local flyTime = distance / speed
		
		local targetHighPos = Vector3.new(islandPos.X, highPos.Y, islandPos.Z)
		
		-- Match orientation to look at target
		local lookCFrame = CFrame.lookAt(highPos, targetHighPos)
		rootPart.CFrame = lookCFrame
		
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		
		local targetCFrame = CFrame.new(targetHighPos) * lookCFrame.Rotation
		local glideInfo = TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local glideTween = tweenService:Create(rootPart, glideInfo, {CFrame = targetCFrame})
		
		glideTween:Play()
		glideTween.Completed:Wait()
		
		-- Align character upright before dropping
		rootPart.CFrame = CFrame.new(targetHighPos)
	end
	
	-- Phase 3: Drop down (Faster and CubicIn for more impact)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local dropInfo = TweenInfo.new(0.6, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	local dropTween = tweenService:Create(rootPart, dropInfo, {CFrame = CFrame.new(islandPos)})
	dropTween:Play()
	dropTween.Completed:Wait()

	if wings then
		wings:Destroy()
	end
	
	rootPart.Anchored = false
	humanoid.PlatformStand = false
end

NetMsg.ConnectNotifyRescueStart(OnRescueStart)
