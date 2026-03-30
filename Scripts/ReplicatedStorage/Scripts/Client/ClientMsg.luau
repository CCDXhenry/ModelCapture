--!strict
local ClientMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local bindableEventsFolder: Folder = replicatedStorage:WaitForChild("BindableEvents") :: Folder
local closeWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CloseWindow") :: BindableEvent
local localPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInfoInit") :: BindableEvent
local otherPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OtherPlayerInfoInit") :: BindableEvent
local localPlayerAcquiredGamePassEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerAcquiredGamePass") :: BindableEvent
local localPlayerInventoryUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInventoryUpdate") :: BindableEvent
local localPlayerCarriedUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerCarriedUpdate") :: BindableEvent
local playerHomeInfoUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("PlayerHomeInfoUpdate") :: BindableEvent
local allPlayersModelYieldsUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("AllPlayersModelYieldsUpdate") :: BindableEvent
local localPlayerCurrencyUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerCurrencyUpdate") :: BindableEvent
local localPlayerSkillLevelUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerSkillLevelUpdate") :: BindableEvent
local showGameTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGameTip") :: BindableEvent
local showAddRewardsTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowAddRewardsTip") :: BindableEvent
local currentGuideTypeChangedEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CurrentGuideTypeChanged") :: BindableEvent

-- Gifting UI events
local showGiftConfirmPopupEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGiftConfirmPopup") :: BindableEvent
local showGiftRequestPopupEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGiftRequestPopup") :: BindableEvent
local showTopTipTextEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowTopTipText") :: BindableEvent
local brainrotQueueUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("BrainrotQueueUpdate") :: BindableEvent
local showRescuePopupEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowRescuePopup") :: BindableEvent
local resumeFallingEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ResumeFalling") :: BindableEvent
local earthquakeUiUpdateEvent: BindableEvent = bindableEventsFolder:FindFirstChild("EarthquakeUiUpdate") :: BindableEvent

--关闭窗口事件
function ClientMsg.FireCloseWindow(windowName: string)
	closeWindowEvent:Fire(windowName)
end

function ClientMsg.ConnectCloseWindow(callback: (windowName: string) -> ())
	closeWindowEvent.Event:Connect(callback)
end

--自己的玩家信息初始化事件
function ClientMsg.FireLocalPlayerInfoInit()
	localPlayerInfoInitEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerInfoInit(callback: () -> ())
	localPlayerInfoInitEvent.Event:Connect(callback)
end

--其他玩家的信息初始化事件
function ClientMsg.FireOtherPlayerInfoInit(playerId: number)
	otherPlayerInfoInitEvent:Fire(playerId)
end

function ClientMsg.ConnectOtherPlayerInfoInit(callback: (playerId: number) -> ())
	otherPlayerInfoInitEvent.Event:Connect(callback)
end

--自己获得了通行证
function ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId: number)
	localPlayerAcquiredGamePassEvent:Fire(gamePassId)
end

function ClientMsg.ConnectLocalPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	localPlayerAcquiredGamePassEvent.Event:Connect(callback)
end

--本地玩家库存更新
function ClientMsg.FireLocalPlayerInventoryUpdate(inventoryInfo: GameConfig.PlayerInventorySaveInfo)
	localPlayerInventoryUpdateEvent:Fire(inventoryInfo)
end

function ClientMsg.ConnectLocalPlayerInventoryUpdate(callback: (inventoryInfo: GameConfig.PlayerInventorySaveInfo) -> ())
	localPlayerInventoryUpdateEvent.Event:Connect(callback)
end

--本地玩家搬运信息更新
function ClientMsg.FireLocalPlayerCarriedUpdate(carriedInfo: GameConfig.PlayerCarriedInfo)
	localPlayerCarriedUpdateEvent:Fire(carriedInfo)
end

function ClientMsg.ConnectLocalPlayerCarriedUpdate(callback: (carriedInfo: GameConfig.PlayerCarriedInfo) -> ())
	localPlayerCarriedUpdateEvent.Event:Connect(callback)
end

--玩家家园信息更新
function ClientMsg.FirePlayerHomeInfoUpdate(playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?)
	playerHomeInfoUpdateEvent:Fire(playerId, homeSlot, homeInfo, rebirthLevel)
end

function ClientMsg.ConnectPlayerHomeInfoUpdate(callback: (playerId: number, homeSlot: string, homeInfo: any, rebirthLevel: number?) -> ())
	playerHomeInfoUpdateEvent.Event:Connect(callback)
end

--所有玩家模型收益更新
function ClientMsg.FireAllPlayersModelYieldsUpdate(allYields: { [string]: { [string]: number } })
	allPlayersModelYieldsUpdateEvent:Fire(allYields)
end

