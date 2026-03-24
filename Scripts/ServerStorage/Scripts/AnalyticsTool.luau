--!strict
local AnalyticsTool = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
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
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end
	local customEventBody: CustomEventBody = customEventBodies[player.UserId]
	if customEventBody == nil then
		return
	end
	local customEvent: CustomEvent = {
		event_name = eventName,
		event_time = DateTime.now().UnixTimestamp,
		total_time = math.floor(playerInfo.gameTime),
		event_params = eventParams
	}
	table.insert(customEventBody.events, customEvent)
	if IsShowAddCustomEventLog then
		print("AnalyticsAddCustomEvent", "EventName=" .. eventName, "EventParams=" .. httpService:JSONEncode(eventParams))
	end
end

--添加设计事件
local function AddDesignEvent(player: Player, eventId: string, value: number?)
	local options = {eventId = eventId}
	if value ~= nil then
		options.value = value
	end
	GameAnalytics:addDesignEvent(player.UserId, options)
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
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
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
	local playerInfo: GameConfig.PlayerInfo = ServerGameInfo.GetPlayerInfo(player)
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