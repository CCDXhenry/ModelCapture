--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local core = ReplicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string
local closeButton = thisFrame:FindFirstChild("CloseButton") :: ImageButton?
local scrollingFrame = thisFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local uiListLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout") :: UIListLayout?
local bundleTemplate = scrollingFrame:WaitForChild("BundleFrame1") :: Frame

if closeButton then
	closeButton.Activated:Connect(function()
		UIManager.CloseWindow(windowId)
	end)
end

local function updateCanvas()
	local contentHeight = 0
	if uiListLayout then
		contentHeight = uiListLayout.AbsoluteContentSize.Y
	else
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				contentHeight += child.AbsoluteSize.Y
			end
		end
	end
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight + 16)
end

local function setRewardText(textLabel: TextLabel, reward: GameConfig.RewardInfo)
	if reward.rewardType == GameConfig.RewardType.Currency then
		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, NumberExtension.FormatBigNumberAA(reward.rewardCount))
		return
	end

	if reward.rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[reward.rewardId]
		local coilName = if coilData then coilData.name_t else "Coil"
		TranslationTool.CustomAutoLocalizeTextLabel(textLabel, coilName, "")
		return
	end

	if reward.rewardType == GameConfig.RewardType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[reward.rewardId]
		if brainrotData then
			local rewardLv = reward.rewardLv or 1
			local yieldPerSecond = NumberExtension.FormatBigNumberAA(GameConfig.GetBrainrotAbility(brainrotData.baseAbility, rewardLv))
			TranslationTool.CustomAutoLocalizeTextLabel(textLabel, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { yieldPerSecond })
			return
		end
	end

	if reward.rewardType == GameConfig.RewardType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[reward.rewardId]
		if chestData then
			local ability = NumberExtension.FormatBigNumberAA(reward.rewardLv or reward.rewardCount)
			TranslationTool.CustomAutoLocalizeTextLabel(textLabel, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { ability })
			return
		end
	end

	TranslationTool.CustomAutoLocalizeTextLabel(textLabel, NumberExtension.FormatBigNumberAA(reward.rewardCount))
end

local function setRewardIcon(iconLabel: ImageLabel, reward: GameConfig.RewardInfo)
	if reward.rewardType == GameConfig.RewardType.Currency then
		iconLabel.Image = GameConfig.CoinIconImage
		return
	end
	if reward.rewardType == GameConfig.RewardType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[reward.rewardId]
		iconLabel.Image = if brainrotData then brainrotData.iconImageId else ""
		return
	end
	if reward.rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[reward.rewardId]
		iconLabel.Image = if coilData then coilData.iconImageId else ""
		return
	end
	if reward.rewardType == GameConfig.RewardType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[reward.rewardId]
		iconLabel.Image = if chestData then chestData.iconImageId else ""
		return
	end
	iconLabel.Image = ""
end

local function createBundleFrame(bundleId: number, index: number)
	local bundleData = GameConfig.ShopBundleById[bundleId]
	if not bundleData then
		return
	end

	local frame = bundleTemplate:Clone()
	frame.Name = `BundleFrame{index}`
	frame.LayoutOrder = index
	frame.Visible = true
	frame.Parent = scrollingFrame

	local bundleNameLabel = frame:WaitForChild("BundleNameLabel") :: TextLabel
	TranslationTool.CustomAutoLocalizeTextLabel(bundleNameLabel, bundleData.config.name_t, "")
	local bgImageLabel = frame:FindFirstChild("BgImageLabel") :: ImageLabel?
	if bgImageLabel then
		bgImageLabel.Image = bundleData.config.bgIconId
	end

	local buyButton = frame:WaitForChild("BuyButton") :: ImageButton
	local buyTextLabel = buyButton:WaitForChild("TextLabel") :: TextLabel
	TranslationTool.CustomAutoLocalizeTextLabel(buyTextLabel, tostring(bundleData.config.price))

	local bundleShowFrame = frame:WaitForChild("BundleShowFrame") :: Frame
	local packTemplate = bundleShowFrame:WaitForChild("PackFrame1") :: Frame
	packTemplate.Visible = false

	for rewardIndex, reward in ipairs(bundleData.rewards) do
		local rewardFrame = packTemplate:Clone()
		rewardFrame.Name = `PackFrame{rewardIndex}`
		rewardFrame.LayoutOrder = rewardIndex
		rewardFrame.Visible = true
		rewardFrame.Parent = bundleShowFrame

		local rewardText = rewardFrame:WaitForChild("TextLabel") :: TextLabel
		setRewardText(rewardText, reward)

		local rewardIcon = rewardFrame:WaitForChild("ImageLabel") :: ImageLabel
		setRewardIcon(rewardIcon, reward)
	end

	buyButton.Activated:Connect(function()
		if not players.LocalPlayer then
			return
		end
		marketplaceService:PromptProductPurchase(players.LocalPlayer, bundleData.config.productId)
	end)
end

bundleTemplate.Visible = false
for index, bundleId in ipairs(GameConfig.ShopBundleList) do
	createBundleFrame(bundleId, index)
end
updateCanvas()
if uiListLayout then
	uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
end

ClientMsg.ConnectCloseWindow(function(windowId: string)
	if windowId == thisFrame:GetAttribute("WindowId") then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end)
UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)