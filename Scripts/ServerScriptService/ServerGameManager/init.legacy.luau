--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local DataStoreTool = require(serverCoreScripts:FindFirstChild("DataStoreTool"))
local MarketplaceTool = require(serverCoreScripts:FindFirstChild("MarketplaceTool"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local PlayerSaveInfoVersionUpdateTool = require(serverScripts:FindFirstChild("PlayerSaveInfoVersionUpdateTool"))
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
AnalyticsTool.SetDataAccess({
	GetPlayerInfo = function(player: Player)
		return ServerGameInfo.GetPlayerInfo(player)
	end,
})
local BrainrotIslandManager = require(serverScripts:FindFirstChild("BrainrotIslandManager"))
local PlayerInteractManager = require(serverScripts:FindFirstChild("PlayerInteractManager"))
local CoilManager = require(serverScripts:FindFirstChild("CoilManager"))
local EarthquakeManager = require(serverScripts:FindFirstChild("EarthquakeManager"))
local GuideProgressManager = require(serverScripts:FindFirstChild("GuideProgressManager"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local dataStoreService: DataStoreService = game:GetService("DataStoreService")
local playerInfoDataStore: DataStore = dataStoreService:GetDataStore("PlayerInfo")
local players: Players = game:GetService("Players")
local localizationService: LocalizationService = game:GetService("LocalizationService")
local runService: RunService = game:GetService("RunService")
local configService: ConfigService = game:GetService("ConfigService")

local AutoSavePlayerInfoInterval: number = 30 --自动保存玩家信息间隔时间

local autoSaveThreads: { [number]: thread } = {}

local function SplitVersion(version: string): { number }
	local result: { number } = {}
	for v: string in string.gmatch(version, "%d+") do
		local v2: number? = tonumber(v)
		if v2 ~= nil then
			table.insert(result, v2)
		end
	end
	return result
end

--版本1是否是版本2后的版本
local function IsVersionAfter(version1: string, version2: string): boolean
	local v1: { number } = SplitVersion(version1)
	local v2: { number } = SplitVersion(version2)
	local length: number = math.max(#v1, #v2)
	for i: number = 1, length do
		local v1i: number = v1[i] or 0
		local v2i: number = v2[i] or 0
		if v1i ~= v2i then
			return v1i > v2i
		end
	end
	return true
end

local function CheckPlayerLoginDays(player: Player, todayDate: DateTimeExtension.DateTimeTable)
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
	if
		playerInfo ~= nil
		and (
			todayDate.Year > playerInfo.lastOnlineDate.Year
			or (todayDate.Year == playerInfo.lastOnlineDate.Year and todayDate.Month > playerInfo.lastOnlineDate.Month)
			or (
				todayDate.Year == playerInfo.lastOnlineDate.Year
				and todayDate.Month == playerInfo.lastOnlineDate.Month
				and todayDate.Day > playerInfo.lastOnlineDate.Day
			)
		)
	then
		--登录天数+1
		ServerGameInfo.ChangePlayerLoginDays(player, playerInfo.loginDays + 1, todayDate)
	end
end

local function CheckOwnedGamePasses(player: Player)
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo ~= nil then
		task.spawn(function()
			for gamePassIdKey: string, gamePassIdValue: number in pairs(GameConfig.GamePassId) do
				if playerInfo.ownedGamePassMap[gamePassIdValue] == nil then
					local success: boolean, result: any = MarketplaceTool.SafeUserOwnsGamePass(player, gamePassIdValue)
					if success and result then
						ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassIdValue)
						AnalyticsTool.AddPassPurchaseEvent(player, gamePassIdValue, GameConfig.GamePassPrice[gamePassIdValue])
					end
				end
			end
		end)
	end
end

--保存玩家信息
local function SavePlayerInfo(player: Player)
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo ~= nil and playerInfo.playerInfoChanged then
		local playerSaveInfo: GameConfig.PlayerSaveInfo = ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo)
		DataStoreTool.SafeSet(playerInfoDataStore, tostring(player.UserId), playerSaveInfo)
		playerInfo.playerInfoChanged = false
	end
end

--玩家加入事件
local function OnPlayerAdded(player: Player)
	--读取玩家存档
	local success: boolean, result: any = DataStoreTool.SafeGet(playerInfoDataStore, tostring(player.UserId))
	--如果没有读取成功，将玩家踢出服务器，提示玩家读取存档失败
	if not success then
		player:Kick(result)
		return
	end
	--初始化玩家信息
	local playerSaveInfo: GameConfig.PlayerSaveInfo
	if result ~= nil then
		PlayerSaveInfoVersionUpdateTool.Update(result)
		playerSaveInfo = result
	else
		playerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo()
	end
	--获取玩家国家/地区
	success, result = RetryAsync(function()
		return localizationService:GetCountryRegionForPlayerAsync(player)
	end, 5, 1)
	local countryRegion: string = success and result or "unknown"
	--远程配置
	local _config: ConfigSnapshot
	if IsVersionAfter(playerSaveInfo.firstEnterVersion, GameConfig.ABTestVersion) then
		_config = configService:GetConfigForPlayerAsync(player)
	else
		--老玩家不参与AB测试
		_config = configService:GetConfigAsync()
	end
	local playerConfigInfo: GameConfig.PlayerConfigInfo = {}
	ServerGameInfo.InitPlayerInfo(player, playerSaveInfo, countryRegion, playerConfigInfo)
	--检查登录天数
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	CheckPlayerLoginDays(player, nowDate)
	--检查拥有的通行证
	CheckOwnedGamePasses(player)
	--每隔一段时间自动保存玩家数据
	local autoSaveThread: thread = coroutine.create(function()
		while true do
			task.wait(AutoSavePlayerInfoInterval)
			--保存玩家数据
			SavePlayerInfo(player)
		end
	end)
	coroutine.resume(autoSaveThread)
	autoSaveThreads[player.UserId] = autoSaveThread

	-- 角色生成时重新应用行走速度
	player.CharacterAdded:Connect(function()
		ServerGameInfo.ApplyWalkSpeed(player)
	end)

	--埋点添加玩家
	AnalyticsTool.AddPlayer(player)
end

--玩家离开事件
local function OnPlayerRemoving(player: Player)
	--埋点移除玩家
	AnalyticsTool.RemovePlayer(player)
	--离开前保存玩家数据
	task.spawn(function()
		SavePlayerInfo(player)
	end)
	--移除玩家数据
	ServerGameInfo.RemovePlayerInfo(player)
	--停止自动保存玩家数据协程
	local autoSaveThread = autoSaveThreads[player.UserId]
	if autoSaveThread ~= nil then
		coroutine.close(autoSaveThread)
		autoSaveThreads[player.UserId] = nil
	end
end

local function OnHeartbeat(deltaTime: number)
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	for playerIndex: number, player: Player in players:GetPlayers() do
		ServerGameInfo.AddPlayerGameTime(player, deltaTime)
		CheckPlayerLoginDays(player, nowDate)
	end
end

print("GameVersion", GameConfig.GameVersion)
AnalyticsTool.Init()
BrainrotIslandManager.Init()
PlayerInteractManager.Init()
CoilManager.Init()
EarthquakeManager.Init()
GuideProgressManager.Init()

players.PlayerAdded:Connect(OnPlayerAdded)
players.PlayerRemoving:Connect(OnPlayerRemoving)
runService.Heartbeat:Connect(OnHeartbeat)
