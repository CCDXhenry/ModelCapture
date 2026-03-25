--!strict
local BrainrotClientManager = {}

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local tweenService = game:GetService("TweenService")

local localPlayer = players.LocalPlayer
local holdAnimInstance = Instance.new("Animation")
holdAnimInstance.AnimationId = "rbxassetid://0" -- 手动替换为双手托举的动作ID
local holdAnimTrack: AnimationTrack? = nil
local isPlayerOnIsland = false -- 将在阶段四中由区域检测系统更新

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(scripts:WaitForChild("Client"):WaitForChild("BillboardManager"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local LittleElfChestOpenAnimationManager = require(scripts:WaitForChild("Client"):WaitForChild("LittleElfChestOpenAnimationManager"))

local islandsFolder = workspace:WaitForChild("Islands")
local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local actualChests = replicatedStorage:WaitForChild("Models"):WaitForChild("LittleElfChests")
local uIFolder = replicatedStorage:WaitForChild("UI")
local brainrotInfoUIParams = uIFolder:WaitForChild("BrainrotInfoUI") :: BillboardGui
local littleElfChestInfoUIParams = uIFolder:WaitForChild("LittleElfChestInfoUI") :: BillboardGui

local AttachInfoUIToModel -- 向前声明
local pendingOpenChestToolMap: { [string]: Tool } = {}
local pendingOpenChestCFrameMap: { [string]: CFrame } = {}

local function SetupVisualBrainrot(targetPart: BasePart)
	if targetPart:FindFirstChild("VisualModel") then
		return -- Already setup
	end

	local configId = targetPart:GetAttribute("ConfigId") :: number?
	local itemType = targetPart:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
	if not configId then
		return
	end

	local data: any
	local sourceFolder: Folder?
	if itemType == GameConfig.ItemType.LittleElfChest then
		data = GameConfig.LittleElfChestIdMap[configId]
		sourceFolder = actualChests
	else
		data = GameConfig.BrainrotIdMap[configId]
		sourceFolder = actualModels
	end

	if not data or not sourceFolder then
		return
	end

	local sourceModel = sourceFolder:FindFirstChild(data.resourceName)
	if not sourceModel or not sourceModel:IsA("Model") then
		return
	end

	local newVisual = sourceModel:Clone()
	newVisual.Name = "VisualModel"
	newVisual:SetAttribute("ConfigId", configId)
	newVisual:SetAttribute("ItemType", itemType)

	local targetCFrame = targetPart.CFrame
	newVisual:PivotTo(targetCFrame)

	for _, part in ipairs(newVisual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part.CanTouch = false
			part.CanQuery = false
		end
	end

	local rootPart = newVisual.PrimaryPart or newVisual:FindFirstChild("RootPart") or newVisual:FindFirstChildWhichIsA("BasePart")
	if rootPart and rootPart:IsA("BasePart") then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = targetPart
		weld.Part1 = rootPart
		weld.Parent = newVisual
	end

	newVisual.Parent = targetPart

	local level = (targetPart:GetAttribute("Level") :: number) or 1
	AttachInfoUIToModel(targetPart, targetPart :: BasePart, configId, level, data.quality or 1, newVisual:GetExtentsSize().Y)
end

-- Attach UI
function AttachInfoUIToModel(targetParent: Instance, adornee: BasePart, configId: number, level: number, quality: number, visualModelHeight: number)
	if targetParent:FindFirstChild("BrainrotInfoUI") or targetParent:FindFirstChild("LittleElfChestInfoUI") then
		return
	end

	local itemType = targetParent:GetAttribute("ItemType") :: number? or GameConfig.ItemType.Brainrot
	local data: any
	if itemType == GameConfig.ItemType.LittleElfChest then
		data = GameConfig.LittleElfChestIdMap[configId]
	else
		data = GameConfig.BrainrotIdMap[configId]
	end

	if not data then
		return
	end

	local newBrainrotUI = if itemType == GameConfig.ItemType.LittleElfChest then littleElfChestInfoUIParams:Clone() else brainrotInfoUIParams:Clone()
	newBrainrotUI.Adornee = adornee
	--newBrainrotUI.ExtentsOffsetWorldSpace = Vector3.new(0, visualModelHeight + 1.2, 0)
	newBrainrotUI.Name = if itemType == GameConfig.ItemType.LittleElfChest then "LittleElfChestInfoUI" else "BrainrotInfoUI"

	local controller = newBrainrotUI:FindFirstChild("Controller") or newBrainrotUI:FindFirstChild("ControllerFrame")
	if controller then
		local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
		local levelText = controller:FindFirstChild("LvLabel") :: TextLabel?
		local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
		local sellPriceText = controller:FindFirstChild("SellPriceText") :: TextLabel?

		local qualityCfg = GameConfig.BrainrotQualityConfig[quality]

		if nameLabel then
			nameLabel.Text = data.name_t or ""
			if qualityCfg then
				nameLabel.TextColor3 = qualityCfg.textColor
			end
		end
		if levelText then
			levelText.Visible = true
			if itemType == GameConfig.ItemType.LittleElfChest then
				if targetParent:IsA("Tool") then
					TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { tostring(level) })
				else
					TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.UnknownLevel.source, GameTexts.UnknownLevel.key, {})
				end
			else
				TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { tostring(level) })
			end

			if qualityCfg then
				levelText.TextColor3 = qualityCfg.textColor
			end
		end
		if abilityText then
			abilityText.Visible = itemType == GameConfig.ItemType.Brainrot
			local ability = if itemType == GameConfig.ItemType.Brainrot then GameConfig.GetBrainrotAbility(data.baseAbility, level) else 0
			local abilityStr = NumberExtension.FormatBigNumberAA(ability)
			TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
		end
		if sellPriceText then
			sellPriceText.Visible = false
		end
	end

	newBrainrotUI.StudsOffset = Vector3.new(0, visualModelHeight + 1, 0)
	newBrainrotUI.Adornee = adornee
	newBrainrotUI.Parent = targetParent
	BillboardManager.Track(newBrainrotUI)
