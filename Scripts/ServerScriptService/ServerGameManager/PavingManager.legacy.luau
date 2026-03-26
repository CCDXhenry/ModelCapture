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

-- 调试：workspace:SetAttribute("PavingDebugFloatBlockRays", true) 显示 FloatBlock 四角竖直射线的命中情况
local DEBUG_FLOATBLOCK_RAYS_ATTR = "PavingDebugFloatBlockRays"
local FLOATBLOCK_RAY_ORIGIN_Y = 50
local FLOATBLOCK_RAY_LENGTH = 60
local DEBUG_RAY_LIFETIME = 4

local function GetOrCreateDebugRaysFolder(): Folder
	local existing = workspace:FindFirstChild("PavingDebugFloatBlockRays")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "PavingDebugFloatBlockRays"
	folder.Parent = workspace
	return folder
end

local function CreateDebugRaySegment(from: Vector3, to: Vector3, color: Color3, parent: Instance)
	local dist = (to - from).Magnitude
	if dist < 0.01 then
		return
	end
	local mid = from:Lerp(to, 0.5)
	local p = Instance.new("Part")
	p.Name = "FloatBlockRay"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.12, 0.12, dist)
	p.CFrame = CFrame.new(mid, to)
	p.Parent = parent
	game:GetService("Debris"):AddItem(p, DEBUG_RAY_LIFETIME)
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

-- FloatBlock：单点竖直射线（与砖块水平尺寸组合为「整块 footprint 才禁铺」）
local function RaycastFloatBlockAtPoint(samplePos: Vector3): RaycastResult?
	local floatBlockFolder = workspace:FindFirstChild("FloatBlock")
	if not floatBlockFolder then
		return nil
	end

	local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
	local rayDirection = Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floatBlockFolder }

	return workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

local function IsPointOverFloatBlock(pos: Vector3): boolean
	return RaycastFloatBlockAtPoint(pos) ~= nil
end

local function GetBrickFootprintCornerPositions(center: Vector3): { Vector3 }
	local size = GameConfig.Paving.BrickSize
	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	local y = center.Y
	return {
		Vector3.new(center.X - hx, y, center.Z - hz),
		Vector3.new(center.X + hx, y, center.Z - hz),
		Vector3.new(center.X - hx, y, center.Z + hz),
		Vector3.new(center.X + hx, y, center.Z + hz),
	}
end

local function IsEntireBrickFootprintOverFloatBlock(center: Vector3): boolean
	for _, p in GetBrickFootprintCornerPositions(center) do
		if not IsPointOverFloatBlock(p) then
			return false
		end
	end
	return true
end

-- 可视化：从 samplePos 向上偏移处向下打射线；绿色=命中 FloatBlock，红色=未命中（线段画满射程）
local function VisualizeFloatBlockRaysForBrickCenter(center: Vector3)
	local folder = GetOrCreateDebugRaysFolder()
	local hitColor = Color3.fromRGB(80, 255, 120)
	local missColor = Color3.fromRGB(255, 80, 80)
	for _, samplePos in GetBrickFootprintCornerPositions(center) do
		local rayOrigin = samplePos + Vector3.new(0, FLOATBLOCK_RAY_ORIGIN_Y, 0)
		local rayEnd = rayOrigin + Vector3.new(0, -FLOATBLOCK_RAY_LENGTH, 0)
		local result = RaycastFloatBlockAtPoint(samplePos)
		if result then
			CreateDebugRaySegment(rayOrigin, result.Position, hitColor, folder)
		else
			CreateDebugRaySegment(rayOrigin, rayEnd, missColor, folder)
		end
	end
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

	local showFloatBlockRays = workspace:GetAttribute(DEBUG_FLOATBLOCK_RAYS_ATTR) == true

	for _, position in ipairs(positions) do
		if typeof(position) ~= "Vector3" then
			continue
		end

		if showFloatBlockRays then
			VisualizeFloatBlockRaysForBrickCenter(position)
		end

		-- 仅当砖块底面四角均落在 FloatBlock 上方时才禁铺
		if IsEntireBrickFootprintOverFloatBlock(position) then
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
