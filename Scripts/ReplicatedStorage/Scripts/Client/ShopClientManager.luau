--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local ClientScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Client")
local SharedScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")

local ClientGameInfo = require(ClientScripts:WaitForChild("ClientGameInfo"))
local ClientMsg = require(ClientScripts:WaitForChild("ClientMsg"))
local UIManager = require(ClientScripts:WaitForChild("UIManager"))
local BillboardManager = require(ClientScripts:WaitForChild("BillboardManager"))
local GameConfig = require(SharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(SharedScripts:WaitForChild("GameTexts"))

local ShopClientManager = {}
local SHOP_MODEL_NAMES = { "ProPack", "NewPack", "SellShop", "UpgradeShop" }
local SHOP_WAIT_TIMEOUT = 10
local PROMPT_BOUND_ATTR = "ShopPromptWindowBound"
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"
local ShopBundleIdAttribute = "id"
local ShopBundleProductIndexAttribute = "productIndex"
local MinShopBundleProductIndex = 1
local MaxShopBundleProductIndex = 3

-- Removed unused getSkillData and getLevel

local function updatePrompts()
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	-- SellBrainrotPrompt logic removed from updatePrompts since it uses a UI now.
end

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local function SetupEquipBoxGuiAdaptation(shopModel: Model)
	local guidePart = shopModel:WaitForChild("GuidePart", SHOP_WAIT_TIMEOUT)
	if not guidePart then
		warn(`[ShopClientManager] GuidePart not found in Workspace.{shopModel.Name}`)
		return
	end

	local equipBoxGuiObj = guidePart:WaitForChild("EquipBoxGui", SHOP_WAIT_TIMEOUT)
	if not equipBoxGuiObj or not equipBoxGuiObj:IsA("BillboardGui") then
		warn(`[ShopClientManager] EquipBoxGui missing or not BillboardGui in Workspace.{shopModel.Name}.GuidePart`)
		return
	end
	local equipBoxGui = equipBoxGuiObj :: BillboardGui
	local controllerFrame = equipBoxGui:FindFirstChild("ControllerFrame") :: Frame?
	if not controllerFrame then
		--warn(`[ShopClientManager] ControllerFrame not found in Workspace.{shopModel.Name}.GuidePart.EquipBoxGui`)
		return
	end

	local uiScale = controllerFrame:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		local newUiScale = Instance.new("UIScale")
		newUiScale.Name = "UIScale"
		newUiScale.Parent = controllerFrame
	end

	if controllerFrame.Size.X.Scale > 0 or controllerFrame.Size.Y.Scale > 0 then
		local absSize = controllerFrame.AbsoluteSize
		if absSize.X > 0 and absSize.Y > 0 then
			controllerFrame.Size = UDim2.fromOffset(absSize.X, absSize.Y)
		end
	end

	EnsureBillboardTracked(equipBoxGui)
end

local function parsePositiveInt(attrValue: unknown): number?
	if type(attrValue) == "number" then
		local n = attrValue :: number
		if n > 0 and n == math.floor(n) then
			return n
		end
	elseif type(attrValue) == "string" then
		local n = tonumber(attrValue)
		if n and n > 0 and n == math.floor(n) then
			return n
		end
	end
	return nil
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

local function shouldBlockShopBundleForPaidRandomPolicy(
	bundleData: GameConfig.ShopBundleData,
	playerInfo: GameConfig.ClientLocalPlayerInfo
): boolean
	if bundleData.config.arePaidRandomItemsRestricted == 0 then
		return false
	end
	return playerInfo.playerConfigInfo.arePaidRandomItemsRestricted == true
end

-- Direct purchase when Model attributes id + productIndex (1–3) are set; true = handled, skip OpenWindow.
local function tryPromptShopBundleDirectPurchase(shopModel: Model): boolean
	local bundleId = parsePositiveInt(shopModel:GetAttribute(ShopBundleIdAttribute))
	local productIndex = parsePositiveInt(shopModel:GetAttribute(ShopBundleProductIndexAttribute))
	if bundleId == nil or productIndex == nil then
		return false
	end
	if productIndex < MinShopBundleProductIndex or productIndex > MaxShopBundleProductIndex then
		return false
	end

	local bundleData = GameConfig.ShopBundleById[bundleId]
	if bundleData == nil then
		warn(`[ShopClientManager] Shop bundle id {bundleId} not found (Workspace.{shopModel.Name})`)
		return true
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if playerInfo == nil then
		return true
	end

	if shouldBlockShopBundleForPaidRandomPolicy(bundleData, playerInfo) then
		local tip = GameTexts.ShopBundlePurchaseRestrictedByPolicy
		ClientMsg.FireShowGameTip(tip.source, GameConfig.GameTipTweenType.FlyUp, tip.key)
		return true
	end

	local canRepurchased = bundleData.config.canRepurchased
	local owned = playerInfo.ownedShopBundleMap ~= nil and playerInfo.ownedShopBundleMap[bundleId] == true
	if canRepurchased == 0 and owned then
		local tip = GameTexts.ShopBundleAlreadyPurchased
		ClientMsg.FireShowGameTip(tip.source, GameConfig.GameTipTweenType.FlyUp, tip.key)
		return true
	end

	local productId = getBundleProductId(bundleData.config, productIndex)
	if productId <= 0 then
		warn(
			`[ShopClientManager] Invalid productId for bundle {bundleId} productIndex {productIndex} (Workspace.{shopModel.Name})`
		)
		return true
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return true
	end
	MarketplaceService:PromptProductPurchase(localPlayer, productId)
	return true
end

local function BindPromptByWindowId(shopModel: Model)
	local rootPart = shopModel:WaitForChild("RootPart", SHOP_WAIT_TIMEOUT)
	if not rootPart then
		warn(`[ShopClientManager] RootPart not found in Workspace.{shopModel.Name}`)
		return
	end

	local openShopAttachment = rootPart:WaitForChild("OpenShopAttachment", SHOP_WAIT_TIMEOUT)
	if not openShopAttachment then
		warn(`[ShopClientManager] OpenShopAttachment not found in Workspace.{shopModel.Name}.RootPart`)
		return
	end

	local promptObj = openShopAttachment:WaitForChild("ProximityPrompt", SHOP_WAIT_TIMEOUT)
	if not promptObj or not promptObj:IsA("ProximityPrompt") then
		warn(`[ShopClientManager] ProximityPrompt missing in Workspace.{shopModel.Name}.RootPart.OpenShopAttachment`)
		return
	end
	local prompt = promptObj :: ProximityPrompt
	if prompt:GetAttribute(PROMPT_BOUND_ATTR) == true then
		return
	end
	prompt:SetAttribute(PROMPT_BOUND_ATTR, true)

	prompt.Triggered:Connect(function()
		if tryPromptShopBundleDirectPurchase(shopModel) then
			return
		end
		local windowIdAttr = shopModel:GetAttribute("WindowId")
		local windowId = if type(windowIdAttr) == "string" then windowIdAttr else ""
		if windowId == "" then
			warn(`[ShopClientManager] WindowId is missing/empty on Workspace.{shopModel.Name}`)
			return
		end
		UIManager.OpenWindow(windowId)
	end)
end

local function InitShopModel(modelName: string)
	local shopModelObj = Workspace:WaitForChild(modelName, SHOP_WAIT_TIMEOUT)
	if not shopModelObj or not shopModelObj:IsA("Model") then
		warn(`[ShopClientManager] Workspace.{modelName} not found or not a Model`)
		return
	end
	local shopModel = shopModelObj :: Model
	BindPromptByWindowId(shopModel)
	SetupEquipBoxGuiAdaptation(shopModel)
end

function ShopClientManager.Init()
	for _, modelName in ipairs(SHOP_MODEL_NAMES) do
		task.spawn(function()
			InitShopModel(modelName)
		end)
	end

	-- Listen for character changes to update SellBrainrotPrompt
	local function onCharacter(char: Model)
		local function update()
			updatePrompts()
		end
		char.ChildAdded:Connect(update)
		char.ChildRemoved:Connect(update)
		update()
	end
	game.Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if game.Players.LocalPlayer.Character then
		onCharacter(game.Players.LocalPlayer.Character)
	end

	-- Listen for data changes to update ActionText
	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
		updatePrompts()
	end)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		updatePrompts()
	end)

	-- Initial update
	updatePrompts()
end

return ShopClientManager
