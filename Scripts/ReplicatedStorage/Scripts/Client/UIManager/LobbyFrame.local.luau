--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local scriptsFolder = core:WaitForChild("Scripts")
local sharedScripts = scriptsFolder:WaitForChild("Shared")
local NumberExtension = require(sharedScripts:FindFirstChild("NumberExtension"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts_game = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts_game:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts_game:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):FindFirstChild("TranslationTool"))
local GameTexts = require(sharedScripts_game:FindFirstChild("GameTexts"))
local userInputService = game:GetService("UserInputService")
local tweenService: TweenService = game:GetService("TweenService")

local lobbyFrame: Frame = script.Parent
local coinFrame: Frame = lobbyFrame:FindFirstChild("CoinFrame") :: Frame
local coinCountText: TextLabel = coinFrame:FindFirstChild("CoinCountText") :: TextLabel
local guideText: TextLabel = lobbyFrame:FindFirstChild("GuideText") :: TextLabel
guideText.Visible = false
local mainGuideText: LocalScript = uiManagerScript:FindFirstChild("MainGuideText") :: LocalScript
local guideTextScript: LocalScript = mainGuideText:Clone()
guideTextScript.Parent = guideText

local maxBricksFrame: Frame = lobbyFrame:FindFirstChild("MaxBricksFrame") :: Frame
local maxBricksText: TextLabel = maxBricksFrame:FindFirstChild("NumberText") :: TextLabel
local maxBricksLvText: TextLabel = maxBricksFrame:FindFirstChild("LvText") :: TextLabel
local walkSpeedFrame: Frame = lobbyFrame:FindFirstChild("WalkSpeedFrame") :: Frame
local walkSpeedText: TextLabel = walkSpeedFrame:FindFirstChild("NumberText") :: TextLabel
local walkSpeedLvText: TextLabel = walkSpeedFrame:FindFirstChild("LvText") :: TextLabel
local decelerationButton: ImageButton? = lobbyFrame:FindFirstChild("DecelerationButton") :: ImageButton?
local decelerationButtonTextLabel: TextLabel? = if decelerationButton then (decelerationButton:FindFirstChild("TextLabel") :: TextLabel?) else nil
local bottomButtonsFrame = lobbyFrame:FindFirstChild("BottomButtonsFrame")
local rebirthFrame: Frame? = (lobbyFrame:FindFirstChild("RebirthFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("RebirthFrame") else nil)) :: Frame?
local rebirthButton: GuiButton? = if rebirthFrame then (rebirthFrame:FindFirstChild("Button") :: any) else nil
local rebirthNumberText: TextLabel? = if rebirthFrame then (rebirthFrame:FindFirstChild("NumberText") :: TextLabel?) else nil
local storeBundleEntryFrame: Frame? = (lobbyFrame:FindFirstChild("StoreBundleFrame") or (if bottomButtonsFrame then bottomButtonsFrame:FindFirstChild("StoreBundleFrame") else nil)) :: Frame?
local storeBundleButton: GuiButton? = if storeBundleEntryFrame then (storeBundleEntryFrame:FindFirstChild("Button") :: any) else nil

local maxBricksAddButton: GuiButton? = maxBricksFrame:FindFirstChild("AddButton") :: any
local walkSpeedAddButton: GuiButton? = walkSpeedFrame:FindFirstChild("AddButton") :: any

local LowBricksThreshold: number = 10
local LowBricksWarningColor = Color3.fromRGB(255, 70, 70)
local MaxBricksWarningGrowTweenInfo: TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MaxBricksWarningShrinkTweenInfo: TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MaxBricksWarningPulseScale: number = 1.12
local defaultWalkSpeedColor = walkSpeedText.TextColor3
local defaultMaxBricksColor = maxBricksText.TextColor3
local maxBricksTextScale: UIScale = (maxBricksText:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")) :: UIScale
if maxBricksTextScale.Parent ~= maxBricksText then
	maxBricksTextScale.Parent = maxBricksText
end
maxBricksTextScale.Scale = 1
local maxBricksWarningGrowTween: Tween? = nil
local maxBricksWarningShrinkTween: Tween? = nil
local localPlayer = game:GetService("Players").LocalPlayer
local humSpeedConnection: RBXScriptConnection? = nil
local DecelerationOnImage = GameConfig.DecelerationOnImage
local DecelerationOffImage = GameConfig.DecelerationOffImage
local DecelerationButtonShowSpeed = GameConfig.DecelerationButtonShowSpeed

local function ResetMaxBricksWarningAnimation()
	if maxBricksWarningGrowTween ~= nil then
		maxBricksWarningGrowTween:Cancel()
		maxBricksWarningGrowTween = nil
	end
	if maxBricksWarningShrinkTween ~= nil then
		maxBricksWarningShrinkTween:Cancel()
		maxBricksWarningShrinkTween = nil
	end
	maxBricksTextScale.Scale = 1
end

local function PlayMaxBricksWarningAnimation()
	ResetMaxBricksWarningAnimation()
	local growTween = tweenService:Create(maxBricksTextScale, MaxBricksWarningGrowTweenInfo, { Scale = MaxBricksWarningPulseScale })
	local shrinkTween = tweenService:Create(maxBricksTextScale, MaxBricksWarningShrinkTweenInfo, { Scale = 1 })
	maxBricksWarningGrowTween = growTween
	maxBricksWarningShrinkTween = shrinkTween
	local growConnection: RBXScriptConnection? = nil
	local shrinkConnection: RBXScriptConnection? = nil
	growConnection = growTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if growConnection ~= nil then
			growConnection:Disconnect()
			growConnection = nil
		end
		if playbackState ~= Enum.PlaybackState.Completed or maxBricksWarningGrowTween ~= growTween then
			return
		end
		maxBricksWarningGrowTween = nil
		shrinkConnection = shrinkTween.Completed:Connect(function()
			if shrinkConnection ~= nil then
				shrinkConnection:Disconnect()
				shrinkConnection = nil
			end
			if maxBricksWarningShrinkTween == shrinkTween then
				maxBricksWarningShrinkTween = nil
			end
		end)
		shrinkTween:Play()
	end)
	growTween:Play()
end

-- RebirthFrame 红点（感叹号圆圈）
local rebirthRedPoint: GuiObject? = if rebirthFrame then (rebirthFrame:FindFirstChild("RedPoint") :: GuiObject?) else nil
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointFrame") :: GuiObject?
end
if rebirthRedPoint == nil and rebirthFrame then
	rebirthRedPoint = rebirthFrame:FindFirstChild("RedPointCircle") :: GuiObject?
end

local DEFAULT_REBIRTH_REQUIRED_LEVEL = 1

local function IsRebirthRedPointConditionMet(): boolean
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end

	local rebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0
	local nextRebirthData = GameConfig.RebirthMap[rebirthLevel + 1]
	if not nextRebirthData then
		return false
	end

	local currentSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or DEFAULT_REBIRTH_REQUIRED_LEVEL
	local currentBricksLevel = localPlayerInfo.shopInfo.maxBricksLevel or DEFAULT_REBIRTH_REQUIRED_LEVEL
	return currentSpeedLevel >= nextRebirthData.speedLv and currentBricksLevel >= nextRebirthData.brickLv
end

local function RefreshRebirthRedPointView()
	if rebirthRedPoint == nil then
		return
	end
	rebirthRedPoint.Visible = IsRebirthRedPointConditionMet()
end

local function GetIsDecelerationOn(): boolean
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return false
	end
	return localPlayerInfo.settingInfo.decelerationOn == true
end

local function RefreshDecelerationButtonImage()
	if decelerationButton == nil then
		return
	end
	decelerationButton.Image = if GetIsDecelerationOn() then DecelerationOnImage else DecelerationOffImage
end

local function RefreshDecelerationButtonText()
	if decelerationButtonTextLabel == nil then
		return
	end
	local textData = if GetIsDecelerationOn() then GameTexts.DecelerationOn else GameTexts.DecelerationOff
	TranslationTool.CustomAutoLocalizeTextLabel(decelerationButtonTextLabel, textData.source, textData.key)
end

local function RefreshDecelerationButtonView()
	RefreshDecelerationButtonImage()
	RefreshDecelerationButtonText()
end

local function RefreshDecelerationButtonVisible(levelSpeed: number)
	if decelerationButton == nil then
		return
	end
	decelerationButton.Visible = levelSpeed > DecelerationButtonShowSpeed
end

local function ToggleDecelerationOn()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo == nil then
		return
	end
	local newDecelerationOn = not (localPlayerInfo.settingInfo.decelerationOn == true)
	localPlayerInfo.settingInfo.decelerationOn = newDecelerationOn
	RefreshDecelerationButtonView()
	NetMsg.FireRequestSetDecelerationOn(newDecelerationOn)
end

if maxBricksAddButton then
	maxBricksAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.UpgradeShop)
	end)
