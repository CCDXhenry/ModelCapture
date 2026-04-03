--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local tweenService: TweenService = game:GetService("TweenService")
local runService: RunService = game:GetService("RunService")
local toolOriginsFolder = replicatedStorage:FindFirstChild("Tools")
local soundFolder = replicatedStorage:WaitForChild("Sounds")
local soundService: SoundService = game:FindFirstChild("SoundService")
local UserInputService = game:GetService("UserInputService")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players = game:GetService("Players")
local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo == nil then
	return
end

type GameTipTweens = {
	flyUpTween1: Tween,
	stayFlyUpTween1: Tween,
	flyUpTween2: Tween,
	twinkleTween: Tween,
	flyUpTwinkleTween: Tween,
	twinkleTween2: Tween,
}

local GameTipFlyUpTween1Info: TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.5)
local GameTipStayFlyUpTween1Info: TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 5)
local GameTipFlyUpTween2Info: TweenInfo = TweenInfo.new(0.5)
local GameTipTwinkleTweenInfo: TweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true)
local GameTipTwinkleTweenInfo2: TweenInfo = TweenInfo.new(
	0.25, -- 单程 0.25s
	Enum.EasingStyle.Linear,
	Enum.EasingDirection.InOut,
	5, -- 重复次数
	true,
	0
)

local ShowAddRewardsTipIntervalMin: number = 0.5

local waitingShowAddRewardInfoList: { GameConfig.RewardInfo } = {}
local lastShowedAddRewardsTipTime: number = -1
local isShowRewardFrame: boolean = false

local gameTipFrame: Frame = script.Parent
local gameTipTextsTweens: { [TextLabel]: GameTipTweens } = {}

-- 常量定义
local GIFT_CONFIRM_TITLE_COLOR = Color3.fromRGB(0, 255, 0) -- 绿色
local GIFT_REQUEST_TITLE_COLOR = Color3.fromRGB(0, 0, 255)  -- 蓝色
local TOP_TIP_DEFAULT_COLOR = Color3.fromRGB(255, 255, 255) -- 白色
local TOP_TIP_SUCCESS_COLOR = Color3.fromRGB(0, 255, 0)     -- 绿色
local _TOP_TIP_FAILURE_COLOR = Color3.fromRGB(255, 0, 0)     -- 红色

local GIFT_POPUP_COUNTDOWN_TIME = 10
local GIFT_TOP_TIP_DURATION = 5
local TOP_TIP_FADE_DURATION = 0.5

--AddRewardTipFrame
local addRewardTipFrameOrigin: Frame = gameTipFrame:FindFirstChild("AddRewardTipFrame") :: Frame
addRewardTipFrameOrigin.Parent = nil
local addRewardsTipTweens: { [Frame]: { tween1: Tween, tween2: Tween } } = {}
local addRewardTipFramePool: { Frame } = {}
local getCoinSound: Sound = (soundFolder:FindFirstChild("GetCoinSound") :: Sound):Clone()
getCoinSound.Parent = soundService
--GameTipText
local gameTipTextOrigin: TextLabel = gameTipFrame:FindFirstChild("GameTipText") :: TextLabel
gameTipTextOrigin.Parent = nil
local gameTipTextsTweens: { [TextLabel]: GameTipTweens } = {}
local gameTipTextsPool: { TextLabel } = {}

--PopUpTipFrame
local popUpTipFrame: Frame? = gameTipFrame:FindFirstChild("PopUpTipFrame") :: Frame
local popUpYesButton: TextButton?
local popUpNoButton: TextButton?
local popUpTitleLabel: TextLabel?
local popUpTipInfoLabel: TextLabel?
local popUpTimeLabel: TextLabel?
local rescueFlightPopUpTipFrame: Frame? = gameTipFrame:FindFirstChild("RescueFlightPopUpTipFrame") :: Frame
local rescueFlightYesButton: TextButton?
local rescueFlightNoButton: TextButton?
local rescueFlightTipInfoLabel: TextLabel?
local rescueFlightTimeLabel: TextLabel?

