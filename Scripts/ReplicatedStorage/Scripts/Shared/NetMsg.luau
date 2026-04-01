--!strict
local NetMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local remoteEventsFolder: Folder = replicatedStorage:FindFirstChild("RemoteEvents") :: Folder
local requestSetBGMVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetBGMVolume") :: RemoteEvent
local requestSetSoundEffectVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetSoundEffectVolume") :: RemoteEvent
local requestSetVibrationsOnOffStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetVibrationsOnOffState") :: RemoteEvent
local requestSetDecelerationOnEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetDecelerationOn") :: RemoteEvent
local notifyPlayerInfoInitEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInfoInit") :: RemoteEvent
local notifyPlayersOtherPlayerInfoInitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayersOtherPlayerInfoInit") :: RemoteEvent
local notifyPlayerAcquiredGamePassEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerAcquiredGamePass") :: RemoteEvent
local notifyPlayerHomeInfoUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerHomeInfoUpdate") :: RemoteEvent
local notifyAllPlayersModelYieldsEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyAllPlayersModelYields") :: RemoteEvent

-- [抓模型] 游戏通信
local requestPlaceBrickBatchEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceBrickBatch") :: RemoteEvent
local requestPickupModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPickupModel") :: RemoteEvent
local requestPlaceHomeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceHomeModel") :: RemoteEvent
local requestUpgradeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestUpgradeModel") :: RemoteEvent
local requestSellModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSellModel") :: RemoteEvent
local requestBuyShopUpgradeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestBuyShopUpgrade") :: RemoteEvent
local requestUpgradeSkillEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestUpgradeSkill") :: RemoteEvent
local requestClaimYieldEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestClaimYield") :: RemoteEvent
local requestPickupHomeModelEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPickupHomeModel") :: RemoteEvent
local requestStartPavingEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestStartPaving") :: RemoteEvent
local notifyPlaceBrickBatchResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlaceBrickBatchResult") :: RemoteEvent
local requestPlaceCarryingBrainrotEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPlaceCarryingBrainrot") :: RemoteEvent
local requestSellCarryingBrainrotEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSellCarryingBrainrot") :: RemoteEvent
local notifyPlayerInventoryUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInventoryUpdate") :: RemoteEvent
local notifyPlayerSkillLevelUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerSkillLevelUpdate") :: RemoteEvent
local notifyPlayerCarriedUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerCarriedUpdate") :: RemoteEvent
local notifyPlayerCurrencyUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerCurrencyUpdate") :: RemoteEvent

-- Gifting
local requestSendGiftEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSendGift") :: RemoteEvent
local notifyReceiveGiftRequestEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyReceiveGiftRequest") :: RemoteEvent
local requestRespondGiftEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestRespondGift") :: RemoteEvent
local notifyGiftResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyGiftResult") :: RemoteEvent
local notifyShowGiftConfirmEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyShowGiftConfirm") :: RemoteEvent
local notifyBrainrotQueueUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyBrainrotQueueUpdate") :: RemoteEvent
local notifyShowGameTipEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyShowGameTip") :: RemoteEvent
local notifyRescueStartEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyRescueStart") :: RemoteEvent
local requestOpenChestEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestOpenChest") :: RemoteEvent
local notifyChestOpenResultEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyChestOpenResult") :: RemoteEvent

-- Rebirth
local requestRebirthEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestRebirth") :: RemoteEvent
local requestPaidRebirthEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestPaidRebirth") :: RemoteEvent

-- Earthquake
local notifyEarthquakeStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeState") :: RemoteEvent
local notifyEarthquakeJudgeDropEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeJudgeDrop") :: RemoteEvent
local notifyEarthquakeRecoverEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeRecover") :: RemoteEvent
local notifyEarthquakeWarningEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyEarthquakeWarning") :: RemoteEvent

--客户端请求设置背景音乐音量
function NetMsg.FireRequestSetBGMVolume(volume: number)
	requestSetBGMVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetBGMVolume(callback: (player: Player, volume: number) -> ())
	requestSetBGMVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置音效音量
function NetMsg.FireRequestSetSoundEffectVolume(volume: number)
	requestSetSoundEffectVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetSoundEffectVolume(callback: (player: Player, volume: number) -> ())
	requestSetSoundEffectVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置振动开关状态
function NetMsg.FireRequestSetVibrationsOnOffState(vibrationsOn: boolean)
	requestSetVibrationsOnOffStateEvent:FireServer(vibrationsOn)
end

function NetMsg.ConnectRequestSetVibrationsOnOffState(callback: (player: Player, vibrationsOn: boolean) -> ())
	requestSetVibrationsOnOffStateEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置减速开关状态
