--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")

type BrickData = {
	Owner: Player,
	ExpireTime: number,
	IsGhost: boolean,
}

local activeBricks: { [Part]: BrickData } = {}
local activeBricksGrid: { [string]: Part } = {} -- O(1) 空间网格字典

local GHOST_DURATION = 1.5 -- 幽灵状态持续时间

local function UpdateBrickVisual(part: Part, isGhost: boolean)
	if isGhost then
		part.BrickColor = BrickColor.new("Neon orange") -- 使用橙色区分
		part.Material = Enum.Material.Neon
		part.Transparency = 0.5
		part:SetAttribute("IsGhost", true)
	else
		part.BrickColor = BrickColor.new("White")
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0
		part:SetAttribute("IsGhost", false)
	end
end

local function GetPosKey(pos: Vector3)
	return string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z)
end

local playerLastPaveTime: { [number]: number } = {}
local brickPool: { Part } = {}
local SEA_LEVEL = 0

-- 动态获取海平面高度 (与客户端逻辑对齐)
local startPointFolder = workspace:FindFirstChild("StartPoint")
local startPointModel = if startPointFolder then startPointFolder:FindFirstChild("StartPointModel") :: Model else nil
local startTrigger = if startPointModel then startPointModel:FindFirstChild("StartTrigger") :: Part else nil
local startAttachment = if startTrigger then startTrigger:FindFirstChild("Attachment") :: Attachment else nil

if startAttachment then
	SEA_LEVEL = startAttachment.WorldPosition.Y
end

local pavedBricksFolder = workspace:FindFirstChild("PavedBricks")
if not pavedBricksFolder then
	pavedBricksFolder = Instance.new("Folder")
	pavedBricksFolder.Name = "PavedBricks"
	pavedBricksFolder.Parent = workspace
end

local function GetBrickFromPool(): Part
	local brick = table.remove(brickPool)
	if not brick then
		local newPart = Instance.new("Part")
		newPart:SetAttribute("IsLocal", false)
		newPart.Anchored = true
		newPart.CanCollide = true
		newPart.Material = Enum.Material.SmoothPlastic
		newPart.Size = GameConfig.Paving.BrickSize

		newPart.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character then
				return
			end
			local hitPlayer = players:GetPlayerFromCharacter(character :: Model)
			if not hitPlayer then
				return
			end

			local data = activeBricks[newPart]
			if data and data.Owner ~= hitPlayer then
				local now = os.clock()

				-- Debounce check
				local lastPenalty = (newPart:GetAttribute("LastPenaltyTime") :: any) or 0
				if now - lastPenalty < 0.5 then
					return
				end
				newPart:SetAttribute("LastPenaltyTime", now)

				-- 只有非幽灵砖块才会被踩踏扣时间
				if not data.IsGhost then
					local remaining = data.ExpireTime - now
					if remaining > 0 then
						data.ExpireTime = now + math.max(GameConfig.Paving.MinCollapseTime, remaining - GameConfig.Paving.SteppedPenalty)
						newPart.BrickColor = BrickColor.new("Bright red") -- 变红提示即将进入进入幽灵态
					end
				end
			end
		end)
		brick = newPart
	end

	local part = brick :: Part
	part.CastShadow = false --性能优化
	return part
end

-- 辅助函数：归还砖块到对象池
local function ReturnBrickToPool(brick: Part)
	local key = GetPosKey(brick.Position)
	activeBricksGrid[key] = nil -- 清理空间字典
	activeBricks[brick] = nil
	brick.Parent = nil
	brick:SetAttribute("IsGhost", nil)
	table.insert(brickPool, brick)
end

-- [新增] 服务端 FloatBlock 检测
local function IsInFloatBlockZone(pos: Vector3): boolean
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if not floatBlockFolder then
		return false
	end

	local rayOrigin = pos + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -60, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floatBlockFolder }

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	return result ~= nil
end

local function OnRequestPlaceBrickBatch(player: Player, positions: any)
	if type(positions) ~= "table" then
		return
	end
	if #positions > GameConfig.Paving.MaxBatchSize then
		warn("[PavingManager] Player", player.Name, "sent too many bricks in one batch:", #positions)
		return
	end

	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local now = os.clock()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	for _, position in ipairs(positions) do
		if typeof(position) ~= "Vector3" then
			continue
		end

		-- [新增] 检测是否在 FloatBlock 区域
		if IsInFloatBlockZone(position) then
			continue
		end

		-- 1. Anti-cheat: Height check (使用动态 SEA_LEVEL)
		if math.abs(position.Y - SEA_LEVEL) > 2 then
			continue
		end

		-- 2. Anti-cheat: Distance check
		if (position - rootPart.Position).Magnitude > GameConfig.Paving.PavingDistanceLimit then
			continue
		end

		-- 3. Inventory check
		if playerInfo.carriedInfo.bricks <= 0 then
			break
		end

		-- [优化] 瞬间查找取代遍历 (O(1) 复杂度)
		local key = GetPosKey(position)
		local existingBrick = activeBricksGrid[key]

		if existingBrick then
			local data = activeBricks[existingBrick]
			if data and data.Owner == player then
				-- 如果是幽灵砖，无视续期阈值直接填实
				-- 如果是非幽灵砖，则走常规续期逻辑
				if data.IsGhost then
					data.IsGhost = false
					data.ExpireTime = now + GameConfig.Paving.BaseCollapseTime
					UpdateBrickVisual(existingBrick, false)
					ServerGameInfo.UpdateInventoryBricks(player, -1)
				else
					-- 防止网络延迟导致的短时间内重复续期扣砖
					local remainingTime = data.ExpireTime - now
					if remainingTime < GameConfig.Paving.BaseCollapseTime * GameConfig.Paving.StationaryRenewalThreshold then
						data.ExpireTime = now + GameConfig.Paving.BaseCollapseTime
						UpdateBrickVisual(existingBrick, false)
						ServerGameInfo.UpdateInventoryBricks(player, -1)
					end
				end
			end
			-- 如果已经有砖了，跳过生成步骤
			continue
		end

		-- 5. Deduct and Place
		ServerGameInfo.UpdateInventoryBricks(player, -1)

		local brick = GetBrickFromPool()
		brick.Position = position
		UpdateBrickVisual(brick, false)
		brick.Parent = pavedBricksFolder

		-- 存入空间哈希字典
		activeBricksGrid[key] = brick

		activeBricks[brick] = {
			Owner = player,
			ExpireTime = now + GameConfig.Paving.BaseCollapseTime,
			IsGhost = false,
		}
	end
end

local function OnHeartbeat(deltaTime: number)
	local now = os.clock()
	for brick, data in pairs(activeBricks) do
		if now >= data.ExpireTime then
			if not data.IsGhost then
				-- 转变为幽灵状态
				data.IsGhost = true
				data.ExpireTime = now + GHOST_DURATION
				UpdateBrickVisual(brick, true)
			else
				-- 幽灵状态也到期，彻底移除
				ReturnBrickToPool(brick)
			end
		end
	end
end

local function OnPlayerRemoving(player: Player)
	playerLastPaveTime[player.UserId] = nil
end

local function OnRequestStartPaving(player: Player)
	ServerGameInfo.SetPlayerBricksToMax(player)
end

NetMsg.ConnectRequestStartPaving(OnRequestStartPaving)
NetMsg.ConnectRequestPlaceBrickBatch(OnRequestPlaceBrickBatch)
runService.Heartbeat:Connect(OnHeartbeat)
players.PlayerRemoving:Connect(OnPlayerRemoving)

return {}
