--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))

local islandsFolder = workspace:WaitForChild("Islands")

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

	BillboardManager.Track(ui)
end

local function OnIslandDescendantAdded(desc: Instance)
	if desc:IsA("BillboardGui") and desc.Name == "BrainrotInfoUI" then
		LocalizeBrainrotUI(desc)
	elseif desc:IsA("ProximityPrompt") then
		local parent = desc.Parent
		if parent and parent.Name == "InteractionAttachment" then
			-- Picking up brainrots from BrainrotIslandManager
			TranslationTool.CustomAutoLocalizeProximityPrompt(desc, GameTexts.PickUpBrainrot.source, GameTexts.PickUpBrainrot.key)
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
