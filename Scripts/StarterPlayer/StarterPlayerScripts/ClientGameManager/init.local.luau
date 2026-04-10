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
local EarthquakeClientManager = require(clientScripts:WaitForChild("EarthquakeClientManager"))
local GuideManager = require(clientScripts:WaitForChild("GuideManager"))
local starterGui: StarterGui = game:GetService("StarterGui")
local contentProvider: ContentProvider = game:GetService("ContentProvider")
local modelOriginsFolder: Folder? = replicatedStorage:FindFirstChild("Models") :: Folder?
local uiOriginsFolder: Folder? = replicatedStorage:FindFirstChild("UI") :: Folder?
local soundOriginsFolder: Folder? = workspace:FindFirstChild("Sounds") :: Folder?

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)
local GameTipZIndex: number = 2000
local soundsFolder: Folder = workspace:FindFirstChild("Sounds")
local bgmSound: Sound = soundsFolder:FindFirstChild("BGM") :: Sound
local PreloadAssets: () -> ()

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
	-- 引导手指层（低于 GameTip，高于 Lobby）
	UIManager.CreateFrame(GameConfig.GuideAssetName.UiFrame, "GuideFrame", gameScreenGui, 1500)
	
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
	EarthquakeClientManager.Init()
	GuideManager.Init()
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
	-- 玩家信息就绪后初始化UI/系统
	task.spawn(function()
		InitUI()
	end)
end

PreloadAssets = function()
	local preloadStartTime = os.clock()
	local assetList: { Instance } = {}
	local meshMap: { [string]: boolean } = {}
	local decalMap: { [string]: boolean } = {}
	local imageMap: { [string]: boolean } = {}
	local soundMap: { [string]: boolean } = {}
	local animationMap: { [string]: boolean } = {}
	local failedAssetList: { string } = {}
	local folderList: { Instance } = {}
	if modelOriginsFolder ~= nil then
		table.insert(folderList, modelOriginsFolder)
	end
	if soundOriginsFolder ~= nil then
		table.insert(folderList, soundOriginsFolder)
	end
	if uiOriginsFolder ~= nil then
		table.insert(folderList, uiOriginsFolder)
	end

	local function AddMesh(meshId: string)
		if meshId == "" or meshMap[meshId] ~= nil then
			return
		end
		local specialMesh = Instance.new("SpecialMesh")
		specialMesh.MeshId = meshId
		table.insert(assetList, specialMesh)
		meshMap[meshId] = true
	end

	local function AddDecal(textureId: string)
		if textureId == "" or decalMap[textureId] ~= nil then
			return
		end
		local decal = Instance.new("Decal")
		decal.Texture = textureId
		table.insert(assetList, decal)
		decalMap[textureId] = true
	end

	local function AddImage(imageId: string)
		if imageId == "" or imageMap[imageId] ~= nil then
			return
		end
		local image = Instance.new("ImageLabel")
		image.Image = imageId
		table.insert(assetList, image)
		imageMap[imageId] = true
	end

	local function AddSound(soundId: string)
		if soundId == "" or soundMap[soundId] ~= nil then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		table.insert(assetList, sound)
		soundMap[soundId] = true
	end

	local function AddAnimation(animationId: string)
		if animationId == "" or animationMap[animationId] ~= nil then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		table.insert(assetList, animation)
		animationMap[animationId] = true
	end

	for _, folder: Instance in folderList do
		for _, descendant: Instance in folder:GetDescendants() do
			if descendant:IsA("MeshPart") then
				AddMesh(descendant.MeshId)
				AddDecal(descendant.TextureID)
			elseif descendant:IsA("SpecialMesh") then
				AddMesh(descendant.MeshId)
				AddDecal(descendant.TextureId)
			elseif descendant:IsA("Decal") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Texture") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Sound") then
				AddSound(descendant.SoundId)
			elseif descendant:IsA("Animation") then
				AddAnimation(descendant.AnimationId)
			elseif descendant:IsA("ParticleEmitter") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Beam") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("ImageLabel") then
				AddImage(descendant.Image)
			elseif descendant:IsA("ImageButton") then
				AddImage(descendant.Image)
			end
		end
	end
	--预加载GameConfig图片资源
	local otherImageList: { string } = {}
	table.insert(otherImageList, GameConfig.CoinIconImage)
	table.insert(otherImageList, GameConfig.RbImage)
	table.insert(otherImageList, GameConfig.DecelerationOnImage)
	table.insert(otherImageList, GameConfig.DecelerationOffImage)

	for _, otherImage: string in otherImageList do
		AddImage(otherImage)
	end

	--print(string.format("[ClientGameManager] PreloadAssets start. candidates=%d", #assetList))
	local preloadSuccess, preloadErr = pcall(function()
		contentProvider:PreloadAsync(assetList, function(assetId: string, assetFetchStatus: Enum.AssetFetchStatus)
			if assetFetchStatus ~= Enum.AssetFetchStatus.Success then
				table.insert(failedAssetList, assetId)
				warn("[ClientGameManager] LoadAssetResult", assetId, assetFetchStatus)
			end
		end)
	end)

	if not preloadSuccess then
		warn("[ClientGameManager] PreloadAssets failed:", preloadErr)
	end

	for _, instance: Instance in assetList do
		instance:Destroy()
	end
	table.clear(assetList)

	local elapsedTime = os.clock() - preloadStartTime
	--print(string.format(
	--	"[ClientGameManager] PreloadAssets complete. failed=%d elapsed=%.2fs",
	--	#failedAssetList,
	--	elapsedTime
	--))
	if #failedAssetList > 0 then
		--print(string.format("[ClientGameManager] PreloadAssets failed sample=%s", tostring(failedAssetList[1])))
	end
	table.clear(failedAssetList)
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
NetMsg.ConnectNotifyPlayerHomeInfoUpdate(function(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	ClientGameInfo.UpdatePlayerHomeInfo(playerId, homeSlot, homeInfo, rebirthLevel)
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

-- 客户端启动时立即异步预加载资源，不阻塞初始化流程
task.spawn(function()
	PreloadAssets()
end)
