--!strict
local _players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))

local islandsFolder = workspace:WaitForChild("Islands")
local homesFolder = workspace:WaitForChild("PlayersHome")

local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local BrainrotCarryingManager = require(serverScripts:FindFirstChild("BrainrotCarryingManager"))

local BrainrotIslandManager = {}

-- Forward declaration
local StartCarryingBrainrot
local SetupBrainrotInteraction
local ConvertCarryingToQueue -- 向前声明

-- 1. 岛屿传送逻辑
local function SetupIslandTeleport(island: Instance)
	local teleportPoint = island:FindFirstChild("TeleportPoint")
	if not teleportPoint or not teleportPoint:IsA("Model") then
		return
	end

	local ring = teleportPoint:FindFirstChild("Ring")
	if not ring or not ring:IsA("MeshPart") then
		return
	end

	local proximityPromptAttachment = ring:FindFirstChild("ProximityPromptAttachment")
	if not proximityPromptAttachment or not proximityPromptAttachment:IsA("Attachment") then
		return
	end

	local proximityPrompt = proximityPromptAttachment:FindFirstChild("ProximityPrompt")
	if not proximityPrompt or not proximityPrompt:IsA("ProximityPrompt") then
		return
	end

	proximityPrompt.Triggered:Connect(function(player)
		local playerInfo = ServerGameInfo.GetPlayerInfo(player)
		if playerInfo and playerInfo.homeSlot ~= "" and homesFolder then
			local homeModel = homesFolder:FindFirstChild(playerInfo.homeSlot)
			if homeModel then
				local homeTeleportPoint = homeModel:FindFirstChild("TeleportPoint")
				if homeTeleportPoint then
					local spawnLocation = homeTeleportPoint:FindFirstChild("SpawnLocation") :: SpawnLocation
					local character = player.Character
					if character then
						local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp then
							hrp.CFrame = spawnLocation.CFrame * CFrame.new(0, 3, 0)
							ConvertCarryingToQueue(player)
						end
					end
				end
			end
		end
	end)
end

function ConvertCarryingToQueue(player: Player)
	local carryingBrainrot = BrainrotCarryingManager.GetCarryingBrainrot(player)
	if not carryingBrainrot then
		return
	end

	local configId = tonumber(carryingBrainrot:GetAttribute("ConfigId"))
	local quality = tonumber(carryingBrainrot:GetAttribute("Quality")) or 1
	local level = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
	local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?

	if configId and uid then
		local success = BrainrotQueueManager.AddItem(player, configId, quality, level, true)
		if success then
			BrainrotCarryingManager.StopCarrying(player)
		else
			--warn("[BrainrotIslandManager] Ground conversion failed: Backpack full for", player.Name)
		end
	end
end

function StartCarryingBrainrot(player: Player, randomBrainrot: Instance)
	local configId = tonumber(randomBrainrot:GetAttribute("ConfigId"))

	if configId then
		local carry = BrainrotCarryingManager.StartCarrying(player, randomBrainrot)
		if carry then
			randomBrainrot:Destroy()
		end
	end
end