local activePopUpConnectionYes: RBXScriptConnection?
local activePopUpConnectionNo: RBXScriptConnection?
local popUpCountdownCoroutine: thread?

if popUpTipFrame then
	popUpYesButton = popUpTipFrame:FindFirstChild("YesButton") :: TextButton
	popUpNoButton = popUpTipFrame:FindFirstChild("NoButton") :: TextButton
	popUpTitleLabel = popUpTipFrame:FindFirstChild("TitleLabel") :: TextLabel
	popUpTipInfoLabel = popUpTipFrame:FindFirstChild("TipInfoLabel") :: TextLabel
	if popUpYesButton then
		popUpTimeLabel = popUpYesButton:FindFirstChild("TimeLabel") :: TextLabel
	end
end

-- RescueFlightPopUpTipFrame
if rescueFlightPopUpTipFrame == nil and popUpTipFrame then
	local rescueFrameClone = popUpTipFrame:Clone()
	rescueFrameClone.Name = "RescueFlightPopUpTipFrame"
	local titleLabelClone = rescueFrameClone:FindFirstChild("TitleLabel")
	if titleLabelClone then
		titleLabelClone:Destroy()
	end
	rescueFrameClone.Visible = false
	rescueFrameClone.Parent = gameTipFrame
	rescueFlightPopUpTipFrame = rescueFrameClone
end
if rescueFlightPopUpTipFrame then
	rescueFlightYesButton = rescueFlightPopUpTipFrame:FindFirstChild("YesButton") :: TextButton
	rescueFlightNoButton = rescueFlightPopUpTipFrame:FindFirstChild("NoButton") :: TextButton
	rescueFlightTipInfoLabel = rescueFlightPopUpTipFrame:FindFirstChild("TipInfoLabel") :: TextLabel
	if rescueFlightYesButton then
		rescueFlightTimeLabel = rescueFlightYesButton:FindFirstChild("TimeLabel") :: TextLabel
	end
end

--TopTipText
local topTipText: TextLabel? = gameTipFrame:FindFirstChild("TopTipText") :: TextLabel
local topTipFadeCoroutine: thread?

local EARTHQUAKE_WARNING_COLOR = Color3.fromRGB(255, 210, 0)
local EARTHQUAKE_DANGER_COLOR = Color3.fromRGB(255, 60, 60)

