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

local function ApplyCoilBuff(character: Model, coilData: GameConfig.CoilData)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local player = players:GetPlayerFromCharacter(character)
		local playerInfo = if player then ServerGameInfo.GetPlayerInfo(player) else nil
		local isDecelerationOn = if playerInfo then playerInfo.settingInfo.decelerationOn == true else false
		if coilData.speedValue and coilData.speedValue > 0 then
			if not isDecelerationOn then
				local speedBoost = coilData.speedValue
				humanoid.WalkSpeed = humanoid.WalkSpeed + speedBoost
			end
		end
		if coilData.gravitationalValue and coilData.gravitationalValue ~= 1 then
			if humanoid.UseJumpPower then
				humanoid.JumpPower = humanoid.JumpPower / coilData.gravitationalValue
			else
				humanoid.JumpHeight = humanoid.JumpHeight / coilData.gravitationalValue
			end
		end
	end
end

local function RevertCoilBuff(character: Model, coilData: GameConfig.CoilData)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if coilData.speedValue and coilData.speedValue > 0 then
			local player = players:GetPlayerFromCharacter(character)
			if player then
				ServerGameInfo.ApplyWalkSpeed(player)
			else
				humanoid.WalkSpeed = defaultWalkSpeed
			end
		end
		if coilData.gravitationalValue and coilData.gravitationalValue ~= 1 then
			if humanoid.UseJumpPower then
				humanoid.JumpPower = defaultJumpPower
			else
				humanoid.JumpHeight = defaultJumpHeight
			end
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
		ApplyCoilBuff(character, coilData)
	end
end

local function OnToolUnequipped(tool: Tool, character: Model)
	local toolName = tool.Name
	local coilData = GameConfig.CoilNameMap[toolName]
	if coilData then
		RevertCoilBuff(character, coilData)
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

function CoilManager.ReapplyEquippedSpeedCoilBuff(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool == nil then
		return
	end
	local coilData = GameConfig.CoilNameMap[equippedTool.Name]
	if coilData == nil then
		return
	end
	if coilData.speedValue and coilData.speedValue > 0 then
		ApplyCoilBuff(character, coilData)
	end
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
