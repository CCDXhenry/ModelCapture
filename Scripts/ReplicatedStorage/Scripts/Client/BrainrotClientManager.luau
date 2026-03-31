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
local ModelBillboardOffsetTool = require(scripts:WaitForChild("Client"):WaitForChild("ModelBillboardOffsetTool"))
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
		elseif part:IsA("WeldConstraint") then
			local weldConstraintAny = part :: any
			local isInvalid = weldConstraintAny.Part0 == nil or weldConstraintAny.Part1 == nil
			local isAuto = part.Name == "AutoWeldConstraint"
			if isInvalid or isAuto then
				part:Destroy()
			end
		elseif part:IsA("Weld") then
			local weldAny = part :: any
			local isInvalid = weldAny.Part0 == nil or weldAny.Part1 == nil
			local isAuto = part.Name == "AutoWeld" or part.Name == "AutoWeld_ComponentBridge" or part.Name == "AutoWeld_RootBridge"
			if isInvalid or isAuto then
				part:Destroy()
			end
		end
	end

	local rootPart = (newVisual.PrimaryPart or newVisual:FindFirstChild("RootPart") or newVisual:FindFirstChildWhichIsA("BasePart")) :: BasePart?
	local attachPart = (newVisual:FindFirstChild("FakeRootPart") or rootPart) :: BasePart?
	if rootPart and attachPart then
		local weld = Instance.new("Weld")
		weld.Name = "IslandVisualWeld"
		weld.Part0 = targetPart
		weld.Part1 = attachPart
		-- 显式固化当前相对位姿，兼容不同骨架中心点（RootPart/FakeRootPart）
		weld.C0 = targetPart.CFrame:ToObjectSpace(attachPart.CFrame)
		weld.C1 = CFrame.new()
		weld.Parent = targetPart
	end

	newVisual.Parent = targetPart

	local level = (targetPart:GetAttribute("Level") :: number) or 1
	AttachInfoUIToModel(targetPart, targetPart :: BasePart, configId, level, data.quality or 1, newVisual)
end

-- Attach UI
function AttachInfoUIToModel(targetParent: Instance, adornee: BasePart, configId: number, level: number, quality: number, visualModel: Model?)
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
	newBrainrotUI.Name = if itemType == GameConfig.ItemType.LittleElfChest then "LittleElfChestInfoUI" else "BrainrotInfoUI"

	local controller = newBrainrotUI:FindFirstChild("Controller") or newBrainrotUI:FindFirstChild("ControllerFrame")
	if controller then
		local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
		local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
		local levelText = controller:FindFirstChild("LvLabel") :: TextLabel?
		local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
		local sellPriceText = controller:FindFirstChild("SellPriceText") :: TextLabel?
			local timerTextLabel = controller:FindFirstChild("TimerText") :: TextLabel?
			local timerImgLabel = controller:FindFirstChild("TimerImg") :: ImageLabel?

		local qualityCfg = GameConfig.BrainrotQualityConfig[quality]

		if nameLabel then
			nameLabel.Text = data.name_t or ""
			-- NameLabel 颜色固定为白色，不随品质变化
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
		end
		if qualityLabel then
			local qualityTextName = GameConfig.BrainrotQualityTextMap[quality]
			local qualityTextData = if qualityTextName then ((GameTexts :: any)[qualityTextName] :: { source: string, key: string }?) else nil
			if qualityTextData then
				TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, qualityTextData.source, qualityTextData.key, {})
			else
				TranslationTool.CustomAutoLocalizeTextLabel(qualityLabel, "", "", {})
			end
			if qualityCfg then
				qualityLabel.TextColor3 = qualityCfg.textColor
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

			-- Brainrot 独立倒计时显示（每个 brainrot 自己的 UI 都有一份）
			if timerTextLabel and timerImgLabel then
				local function updateTimer()
					local isBrainrot = itemType == GameConfig.ItemType.Brainrot
					if not isBrainrot then
						timerTextLabel.Visible = false
						timerImgLabel.Visible = false
						return
					end

					local remaining = tonumber(adornee:GetAttribute("BrainrotTimerRemainingSeconds")) or 0
					local visible = remaining > 0
					timerTextLabel.Visible = visible
					timerImgLabel.Visible = visible
					if visible then
						timerTextLabel.Text = tostring(remaining)
					end
				end

				updateTimer()
				adornee:GetAttributeChangedSignal("BrainrotTimerRemainingSeconds"):Connect(function()
					updateTimer()
				end)
			end
	end

	local offsetY = if visualModel then ModelBillboardOffsetTool.GetVisualOffsetY(visualModel, adornee) else 2
	newBrainrotUI.StudsOffset = Vector3.new(0, offsetY, 0)
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
					visualModel
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