local countdownText: TextLabel? = gameTipFrame:FindFirstChild("CountdownText") :: TextLabel
if countdownText == nil and topTipText ~= nil then
	local label = Instance.new("TextLabel")
	label.Name = "CountdownText"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(0, 140, 0, 80)
	label.Position = UDim2.new(0.5, 0, 0.4, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = EARTHQUAKE_WARNING_COLOR
	label.Text = ""
	label.Visible = false
	label.Parent = gameTipFrame
	countdownText = label
end
local function PlayPopTween(ui: ImageLabel, popTime: number, maxScale: number, hideOnMax: boolean)
	ui.ImageTransparency = 0
	ui.Visible = true
	local uiScale: UIScale = ui:FindFirstChild("UIScale") :: UIScale
	uiScale.Scale = 0

	local popTween = tweenService:Create(uiScale, TweenInfo.new(popTime * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = maxScale })

	local backTween = tweenService:Create(uiScale, TweenInfo.new(popTime * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = maxScale })

	popTween.Completed:Once(function()
		if hideOnMax then
			ui.Visible = false
			uiScale.Scale = 0
		end
		backTween:Play()
	end)

	popTween:Play()
end

local function ShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: { string }?, textColor: Color3?)
	local gameTipText: TextLabel = table.remove(gameTipTextsPool) or gameTipTextOrigin:Clone()
	if textColor then
		gameTipText.TextColor3 = textColor
	else
		gameTipText.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	local gameTipTextTweens: GameTipTweens = gameTipTextsTweens[gameTipText]
	if gameTipTextTweens == nil then
		local gameTextStroke: UIStroke = gameTipText:FindFirstChild("UIStroke") :: UIStroke
		gameTipText:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			gameTextStroke.Transparency = gameTipText.TextTransparency
		end)
		local flyUpTween1: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local stayFlyUpTween1: Tween = tweenService:Create(gameTipText, GameTipStayFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local flyUpTwinkleTween: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local flyUpTween2: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween2Info, { TextTransparency = 1 })
		local twinkleTween2 = tweenService:Create(gameTipText, GameTipTwinkleTweenInfo2, { TextTransparency = 1 })
		flyUpTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			flyUpTween2:Play()
		end)
		stayFlyUpTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			flyUpTween2:Play()
		end)
		flyUpTween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		local twinkleTween: Tween = tweenService:Create(gameTipText, GameTipTwinkleTweenInfo, { TextTransparency = 0 })
		twinkleTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		twinkleTween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		flyUpTwinkleTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			twinkleTween2:Play()
		end)

		gameTipTextTweens = {
			flyUpTween1 = flyUpTween1,
			stayFlyUpTween1 = stayFlyUpTween1,
			flyUpTween2 = flyUpTween2,
			twinkleTween = twinkleTween,
			flyUpTwinkleTween = flyUpTwinkleTween,
			twinkleTween2 = twinkleTween2,
		}
	end
	gameTipText.Parent = gameTipFrame
	local absolutePosition: Vector2 = gameTipText.AbsolutePosition
	if tweenType == GameConfig.GameTipTweenType.FlyUp then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.flyUpTween1:Play()
	elseif tweenType == GameConfig.GameTipTweenType.Twinkle then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 1
		gameTipTextTweens.twinkleTween:Play()
	elseif tweenType == GameConfig.GameTipTweenType.StayFlyUp then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.stayFlyUpTween1:Play()
	elseif tweenType == GameConfig.GameTipTweenType.FlyUpTwinkle then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.flyUpTwinkleTween:Play()
	elseif tweenType == GameConfig.GameTipTweenType.Twinkle2 then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 110)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.twinkleTween2:Play()
	end
	TranslationTool.CustomAutoLocalizeTextLabel(gameTipText, tipContentSource, tipContentKey, tipContentArgs)
end

local function ShowAddRewardsTip(rewardIcon: string, rewardCount: number)
	local addRewardTipFrame: Frame = table.remove(addRewardTipFramePool) or addRewardTipFrameOrigin:Clone()
	local transparencyValue: NumberValue = addRewardTipFrame:FindFirstChild("Transparency") :: NumberValue
	local rewardIconImage: ImageLabel = addRewardTipFrame:FindFirstChild("RewardIconImage") :: ImageLabel
	rewardIconImage.Image = rewardIcon
	local rewardCountText: TextLabel = addRewardTipFrame:FindFirstChild("RewardCountText") :: TextLabel
	rewardCountText.Text = "+" .. NumberExtension.FormatBigNumberAA(rewardCount)
	local addRewardsTipTweens: { tween1: Tween, tween2: Tween } = addRewardsTipTweens[addRewardTipFrame]
	if addRewardsTipTweens == nil then
		local rewardCountTextStroke: UIStroke = rewardCountText:FindFirstChild("UIStroke") :: UIStroke
		transparencyValue.Changed:Connect(function(value: number)
			rewardIconImage.ImageTransparency = value
			rewardCountText.TextTransparency = value
			rewardCountTextStroke.Transparency = value
		end)
		local tween1: Tween = tweenService:Create(addRewardTipFrame, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, 0) })
		local tween2: Tween = tweenService:Create(transparencyValue, GameTipFlyUpTween2Info, { Value = 1 })
		tween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			tween2:Play()
		end)
		tween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			addRewardTipFrame.Parent = nil
			table.insert(addRewardTipFramePool, addRewardTipFrame)
		end)
		addRewardsTipTweens = { tween1 = tween1, tween2 = tween2 }
	end
	addRewardTipFrame.Parent = gameTipFrame
	addRewardTipFrame.Position = UDim2.new(0.5, 0, 0.8, 0)
	transparencyValue.Value = 0
	addRewardsTipTweens.tween1:Play()
	SoundTool.PlayDesignatedSoundEffect(getCoinSound)
