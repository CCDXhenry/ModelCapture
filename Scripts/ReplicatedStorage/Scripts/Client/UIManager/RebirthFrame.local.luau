--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local core = ReplicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local UIAdapter = require(coreClientScripts:WaitForChild("UIAdapter"))
local TranslationTool = require(coreScripts:WaitForChild("Client"):WaitForChild("TranslationTool"))

local FullProgress = 1
local EmptyProgress = 0
local DefaultRequiredLevel = 1

local thisFrame = script.Parent :: Frame
local windowId = thisFrame:GetAttribute("WindowId") :: string

local closeButton = thisFrame:WaitForChild("CloseButton") :: ImageButton
local mainFrame = thisFrame:WaitForChild("MainFrame") :: Frame
local rebirthButton = mainFrame:WaitForChild("RebirthButton") :: ImageButton
local payRebirthButton = mainFrame:WaitForChild("PayRebirthButton") :: ImageButton
local oldImage = mainFrame:WaitForChild("OldImage") :: ImageLabel
local oldImageNumberLabel = oldImage:WaitForChild("NumberLabel") :: TextLabel
local oldImageValueLabel = oldImage:WaitForChild("ValueLabel") :: TextLabel
local newImage = mainFrame:WaitForChild("NewImage") :: ImageLabel
local newImageNumberLabel = newImage:WaitForChild("NumberLabel") :: TextLabel
local newImageValueLabel = newImage:WaitForChild("ValueLabel") :: TextLabel
local infoFrame = mainFrame:WaitForChild("InfoFrame") :: Frame
local speedImage = infoFrame:WaitForChild("SpeedImage") :: ImageLabel
local bricksImage = infoFrame:WaitForChild("BricksImage") :: ImageLabel

local function getProgressScale(imageLabel: ImageLabel): ImageLabel?
	local scaleBar = imageLabel:FindFirstChild("ScaleBar")
	if not scaleBar or not scaleBar:IsA("ImageLabel") then
		return nil
	end
	local scale = scaleBar:FindFirstChild("Scale")
	if not scale or not scale:IsA("ImageLabel") then
		return nil
	end
	return scale
end

local function findProgressLabel(imageLabel: ImageLabel, keyword: string): TextLabel?
	local label = imageLabel:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		return label
	end
	for _, child in infoFrame:GetChildren() do
		if child:IsA("TextLabel") and string.find(string.lower(child.Text), keyword) then
			return child
		end
	end
	return nil
end

local speedTextLabel = findProgressLabel(speedImage, "speed")
local bricksTextLabel = findProgressLabel(bricksImage, "brick")
local speedScale = getProgressScale(speedImage)
local bricksScale = getProgressScale(bricksImage)

local function refreshScaleX(scaleImage: ImageLabel?, percent: number)
	if not scaleImage then
		return
	end
	local clamped = math.clamp(percent, EmptyProgress, FullProgress)
	scaleImage.Size = UDim2.new(clamped, 0, scaleImage.Size.Y.Scale, scaleImage.Size.Y.Offset)
end

local function getRebirthMultiplier(rebirthCount: number): number
	if rebirthCount <= 0 then
		return 1
	end
	local rebirthData = GameConfig.RebirthMap[rebirthCount]
	if not rebirthData then
		return 1
	end
	return rebirthData.collectMultiple
end

local function formatTemplate(sourceText: string, args: { string }): string
	local formattedText = sourceText
	for i, value in args do
		formattedText = string.gsub(formattedText, "{" .. tostring(i) .. "}", value)
	end
	return formattedText
end

local function checkRebirthRequirements(localPlayerInfo: GameConfig.ClientLocalPlayerInfo): boolean
	local currentRebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0
	local nextRebirthData = GameConfig.RebirthMap[currentRebirthLevel + 1]
	if not nextRebirthData then
		return false
	end

	local currentSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or DefaultRequiredLevel
	local currentBricksLevel = localPlayerInfo.shopInfo.maxBricksLevel or DefaultRequiredLevel
	local missingRequirements: { string } = {}

	if currentSpeedLevel < nextRebirthData.speedLv then
		table.insert(
			missingRequirements,
			formatTemplate(GameTexts.SpeedLevelProgress.source, { tostring(currentSpeedLevel), tostring(nextRebirthData.speedLv) })
		)
	end
	if currentBricksLevel < nextRebirthData.brickLv then
		table.insert(
			missingRequirements,
			formatTemplate(GameTexts.BricksLevelProgress.source, { tostring(currentBricksLevel), tostring(nextRebirthData.brickLv) })
		)
	end

	if #missingRequirements > 0 then
		ClientMsg.FireShowGameTip(
			GameTexts.MissingRequirementsFormat.source,
			GameConfig.GameTipTweenType.FlyUp,
			GameTexts.MissingRequirementsFormat.key,
			{ table.concat(missingRequirements, ", ") }
		)
		return false
	end

	return true
