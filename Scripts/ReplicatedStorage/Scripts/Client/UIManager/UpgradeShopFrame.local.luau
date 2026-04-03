--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local GameSoundManager = require(clientScripts:WaitForChild("GameSoundManager"))
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local core = ReplicatedStorage:WaitForChild("Core")
local NumberExtension = require(core:WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("NumberExtension"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):WaitForChild("TranslationTool"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string

local closeButton = thisFrame:WaitForChild("CloseButton") :: ImageButton
local scrollingFrame = thisFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame

local upgradeWalkSpeedFrame1 = scrollingFrame:WaitForChild("UpgradeWalkSpeedFrame1") :: Frame
local upgradeWalkSpeedFrame10 = scrollingFrame:WaitForChild("UpgradeWalkSpeedFrame10") :: Frame
local upgradeMaxBricksFrame1 = scrollingFrame:WaitForChild("UpgradeMaxBricksFrame1") :: Frame
local upgradeMaxBricksFrame10 = scrollingFrame:WaitForChild("UpgradeMaxBricksFrame10") :: Frame
local uiListLayout = scrollingFrame:WaitForChild("UIListLayout") :: UIListLayout

closeButton.Activated:Connect(function()
	UIManager.CloseWindow(windowId)
end)

local UpgradeSuccessTipColor = Color3.fromRGB(80, 255, 120)

local function showUpgradeTip(skillType: number, level: number)
	if skillType == GameConfig.SkillType.WalkSpeed then
		ClientMsg.FireShowGameTip(
			GameTexts.UpgradeSpeedLevelIncreased.source,
			GameConfig.GameTipTweenType.FlyUp,
			GameTexts.UpgradeSpeedLevelIncreased.key,
			{ tostring(level) },
			UpgradeSuccessTipColor
		)
	elseif skillType == GameConfig.SkillType.MaxBricks then
		ClientMsg.FireShowGameTip(
			GameTexts.UpgradeBricksLevelIncreased.source,
			GameConfig.GameTipTweenType.FlyUp,
			GameTexts.UpgradeBricksLevelIncreased.key,
			{ tostring(level) },
			UpgradeSuccessTipColor
		)
	end
end

local function getCostAndLimit(abilityName: string, currentLevel: number, levelAdd: number)
	local shopData = GameConfig.Shop[abilityName]
	local totalCost = 0
	local nextLevel = currentLevel
	for i = 1, levelAdd do
		local cost = shopData.upgradeCostList[nextLevel]
		if not cost then
			return false, totalCost, nextLevel
		end
		totalCost += cost
		nextLevel += 1
	end
	return true, totalCost, nextLevel
end

local function refreshFrame(frame: Frame, skillType: number, levelAdd: number)
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	local abilityName, currentLevel
	if skillType == GameConfig.SkillType.WalkSpeed then
		abilityName = "WalkSpeed"
		currentLevel = playerInfo.shopInfo.walkSpeedLevel
	elseif skillType == GameConfig.SkillType.MaxBricks then
		abilityName = "MaxBricks"
		currentLevel = playerInfo.shopInfo.maxBricksLevel
	else
		return
	end

	local oldNumberLabel = frame:WaitForChild("OldNumberLabel") :: TextLabel
	local newNumberLabel = frame:WaitForChild("NewNumberLabel") :: TextLabel
	local imageButton = frame:WaitForChild("ImageButton") :: ImageButton
	local textLabel = imageButton:WaitForChild("TextLabel") :: TextLabel

	local shopData = GameConfig.Shop[abilityName]

	local currentValue = shopData.abilityList[currentLevel] or shopData.abilityList[#shopData.abilityList]
	local currentValueStr = NumberExtension.FormatBigNumberAA(currentValue)

	if abilityName == "WalkSpeed" then
		TranslationTool.CustomAutoLocalizeTextLabel(oldNumberLabel, GameTexts.SpeedWithNumber.source, GameTexts.SpeedWithNumber.key, { currentValueStr })
	else
		TranslationTool.CustomAutoLocalizeTextLabel(oldNumberLabel, GameTexts.BricksWithNumber.source, GameTexts.BricksWithNumber.key, { currentValueStr })
	end

	local canUpgrade, totalCost, targetLevel = getCostAndLimit(abilityName, currentLevel, levelAdd)
	if canUpgrade then
		local nextValue = shopData.abilityList[targetLevel]
		local nextValueStr = NumberExtension.FormatBigNumberAA(nextValue)

		if abilityName == "WalkSpeed" then
			TranslationTool.CustomAutoLocalizeTextLabel(newNumberLabel, GameTexts.SpeedWithNumber.source, GameTexts.SpeedWithNumber.key, { nextValueStr })
		else
			TranslationTool.CustomAutoLocalizeTextLabel(newNumberLabel, GameTexts.BricksWithNumber.source, GameTexts.BricksWithNumber.key, { nextValueStr })
		end

		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, NumberExtension.FormatBigNumberAA(totalCost))

		local currentCoin = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
		if currentCoin >= totalCost then
			imageButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			-- Could tint green or restore normal color
		else
			imageButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		end
	else
		TranslationTool.CustomAutoLocalizeTextLabel(newNumberLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
		imageButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	end
end

local function refreshAll()
	refreshFrame(upgradeWalkSpeedFrame1, GameConfig.SkillType.WalkSpeed, 1)
	refreshFrame(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10)
	refreshFrame(upgradeMaxBricksFrame1, GameConfig.SkillType.MaxBricks, 1)
	refreshFrame(upgradeMaxBricksFrame10, GameConfig.SkillType.MaxBricks, 10)
end

local function updateCanvas()
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y * 2.5)
end
uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
updateCanvas()

local function bindButton(frame: Frame, skillType: number, levelAdd: number)
	local imageButton = frame:WaitForChild("ImageButton") :: ImageButton
	imageButton:SetAttribute("SkipButtonClickSound", true)
	imageButton.Activated:Connect(function()
		local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not playerInfo then
			return
		end

		local abilityName = if skillType == GameConfig.SkillType.WalkSpeed then "WalkSpeed" else "MaxBricks"
		local currentLevel = if abilityName == "WalkSpeed" then playerInfo.shopInfo.walkSpeedLevel else playerInfo.shopInfo.maxBricksLevel
		local canUpgrade, totalCost = getCostAndLimit(abilityName, currentLevel, levelAdd)

		if canUpgrade then
			local currentCoin = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
			if currentCoin >= totalCost then
				GameSoundManager.PlayUpgradeAbilitySound()
				NetMsg.SendRequestUpgradeSkill(skillType, levelAdd)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.InsufficientCoin.key)
			end
		end
	end)
end

local function getMaxUpgradeableSteps(abilityName: string, currentLevel: number, levelAdd: number): number
	local shopData = GameConfig.Shop[abilityName]
	local nextLevel = currentLevel
	local steps = 0
	for _ = 1, levelAdd do
		local upgradeCost = shopData.upgradeCostList[nextLevel]
		if upgradeCost == nil then
			break
		end
		steps += 1
		nextLevel += 1
	end
	return steps
end

local function bindPaymentButton(frame: Frame, skillType: number, levelAdd: number, productId: number)
	-- PaymentButton 由 UI 侧新增；这里绑定其点击事件并触发内购
	local paymentButton = frame:WaitForChild("PaymentButton") :: any
	paymentButton.Activated:Connect(function()
		local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
		if not playerInfo then
			return
		end

		local abilityName, currentLevel
		if skillType == GameConfig.SkillType.WalkSpeed then
			abilityName = "WalkSpeed"
			currentLevel = playerInfo.shopInfo.walkSpeedLevel
		elseif skillType == GameConfig.SkillType.MaxBricks then
			abilityName = "MaxBricks"
			currentLevel = playerInfo.shopInfo.maxBricksLevel
		else
			return
		end

		local maxSteps = getMaxUpgradeableSteps(abilityName, currentLevel, levelAdd)
		if maxSteps <= 0 then
			ClientMsg.FireShowGameTip(GameTexts.MaxLevel.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.MaxLevel.key)
			return
		end

		if productId == 0 then
			warn(`[UpgradeShopFrame] ShopPaid productId is 0 for {abilityName}`)
			return
		end

		if not players.LocalPlayer then
			return
		end

		marketplaceService:PromptProductPurchase(players.LocalPlayer, productId)
	end)
end

bindButton(upgradeWalkSpeedFrame1, GameConfig.SkillType.WalkSpeed, 1)
bindButton(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10)
bindButton(upgradeMaxBricksFrame1, GameConfig.SkillType.MaxBricks, 1)
bindButton(upgradeMaxBricksFrame10, GameConfig.SkillType.MaxBricks, 10)

bindPaymentButton(upgradeWalkSpeedFrame10, GameConfig.SkillType.WalkSpeed, 10, GameConfig.ShopPaid.WalkSpeed10ProductId)
bindPaymentButton(upgradeMaxBricksFrame10, GameConfig.SkillType.MaxBricks, 10, GameConfig.ShopPaid.MaxBricks10ProductId)

local function OnCloseWindow(windowId: string)
	if windowId == thisFrame:GetAttribute("WindowId") then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
	refreshAll()
	if skillType == GameConfig.SkillType.WalkSpeed or skillType == GameConfig.SkillType.MaxBricks then
		showUpgradeTip(skillType, level)
	end
end)

ClientMsg.ConnectLocalPlayerCurrencyUpdate(function()
	refreshAll()
end)

ClientMsg.ConnectCloseWindow(OnCloseWindow)
refreshAll()

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)