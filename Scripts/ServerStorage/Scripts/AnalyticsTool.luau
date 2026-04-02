--!strict
local AnalyticsTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameAnalytics = require(replicatedStorage:FindFirstChild("GameAnalytics"))
local httpService: HttpService = game:GetService("HttpService")
local runService: RunService = game:GetService("RunService")

local PostCustomEventsInterval: number = 8
local PostCustomEventsUrl: string = "https://cloudapi.sixcubeapis.com/log_event"
local IsShowAddCustomEventLog: boolean = true

type CustomEventParam = {
	filed: string,
	value: string,
}

type CustomEvent = {
	event_name: string,
	event_time: number,
	total_time: number,
	event_params: {CustomEventParam}
}

type CustomEventBody = {
	proj_id: string,
	user_id: string,
	first_time: number,
	version: string,
	country: string,
	events: {CustomEvent}
}

local customEventBodies: {[number]: CustomEventBody} = {}
local removedCustomEventBodies: {[number]: CustomEventBody} = {}

-- 由 init.legacy 注入，本模块不 require ServerGameInfo，避免循环依赖
export type AnalyticsDataAccess = {
	GetPlayerInfo: (Player) -> GameConfig.PlayerInfo?,
}

local dataAccess: AnalyticsDataAccess? = nil

function AnalyticsTool.SetDataAccess(access: AnalyticsDataAccess)
	dataAccess = access
end

local function resolvePlayerInfo(player: Player): GameConfig.PlayerInfo?
	local a = dataAccess
	if a then
		return a.GetPlayerInfo(player)
	end
	return nil
end

local function PostCustomEvent(customEventBody: CustomEventBody)
	if #customEventBody.events == 0 then
		return
	end
	local requestBody: string = httpService:JSONEncode(customEventBody)
	table.clear(customEventBody.events)
	if not runService:IsStudio() then
		local success: boolean, result: any = pcall(function()
			return httpService:RequestAsync({
				Url = PostCustomEventsUrl,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
				},
				Body = requestBody,
				Compress = Enum.HttpCompression.None,
			})
		end)
		if not success or not result.Success then
			warn("Post Custom Events Error", result)
		end
	end
end

local function PostCustomEvents()
	for playerId: number, customEventBody: CustomEventBody in customEventBodies do
		PostCustomEvent(customEventBody)
	end
	for playerId: number, customEventBody: CustomEventBody in removedCustomEventBodies do
		PostCustomEvent(customEventBody)
	end
	table.clear(removedCustomEventBodies)
end

local function AddCustomEvent(player: Player, eventName: string, eventParams: {CustomEventParam})
	local playerInfo = resolvePlayerInfo(player)
	if playerInfo == nil then
		return
	end
	local customEventBody: CustomEventBody = customEventBodies[player.UserId]
	if customEventBody == nil then
		return
	end
	local heartTime = math.floor(playerInfo.gameTime)
	local mergedParams: {CustomEventParam} = {
		{ filed = "heart_time", value = tostring(heartTime) },
	}
	for _, p in ipairs(eventParams) do
		table.insert(mergedParams, p)
	end
	local customEvent: CustomEvent = {
		event_name = eventName,
		event_time = DateTime.now().UnixTimestamp,
		total_time = heartTime,
		event_params = mergedParams,
	}
	table.insert(customEventBody.events, customEvent)
	if IsShowAddCustomEventLog then
		print("AnalyticsAddCustomEvent", "EventName=" .. eventName, "EventParams=" .. httpService:JSONEncode(mergedParams))
	end
end

local function getMoneyCount(player: Player): number
	local playerInfo = resolvePlayerInfo(player)
	if playerInfo == nil then
		return 0
	end
	return playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
end

function AnalyticsTool.LogModelPickUp(player: Player, modelId: number, modelLevel: number, itemType: number)
	AddCustomEvent(player, "model_pick_up", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevel) },
		{ filed = "item_type", value = tostring(itemType) },
	})
end

function AnalyticsTool.LogModelGet(
	player: Player,
	modelId: number,
	modelLevel: number,
	getSource: number,
	getSourceId: number,
	itemType: number
)
	AddCustomEvent(player, "model_get", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevel) },
		{ filed = "item_type", value = tostring(itemType) },
		{ filed = "get_source", value = tostring(getSource) },
		{ filed = "get_source_id", value = tostring(getSourceId) },
	})
end

function AnalyticsTool.LogModelPlace(player: Player, modelId: number, modelLevel: number)
	AddCustomEvent(player, "model_place", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevel) },
	})
end

function AnalyticsTool.LogModelHold(player: Player, modelId: number, modelLevel: number)
	AddCustomEvent(player, "model_hold", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevel) },
	})
end

function AnalyticsTool.LogModelSell(
	player: Player,
	modelCount: number,
	moneyGet: number,
	modelIdList: { number },
	levelList: { number }
)
	AddCustomEvent(player, "model_sell", {
		{ filed = "model_count", value = tostring(modelCount) },
		{ filed = "money_get", value = tostring(moneyGet) },
		{ filed = "model_id_list", value = httpService:JSONEncode(modelIdList) },
		{ filed = "level_list", value = httpService:JSONEncode(levelList) },
		{ filed = "money_count", value = tostring(getMoneyCount(player)) },
	})
end

function AnalyticsTool.LogModelUpgrade(player: Player, modelId: number, modelLevelAfter: number)
	AddCustomEvent(player, "model_upgrade", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevelAfter) },
		{ filed = "money_count", value = tostring(getMoneyCount(player)) },
	})
end

