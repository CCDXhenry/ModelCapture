--!strict
local CoilClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local players: Players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")

local localPlayer = players.LocalPlayer
local maxExtraJumps = 0
local extraJumpsPerformed = 0
local currentGravityVal = 0
local initialGravity = workspace.Gravity
local lastJumpTick = 0

local function OnJumpRequest()
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if humanoid and rootPart and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
		-- 获取当前状态
		local currentState = humanoid:GetState()

		-- 自动连跳 (落地后直接起跳)
		if currentState == Enum.HumanoidStateType.Running or currentState == Enum.HumanoidStateType.Landed then
			humanoid.Jump = true
		end

		-- 多段跳核心逻辑：只有在空中（自由落体/跳起中）且还没进行二段跳时触发
		-- 加入 tick() 检查，防止连发，且确保次数未达上限
		if currentState == Enum.HumanoidStateType.Freefall or currentState == Enum.HumanoidStateType.Jumping then
			if extraJumpsPerformed < maxExtraJumps and (tick() - lastJumpTick > 0.25) then
				extraJumpsPerformed += 1
				lastJumpTick = tick() -- 更新跳跃时间，防止连续多段跳瞬间触发

				-- 计算跳跃速度
				local jumpPower = humanoid.UseJumpPower and humanoid.JumpPower or math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)

				rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, jumpPower, rootPart.AssemblyLinearVelocity.Z)
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end
	end
end

local function OnLocalToolEquipped(tool: Tool, character: Model)
	local toolName = tool.Name
	local coilData = GameConfig.CoilNameMap[toolName]
	if coilData then
		maxExtraJumps = coilData.extraJumps or 0
		if coilData.gravitationalValue and coilData.gravitationalValue ~= 1 then
			currentGravityVal = coilData.gravitationalValue
			workspace.Gravity = initialGravity * currentGravityVal
		end
	end
end

local function OnLocalToolUnequipped(tool: Tool)
	local toolName = tool.Name
	local coilData = GameConfig.CoilNameMap[toolName]
	if coilData then
		maxExtraJumps = 0
		if coilData.gravitationalValue and coilData.gravitationalValue ~= 1 then
			workspace.Gravity = initialGravity
			currentGravityVal = 0
		end
	end
end

local function OnCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.StateChanged:Connect(function(oldState, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			lastJumpTick = tick()
		end
		if newState == Enum.HumanoidStateType.Landed then
			extraJumpsPerformed = 0
		end
	end)

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			OnLocalToolEquipped(child, character)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			OnLocalToolUnequipped(child)
		end
	end)
end

function CoilClientManager.Init()
	userInputService.JumpRequest:Connect(OnJumpRequest)

	-- 关键：心跳检测按键状态，实现“一直按着空格”触发连跳和多段跳
	game:GetService("RunService").Heartbeat:Connect(function()
		if userInputService:IsKeyDown(Enum.KeyCode.Space) then
			OnJumpRequest()
		end
	end)

	localPlayer.CharacterAdded:Connect(OnCharacterAdded)
	if localPlayer.Character then
		OnCharacterAdded(localPlayer.Character)
	end
end

return CoilClientManager