end

if walkSpeedAddButton then
	walkSpeedAddButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.UpgradeShop)
	end)
end

if rebirthButton then
	rebirthButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.Rebirth)
	end)
end

if storeBundleButton then
	storeBundleButton.Activated:Connect(function()
		UIManager.OpenWindow(UIManager.WindowId.StoreBundle)
	end)
end

if decelerationButton then
	decelerationButton.Activated:Connect(function()
		ToggleDecelerationOn()
	end)
end

userInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if inputObject.KeyCode ~= Enum.KeyCode.T then
		return
	end
	ToggleDecelerationOn()
end)

--刷新金币数量
local function RefreshCoinCountText()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	local coinAmount: number = localPlayerInfo.currencies["1"] or 0
	coinCountText.Text = NumberExtension.FormatBigNumberAA(coinAmount)
end

--刷新砖块数量
local function RefreshBricksDisplay()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	-- Current Bricks
	local bricksAmount: number = localPlayerInfo.carriedInfo.bricks or 0
	local bricksStr = NumberExtension.FormatBigNumberAA(bricksAmount)

	-- Max Bricks
	local maxBricksLevel = localPlayerInfo.shopInfo.maxBricksLevel or 1
	local maxBricksConfig = GameConfig.Shop.MaxBricks
	local maxValue = 0
	if maxBricksConfig then
		maxValue = maxBricksConfig.abilityList[maxBricksLevel] or maxBricksConfig.abilityList[1]
	end
	local maxValueStr = NumberExtension.FormatBigNumberAA(maxValue)

	TranslationTool.CustomAutoLocalizeTextLabel(maxBricksText, GameTexts.BricksCurrentMax.source, GameTexts.BricksCurrentMax.key, { bricksStr, maxValueStr })
	local remainingBricks = bricksAmount
	if remainingBricks <= LowBricksThreshold then
		maxBricksText.TextColor3 = LowBricksWarningColor
		PlayMaxBricksWarningAnimation()
	else
		maxBricksText.TextColor3 = defaultMaxBricksColor
		ResetMaxBricksWarningAnimation()
	end