function AnalyticsTool.LogModelCollectCash(
	player: Player,
	modelId: number,
	modelLevel: number,
	durationSec: number,
	moneyGet: number
)
	AddCustomEvent(player, "model_collect_cash", {
		{ filed = "model_id", value = tostring(modelId) },
		{ filed = "model_level", value = tostring(modelLevel) },
		{ filed = "duration_sec", value = tostring(durationSec) },
		{ filed = "money_get", value = tostring(moneyGet) },
		{ filed = "money_count", value = tostring(getMoneyCount(player)) },
	})
end

function AnalyticsTool.LogBaseUpgrade(player: Player, baseLevelAfter: number)
	AddCustomEvent(player, "base_upgrade", {
		{ filed = "base_level", value = tostring(baseLevelAfter) },
		{ filed = "money_count", value = tostring(getMoneyCount(player)) },
	})
end

function AnalyticsTool.LogPlayerUpgrade(player: Player, upgradeType: number, newLevel: number)
	AddCustomEvent(player, "player_upgrade", {
		{ filed = "upgrade_type", value = tostring(upgradeType) },
		{ filed = "new_level", value = tostring(newLevel) },
		{ filed = "money_count", value = tostring(getMoneyCount(player)) },
	})
end

function AnalyticsTool.LogPlayerRebirth(player: Player, rebirthCount: number, brickLevel: number, speedLevel: number, isSkipRebirth: number)
	AddCustomEvent(player, "player_rebirth", {
		{ filed = "rebirth_count", value = tostring(rebirthCount) },
		{ filed = "brick_level", value = tostring(brickLevel) },
		{ filed = "speed_level", value = tostring(speedLevel) },
		{ filed = "is_Skip_Rebirth", value = tostring(isSkipRebirth) },
	})
end

function AnalyticsTool.LogPlayerDeath(player: Player, totalBricks: number, remainingBricks: number, islandId: number)
	AddCustomEvent(player, "player_death", {
		{ filed = "total_bricks", value = tostring(totalBricks) },
		{ filed = "remaining_bricks", value = tostring(remainingBricks) },
		{ filed = "island_id", value = tostring(islandId) },
	})
end

function AnalyticsTool.LogIslandDiscover(player: Player, islandId: number)
	AddCustomEvent(player, "island_discover", {
		{ filed = "island_id", value = tostring(islandId) },
	})
end

function AnalyticsTool.Init()
	--初始化GA埋点
	--GameAnalytics:setEnabledInfoLog(true)
	--GameAnalytics:setEnabledVerboseLog(true)
	--GameAnalytics:configureBuild(GameConfig.GameVersion)
	--GameAnalytics:initServer(ServerConfig.GoogleAnalyticsGameKey, ServerConfig.GoogleAnalyticsSecretKey)
	--报错信息直接在Roblox后台看，GA不需要采集
	--GameAnalytics.setEnabledReportErrors(false)

	--初始化自定义事件
	task.spawn(function()
		while true do
			task.wait(PostCustomEventsInterval)
			PostCustomEvents()
		end
	end)
	local postCustomEventsThread: thread = coroutine.create(PostCustomEvents)
	coroutine.resume(postCustomEventsThread)
	game:BindToClose(function(closeReason: Enum.CloseReason)
		PostCustomEvents()
	end)
end

function AnalyticsTool.AddPlayer(player: Player)
	local playerInfo = resolvePlayerInfo(player)
	if playerInfo == nil then
		return
	end
	local customEventBody: CustomEventBody = {
		proj_id = tostring(game.GameId),
		user_id = tostring(player.UserId),
		first_time = playerInfo.firstEnterTime,
		version = playerInfo.firstEnterVersion,
		country = playerInfo.countryRegion,
		events = {}
	}
	customEventBodies[player.UserId] = customEventBody
	AddCustomEvent(player, "PlayerAdded", {})
end

function AnalyticsTool.RemovePlayer(player: Player)
	local playerInfo = resolvePlayerInfo(player)
	if playerInfo == nil then
		return
	end
	AddCustomEvent(player, "PlayerRemoving", {
		{filed = "start_time", value = tostring(playerInfo.timeOfThisLogin)},
		{filed = "game_time", value = tostring(DateTime.now().UnixTimestamp - playerInfo.timeOfThisLogin)},
	})
	local customEventBody: CustomEventBody = customEventBodies[player.UserId]
	if customEventBody == nil then
		return
	end
	removedCustomEventBodies[player.UserId] = customEventBody
	customEventBodies[player.UserId] = nil
end

--普通商品内购事件
function AnalyticsTool.AddProductPurchaseEvent(player: Player, receiptInfo: GameConfig.ReceiptInfo)
	AddCustomEvent(player, "GamePurchase", {
		{filed = "purchase_id", value = receiptInfo.PurchaseId},
		{filed = "player_id", value = tostring(receiptInfo.PlayerId)},
		{filed = "product_id", value = tostring(receiptInfo.ProductId)},
		{filed = "spent", value = tostring(receiptInfo.CurrencySpent)},
	})

	GameAnalytics:ProcessReceiptCallback(receiptInfo)
end

--Pass内购事件
function AnalyticsTool.AddPassPurchaseEvent(player: Player, gamePassId: number, price: number)
	AddCustomEvent(player, "GamePurchase", {
		{filed = "purchase_id", value = httpService:GenerateGUID()},
		{filed = "player_id", value = tostring(player.UserId)},
		{filed = "product_id", value = tostring(gamePassId)},
		{filed = "spent", value = tostring(price)},
	})
end

--添加传送数据
function AnalyticsTool.AddTeleportData(players: {Instance}, teleportData: any)
	local playerIds: {number} = {}
	for playerIndex: number, player: Instance in players do
		if player:IsA("Player") then
			table.insert(playerIds, player.UserId)
		end
	end
	GameAnalytics:addGameAnalyticsTeleportData(playerIds, teleportData)
end

return AnalyticsTool
