--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local GMConfig = require(serverCoreScripts:FindFirstChild("GMConfig"))
local TeleportTool = require(serverCoreScripts:FindFirstChild("TeleportTool"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local textChatService: TextChatService = game:GetService("TextChatService")
local customTextChatCommandsFolder: Folder = textChatService:FindFirstChild("CustomTextChatCommands") :: Folder
local serverScripts = serverStorage:WaitForChild("Scripts")
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))

local clearDataStoreCommand: TextChatCommand = customTextChatCommandsFolder:FindFirstChild("ClearDataStoreCommand") :: TextChatCommand
local getCoilCommand: TextChatCommand = customTextChatCommandsFolder:FindFirstChild("GetCoilCommand") :: TextChatCommand

--清空数据
local function OnClearDataStoreCommandTrigged(originTextSource: TextSource, unfilteredText: string)
	if runService:IsStudio() or not GMConfig.IsGMPlayer(originTextSource.UserId) then
		return
	end
	local player: Player? = players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end
	--传送到清除玩家数据场景
	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData: any = {
		gameStartPlaceId = GameConfig.GamePlaceId,
		defaultPlayerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo()
	}
	teleportOptions:SetTeleportData(teleportData)
	TeleportTool.SafeTeleport(GameConfig.ClearDataStorePlaceId, {player}, teleportOptions)
end

local function OnGiveCoilCommandTriggered(originTextSource: TextSource, unfilteredText: string)
	if not GMConfig.IsGMPlayer(originTextSource.UserId) then
		return
	end
	
	local player: Player? = players:GetPlayerByUserId(originTextSource.UserId)
	if not player then return end

	local args = string.split(unfilteredText, " ")
	if #args >= 2 then
		local configId = tonumber(args[2])
		if configId then
			BrainrotQueueManager.AddItem(player, configId, 1, 1, true, GameConfig.ItemType.Coil)
			print("[PlayerChatCommandManager] Gave Coil", configId, "to", player.Name)
		end
	end
end

clearDataStoreCommand.Triggered:Connect(OnClearDataStoreCommandTrigged)
getCoilCommand.Triggered:Connect(OnGiveCoilCommandTriggered)