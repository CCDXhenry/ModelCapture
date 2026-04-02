local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local core = ReplicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")

local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local GameSoundManager = require(clientScripts:WaitForChild("GameSoundManager"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))

local ROW_COUNT = 4
local CLOSE_DISTANCE_STUDS = 15

local thisFrame = script.Parent :: BillboardGui
local windowId = thisFrame:GetAttribute("WindowId") :: string

thisFrame.AlwaysOnTop = true

local controllerFrame = thisFrame:WaitForChild("ControllerFrame") :: Frame

local uiScale = controllerFrame:FindFirstChildOfClass("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Parent = controllerFrame
end

local templateRow = controllerFrame:WaitForChild("RowFrame1") :: Frame
local oldRow2 = controllerFrame:FindFirstChild("RowFrame2")
if oldRow2 then
	oldRow2:Destroy()
end

local rowFrames: { Frame } = {}
for i = 1, ROW_COUNT do
	local row = templateRow:Clone()
	row.Name = "SellShopRow" .. i
	row.LayoutOrder = i
	row.Parent = controllerFrame
	rowFrames[i] = row
end
templateRow:Destroy()

local LINE_TEXTS = {
	GameTexts.SellShopSellSingle,
	GameTexts.SellShopSellAll,
	GameTexts.SellShopAskPrice,
	GameTexts.SellShopGoodbye,
}

local player = game.Players.LocalPlayer
local camera = Workspace.CurrentCamera

local sellShopModel = Workspace:FindFirstChild("SellShop") :: Model?
local rootPart = nil

if sellShopModel then
	rootPart = sellShopModel:FindFirstChild("RootPart") or sellShopModel:FindFirstChild("rootpart") or sellShopModel.PrimaryPart
end

local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function ApplyHoverEffect(button: ImageButton)
	local originalPosition = button.Position
	local originalColor = button.ImageColor3
	local hoverColor = Color3.new(originalColor.R * 0.8, originalColor.G * 0.8, originalColor.B * 0.8)
	local hoverPosition = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset + 10, originalPosition.Y.Scale, originalPosition.Y.Offset)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO, {
			Position = hoverPosition,
			ImageColor3 = hoverColor,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_INFO, {
			Position = originalPosition,
			ImageColor3 = originalColor,
		}):Play()
	end)
end

--- 与 BrainrotIslandManager.GetActiveBrainrot 一致：先 CarryingBrainrot，再装备 Tool
local function GetActiveBrainrotForCharacter(character: Model): Instance?
	local carrying = character:FindFirstChild("CarryingBrainrot")
	if carrying and carrying:GetAttribute("BrainrotUID") then
		if carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return carrying
		end
		return nil
	end
	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool:GetAttribute("BrainrotUID") then
		if equippedTool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
			return equippedTool
		end
	end
	return nil
end

local function HasBrainrotInQueue(): boolean
	local queue = ClientGameInfo.GetBrainrotQueue()
	for _, item in ipairs(queue) do
		if item.itemType == GameConfig.ItemType.Brainrot then
			return true
		end
	end
	return false
end

local function FireNoBrainrotToSellTip()
	ClientMsg.FireShowGameTip(
		GameTexts.NoBrainrotToSell.source,
		GameConfig.GameTipTweenType.FlyUp,
		GameTexts.NoBrainrotToSell.key
	)
end