function SetupBrainrotInteraction(randomBrainrot: Instance, island: Instance, spawnPos: Vector3, sizeY: number)
	local interactionTarget: BasePart? = if randomBrainrot:IsA("BasePart") then randomBrainrot :: any else nil

	if not interactionTarget then
		return
	end

	local attachment = interactionTarget:FindFirstChild("InteractionAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		if attachment then
			attachment.Name = "InteractionAttachment"
			attachment.Position = Vector3.new(0, 2, 0)
			attachment.Parent = interactionTarget
		end
	end

	local attachmentObj = attachment :: Attachment
	local prompt: ProximityPrompt = attachmentObj:FindFirstChild("ProximityPrompt") :: ProximityPrompt

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		if prompt then
			prompt.ActionText = GameTexts.PickUpBrainrot.source
			local configId: number? = randomBrainrot:GetAttribute("ConfigId") :: number?
			local brainrotConfig = if configId then GameConfig.BrainrotIdMap[configId] else nil
			prompt.ObjectText = if brainrotConfig then brainrotConfig.name_t else randomBrainrot.Name
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 10
			prompt.Enabled = true
			prompt.Parent = attachment
		end
	end

	prompt.Triggered:Connect(function(player)
		StartCarryingBrainrot(player, randomBrainrot)
	end)
end

local function SpawnOneBrainrotInternal(island: Instance): BasePart?
	local brainrotIds = {}
	for id, _ in pairs(GameConfig.BrainrotIdMap) do
		table.insert(brainrotIds, id)
	end
	if #brainrotIds == 0 then
		return nil
	end

	local randomId = brainrotIds[math.random(1, #brainrotIds)]
	local brainrotConfig = GameConfig.BrainrotIdMap[randomId]
	if not brainrotConfig then
		return nil
	end

	local randomBrainrot = Instance.new("Part")
	randomBrainrot.Size = Vector3.new(1, 1, 1)
	randomBrainrot.Transparency = 1
	randomBrainrot.CanCollide = false
	randomBrainrot.Anchored = true
	randomBrainrot.Name = "IslandBrainrot"

	randomBrainrot:SetAttribute("ConfigId", brainrotConfig.id)
	randomBrainrot:SetAttribute("Quality", brainrotConfig.quality)
	randomBrainrot:SetAttribute("Level", 1)
	randomBrainrot:SetAttribute("HomeIslandName", island.Name)

	local basePos = if island:IsA("BasePart") then island.Position else Vector3.zero
	local rayOrigin = basePos + Vector3.new(math.random(-40, 40), 50, math.random(-40, 40))
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { island }
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	local raycastResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), raycastParams)
	local spawnPos = raycastResult and raycastResult.Position or (basePos + Vector3.new(rayOrigin.X - basePos.X, 5, rayOrigin.Z - basePos.Z))

	local sizeY = 0
	randomBrainrot.CFrame = CFrame.new(spawnPos)

	randomBrainrot:SetAttribute("SpawnPos", spawnPos)
	randomBrainrot:SetAttribute("SpawnSizeY", sizeY)

	randomBrainrot.Parent = island
	SetupBrainrotInteraction(randomBrainrot, island, spawnPos, sizeY)
	return randomBrainrot
end

-- 4. 业务逻辑封装
local function SpawnBrainrotsOnIsland(island: Instance)
	for i = 1, 3 do
		SpawnOneBrainrotInternal(island)
	end
end

local function GetActiveBrainrot(player: Player): Instance?
	local character = player.Character
	if not character then
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool:GetAttribute("BrainrotUID") then
		if equippedTool:GetAttribute("ItemType") == 2 then return nil end
		return equippedTool
	end

	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying and carrying:GetAttribute("BrainrotUID") then
		if carrying:GetAttribute("ItemType") == 2 then return nil end
		return carrying
	end

	return nil
end

local function OnRequestPlaceCarryingBrainrot(player: Player, pointIndex: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local carryingBrainrot = GetActiveBrainrot(player)
	if carryingBrainrot then
		local configId = carryingBrainrot:GetAttribute("ConfigId")
		local quality = carryingBrainrot:GetAttribute("Quality") or 2

		if configId then
			local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
			if not uid then
				return
			end

			if carryingBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, uid) then
					return
				end
			else
				if not carryingBrainrot.Parent then
					return
				end
			end

			local qualityCfg = GameConfig.BrainrotQualityConfig[quality :: number]
			local rarity: GameConfig.ModelRarity = (if qualityCfg then qualityCfg.rarity else "Common") :: any
			local placedLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1

			ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, {
				instanceId = "brainrot_" .. tostring(math.floor(os.clock() * 1000)),
				configId = tonumber(configId) or 1,
				level = placedLevel,
				rarity = rarity,
			})

			carryingBrainrot:Destroy()
		end
	end
end