function NetMsg.FireRequestSetDecelerationOn(decelerationOn: boolean)
	requestSetDecelerationOnEvent:FireServer(decelerationOn)
end

function NetMsg.ConnectRequestSetDecelerationOn(callback: (player: Player, decelerationOn: boolean) -> ())
	requestSetDecelerationOnEvent.OnServerEvent:Connect(callback)
end

--通知客户端玩家信息初始化完成
function NetMsg.FireNotifyPlayerInfoInit(
	player: Player,
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	notifyPlayerInfoInitEvent:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end

function NetMsg.ConnectNotifyPlayerInfoInit(callback: (
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
) -> ())
	notifyPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端其他玩家信息初始化完成
function NetMsg.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	notifyPlayersOtherPlayerInfoInitEvent:FireAllClients(playerId, otherPlayerSaveInfo)
end

function NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(callback: (playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo) -> ())
	notifyPlayersOtherPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端玩家获得了通行证
function NetMsg.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number)
	print("[NetMsg] FireNotifyPlayerAcquiredGamePass for player", player.Name, "gamePassId", gamePassId)
	notifyPlayerAcquiredGamePassEvent:FireClient(player, gamePassId)
end

function NetMsg.ConnectNotifyPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	notifyPlayerAcquiredGamePassEvent.OnClientEvent:Connect(callback)
end

