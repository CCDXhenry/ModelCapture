--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local BILLBOARD_TRACKED_ATTR = "BillboardTracked"

local function EnsureBillboardTracked(gui: BillboardGui)
	if gui:GetAttribute(BILLBOARD_TRACKED_ATTR) ~= true then
		gui:SetAttribute(BILLBOARD_TRACKED_ATTR, true)
	end
	BillboardManager.Track(gui)
end

local islandsFolder = workspace:WaitForChild("Islands")

local function LocalizeLittleElfChestInfoUI(ui: BillboardGui)
	local controller = ui:FindFirstChild("ControllerFrame")
	if not controller then
		return
	end

	local levelLabel = controller:FindFirstChild("LvLabel") :: TextLabel?
	if levelLabel then
		TranslationTool.CustomAutoLocalizeTextLabel(levelLabel, GameTexts.UnknownLevel.source, GameTexts.UnknownLevel.key, {})
	end
	EnsureBillboardTracked(ui)
end

local function LocalizeBrainrotUI(ui: BillboardGui)
	local controller = ui:FindFirstChild("ControllerFrame")
	if not controller then
		return
	end

	local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
	local levelLabel = controller:FindFirstChild("LvLabel") :: TextLabel?
	-- SellPriceText is usually raw number, but we can localize if needed.
	-- For wild brainrots, level is usually 1.

	if abilityText then
		-- Extract current value or use a default if missing
		local rawText = abilityText.Text
		local val = rawText:match("([%d%.%w]+)/s") or "0"
		TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { val })
	end

	if levelLabel then
		local lv = levelLabel.Text:match("Lv%.(%d+)") or "1"
		TranslationTool.CustomAutoLocalizeTextLabel(levelLabel, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { lv })
	end

	EnsureBillboardTracked(ui)
end

local function OnIslandDescendantAdded(desc: Instance)
	if desc:IsA("BillboardGui") and desc.Name == "BrainrotInfoUI" then
		LocalizeBrainrotUI(desc)
	elseif desc:IsA("BillboardGui") and desc.Name == "LittleElfChestInfoUI" then
		LocalizeLittleElfChestInfoUI(desc)
	elseif desc:IsA("ProximityPrompt") then
		local parent = desc.Parent
		if parent and parent.Name == "InteractionAttachment" then
			local holder = parent.Parent
			if holder and holder:IsA("BasePart") and (holder.Name == "IslandBrainrot" or holder.Name == "IslandChest") then
				local configId = holder:GetAttribute("ConfigId") :: number?
				local level = holder:GetAttribute("Level") or 1
				local itemType = (holder:GetAttribute("ItemType") :: number?) or 1
				local config: any = nil
				if itemType == GameConfig.ItemType.LittleElfChest then
					config = if configId then GameConfig.LittleElfChestIdMap[configId] else nil
				else
					config = if configId then GameConfig.BrainrotIdMap[configId] else nil
				end
				local displayName: string = if config and config.name_t then config.name_t else holder.Name
				local levelStr = if itemType == GameConfig.ItemType.LittleElfChest then "???" else tostring(level)
				local objectTip = GameTexts.BrainrotPickupObjectText
				TranslationTool.CustomAutoLocalizeProximityPrompt(
					desc,
					GameTexts.PickUpBrainrot.source,
					GameTexts.PickUpBrainrot.key,
					nil,
					objectTip.source,
					objectTip.key,
					{ displayName, levelStr }
				)
			else
				TranslationTool.CustomAutoLocalizeProximityPrompt(desc, GameTexts.PickUpBrainrot.source, GameTexts.PickUpBrainrot.key)
			end
		end
	end
end

local IslandClientManager = {}

function IslandClientManager.Init()
	for _, island in ipairs(islandsFolder:GetChildren()) do
		island.DescendantAdded:Connect(OnIslandDescendantAdded)
		for _, desc in ipairs(island:GetDescendants()) do
			OnIslandDescendantAdded(desc)
		end
	end

	islandsFolder.ChildAdded:Connect(function(island)
		island.DescendantAdded:Connect(OnIslandDescendantAdded)
	end)
end

return IslandClientManager