end

--刷新升级数值
local function RefreshUpgradeValues()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end

	-- MaxBricks done in RefreshBricksDisplay
	RefreshBricksDisplay()

	-- Level text (用于显示“（Lv.10）”)
	local maxBricksLevel = localPlayerInfo.shopInfo.maxBricksLevel or 1
	TranslationTool.CustomAutoLocalizeTextLabel(
		maxBricksLvText,
		GameTexts.LevelWithFullWidthParentheses.source,
		GameTexts.LevelWithFullWidthParentheses.key,
		{ tostring(maxBricksLevel) }
	)

	-- WalkSpeed
	local walkSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or 1
	TranslationTool.CustomAutoLocalizeTextLabel(
		walkSpeedLvText,
		GameTexts.LevelWithFullWidthParentheses.source,
		GameTexts.LevelWithFullWidthParentheses.key,
		{ tostring(walkSpeedLevel) }
	)

	local isDecelerationOn = localPlayerInfo.settingInfo.decelerationOn == true
	local targetWalkSpeedLevel = if isDecelerationOn then 1 else walkSpeedLevel
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	local levelSpeed = 16
	local baseSpeed = 16
	if walkSpeedConfig then
		levelSpeed = walkSpeedConfig.abilityList[walkSpeedLevel] or walkSpeedConfig.abilityList[1]
		baseSpeed = walkSpeedConfig.abilityList[targetWalkSpeedLevel] or walkSpeedConfig.abilityList[1]
	end

	local char = localPlayer.Character
	local currentSpeed = baseSpeed
	local isBuffed = false
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			currentSpeed = hum.WalkSpeed
			if currentSpeed > baseSpeed + 0.1 then
				isBuffed = true
			end
		end
	end

	if isBuffed then
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(currentSpeed)
		walkSpeedText.TextColor3 = Color3.new(0, 1, 0) -- Green
	else
		walkSpeedText.Text = NumberExtension.FormatBigNumberAA(baseSpeed)
		walkSpeedText.TextColor3 = defaultWalkSpeedColor
	end
	RefreshDecelerationButtonVisible(levelSpeed)
end

local function RefreshView()
	RefreshCoinCountText()
	RefreshUpgradeValues()
end

local function RefreshRebirthDisplay()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo or not rebirthNumberText then
		return
	end
	local rebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0
	TranslationTool.CustomAutoLocalizeTextLabel(
		rebirthNumberText,
		GameTexts.RebirthCountBracket.source,
		GameTexts.RebirthCountBracket.key,
		{ tostring(rebirthLevel) }
	)
end

local function OnLocalPlayerCoinCountChanged()
	RefreshCoinCountText()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
	RefreshRebirthDisplay()
	RefreshDecelerationButtonView()
	RefreshRebirthRedPointView()
end

local function ConnectHumanoid(char: Model)
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid
	if hum then
		if humSpeedConnection then humSpeedConnection:Disconnect() end
		humSpeedConnection = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			RefreshUpgradeValues()
		end)
		RefreshUpgradeValues()
	end
end

localPlayer.CharacterAdded:Connect(ConnectHumanoid)
if localPlayer.Character then
	task.spawn(function()
		ConnectHumanoid(localPlayer.Character)
	end)
end

local function OnLocalPlayerCarriedChanged()
	RefreshBricksDisplay()
end

local function OnLocalPlayerSkillLevelChanged(skillType: number, level: number)
	RefreshUpgradeValues()
	if skillType == GameConfig.SkillType.RebirthLevel then
		RefreshRebirthDisplay()
	end

	if skillType == GameConfig.SkillType.RebirthLevel
		or skillType == GameConfig.SkillType.WalkSpeed
		or skillType == GameConfig.SkillType.MaxBricks
	then
		RefreshRebirthRedPointView()
	end
end

UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)

RefreshView()
RefreshRebirthDisplay()
RefreshDecelerationButtonView()
RefreshRebirthRedPointView()

ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCoinCountChanged)
ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
ClientMsg.ConnectLocalPlayerSkillLevelUpdate(OnLocalPlayerSkillLevelChanged)
ClientMsg.ConnectLocalPlayerCarriedUpdate(OnLocalPlayerCarriedChanged)
