--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local players = game:GetService("Players")
local HomeClientManager = require(clientScripts:FindFirstChild("HomeClientManager"))
local IslandClientManager = require(clientScripts:FindFirstChild("IslandClientManager"))
local ShopClientManager = require(clientScripts:WaitForChild("ShopClientManager"))
local PlayerInteractClientManager = require(clientScripts:WaitForChild("PlayerInteractClientManager"))
local BrainrotClientManager = require(clientScripts:WaitForChild("BrainrotClientManager"))
local CoilClientManager = require(clientScripts:WaitForChild("CoilClientManager"))
local starterGui: StarterGui = game:GetService("StarterGui")

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)
local GameTipZIndex: number = 2000
local soundsFolder: Folder = workspace:FindFirstChild("Sounds")
local bgmSound: Sound = soundsFolder:FindFirstChild("BGM") :: Sound

local function InitUI()
	local playerGui: PlayerGui = players.LocalPlayer:WaitForChild("PlayerGui")
	local gameScreenGui: ScreenGui = playerGui:WaitForChild("GameScreenGui") :: ScreenGui
	--禁用默认工具栏
	starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	--设置窗口容器
	UIManager.Init(gameScreenGui)
	-- 创建主界面
	UIManager.CreateFrame("GameFrame", "GameFrame", gameScreenGui, 0)
	local lobbyFrame = UIManager.CreateFrame("LobbyFrame", "LobbyFrame", gameScreenGui, 0) :: Frame
	-- 创建游戏提示界面
	UIManager.CreateFrame("GameTipFrame", "GameTipFrame", gameScreenGui, GameTipZIndex)
	
	-- 创建背包界面 (逻辑已集成到 LobbyFrame.BottomButtonsFrame)
	-- UIManager.CreateFrame("BackpackFrame", "BackpackFrame", gameScreenGui, 10)
	local backpackScriptOrigin = scripts:WaitForChild("Client"):WaitForChild("UIManager"):FindFirstChild("BackpackFrame")
	if backpackScriptOrigin then
		local backpackScript = backpackScriptOrigin:Clone() :: any
		backpackScript.Parent = lobbyFrame
	end

	--UI适配器初始化
	UIAdapter.Init(DesignScreenSize, gameScreenGui.AbsoluteSize)
	gameScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		UIAdapter.OnScreenSizeChange(gameScreenGui.AbsoluteSize)
	end)

	-- 初始化系统经理
	HomeClientManager.Init()
	IslandClientManager.Init()
	ShopClientManager.Init()
	PlayerInteractClientManager.Init()
	BrainrotClientManager.Init()
	CoilClientManager.Init()
	-- 初始化背包输入控制
	local BackpackInputManager = require(clientScripts:WaitForChild("BackpackInputManager"))
	BackpackInputManager.Init()
end

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		SoundTool.SetBGMVolumn(localPlayerInfo.settingInfo.bgmVolume)
		SoundTool.SetSoundEffectVolume(localPlayerInfo.settingInfo.soundEffectVolume)
	end
	SoundTool.PlayBGM(bgmSound)
	--初始化UI
	task.spawn(function()
		InitUI()
	end)
end

local function OnNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	if playerId ~= players.LocalPlayer.UserId then
		ClientGameInfo.InitOtherPlayerInfo(playerId, otherPlayerSaveInfo)
	end
end

local function OnNotifyPlayerAcquiredGamePass(gamePassId: number)
	ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId)
end

NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit)
NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit)
NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass)

-- 监听库存同步消息 (持有物/持久化)
NetMsg.ConnectNotifyPlayerInventoryUpdate(function(inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	ClientGameInfo.UpdateInventory(inventoryInfo)
end)

-- 监听 Brainrot 背包队列更新
NetMsg.ConnectNotifyBrainrotQueueUpdate(function(queue: { GameConfig.BrainrotQueueItem })
	ClientGameInfo.UpdateBrainrotQueue(queue)
end)

-- 监听搬运同步消息 (瞬态)
NetMsg.ConnectNotifyPlayerCarriedUpdate(function(carriedInfo: GameConfig.PlayerCarriedInfo)
	ClientGameInfo.UpdateCarriedInfo(carriedInfo)
end)

NetMsg.ConnectNotifyPlayerSkillLevelUpdate(function(skillType, level)
	ClientGameInfo.UpdateSkillLevel(skillType, level)
end)

-- 监听家园信息更新
NetMsg.ConnectNotifyPlayerHomeInfoUpdate(function(playerId: number, homeSlot: string, homeInfo: any)
	ClientGameInfo.UpdatePlayerHomeInfo(playerId, homeSlot, homeInfo)
end)

-- 监听模型收益更新
NetMsg.ConnectNotifyAllPlayersModelYields(function(allYields: { [string]: { [string]: number } })
	ClientGameInfo.UpdateAllPlayersModelYields(allYields)
end)

--监听货币更新
NetMsg.ConnectNotifyPlayerCurrencyUpdate(function(currencyType, totalAmount, lastChange, reason)
	ClientGameInfo.UpdateCurrency(currencyType, totalAmount, lastChange, reason)
end)

-- 监听网络层出的游戏提示
NetMsg.ConnectNotifyShowGameTip(function(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
	ClientMsg.FireShowGameTip(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end)
