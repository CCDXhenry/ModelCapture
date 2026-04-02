--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local guideText: TextLabel = script.Parent

local function RefreshGuideText()
	if ClientGameInfo.GetLocalPlayerInfo() == nil then
		guideText.Visible = false
		return
	end
	local currentGuideType = ClientGameInfo.GetCurrentGuideType()
	if currentGuideType == GameConfig.GuideType.None then
		guideText.Visible = false
		return
	end

	local textKey = GameConfig.GuideTextKeyMap[currentGuideType]
	local textConfig = if textKey then (GameTexts[textKey] :: { source: string, key: string }) else nil
	if textConfig == nil then
		guideText.Visible = false
		return
	end

	guideText.Visible = true
	TranslationTool.CustomAutoLocalizeTextLabel(guideText, textConfig.source, textConfig.key)
end

local function OnCurrentGuideTypeChanged()
	RefreshGuideText()
end

ClientMsg.ConnectLocalPlayerInfoInit(function()
	RefreshGuideText()
end)

ClientMsg.ConnectCurrentGuideTypeChanged(OnCurrentGuideTypeChanged)

RefreshGuideText()