function ClientMsg.ConnectAllPlayersModelYieldsUpdate(callback: (allYields: { [string]: { [string]: number } }) -> ())
	allPlayersModelYieldsUpdateEvent.Event:Connect(callback)
end

--本地玩家货币更新
function ClientMsg.FireLocalPlayerCurrencyUpdate()
	localPlayerCurrencyUpdateEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerCurrencyUpdate(callback: () -> ())
	localPlayerCurrencyUpdateEvent.Event:Connect(callback)
end

--显示游戏提示
function ClientMsg.FireShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?)
	showGameTipEvent:Fire(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

function ClientMsg.ConnectShowGameTip(callback: (tipContentSource: string, tweenType: number,
	tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?) -> ())
	showGameTipEvent.Event:Connect(callback)
end

--显示获得奖励提示
function ClientMsg.FireShowAddRewardsTip(rewardInfoList: {GameConfig.RewardInfo})
	showAddRewardsTipEvent:Fire(rewardInfoList)
end

function ClientMsg.ConnectShowAddRewardsTip(callback: (rewardInfoList: {GameConfig.RewardInfo}) -> ())
	showAddRewardsTipEvent.Event:Connect(callback)
end

--当前引导类型改变
function ClientMsg.FireCurrentGuideTypeChanged()
	currentGuideTypeChangedEvent:Fire()
end

function ClientMsg.ConnectCurrentGuideTypeChanged(callback: () -> ())
	currentGuideTypeChangedEvent.Event:Connect(callback)
end

--触发本地玩家技能等级更新
function ClientMsg.FireLocalPlayerSkillLevelUpdate(skillType: number, level: number)
	localPlayerSkillLevelUpdateEvent:Fire(skillType, level)
end

--连接本地玩家技能等级更新
function ClientMsg.ConnectLocalPlayerSkillLevelUpdate(callback: (skillType: number, level: number) -> ())
	localPlayerSkillLevelUpdateEvent.Event:Connect(callback)
end

--显示发送礼物确认弹窗
function ClientMsg.FireShowGiftConfirmPopup(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	showGiftConfirmPopupEvent:Fire(targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
end

function ClientMsg.ConnectShowGiftConfirmPopup(callback: (targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string) -> ())
	showGiftConfirmPopupEvent.Event:Connect(callback)
end

--显示收到礼物请求弹窗
function ClientMsg.FireShowGiftRequestPopup(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	showGiftRequestPopupEvent:Fire(senderId, senderName, brainrotName, brainrotLevel)
end

function ClientMsg.ConnectShowGiftRequestPopup(callback: (senderId: number, senderName: string, brainrotName: string, brainrotLevel: number) -> ())
	showGiftRequestPopupEvent.Event:Connect(callback)
end

--显示头顶UI提示
function ClientMsg.FireShowTopTipText(textSource: string, color: Color3, duration: number, args: {string}?, key: string?)
	showTopTipTextEvent:Fire(textSource, color, duration, args, key)
end

function ClientMsg.ConnectShowTopTipText(callback: (textSource: string, color: Color3, duration: number, args: {string}?, key: string?) -> ())
	showTopTipTextEvent.Event:Connect(callback)
end

-- 地震 UI：phase 为 "warning" | "active" | "hide"；countdownSeconds 为预警距开始剩余秒数，或地震进行中剩余时长（秒）
function ClientMsg.FireEarthquakeUiUpdate(phase: string, countdownSeconds: number?)
	earthquakeUiUpdateEvent:Fire(phase, countdownSeconds)
end

function ClientMsg.ConnectEarthquakeUiUpdate(callback: (phase: string, countdownSeconds: number?) -> ())
	earthquakeUiUpdateEvent.Event:Connect(callback)
end

-- Brainrot 背包队列更新
function ClientMsg.FireBrainrotQueueUpdate(queue: { GameConfig.BrainrotQueueItem })
	brainrotQueueUpdateEvent:Fire(queue)
end

function ClientMsg.ConnectBrainrotQueueUpdate(callback: (queue: { GameConfig.BrainrotQueueItem }) -> ())
	brainrotQueueUpdateEvent.Event:Connect(callback)
end

-- 显示救援弹窗
function ClientMsg.FireShowRescuePopup()
	if showRescuePopupEvent then
		showRescuePopupEvent:Fire()
	end
end

function ClientMsg.ConnectShowRescuePopup(callback: () -> ())
	if showRescuePopupEvent then
		showRescuePopupEvent.Event:Connect(callback)
	end
end

-- 恢复掉落（拒绝救援或超时）
function ClientMsg.FireResumeFalling()
	if resumeFallingEvent then
		resumeFallingEvent:Fire()
	end
end

function ClientMsg.ConnectResumeFalling(callback: () -> ())
	if resumeFallingEvent then
		resumeFallingEvent.Event:Connect(callback)
	end
end

return ClientMsg