end

local function ProcessDescendantAdded(descendant: Instance)
	if descendant:IsA("BasePart") and (descendant.Name == "IslandBrainrot" or descendant.Name == "IslandChest" or descendant.Name == "CarryingBrainrot") then
		SetupVisualBrainrot(descendant :: any)
	elseif descendant:IsA("Tool") and descendant:GetAttribute("BrainrotUID") then
		local visualModel = descendant:WaitForChild("VisualModel", 3) :: Model?
		if visualModel then
			local root = visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart")
			if root then
				local configId = descendant:GetAttribute("ConfigId") :: number
				local level = (descendant:GetAttribute("Level") :: number) or 1
				local quality = (descendant:GetAttribute("Quality") :: number) or 1
				AttachInfoUIToModel(
					descendant,
					visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart") or (visualModel:GetChildren()[1] :: any),
					configId,
					level,
					quality,
					visualModel:GetExtentsSize().Y
				)
			end
		end
	end
end

local function OnLocalToolEquipped(tool: Tool, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	if not holdAnimTrack then
		holdAnimTrack = animator:LoadAnimation(holdAnimInstance)
		if holdAnimTrack then
			holdAnimTrack.Priority = Enum.AnimationPriority.Action
		end
	end

	-- 停止默认拿取动画
	task.defer(function()
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Name == "toolanim" then
				track:Stop()
			end
		end
	end)

	if holdAnimTrack then
		holdAnimTrack:Play()
	end

	-- Motor6D Tween 视觉位置
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local visualMotor = handle:FindFirstChild("VisualMotor") :: Motor6D
		if visualMotor then
			local visualModel = tool:FindFirstChild("VisualModel") :: Model
			local targetC0 = CFrame.new()
			if isPlayerOnIsland and visualModel then
				local extents = visualModel:GetExtentsSize()
				targetC0 = CFrame.new(0, (extents.Y / 2) + 1.5, 0) -- 1.5 为预估头部偏移量
			end
			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tweenService:Create(visualMotor, tweenInfo, { C0 = targetC0 }):Play()
		end
	end
end

local function OnLocalToolUnequipped(tool: Tool)
	if holdAnimTrack then
		holdAnimTrack:Stop()
	end
end

local function SetupLocalPlayerToolTracking(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") then
			OnLocalToolEquipped(child :: Tool, character)

			-- 如果是宝箱，监听点击
			if child:GetAttribute("ItemType") == GameConfig.ItemType.LittleElfChest then
				local uid = child:GetAttribute("BrainrotUID") :: string
				pendingOpenChestToolMap[uid] = child :: Tool
				local activatedConn: RBXScriptConnection? = nil
				activatedConn = (child :: Tool).Activated:Connect(function()
					pendingOpenChestToolMap[uid] = child :: Tool
					local visualModel = child:FindFirstChild("VisualModel")
					if visualModel and visualModel:IsA("Model") then
						pendingOpenChestCFrameMap[uid] = visualModel:GetPivot()
					else
						local handle = child:FindFirstChild("Handle")
						if handle and handle:IsA("BasePart") then
							pendingOpenChestCFrameMap[uid] = handle.CFrame
						end
					end
					if activatedConn then
						activatedConn:Disconnect()
						activatedConn = nil
					end
					NetMsg.FireRequestOpenChest(uid)
				end)
			end
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUID") then
			OnLocalToolUnequipped(child :: Tool)
		end
	end)
end

local function OnNotifyChestOpenResult(uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number)
	local fallbackCFrame = pendingOpenChestCFrameMap[uid]
	if not fallbackCFrame then
		local character = localPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			fallbackCFrame = hrp.CFrame * CFrame.new(0, 0, -4)
		else
			warn("[BrainrotClientManager] OnNotifyChestOpenResult no fallback cframe, uid:", uid)
			return
		end
	end
	task.spawn(function()
		-- 开箱动画固定在世界中播放，不在手上变形
		LittleElfChestOpenAnimationManager.Play(nil, uid, chestConfigId, chestLevel, finalBrainrotId, fallbackCFrame)
	end)
	pendingOpenChestToolMap[uid] = nil
	pendingOpenChestCFrameMap[uid] = nil
end

function BrainrotClientManager.Init()
	local isWelded = replicatedStorage:FindFirstChild("BrainrotModelsWelded")
	if not isWelded then
		isWelded = replicatedStorage:WaitForChild("BrainrotModelsWelded", 10)
	end
	if isWelded and not (isWelded :: BoolValue).Value then
		(isWelded :: BoolValue):GetPropertyChangedSignal("Value"):Wait()
	end

	-- Listen on islands
	islandsFolder.DescendantAdded:Connect(ProcessDescendantAdded)
	for _, desc in ipairs(islandsFolder:GetDescendants()) do
		ProcessDescendantAdded(desc)
	end

	-- Listen on all items hitting Workspace (including Characters equipping Tools)
	workspace.DescendantAdded:Connect(function(desc)
		if not desc:IsDescendantOf(islandsFolder) then
			ProcessDescendantAdded(desc)
		end
	end)

	-- Scan existing characters
	for _, player in ipairs(players:GetPlayers()) do
		if player.Character then
			for _, desc in ipairs(player.Character:GetDescendants()) do
				ProcessDescendantAdded(desc)
			end
		end
	end

	-- Local Player Tool Tracking
	if localPlayer.Character then
		SetupLocalPlayerToolTracking(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(SetupLocalPlayerToolTracking)

	NetMsg.ConnectNotifyChestOpenResult(OnNotifyChestOpenResult)
end

return BrainrotClientManager