--通知所有客户端更新在线玩家的房子信息
function NetMsg.FireNotifyPlayerHomeInfoUpdate(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	print("[NetMsg] FireNotifyPlayerHomeInfoUpdate for playerId", playerId)
	notifyPlayerHomeInfoUpdateEvent:FireAllClients(playerId, homeSlot, homeInfo, rebirthLevel)
end

function NetMsg.ConnectNotifyPlayerHomeInfoUpdate(callback: (playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?) -> ())
	notifyPlayerHomeInfoUpdateEvent.OnClientEvent:Connect(callback)
end

--通知全服玩家模型收益更新 (深度优化版：单次广播同步所有玩家数值)
function NetMsg.FireNotifyAllPlayersModelYields(allYields: { [string]: { [string]: number } })
	notifyAllPlayersModelYieldsEvent:FireAllClients(allYields)
end

function NetMsg.ConnectNotifyAllPlayersModelYields(callback: (allYields: { [string]: { [string]: number } }) -> ())
	notifyAllPlayersModelYieldsEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求批量放置砖块 (跑酷)
function NetMsg.FireRequestPlaceBrickBatch(positions: { Vector3 }, batchId: number?, clientSentAt: number?)
	--print("[NetMsg] FireRequestPlaceBrickBatch with", #positions, "points")
	requestPlaceBrickBatchEvent:FireServer(positions, batchId, clientSentAt)
end
function NetMsg.ConnectRequestPlaceBrickBatch(callback: (player: Player, positions: { Vector3 }, batchId: number?, clientSentAt: number?) -> ())
	requestPlaceBrickBatchEvent.OnServerEvent:Connect(callback)
end

function NetMsg.FireNotifyPlaceBrickBatchResult(
	player: Player,
	batchId: number,
	acceptedIndexes: { number },
	rejectedList: { { index: number, reason: string } },
	serverBricks: number,
	serverNow: number?
)
	notifyPlaceBrickBatchResultEvent:FireClient(player, batchId, acceptedIndexes, rejectedList, serverBricks, serverNow or os.clock())
end

function NetMsg.ConnectNotifyPlaceBrickBatchResult(
	callback: (batchId: number, acceptedIndexes: { number }, rejectedList: { { index: number, reason: string } }, serverBricks: number, serverNow: number) -> ()
)
	notifyPlaceBrickBatchResultEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求拾取模型
function NetMsg.FireRequestPickupModel(instanceId: string)
	print("[NetMsg] FireRequestPickupModel", instanceId)
	requestPickupModelEvent:FireServer(instanceId)
end
function NetMsg.ConnectRequestPickupModel(callback: (player: Player, instanceId: string) -> ())
	requestPickupModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求放置模型到家园展台
function NetMsg.FireRequestPlaceHomeModel(instanceId: string, pointIndex: number)
	print("[NetMsg] FireRequestPlaceHomeModel", instanceId, "at pointIndex", pointIndex)
	requestPlaceHomeModelEvent:FireServer(instanceId, pointIndex)
end
function NetMsg.ConnectRequestPlaceHomeModel(callback: (player: Player, instanceId: string, pointIndex: number) -> ())
	requestPlaceHomeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求升级家园展台模型
function NetMsg.FireRequestUpgradeModel(pointIndex: number)
	print("[NetMsg] FireRequestUpgradeModel at pointIndex", pointIndex)
	requestUpgradeModelEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestUpgradeModel(callback: (player: Player, pointIndex: number) -> ())
	requestUpgradeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求出售家园展台模型
function NetMsg.FireRequestSellModel(pointIndex: number)
	print("[NetMsg] FireRequestSellModel at pointIndex", pointIndex)
	requestSellModelEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestSellModel(callback: (player: Player, pointIndex: number) -> ())
	requestSellModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求购买商店升级
function NetMsg.FireRequestBuyShopUpgrade(upgradeType: string)
	print("[NetMsg] FireRequestBuyShopUpgrade", upgradeType)
	requestBuyShopUpgradeEvent:FireServer(upgradeType)
end
function NetMsg.ConnectRequestBuyShopUpgrade(callback: (player: Player, upgradeType: string) -> ())
	requestBuyShopUpgradeEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求领取展示台收益 (由触碰本地 CollectPart 触发)
function NetMsg.FireRequestClaimYield(targetPlayerId: number, pointIndex: number)
	print("[NetMsg] FireRequestClaimYield from target", targetPlayerId, "plot", pointIndex)
	requestClaimYieldEvent:FireServer(targetPlayerId, pointIndex)
end
function NetMsg.ConnectRequestClaimYield(callback: (player: Player, targetPlayerId: number, pointIndex: number) -> ())
	requestClaimYieldEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求从家园展台拾取模型
function NetMsg.FireRequestPickupHomeModel(pointIndex: number)
	print("[NetMsg] FireRequestPickupHomeModel at pointIndex", pointIndex)
	requestPickupHomeModelEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestPickupHomeModel(callback: (player: Player, pointIndex: number) -> ())
	requestPickupHomeModelEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求触发铺砖模式 (触碰 StartTrigger)
function NetMsg.FireRequestStartPaving()
	print("[NetMsg] FireRequestStartPaving")
	requestStartPavingEvent:FireServer()
end
function NetMsg.ConnectRequestStartPaving(callback: (player: Player) -> ())
	requestStartPavingEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求放置正在搬运的宠物
function NetMsg.FireRequestPlaceCarryingBrainrot(pointIndex: number)
	print("[NetMsg] FireRequestPlaceCarryingBrainrot at pointIndex", pointIndex)
	requestPlaceCarryingBrainrotEvent:FireServer(pointIndex)
end
function NetMsg.ConnectRequestPlaceCarryingBrainrot(callback: (player: Player, pointIndex: number) -> ())
	requestPlaceCarryingBrainrotEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求出售正在搬运的宠物
function NetMsg.FireRequestSellCarryingBrainrot()
	print("[NetMsg] FireRequestSellCarryingBrainrot")
	requestSellCarryingBrainrotEvent:FireServer()
end
function NetMsg.ConnectRequestSellCarryingBrainrot(callback: (player: Player) -> ())
	requestSellCarryingBrainrotEvent.OnServerEvent:Connect(callback)
end

-- 通知客户端玩家库存更新 (持久化部分)
function NetMsg.FireNotifyPlayerInventoryUpdate(player: Player, inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	print("[NetMsg] FireNotifyPlayerInventoryUpdate for player", player.Name)
	notifyPlayerInventoryUpdateEvent:FireClient(player, inventoryInfo)
end
function NetMsg.ConnectNotifyPlayerInventoryUpdate(callback: (inventoryInfo: GameConfig.PlayerInventorySaveInfo) -> ())
	notifyPlayerInventoryUpdateEvent.OnClientEvent:Connect(callback)
end

-- 通知客户端玩家搬运信息更新 (瞬态)
function NetMsg.FireNotifyPlayerCarriedUpdate(player: Player, carriedInfo: GameConfig.PlayerCarriedInfo)
	--print("[NetMsg] FireNotifyPlayerCarriedUpdate for player", player.Name)
	notifyPlayerCarriedUpdateEvent:FireClient(player, carriedInfo)
end
function NetMsg.ConnectNotifyPlayerCarriedUpdate(callback: (carriedInfo: GameConfig.PlayerCarriedInfo) -> ())
	notifyPlayerCarriedUpdateEvent.OnClientEvent:Connect(callback)
end

--通知玩家货币更新
function NetMsg.FireNotifyPlayerCurrencyUpdate(player: Player, currencyType: number, totalAmount: number, lastChange: number, reason: number)
	notifyPlayerCurrencyUpdateEvent:FireClient(player, currencyType, totalAmount, lastChange, reason)
end

function NetMsg.ConnectNotifyPlayerCurrencyUpdate(callback: (currencyType: number, totalAmount: number, lastChange: number, reason: number) -> ())
	notifyPlayerCurrencyUpdateEvent.OnClientEvent:Connect(callback)
end

--客户端发送升级请求
function NetMsg.SendRequestUpgradeSkill(skillType: number, levelAdd: number?)
	requestUpgradeSkillEvent:FireServer(skillType, levelAdd or 1)
end

--服务端连接升级请求
function NetMsg.ConnectRequestUpgradeSkill(callback: (player: Player, skillType: number, levelAdd: number) -> ())
	requestUpgradeSkillEvent.OnServerEvent:Connect(callback)
end

--服务端通知技能等级更新
function NetMsg.FireNotifyPlayerSkillLevelUpdate(player: Player, skillType: number, level: number)
	notifyPlayerSkillLevelUpdateEvent:FireClient(player, skillType, level)
end

--客户端连接技能等级更新通知
function NetMsg.ConnectNotifyPlayerSkillLevelUpdate(callback: (skillType: number, level: number) -> ())
	notifyPlayerSkillLevelUpdateEvent.OnClientEvent:Connect(callback)
end

--客户端发送送礼请求
function NetMsg.FireRequestSendGift(targetPlayerId: number, brainrotInstanceId: string)
	print("[NetMsg] FireRequestSendGift to target", targetPlayerId, "brainrot", brainrotInstanceId)
	requestSendGiftEvent:FireServer(targetPlayerId, brainrotInstanceId)
end

function NetMsg.ConnectRequestSendGift(callback: (player: Player, targetPlayerId: number, brainrotInstanceId: string) -> ())
	requestSendGiftEvent.OnServerEvent:Connect(callback)
end

--服务端通知玩家收到送礼请求
function NetMsg.FireNotifyReceiveGiftRequest(player: Player, senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	notifyReceiveGiftRequestEvent:FireClient(player, senderId, senderName, brainrotName, brainrotLevel)
end

function NetMsg.ConnectNotifyReceiveGiftRequest(callback: (senderId: number, senderName: string, brainrotName: string, brainrotLevel: number) -> ())
	notifyReceiveGiftRequestEvent.OnClientEvent:Connect(callback)
end

--客户端回应送礼请求
function NetMsg.FireRequestRespondGift(senderId: number, isAccepted: boolean)
	print("[NetMsg] FireRequestRespondGift to sender", senderId, "accepted", isAccepted)
	requestRespondGiftEvent:FireServer(senderId, isAccepted)
end

function NetMsg.ConnectRequestRespondGift(callback: (player: Player, senderId: number, isAccepted: boolean) -> ())
	requestRespondGiftEvent.OnServerEvent:Connect(callback)
end

--服务端通知送礼结果
function NetMsg.FireNotifyGiftResult(player: Player, isSuccess: boolean, message: string?)
	notifyGiftResultEvent:FireClient(player, isSuccess, message)
end

function NetMsg.ConnectNotifyGiftResult(callback: (isSuccess: boolean, message: string?) -> ())
	notifyGiftResultEvent.OnClientEvent:Connect(callback)
end

--服务端通知发件人打开确认弹窗
function NetMsg.FireNotifyShowGiftConfirm(player: Player, targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	notifyShowGiftConfirmEvent:FireClient(player, targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
end

function NetMsg.ConnectNotifyShowGiftConfirm(callback: (targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string) -> ())
	notifyShowGiftConfirmEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知玩家 Brainrot 背包队列更新
function NetMsg.FireNotifyBrainrotQueueUpdate(player: Player, queue: { GameConfig.BrainrotQueueItem })
	print("[NetMsg] FireNotifyBrainrotQueueUpdate for player", player.Name, "count:", #queue)
	notifyBrainrotQueueUpdateEvent:FireClient(player, queue)
end

function NetMsg.ConnectNotifyBrainrotQueueUpdate(callback: (queue: { GameConfig.BrainrotQueueItem }) -> ())
	notifyBrainrotQueueUpdateEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知客户端显示游戏提示
function NetMsg.FireNotifyShowGameTip(player: Player, tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?)
	notifyShowGameTipEvent:FireClient(player, tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

function NetMsg.ConnectNotifyShowGameTip(callback: (tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?) -> ())
	notifyShowGameTipEvent.OnClientEvent:Connect(callback)
end

-- 服务端通知客户端开始飞行救援
function NetMsg.FireNotifyRescueStart(player: Player)
	notifyRescueStartEvent:FireClient(player)
end

function NetMsg.ConnectNotifyRescueStart(callback: () -> ())
	notifyRescueStartEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求开启宝箱
function NetMsg.FireRequestOpenChest(uid: string)
	print("[NetMsg] FireRequestOpenChest", uid)
	requestOpenChestEvent:FireServer(uid)
end

function NetMsg.ConnectRequestOpenChest(callback: (player: Player, uid: string) -> ())
	requestOpenChestEvent.OnServerEvent:Connect(callback)
end

-- 服务端通知客户端宝箱开箱结果（权威结果）
function NetMsg.FireNotifyChestOpenResult(player: Player, uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number)
	notifyChestOpenResultEvent:FireClient(player, uid, chestConfigId, chestLevel, finalBrainrotId)
end

function NetMsg.ConnectNotifyChestOpenResult(callback: (uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number) -> ())
	notifyChestOpenResultEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求重生
function NetMsg.FireRequestRebirth()
	print("[NetMsg] FireRequestRebirth")
	requestRebirthEvent:FireServer()
end

function NetMsg.ConnectRequestRebirth(callback: (player: Player) -> ())
	requestRebirthEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求付费重生
function NetMsg.FireRequestPaidRebirth()
	print("[NetMsg] FireRequestPaidRebirth")
	requestPaidRebirthEvent:FireServer()
end

function NetMsg.ConnectRequestPaidRebirth(callback: (player: Player) -> ())
	requestPaidRebirthEvent.OnServerEvent:Connect(callback)
end

-- 服务端广播地震开始/结束状态
function NetMsg.FireNotifyEarthquakeState(earthquakeId: number, isStart: boolean, duration: number, judgeCount: number)
	notifyEarthquakeStateEvent:FireAllClients(earthquakeId, isStart, duration, judgeCount)
end

function NetMsg.FireNotifyEarthquakeStateToPlayer(
	player: Player,
	earthquakeId: number,
	isStart: boolean,
	duration: number,
	judgeCount: number
)
	notifyEarthquakeStateEvent:FireClient(player, earthquakeId, isStart, duration, judgeCount)
end

function NetMsg.ConnectNotifyEarthquakeState(callback: (earthquakeId: number, isStart: boolean, duration: number, judgeCount: number) -> ())
	notifyEarthquakeStateEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播地震预警（距开始剩余秒数）
function NetMsg.FireNotifyEarthquakeWarning(earthquakeId: number, secondsUntilStart: number)
	notifyEarthquakeWarningEvent:FireAllClients(earthquakeId, secondsUntilStart)
end

function NetMsg.FireNotifyEarthquakeWarningToPlayer(player: Player, earthquakeId: number, secondsUntilStart: number)
	notifyEarthquakeWarningEvent:FireClient(player, earthquakeId, secondsUntilStart)
end

function NetMsg.ConnectNotifyEarthquakeWarning(callback: (earthquakeId: number, secondsUntilStart: number) -> ())
	notifyEarthquakeWarningEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播本轮判定掉落结果
function NetMsg.FireNotifyEarthquakeJudgeDrop(
	earthquakeId: number,
	judgeIndex: number,
	droppedFloatBlocks: { any },
	droppedPavedBricks: { any }
)
	notifyEarthquakeJudgeDropEvent:FireAllClients(earthquakeId, judgeIndex, droppedFloatBlocks, droppedPavedBricks)
end

function NetMsg.FireNotifyEarthquakeJudgeDropToPlayer(
	player: Player,
	earthquakeId: number,
	judgeIndex: number,
	droppedFloatBlocks: { any },
	droppedPavedBricks: { any }
)
	notifyEarthquakeJudgeDropEvent:FireClient(player, earthquakeId, judgeIndex, droppedFloatBlocks, droppedPavedBricks)
end

function NetMsg.ConnectNotifyEarthquakeJudgeDrop(
	callback: (earthquakeId: number, judgeIndex: number, droppedFloatBlocks: { any }, droppedPavedBricks: { any }) -> ()
)
	notifyEarthquakeJudgeDropEvent.OnClientEvent:Connect(callback)
end

-- 服务端广播地震回浮结果
function NetMsg.FireNotifyEarthquakeRecover(earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any })
	notifyEarthquakeRecoverEvent:FireAllClients(earthquakeId, recoverFloatBlocks, recoverPavedBricks)
end

function NetMsg.ConnectNotifyEarthquakeRecover(
	callback: (earthquakeId: number, recoverFloatBlocks: { any }, recoverPavedBricks: { any }) -> ()
)
	notifyEarthquakeRecoverEvent.OnClientEvent:Connect(callback)
end

return NetMsg