for i = 1, ROW_COUNT do
	local rowFrame = rowFrames[i]
	local indexLabel = rowFrame:WaitForChild("TextLabel") :: TextLabel
	local imageButton = rowFrame:WaitForChild("ImageButton") :: ImageButton
	local lineTextLabel = imageButton:WaitForChild("TextLabel") :: TextLabel

	imageButton:SetAttribute("SkipButtonClickSound", true)
	ApplyHoverEffect(imageButton)

	TranslationTool.CustomAutoLocalizeTextLabel(
		indexLabel,
		GameTexts.SellShopOptionIndex.source,
		GameTexts.SellShopOptionIndex.key,
		{ tostring(i) }
	)

	local textEntry = LINE_TEXTS[i]
	TranslationTool.CustomAutoLocalizeTextLabel(lineTextLabel, textEntry.source, textEntry.key)

	if i == 1 then
		imageButton.Activated:Connect(function()
			GameSoundManager.PlayButtonClickSound()
			local character = player.Character
			if not character then
				return
			end
			if not GetActiveBrainrotForCharacter(character) then
				FireNoBrainrotToSellTip()
				return
			end
			GameSoundManager.PlaySellSound()
			NetMsg.FireRequestSellCarryingBrainrot()
			UIManager.CloseWindow(windowId)
		end)
	elseif i == 2 then
		imageButton.Activated:Connect(function()
			GameSoundManager.PlayButtonClickSound()
			local character = player.Character
			if not character then
				return
			end
			if not GetActiveBrainrotForCharacter(character) and not HasBrainrotInQueue() then
				FireNoBrainrotToSellTip()
				return
			end
			GameSoundManager.PlaySellSound()
			NetMsg.FireRequestSellAllBrainrotInQueue()
			UIManager.CloseWindow(windowId)
		end)
	elseif i == 3 then
		imageButton.Activated:Connect(function()
			GameSoundManager.PlayButtonClickSound()
			local character = player.Character
			if not character then
				return
			end
			local active = GetActiveBrainrotForCharacter(character)
			if not active then
				FireNoBrainrotToSellTip()
				return
			end
			local configId = active:GetAttribute("ConfigId")
			local brainrotConfig = configId and GameConfig.BrainrotIdMap[tonumber(configId) or 0] or nil
			if not brainrotConfig then
				FireNoBrainrotToSellTip()
				return
			end
			local level = tonumber(active:GetAttribute("Level")) or 1
			local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotConfig.baseAbility, level)
			local priceStr = NumberExtension.FormatBigNumberAA(sellPrice)
			ClientMsg.FireShowGameTip(
				GameTexts.SellShopBrainrotPriceTip.source,
				GameConfig.GameTipTweenType.FlyUp,
				GameTexts.SellShopBrainrotPriceTip.key,
				{ priceStr }
			)
		end)
	else
		imageButton.Activated:Connect(function()
			GameSoundManager.PlayButtonClickSound()
			UIManager.CloseWindow(windowId)
		end)
	end
end

local function OnCloseWindow(id: string)
	if id == windowId then
		BillboardManager.Untrack(thisFrame)
		thisFrame:Destroy()
	end
end
ClientMsg.ConnectCloseWindow(OnCloseWindow)

BillboardManager.Track(thisFrame)

local proxyAttachment: Attachment? = nil

local connection = RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		return
	end

	local charPrimary = character.PrimaryPart
	if not charPrimary then
		return
	end

	if rootPart then
		local distance = (charPrimary.Position - rootPart.Position).Magnitude
		if distance > CLOSE_DISTANCE_STUDS then
			UIManager.CloseWindow(windowId)
			return
		end
	end

	if not proxyAttachment or proxyAttachment.Parent ~= charPrimary then
		proxyAttachment = charPrimary:FindFirstChild("SellShopUI_Attachment") :: Attachment?
		if not proxyAttachment then
			proxyAttachment = Instance.new("Attachment")
			proxyAttachment.Name = "SellShopUI_Attachment"
			proxyAttachment.Parent = charPrimary
		end
		thisFrame.Adornee = proxyAttachment
	end

	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	if proxyAttachment then
		proxyAttachment.Position = charPrimary.CFrame:VectorToObjectSpace(right * 6 + up * 0.5)
	end
end)

thisFrame.Destroying:Connect(function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if proxyAttachment then
		proxyAttachment:Destroy()
	end
	BillboardManager.Untrack(thisFrame)
end)
