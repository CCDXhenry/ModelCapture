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
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local DEFAULT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local MAX_CHEST_POOL_SHOW_COUNT = 7
local SHOP_BUNDLE_TYPE_MIX = 1
local SHOP_BUNDLE_TYPE_LITTLE_ELF_CHEST = 2
local SHOP_BUNDLE_TYPE_SINGLE = 3

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string
local closeButton = thisFrame:FindFirstChild("CloseButton") :: ImageButton?
local scrollingFrame = thisFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local uiListLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout") :: UIListLayout?
local mixBundleTemplate = scrollingFrame:WaitForChild("MixBundleFrame1") :: Frame
local littleElfChestBundleTemplate = scrollingFrame:WaitForChild("LittleElfChestBundleFrame1") :: Frame
local singleBundleTemplate = scrollingFrame:WaitForChild("SingleBundleFrame1") :: Frame

local bundleFramesById: { [number]: Frame } = {}
local isWindowClosed = false

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

local function getQualityColor(quality: number): Color3
	local qualityCfg = GameConfig.BrainrotQualityConfig[quality]
	if qualityCfg then
		return qualityCfg.textColor
	end
	return DEFAULT_TEXT_COLOR
end

local function localizeText(textLabel: TextLabel, textValue: string)
	TranslationTool.CustomAutoLocalizeTextLabel(textLabel, textValue, "")
end

local function getBundleNameColor(bundleConfig: GameConfig.ShopBundleConfigurationData): Color3
	local nameColor = bundleConfig.nameColor
	if nameColor and #nameColor >= 3 then
		return Color3.fromRGB(nameColor[1], nameColor[2], nameColor[3])
	end
	return DEFAULT_TEXT_COLOR
end

local function getBundleProductId(bundleConfig: GameConfig.ShopBundleConfigurationData, productIndex: number): number
	if productIndex == 1 then
		return bundleConfig.productId1
	end
	if productIndex == 2 then
		return bundleConfig.productId2
	end
	if productIndex == 3 then
		return bundleConfig.productId3
	end
	return 0
end

local function getBundlePrice(bundleConfig: GameConfig.ShopBundleConfigurationData, productIndex: number): number
	if productIndex == 1 then
		return bundleConfig.price1
	end
	if productIndex == 2 then
		return bundleConfig.price2
	end
	if productIndex == 3 then
		return bundleConfig.price3
	end
	return 0
end

local function getBundleBeforeDiscountPrice(bundleConfig: GameConfig.ShopBundleConfigurationData, productIndex: number): number
	if productIndex == 2 then
		return bundleConfig.beforeDiscountPrice2
	end
	if productIndex == 3 then
		return bundleConfig.beforeDiscountPrice3
	end
	return 0
end

local function shouldHideBundleForPaidRandomPolicy(
	bundleData: GameConfig.ShopBundleData,
	playerInfo: GameConfig.ClientLocalPlayerInfo
): boolean
	
	if bundleData.config.arePaidRandomItemsRestricted == 0 then
		return false
	end

	return playerInfo.playerConfigInfo.arePaidRandomItemsRestricted == true
end

local function getBundleRewardsByProductIndex(bundleData: GameConfig.ShopBundleData, productIndex: number): { GameConfig.RewardInfo }
	local rewards: { GameConfig.RewardInfo } = {}
	for _, reward in ipairs(bundleData.rewards) do
		if (reward.productIndex or 1) == productIndex then
			table.insert(rewards, reward)
		end
	end
	return rewards
end

local function setRewardText(textLabel: TextLabel, reward: GameConfig.RewardInfo)
	textLabel.TextColor3 = DEFAULT_TEXT_COLOR

	if reward.rewardType == GameConfig.RewardType.Currency then
		localizeText(textLabel, NumberExtension.FormatBigNumberAA(reward.rewardCount))
		return
	end

	if reward.rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[reward.rewardId]
		local coilName = if coilData then coilData.name_t else "Coil"
		localizeText(textLabel, coilName)
		return
	end

	if reward.rewardType == GameConfig.RewardType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[reward.rewardId]
		if brainrotData then
			localizeText(textLabel, brainrotData.name_t)
			textLabel.TextColor3 = getQualityColor(brainrotData.quality)
			return
		end
	end

	if reward.rewardType == GameConfig.RewardType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[reward.rewardId]
		if chestData then
			localizeText(textLabel, chestData.name_t)
			textLabel.TextColor3 = getQualityColor(chestData.quality)
			return
		end
	end

	localizeText(textLabel, NumberExtension.FormatBigNumberAA(reward.rewardCount))
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