end

local function OnRenderStepped(deltaTime: number)
	local nowTime: number = time()
	--获得奖励提示
	if #waitingShowAddRewardInfoList > 0 and (lastShowedAddRewardsTipTime == -1 or nowTime - lastShowedAddRewardsTipTime >= ShowAddRewardsTipIntervalMin) then
		local rewardInfo: GameConfig.RewardInfo? = table.remove(waitingShowAddRewardInfoList, 1)
		if rewardInfo ~= nil then
			if rewardInfo.rewardType == GameConfig.RewardType.Currency then
				local currencyType: number? = tonumber(rewardInfo.rewardId)
				if currencyType == GameConfig.CurrencyType.Coin then
					ShowAddRewardsTip(GameConfig.CoinIconImage, rewardInfo.rewardCount)
				end
			elseif rewardInfo.rewardType == GameConfig.RewardType.Brainrot then
				local brainrotData = GameConfig.BrainrotIdMap[rewardInfo.rewardId]
				if brainrotData and brainrotData.iconImageId and brainrotData.iconImageId ~= "" then
					ShowAddRewardsTip(brainrotData.iconImageId, rewardInfo.rewardCount)
				end
			elseif rewardInfo.rewardType == GameConfig.RewardType.Coil then
				local coilData = GameConfig.CoilIdMap[rewardInfo.rewardId]
				if coilData and coilData.iconImageId and coilData.iconImageId ~= "" then
					ShowAddRewardsTip(coilData.iconImageId, rewardInfo.rewardCount)
				end
			elseif rewardInfo.rewardType == GameConfig.RewardType.LittleElfChest then
				local chestData = GameConfig.LittleElfChestIdMap[rewardInfo.rewardId]
				if chestData and chestData.iconImageId and chestData.iconImageId ~= "" then
					ShowAddRewardsTip(chestData.iconImageId, rewardInfo.rewardCount)
				end
			end
		end
		lastShowedAddRewardsTipTime = nowTime
	end
end

