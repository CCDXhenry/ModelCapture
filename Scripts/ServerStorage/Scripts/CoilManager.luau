--!strict
local CoilManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local players: Players = game:GetService("Players")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))

local defaultWalkSpeed: number = 16

local defaultJumpPower: number = 50
local defaultJumpHeight: number = 7.2

-- 按当前装备的 Tool 一次性写入 WalkSpeed 与跳跃，避免 += / 重复除法在切 Tool 时算错
local function syncCoilLocomotionForCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local player = players:GetPlayerFromCharacter(character)
	local baseWalk = defaultWalkSpeed
	local isDecelerationOn = false
	if player ~= nil then
		local resolved = ServerGameInfo.GetResolvedShopWalkSpeed(player)
		if resolved ~= nil then
			baseWalk = resolved
		end
		local playerInfo = ServerGameInfo.GetPlayerInfo(player)
		isDecelerationOn = playerInfo ~= nil and playerInfo.settingInfo.decelerationOn == true
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	local coilData = if equippedTool then GameConfig.CoilNameMap[equippedTool.Name] else nil

	local speedBoost = 0
	if coilData and coilData.speedValue and coilData.speedValue > 0 and not isDecelerationOn then
		speedBoost = coilData.speedValue
	end
	humanoid.WalkSpeed = baseWalk + speedBoost

	if humanoid.UseJumpPower then
		humanoid.JumpPower = defaultJumpPower
	else
		humanoid.JumpHeight = defaultJumpHeight
	end
	if coilData and coilData.gravitationalValue and coilData.gravitationalValue ~= 1 then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = humanoid.JumpPower / coilData.gravitationalValue
		else
			humanoid.JumpHeight = humanoid.JumpHeight / coilData.gravitationalValue
		end
	end
end

local function OnToolEquipped(tool: Tool, character: Model)
	local toolName = tool.Name
	local coilData = GameConfig.CoilNameMap[toolName]
	if coilData then
		local handle = tool:FindFirstChild("Handle") :: MeshPart
		if handle then
			local coilSound = handle:FindFirstChild("CoilSound") :: Sound
			if coilSound then
				coilSound:Play()
			end
		end
		syncCoilLocomotionForCharacter(character)
	end
end

local function OnToolUnequipped(tool: Tool, character: Model)
	local toolName = tool.Name
	local coilData = GameConfig.CoilNameMap[toolName]
	if coilData then
		syncCoilLocomotionForCharacter(character)
	end
end

local function OnCharacterAdded(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			OnToolEquipped(child, character)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			OnToolUnequipped(child, character)
		end
	end)
end

function CoilManager.SyncHumanoidCoilLocomotion(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	syncCoilLocomotionForCharacter(character)
end

function CoilManager.ReapplyEquippedSpeedCoilBuff(player: Player)
	CoilManager.SyncHumanoidCoilLocomotion(player)
end

function CoilManager.Init()
	players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(OnCharacterAdded)
		if player.Character then
			OnCharacterAdded(player.Character)
		end
	end)
	for _, player in players:GetPlayers() do
		player.CharacterAdded:Connect(OnCharacterAdded)
		if player.Character then
			OnCharacterAdded(player.Character)
		end
	end
end

return CoilManager
