--!strict
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))

local localPlayer = players.LocalPlayer
local backBricks: { Part } = {}
local container: Model? = nil

local modelsFolder = replicatedStorage:WaitForChild("Models")
local bricksFolder = modelsFolder:WaitForChild("Bricks")
local brickTemplate = bricksFolder:WaitForChild("Brick1") :: Part

local BRICK_SIZE = brickTemplate.Size
local VISUAL_SCALE = 0.25 -- 背部砖块缩放比例
local MAX_VISUAL = GameConfig.Paving.BackBricksMaxVisual or 10
local STACK_OFFSET = Vector3.new(0, 0, 1.2) -- 基础偏移 (调远一些)

local function GetContainer(): Model?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	-- 检查容器是否有效且属于当前角色
	if container and container.Parent == character then
		return container
	end

	-- 如果容器属于旧角色或已失效
	if container then
		container:Destroy()
	end

	container = Instance.new("Model")
	if not container then
		return nil
	end
	container.Name = "BackBricks"
	container.Parent = character

	-- 重要：清除旧有的 Part 引用，防止重生后引用到销毁的 Part
	table.clear(backBricks)

	return container :: Model
end

local function UpdateBackBricks()
	local character = localPlayer.Character
	if not character then
		return
	end

	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not upperTorso then
		return
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	-- 检测是否在 StartPoint 附近 (优先级最高)
	local isOnStartPoint = false
	local startPointFolder = workspace:FindFirstChild("StartPoint")
	if startPointFolder then
		local startPointModel = startPointFolder:FindFirstChild("StartPointModel")
		local startTrigger = if startPointModel then startPointModel:FindFirstChild("StartTrigger") else nil
		if startTrigger then
			local dist = math.abs(upperTorso.Position.X - (startTrigger :: BasePart).Position.X)
			if dist < 20 then
				isOnStartPoint = true
			end
		end
	end

	-- 检测是否在安全区 (地面 / 岛屿 / 玩家房屋)
	local isInSafeZone = false
	local hitUnderIslands = false
	local groundFolder = workspace:FindFirstChild("Ground") or workspace:FindFirstChild("ground")
	local islandsFolder = workspace:FindFirstChild("Islands")
	local homesFolder = workspace:FindFirstChild("PlayersHome")

	local rayOrigin = (upperTorso :: BasePart).Position + Vector3.new(0, 10, 0) -- 从上方探测，覆盖脚下障碍
	local rayDirection = Vector3.new(0, -200, 0) -- 增加探测深度，覆盖高层建筑
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
		if result then
			isInSafeZone = true
			if islandsFolder then
				hitUnderIslands = result.Instance:IsDescendantOf(islandsFolder)
			end
		end
	end

	-- 视觉砖块数量逻辑: 基于玩家当前瞬态搬运量，实现铺砖减少的视觉
	local currentBricks = playerInfo.carriedInfo.bricks

	-- 这里的除数可以根据表现调整，比如 1 表示 1:1 显示，10 表示 1:10 显示
	-- 之前用户手动改成了 / 1，遵循此设定
	local visualCount = math.min(MAX_VISUAL, math.ceil(currentBricks / 1))

	-- 判定显示: 在 StartPoint 必显；岛屿上显示；其余安全区 (地面/房屋) 隐藏
	if isInSafeZone and not isOnStartPoint and not hitUnderIslands then
		visualCount = 0
	end

	local c = GetContainer()
	if not c then
		return
	end

	-- 同步数量
	while #backBricks < visualCount do
		local p = brickTemplate:Clone()
		p.Size = BRICK_SIZE * VISUAL_SCALE
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = c
		table.insert(backBricks, p)
	end

	while #backBricks > visualCount do
		local p = table.remove(backBricks)
		if p then
			p:Destroy()
		end
	end

	-- 更新位置
	for i, p in ipairs(backBricks) do
		local offset = STACK_OFFSET + Vector3.new(0, (i - 1) * (BRICK_SIZE.Y * VISUAL_SCALE), 0)
		p.CFrame = (upperTorso :: BasePart).CFrame * CFrame.new(offset)
	end
end

runService.RenderStepped:Connect(UpdateBackBricks)

return {}