local function OnShowAddRewardsTip(rewardInfoList: { GameConfig.RewardInfo })
	table.move(rewardInfoList, 1, #rewardInfoList, #waitingShowAddRewardInfoList + 1, waitingShowAddRewardInfoList)
end

--显示游戏提示
local function OnShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: { string }?, textColor: Color3?)
	ShowGameTip(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

local function HidePopUpTipFrame()
	if popUpTipFrame then
		popUpTipFrame.Visible = false
	end
	if rescueFlightPopUpTipFrame then
		rescueFlightPopUpTipFrame.Visible = false
	end
	if activePopUpConnectionYes then
		activePopUpConnectionYes:Disconnect()
		activePopUpConnectionYes = nil
	end
	if activePopUpConnectionNo then
		activePopUpConnectionNo:Disconnect()
		activePopUpConnectionNo = nil
	end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
		popUpCountdownCoroutine = nil
	end
end

local function StartPopUpCountdown(targetTimeLabel: TextLabel?, timeoutCallback: () -> ())
	if not targetTimeLabel then return end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
	end
	local newCoroutine = coroutine.create(function()
		for i = GIFT_POPUP_COUNTDOWN_TIME, 0, -1 do
			TranslationTool.CustomAutoLocalizeTextLabel(targetTimeLabel, string.gsub(GameTexts.CountdownFormat.source, "{1}", tostring(i)), GameTexts.CountdownFormat.key, {tostring(i)})
			task.wait(1)
		end
		timeoutCallback()
	end)
	popUpCountdownCoroutine = newCoroutine
	coroutine.resume(newCoroutine)
end

local function OnShowGiftConfirmPopup(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
	if not popUpTipFrame or not popUpYesButton or not popUpNoButton or not popUpTitleLabel or not popUpTipInfoLabel then return end
	HidePopUpTipFrame()
	popUpTipFrame.Visible = true
	popUpTitleLabel.TextColor3 = GIFT_CONFIRM_TITLE_COLOR
	
	TranslationTool.CustomAutoLocalizeTextLabel(popUpTitleLabel, GameTexts.GiftConfirmTitle.source, GameTexts.GiftConfirmTitle.key)
	TranslationTool.CustomAutoLocalizeTextLabel(popUpTipInfoLabel, GameTexts.GiftConfirmBody.source, GameTexts.GiftConfirmBody.key, {giftName, targetPlayerName})
	
	activePopUpConnectionYes = popUpYesButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestSendGift(targetPlayerId, brainrotInstanceId)
		HidePopUpTipFrame()
		ClientMsg.FireShowTopTipText(GameTexts.GiftRequestSent.source, TOP_TIP_DEFAULT_COLOR, GIFT_TOP_TIP_DURATION, {targetPlayerName}, GameTexts.GiftRequestSent.key)
	end)
	activePopUpConnectionNo = popUpNoButton.MouseButton1Click:Connect(function()
		HidePopUpTipFrame()
	end)
	StartPopUpCountdown(popUpTimeLabel, function() HidePopUpTipFrame() end)
end

local function OnShowGiftRequestPopup(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
	if not popUpTipFrame or not popUpYesButton or not popUpNoButton or not popUpTitleLabel or not popUpTipInfoLabel then return end
	HidePopUpTipFrame()
	popUpTipFrame.Visible = true
	popUpTitleLabel.TextColor3 = GIFT_REQUEST_TITLE_COLOR
	
	TranslationTool.CustomAutoLocalizeTextLabel(popUpTitleLabel, GameTexts.GiftRequestTitle.source, GameTexts.GiftRequestTitle.key)
	TranslationTool.CustomAutoLocalizeTextLabel(popUpTipInfoLabel, GameTexts.GiftRequestBody.source, GameTexts.GiftRequestBody.key, {senderName, brainrotName, tostring(brainrotLevel)})
	
	activePopUpConnectionYes = popUpYesButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestRespondGift(senderId, true)
		HidePopUpTipFrame()
		ClientMsg.FireShowTopTipText(GameTexts.GiftSuccess.source, TOP_TIP_SUCCESS_COLOR, GIFT_TOP_TIP_DURATION, nil, GameTexts.GiftSuccess.key)
	end)
	activePopUpConnectionNo = popUpNoButton.MouseButton1Click:Connect(function()
		NetMsg.FireRequestRespondGift(senderId, false)
		HidePopUpTipFrame()
	end)
	StartPopUpCountdown(popUpTimeLabel, function() HidePopUpTipFrame() end)
end

local function OnShowRescuePopup()
	if not rescueFlightPopUpTipFrame or not rescueFlightYesButton or not rescueFlightNoButton or not rescueFlightTipInfoLabel then return end
	HidePopUpTipFrame()
	rescueFlightPopUpTipFrame.Visible = true
	TranslationTool.CustomAutoLocalizeTextLabel(rescueFlightTipInfoLabel, GameTexts.RescueFlightBody.source, GameTexts.RescueFlightBody.key)
	
	activePopUpConnectionYes = rescueFlightYesButton.MouseButton1Click:Connect(function()
		marketplaceService:PromptProductPurchase(players.LocalPlayer, GameConfig.Paving.DeathRescueProductId)
		HidePopUpTipFrame()
	end)
	
	activePopUpConnectionNo = rescueFlightNoButton.MouseButton1Click:Connect(function()
		ClientMsg.FireResumeFalling()
		HidePopUpTipFrame()
	end)
	
	StartPopUpCountdown(rescueFlightTimeLabel, function() 
		ClientMsg.FireResumeFalling()
		HidePopUpTipFrame() 
	end)
end

local function OnEarthquakeUiUpdate(phase: string, countdownSeconds: number?)
	if not topTipText then
		return
	end
	if topTipFadeCoroutine then
		coroutine.close(topTipFadeCoroutine)
		topTipFadeCoroutine = nil
	end
	topTipText.TextTransparency = 0
	local topStroke = topTipText:FindFirstChild("UIStroke") :: UIStroke?
	if topStroke then
		topStroke.Transparency = 0
	end
	if phase == "warning" then
		topTipText.Visible = true
		TranslationTool.CustomAutoLocalizeTextLabel(topTipText, GameTexts.EarthquakeImminent.source, GameTexts.EarthquakeImminent.key, {})
		topTipText.TextColor3 = EARTHQUAKE_WARNING_COLOR
		if countdownText then
			countdownText.Visible = true
			if type(countdownSeconds) == "number" then
				countdownText.Text = tostring(countdownSeconds)
			end
			countdownText.TextColor3 = EARTHQUAKE_WARNING_COLOR
		end
	elseif phase == "active" then
		topTipText.Visible = true
		TranslationTool.CustomAutoLocalizeTextLabel(topTipText, GameTexts.EarthquakeActive.source, GameTexts.EarthquakeActive.key, {})
		topTipText.TextColor3 = EARTHQUAKE_DANGER_COLOR
		if countdownText then
			countdownText.Visible = true
			if type(countdownSeconds) == "number" then
				countdownText.Text = tostring(countdownSeconds)
			end
			countdownText.TextColor3 = EARTHQUAKE_DANGER_COLOR
		end
	elseif phase == "hide" then
		topTipText.Visible = false
		if countdownText then
			countdownText.Visible = false
		end
	end
end

local function OnShowTopTipText(textSource: string, color: Color3, duration: number, args: {string}?, key: string?)
	if not topTipText then return end
	if topTipFadeCoroutine then
		coroutine.close(topTipFadeCoroutine)
	end
	topTipText.Visible = true
	topTipText.TextColor3 = color
	topTipText.TextTransparency = 0
	
	local stroke = topTipText:FindFirstChild("UIStroke") :: UIStroke
	if stroke then stroke.Transparency = 0 end

	TranslationTool.CustomAutoLocalizeTextLabel(topTipText, textSource, key, args)
	
	local newCoroutine = coroutine.create(function()
		task.wait(duration)
		local tween = tweenService:Create(topTipText, TweenInfo.new(TOP_TIP_FADE_DURATION), {TextTransparency = 1})
		tween:Play()
		if stroke then
			local strokeTween = tweenService:Create(stroke, TweenInfo.new(TOP_TIP_FADE_DURATION), {Transparency = 1})
			strokeTween:Play()
		end
		tween.Completed:Wait()
		topTipText.Visible = false
	end)
	topTipFadeCoroutine = newCoroutine
	coroutine.resume(newCoroutine)
end

UIAdapter.AddAdaptiveFrame(gameTipFrame, UIAdapter.AdaptiveType.FullScreen)

marketplaceService.PromptProductPurchaseFinished:Connect(function(playerId, productId, isPurchased)
	if playerId ~= players.LocalPlayer.UserId then
		return
	end
	if productId ~= GameConfig.Paving.DeathRescueProductId then
		return
	end
	-- 点「是」后关闭/取消付款界面：与首屏点「否」一致，恢复坠落（ConnectResumeFalling 内会校验 isAwaitingRescue）
	if not isPurchased then
		ClientMsg.FireResumeFalling()
	end
end)

runService:BindToRenderStep("GameTipFrame.RenderStepped", Enum.RenderPriority.Camera.Value + 2, OnRenderStepped)

ClientMsg.ConnectShowGameTip(OnShowGameTip)
ClientMsg.ConnectShowAddRewardsTip(OnShowAddRewardsTip)
ClientMsg.ConnectShowGiftConfirmPopup(OnShowGiftConfirmPopup)
ClientMsg.ConnectShowGiftRequestPopup(OnShowGiftRequestPopup)
ClientMsg.ConnectShowTopTipText(OnShowTopTipText)
ClientMsg.ConnectEarthquakeUiUpdate(OnEarthquakeUiUpdate)
ClientMsg.ConnectShowRescuePopup(OnShowRescuePopup)
--ClientMsg.ConnectShowRewardFrame(OnShowRewardFrame)
