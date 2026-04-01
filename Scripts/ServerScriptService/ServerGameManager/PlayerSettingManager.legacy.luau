--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local CoilManager = require(serverScripts:FindFirstChild("CoilManager"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local function OnPlayerRequestSetBGMVolume(player: Player, volume: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.bgmVolume == volume then
		return
	end
	ServerGameInfo.UpdateBGMVolume(player, volume)
end

local function OnPlayerRequestSetSoundEffectVolume(player: Player, volume: number)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.soundEffectVolume == volume then
		return
	end
	ServerGameInfo.UpdateSoundEffectVolume(player, volume)
end

local function OnPlayerRequestSetVibrationsOnOffState(player: Player, vibrationsOn: boolean)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.vibrationOn == vibrationsOn then
		return
	end
	ServerGameInfo.UpdateVibrationOn(player, vibrationsOn)
end

local function OnPlayerRequestSetDecelerationOn(player: Player, decelerationOn: boolean)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.decelerationOn == decelerationOn then
		return
	end
	ServerGameInfo.UpdateDecelerationOn(player, decelerationOn)
	ServerGameInfo.ApplyWalkSpeed(player)
	if decelerationOn == false then
		CoilManager.ReapplyEquippedSpeedCoilBuff(player)
	end
end

NetMsg.ConnectRequestSetBGMVolume(OnPlayerRequestSetBGMVolume)
NetMsg.ConnectRequestSetSoundEffectVolume(OnPlayerRequestSetSoundEffectVolume)
NetMsg.ConnectRequestSetVibrationsOnOffState(OnPlayerRequestSetVibrationsOnOffState)
NetMsg.ConnectRequestSetDecelerationOn(OnPlayerRequestSetDecelerationOn)