end

local function refreshView()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end

	local currentSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or DefaultRequiredLevel
	local currentBricksLevel = localPlayerInfo.shopInfo.maxBricksLevel or DefaultRequiredLevel
	local currentRebirthLevel = localPlayerInfo.shopInfo.rebirthLevel or 0

	local nextRebirthData = GameConfig.RebirthMap[currentRebirthLevel + 1]
	local nextRebirthLevel = currentRebirthLevel + 1
	local requiredSpeedLevel = if nextRebirthData then nextRebirthData.speedLv else currentSpeedLevel
	local requiredBricksLevel = if nextRebirthData then nextRebirthData.brickLv else currentBricksLevel

	local speedProgress = if nextRebirthData and requiredSpeedLevel > 0 then currentSpeedLevel / requiredSpeedLevel else FullProgress
	local bricksProgress = if nextRebirthData and requiredBricksLevel > 0 then currentBricksLevel / requiredBricksLevel else FullProgress
	local currentMultiplier = getRebirthMultiplier(currentRebirthLevel)
	local nextMultiplier = if nextRebirthData then getRebirthMultiplier(nextRebirthLevel) else currentMultiplier

	TranslationTool.CustomAutoLocalizeTextLabel(
		oldImageNumberLabel,
		GameTexts.RebirthCountPlain.source,
		GameTexts.RebirthCountPlain.key,
		{ tostring(currentRebirthLevel) }
	)
	TranslationTool.CustomAutoLocalizeTextLabel(
		oldImageValueLabel,
		GameTexts.CoinMultiplierText.source,
		GameTexts.CoinMultiplierText.key,
		{ string.format("%.1f", currentMultiplier) }
	)
	TranslationTool.CustomAutoLocalizeTextLabel(
		newImageNumberLabel,
		GameTexts.RebirthCountPlain.source,
		GameTexts.RebirthCountPlain.key,
		{ tostring(nextRebirthLevel) }
	)
	TranslationTool.CustomAutoLocalizeTextLabel(
		newImageValueLabel,
		GameTexts.CoinMultiplierText.source,
		GameTexts.CoinMultiplierText.key,
		{ string.format("%.1f", nextMultiplier) }
	)

	if speedTextLabel then
		TranslationTool.CustomAutoLocalizeTextLabel(
			speedTextLabel,
			GameTexts.SpeedLevelProgress.source,
			GameTexts.SpeedLevelProgress.key,
			{ tostring(currentSpeedLevel), tostring(requiredSpeedLevel) }
		)
	end

	if bricksTextLabel then
		TranslationTool.CustomAutoLocalizeTextLabel(
			bricksTextLabel,
			GameTexts.BricksLevelProgress.source,
			GameTexts.BricksLevelProgress.key,
			{ tostring(currentBricksLevel), tostring(requiredBricksLevel) }
		)
	end

	refreshScaleX(speedScale, speedProgress)
	refreshScaleX(bricksScale, bricksProgress)
end

closeButton.Activated:Connect(function()
	UIManager.CloseWindow(windowId)
end)

rebirthButton.Activated:Connect(function()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	if not checkRebirthRequirements(localPlayerInfo) then
		return
	end
	NetMsg.FireRequestRebirth()
end)

payRebirthButton.Activated:Connect(function()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	if not checkRebirthRequirements(localPlayerInfo) then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	MarketplaceService:PromptProductPurchase(localPlayer, GameConfig.Paving.RebirthProductId)
end)

local function OnCloseWindow(closeWindowId: string)
	if closeWindowId ~= windowId then
		return
	end
	UIAdapter.RemoveAdaptiveFrame(thisFrame)
	thisFrame:Destroy()
end

ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function()
	refreshView()
end)

ClientMsg.ConnectLocalPlayerInfoInit(function()
	refreshView()
end)

ClientMsg.ConnectCloseWindow(OnCloseWindow)
refreshView()

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.FullScreen)