local function getRewardDisplayName(reward: GameConfig.RewardInfo): string
	if reward.rewardType == GameConfig.RewardType.Currency then
		return NumberExtension.FormatBigNumberAA(reward.rewardCount)
	end

	if reward.rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[reward.rewardId]
		return if coilData then coilData.name_t else "Coil"
	end

	if reward.rewardType == GameConfig.RewardType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[reward.rewardId]
		return if brainrotData then brainrotData.name_t else "Brainrot"
	end

	if reward.rewardType == GameConfig.RewardType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[reward.rewardId]
		return if chestData then chestData.name_t else "Little Elf Chest"
	end

	return NumberExtension.FormatBigNumberAA(reward.rewardCount)
end

local function getRewardDescription(reward: GameConfig.RewardInfo): string
	if reward.rewardType == GameConfig.RewardType.Coil then
		local coilData = GameConfig.CoilIdMap[reward.rewardId]
		if coilData and coilData.description ~= "" then
			return coilData.description
		end
	end
	return getRewardDisplayName(reward)
end

local function formatProbabilityPercent(weight: number, totalWeight: number): string
	if totalWeight <= 0 then
		return "0%"
	end
	local percent = (weight / totalWeight) * 100
	local text = string.format("%.4f", percent)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	if text == "" then
		text = "0"
	end
	return text .. "%"
end

type ChestPoolDisplayEntry = {
	itemType: number,
	itemId: number,
	weight: number,
}

