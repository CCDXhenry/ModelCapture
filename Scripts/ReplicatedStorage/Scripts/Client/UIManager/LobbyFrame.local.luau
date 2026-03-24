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
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):FindFirstChild("TranslationTool"))
local GameTexts = require(sharedScripts_game:FindFirstChild("GameTexts"))

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
local walkSpeedFrame: Frame = lobbyFrame:FindFirstChild("WalkSpeedFrame") :: Frame
local walkSpeedText: TextLabel = walkSpeedFrame:FindFirstChild("NumberText") :: TextLabel

local maxBricksAddButton: GuiButton? = maxBricksFrame:FindFirstChild("AddButton") :: any
local walkSpeedAddButton: GuiButton? = walkSpeedFrame:FindFirstChild("AddButton") :: any

local defaultWalkSpeedColor = walkSpeedText.TextColor3
local localPlayer = game:GetService("Players").LocalPlayer
local humSpeedConnection: RBXScriptConnection? = nil

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
end

--刷新升级数值
local function RefreshUpgradeValues()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end

	-- MaxBricks done in RefreshBricksDisplay
	RefreshBricksDisplay()

	-- WalkSpeed
	local walkSpeedLevel = localPlayerInfo.shopInfo.walkSpeedLevel or 1
	local walkSpeedConfig = GameConfig.Shop.WalkSpeed
	local baseSpeed = 16
	if walkSpeedConfig then
		baseSpeed = walkSpeedConfig.abilityList[walkSpeedLevel] or walkSpeedConfig.abilityList[1]
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
end

local function RefreshView()
	RefreshCoinCountText()
	RefreshUpgradeValues()
end

local function OnLocalPlayerCoinCountChanged()
	RefreshCoinCountText()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
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
end

UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)

RefreshView()

ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCoinCountChanged)
ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
ClientMsg.ConnectLocalPlayerSkillLevelUpdate(OnLocalPlayerSkillLevelChanged)
ClientMsg.ConnectLocalPlayerCarriedUpdate(OnLocalPlayerCarriedChanged)