local function OnRequestSellCarryingBrainrot(player: Player)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end
	local carryingBrainrot = GetActiveBrainrot(player)
	if carryingBrainrot then
		local configId = carryingBrainrot:GetAttribute("ConfigId")
		if configId then
			local uid = carryingBrainrot:GetAttribute("BrainrotUID") :: string?
			if not uid then
				return
			end

			if carryingBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, uid) then
					return
				end
			else
				if not carryingBrainrot.Parent then
					return
				end
			end

			local brainrotConfig = GameConfig.BrainrotIdMap[tonumber(configId) or 0]
			if brainrotConfig then
				local currentLevel = tonumber(carryingBrainrot:GetAttribute("Level")) or 1
				local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotConfig.baseAbility, currentLevel)

				ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, sellPrice, GameConfig.ItemCountChangeReason.GainFromSellModel)
				carryingBrainrot:Destroy()

				print("[BrainrotIslandManager] Player", player.Name, "sold tool brainrot for", sellPrice)
			end
		end
	end
end

local function StartSpawnLoop()
	task.spawn(function()
		while true do
			task.wait(10)
			if not islandsFolder then
				continue
			end

			local currentPlayers = #game:GetService("Players"):GetPlayers()
			local targetCount = math.max(1, currentPlayers) * 3

			for _, island in ipairs(islandsFolder:GetChildren()) do
				if island.Name:match("^Island%d+$") then
					local existingCount = 0
					for _, child in ipairs(island:GetChildren()) do
						if child.Name == "IslandBrainrot" then
							existingCount += 1
						end
					end

					if existingCount < targetCount then
						local toSpawn = targetCount - existingCount
						for i = 1, toSpawn do
							SpawnOneBrainrotInternal(island)
						end
					end
				end
			end
		end
	end)
end

local function InitBrainrotModelsWelds()
	if not actualModels then
		return
	end
	for _, model in ipairs(actualModels:GetChildren()) do
		if model:IsA("Model") then
			local root = model.PrimaryPart or model:FindFirstChild("RootPart") or model:FindFirstChildWhichIsA("BasePart")
			if root and root:IsA("BasePart") then
				model.PrimaryPart = root :: BasePart
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part ~= root then
						-- Clear old welds just to be safe
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("WeldConstraint") or child:IsA("Weld") then
								child:Destroy()
							end
						end
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = root :: BasePart
						weld.Part1 = part
						weld.Parent = part
					end
				end
			end
		end
	end
end

local function SetupGroundTrigger()
	local groundFolder = workspace:FindFirstChild("Ground")
	if not groundFolder then
		return
	end

	local function OnTouched(hit)
		local char = hit.Parent
		if not char then
			return
		end
		local player = _players:GetPlayerFromCharacter(char)
		if player then
			local now = os.clock()
			local lastTouch = player:GetAttribute("LastGroundTouch") or 0
			if now - lastTouch > 0.5 then
				player:SetAttribute("LastGroundTouch", now)
				ConvertCarryingToQueue(player)
			end
		end
	end

	if groundFolder:IsA("BasePart") then
		groundFolder.Touched:Connect(OnTouched)
	end
	for _, ground in ipairs(groundFolder:GetDescendants()) do
		if ground:IsA("BasePart") then
			ground.Touched:Connect(OnTouched)
		end
	end
end

function BrainrotIslandManager.Init()
	InitBrainrotModelsWelds()
	SetupGroundTrigger()

	if not islandsFolder then
		return
	end

	local isWelded = Instance.new("BoolValue")
	isWelded.Name = "BrainrotModelsWelded"
	isWelded.Value = true
	isWelded.Parent = replicatedStorage
	for _, island in ipairs(islandsFolder:GetChildren()) do
		if island.Name:match("^Island%d+$") then
			SetupIslandTeleport(island)
			SpawnBrainrotsOnIsland(island)
		end
	end
	islandsFolder.ChildAdded:Connect(function(child)
		if child.Name:match("^Island%d+$") then
			SetupIslandTeleport(child)
			SpawnBrainrotsOnIsland(child)
		end
	end)

	NetMsg.ConnectRequestPlaceCarryingBrainrot(OnRequestPlaceCarryingBrainrot)
	NetMsg.ConnectRequestSellCarryingBrainrot(OnRequestSellCarryingBrainrot)

	StartSpawnLoop()
end

function BrainrotIslandManager.StartCarryingBrainrot(player: Player, brainrot: Instance)
	StartCarryingBrainrot(player, brainrot)
end

BrainrotIslandManager.SetupBrainrotInteraction = SetupBrainrotInteraction

return BrainrotIslandManager