local function getChestPoolDisplayEntries(chestId: number): { ChestPoolDisplayEntry }
	local sourcePool = GameConfig.LittleElfChestRewardPoolMap[chestId]
	if sourcePool == nil then
		return {}
	end

	local copied: { ChestPoolDisplayEntry } = {}
	for _, entry in ipairs(sourcePool) do
		table.insert(copied, {
			itemType = entry.itemType,
			itemId = entry.itemId,
			weight = entry.weight,
		})
	end
	table.sort(copied, function(a, b)
		if a.weight == b.weight then
			return a.itemId < b.itemId
		end
		return a.weight > b.weight
	end)

	local displayEntries: { ChestPoolDisplayEntry } = {}
	local maxCount = math.min(MAX_CHEST_POOL_SHOW_COUNT, #copied)
	for i = 1, maxCount do
		table.insert(displayEntries, copied[i])
	end
	return displayEntries
end

local function getPoolItemIcon(itemType: number, itemId: number): string
	if itemType == GameConfig.ItemType.Brainrot then
		local brainrotData = GameConfig.BrainrotIdMap[itemId]
		return if brainrotData then brainrotData.iconImageId else ""
	end
	if itemType == GameConfig.ItemType.Coil then
		local coilData = GameConfig.CoilIdMap[itemId]
		return if coilData then coilData.iconImageId else ""
	end
	if itemType == GameConfig.ItemType.LittleElfChest then
		local chestData = GameConfig.LittleElfChestIdMap[itemId]
		return if chestData then chestData.iconImageId else ""
	end
	return ""
end

local function bindProductPurchase(button: ImageButton, productId: number)
	button.Active = productId > 0
	if productId <= 0 then
		return
	end
	button.Activated:Connect(function()
		if not players.LocalPlayer then
			return
		end
		marketplaceService:PromptProductPurchase(players.LocalPlayer, productId)
	end)
end

local function createMixBundleFrame(bundleData: GameConfig.ShopBundleData, index: number)
	local frame = mixBundleTemplate:Clone()
	frame.Name = `MixBundleFrame{index}`
	frame.LayoutOrder = index
	frame.Visible = true
	frame.Parent = scrollingFrame

	local bundleConfig = bundleData.config
	bundleFramesById[bundleConfig.id] = frame
	local bundleNameLabel = frame:WaitForChild("BundleNameLabel") :: TextLabel
	localizeText(bundleNameLabel, bundleConfig.name_t)
	bundleNameLabel.TextColor3 = getBundleNameColor(bundleConfig)

	local bgImageLabel = frame:FindFirstChild("BgImageLabel") :: ImageLabel?
	if bgImageLabel then
		bgImageLabel.Image = bundleConfig.bgIconId
	end

	local buyButton = frame:WaitForChild("BuyButton") :: ImageButton
	local buyTextLabel = buyButton:WaitForChild("TextLabel") :: TextLabel
	localizeText(buyTextLabel, tostring(bundleConfig.price1))
	bindProductPurchase(buyButton, bundleConfig.productId1)

	local bundleShowFrame = frame:WaitForChild("BundleShowFrame") :: Frame
	local packTemplate = bundleShowFrame:WaitForChild("PackFrame1") :: Frame
	for _, child in ipairs(bundleShowFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= packTemplate then
			child:Destroy()
		end
	end
	packTemplate.Visible = false

	local productRewards = getBundleRewardsByProductIndex(bundleData, 1)
	for rewardIndex, reward in ipairs(productRewards) do
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
end

local function createSingleBundleFrame(bundleData: GameConfig.ShopBundleData, index: number)
	local frame = singleBundleTemplate:Clone()
	frame.Name = `SingleBundleFrame{index}`
	frame.LayoutOrder = index
	frame.Visible = true
	frame.Parent = scrollingFrame

	local bundleConfig = bundleData.config
	bundleFramesById[bundleConfig.id] = frame
	local rewards = getBundleRewardsByProductIndex(bundleData, 1)
	local mainReward = rewards[1]

	local bundleNameLabel = frame:WaitForChild("BundleNameLabel") :: TextLabel
	localizeText(bundleNameLabel, bundleConfig.name_t)
	bundleNameLabel.TextColor3 = getBundleNameColor(bundleConfig)

	local bundleDescribeLabel = frame:WaitForChild("BundleDescribeLabel") :: TextLabel
	localizeText(bundleDescribeLabel, if mainReward then getRewardDescription(mainReward) else "")

	local bgImageLabel = frame:FindFirstChild("BgImageLabel") :: ImageLabel?
	if bgImageLabel then
		bgImageLabel.Image = bundleConfig.bgIconId
	end

	local rewardImageLabel = frame:FindFirstChild("ImageLabel") :: ImageLabel?
	if rewardImageLabel then
		if mainReward then
			setRewardIcon(rewardImageLabel, mainReward)
		else
			rewardImageLabel.Image = ""
		end
	end

	local buyButton = frame:WaitForChild("BuyButton") :: ImageButton
	local buyTextLabel = buyButton:WaitForChild("TextLabel") :: TextLabel
	localizeText(buyTextLabel, tostring(bundleConfig.price1))
	bindProductPurchase(buyButton, bundleConfig.productId1)
end

local function createLittleElfChestBundleFrame(bundleData: GameConfig.ShopBundleData, index: number)
	local frame = littleElfChestBundleTemplate:Clone()
	frame.Name = `LittleElfChestBundleFrame{index}`
	frame.LayoutOrder = index
	frame.Visible = true
	frame.Parent = scrollingFrame

	local bundleConfig = bundleData.config
	bundleFramesById[bundleConfig.id] = frame
	local bundleNameLabel = frame:WaitForChild("BundleNameLabel") :: TextLabel
	localizeText(bundleNameLabel, bundleConfig.name_t)
	bundleNameLabel.TextColor3 = getBundleNameColor(bundleConfig)

	local bgImageLabel = frame:FindFirstChild("BgImageLabel") :: ImageLabel?
	if bgImageLabel then
		bgImageLabel.Image = bundleConfig.bgIconId
	end

	local chestReward: GameConfig.RewardInfo? = nil
	for _, reward in ipairs(bundleData.rewards) do
		if reward.rewardType == GameConfig.RewardType.LittleElfChest and (reward.productIndex or 1) == 1 then
			chestReward = reward
			break
		end
	end
	if chestReward == nil then
		for _, reward in ipairs(bundleData.rewards) do
			if reward.rewardType == GameConfig.RewardType.LittleElfChest then
				chestReward = reward
				break
			end
		end
	end

	local chestImageLabel = frame:FindFirstChild("ImageLabel") :: ImageLabel?
	if chestImageLabel then
		if chestReward then
			setRewardIcon(chestImageLabel, chestReward)
		else
			chestImageLabel.Image = ""
		end
	end

	local bundleShowFrame = frame:WaitForChild("BundleShowFrame") :: Frame
	local packFrames: { Frame } = {}
	for packIndex = 1, MAX_CHEST_POOL_SHOW_COUNT do
		local packFrame = bundleShowFrame:FindFirstChild(`PackFrame{packIndex}`) :: Frame?
		if packFrame then
			packFrame.Visible = false
			table.insert(packFrames, packFrame)
		end
	end

	if chestReward then
		local poolEntries = getChestPoolDisplayEntries(chestReward.rewardId)
		local totalSlots = #packFrames
		local showCount = math.min(totalSlots, #poolEntries)
		local totalWeight = 0
		for i = 1, showCount do
			local poolEntry = poolEntries[i]
			totalWeight += poolEntry.weight
		end

		-- 当池子数量不足时：优先隐藏 PackFrame1，而不是隐藏到 PackFrame7。
		-- 也就是把可见项映射到 PackFrame{(totalSlots-showCount)+1}...PackFrame{totalSlots}
		local offset = totalSlots - showCount
		for entryIndex = 1, showCount do
			local poolEntry = poolEntries[entryIndex]
			local packFrame = packFrames[offset + entryIndex]
			if packFrame then
				packFrame.Visible = true
				local iconLabel = packFrame:FindFirstChild("ImageLabel") :: ImageLabel?
				if iconLabel then
					iconLabel.Image = getPoolItemIcon(poolEntry.itemType, poolEntry.itemId)
				end
				local probabilityLabel = packFrame:FindFirstChild("TextLabel") :: TextLabel?
				if probabilityLabel then
					localizeText(probabilityLabel, formatProbabilityPercent(poolEntry.weight, totalWeight))
				end
			end
		end
	end

	for productIndex = 1, 3 do
		local button = frame:FindFirstChild(`BuyButton{productIndex}`) :: ImageButton?
		if not button then
			continue
		end

		local productId = getBundleProductId(bundleConfig, productIndex)
		local price = getBundlePrice(bundleConfig, productIndex)
		local beforeDiscountPrice = getBundleBeforeDiscountPrice(bundleConfig, productIndex)
		local rewards = getBundleRewardsByProductIndex(bundleData, productIndex)
		local firstReward = rewards[1]
		local rewardCount = if firstReward then firstReward.rewardCount else 0

		local textLabel = button:FindFirstChild("TextLabel") :: TextLabel?
		if textLabel then
			localizeText(textLabel, tostring(price))
		end

		local originalPriceText = button:FindFirstChild("OriginalPriceText") :: TextLabel?
		if originalPriceText then
			if beforeDiscountPrice > 0 then
				originalPriceText.Visible = true
				localizeText(originalPriceText, GameConfig.RobuxIconText .. tostring(beforeDiscountPrice))
			else
				originalPriceText.Visible = false
			end
		end

		local numberTextLabel = button:FindFirstChild("NumberTextLabel") :: TextLabel?
		if numberTextLabel then
			localizeText(numberTextLabel, `{rewardCount}x Block`)
		end

		bindProductPurchase(button, productId)
	end
end

local function updateRepurchaseMask()
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	for bundleId, frame in pairs(bundleFramesById) do
		local bundleData = GameConfig.ShopBundleById[bundleId]
		if bundleData and frame and frame.Parent ~= nil then
			local canRepurchased = bundleData.config.canRepurchased
			local owned = playerInfo.ownedShopBundleMap and playerInfo.ownedShopBundleMap[bundleId] == true
			local maskNeeded = canRepurchased == 0 and owned

			local maskImageLabel = frame:FindFirstChild("MaskImageLabel") :: ImageLabel?
			if maskImageLabel then
				maskImageLabel.Visible = maskNeeded
			end

			if maskNeeded then
				-- Mix/Single 的 BuyButton
				local buyButton = frame:FindFirstChild("BuyButton") :: ImageButton?
				if buyButton then
					buyButton.Active = false
				end

				-- LittleElfChest 的 BuyButton1/2/3
				for productIndex = 1, 3 do
					local productButton = frame:FindFirstChild(`BuyButton{productIndex}`) :: ImageButton?
					if productButton then
						productButton.Active = false
					end
				end
			end
		end
	end
end

mixBundleTemplate.Visible = false
littleElfChestBundleTemplate.Visible = false
singleBundleTemplate.Visible = false

local shopBundleFramesBuilt = false

local function buildShopBundleFrames(): boolean
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return false
	end
	local visibleIndex = 0
	for _, bundleId in ipairs(GameConfig.ShopBundleList) do
		local bundleData = GameConfig.ShopBundleById[bundleId]
		if not bundleData then
			continue
		end
		if shouldHideBundleForPaidRandomPolicy(bundleData, playerInfo) then
			continue
		end
		visibleIndex += 1
		local bundleType = bundleData.config.type
		if bundleType == SHOP_BUNDLE_TYPE_MIX then
			createMixBundleFrame(bundleData, visibleIndex)
		elseif bundleType == SHOP_BUNDLE_TYPE_LITTLE_ELF_CHEST then
			createLittleElfChestBundleFrame(bundleData, visibleIndex)
		elseif bundleType == SHOP_BUNDLE_TYPE_SINGLE then
			createSingleBundleFrame(bundleData, visibleIndex)
		end
	end
	return true
end

local function tryFinalizeShopBundleFrames(): boolean
	if shopBundleFramesBuilt then
		return true
	end
	if not buildShopBundleFrames() then
		return false
	end
	shopBundleFramesBuilt = true
	updateCanvas()
	updateRepurchaseMask()
	return true
end

if not tryFinalizeShopBundleFrames() then
	local conn: RBXScriptConnection?
	conn = NetMsg.ConnectNotifyPlayerInfoInit(function()
		if conn then
			conn:Disconnect()
		end
		tryFinalizeShopBundleFrames()
	end)
	task.defer(function()
		tryFinalizeShopBundleFrames()
	end)
end

ClientMsg.ConnectBrainrotQueueUpdate(function(_queue: { GameConfig.BrainrotQueueItem })
	if isWindowClosed then
		return
	end
	updateRepurchaseMask()
end)

if uiListLayout then
	uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
end

ClientMsg.ConnectCloseWindow(function(windowId: string)
	if windowId == thisFrame:GetAttribute("WindowId") then
		isWindowClosed = true
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end)
UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)