--!strict
-- 集中管理 ReplicatedStorage.Sounds 模板音效；播放走 SoundTool（不修改 SoundTool 源码）。
local GameSoundManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))

local soundsFolder: Folder = replicatedStorage:WaitForChild("Sounds") :: Folder

local function getTemplateSound(name: string): Sound?
	local inst = soundsFolder:FindFirstChild(name)
	if inst and inst:IsA("Sound") then
		return inst
	end
	warn("[GameSoundManager] Missing Sound in ReplicatedStorage.Sounds:", name)
	return nil
end

local function playGlobalFromName(soundName: string)
	local template = getTemplateSound(soundName)
	if template then
		SoundTool.PlayGlobalSoundEffect(template, false)
	end
end

function GameSoundManager.PlayUpgradeAbilitySound()
	playGlobalFromName("UpgradeAbilitySound")
end

function GameSoundManager.PlayUpgradeHomeSound()
	playGlobalFromName("UpgradeHomeSound")
end

function GameSoundManager.PlaySellSound()
	playGlobalFromName("SellSound")
end

function GameSoundManager.PlayPickUpOrPutDownSound()
	playGlobalFromName("PickUpOrPutDownSound")
end

function GameSoundManager.PlayButtonClickSound()
	playGlobalFromName("ButtonClickSound")
end

return GameSoundManager
