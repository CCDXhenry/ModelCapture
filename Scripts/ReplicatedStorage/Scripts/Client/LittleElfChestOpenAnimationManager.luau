--!strict
local LittleElfChestOpenAnimationManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:WaitForChild("TranslationTool"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local ModelBillboardOffsetTool = require(clientScripts:WaitForChild("ModelBillboardOffsetTool"))

local actualModels = replicatedStorage:WaitForChild("Models"):WaitForChild("Brainrots")
local actualChests = replicatedStorage:WaitForChild("Models"):WaitForChild("LittleElfChests")
local uiFolder = replicatedStorage:WaitForChild("UI")
local brainrotInfoUIParams = uiFolder:WaitForChild("BrainrotInfoUI") :: BillboardGui

local RandomCount = 10
local TinyScale = 0.02
local ChestThrowForwardDistance = 1.0

local playingUidMap: { [string]: boolean } = {}

local function TweenProperty(target: Instance, tweenInfo: TweenInfo, props: { [string]: any })
	local tween = tweenService:Create(target, tweenInfo, props)
	tween:Play()
	tween.Completed:Wait()
end

local function TweenPropertyNoWait(target: Instance, tweenInfo: TweenInfo, props: { [string]: any })
	local tween = tweenService:Create(target, tweenInfo, props)
	tween:Play()
	return tween
end

local function TweenModelScale(model: Model, fromScale: number, toScale: number, duration: number, easingStyle: Enum.EasingStyle, easingDir: Enum.EasingDirection)
	local driver = Instance.new("NumberValue")
	driver.Value = fromScale
	local conn = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:ScaleTo(driver.Value)
		end
	end)
	model:ScaleTo(fromScale)
	local tween = tweenService:Create(driver, TweenInfo.new(duration, easingStyle, easingDir), { Value = toScale })
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	driver:Destroy()
	if model.Parent then
		model:ScaleTo(toScale)
	end
end

local function CreateOrUpdateInfoUI(
	parentInstance: Instance,
	adornee: BasePart,
	brainrotId: number,
	level: number,
	model: Model?,
	hideTimers: boolean?
)

	local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
	if not brainrotData then
		return
	end

	local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
	local ui = parentInstance:FindFirstChild("BrainrotInfoUI") :: BillboardGui?
	
	if not ui then
		local clonedUi = brainrotInfoUIParams:Clone() :: BillboardGui
		clonedUi.Name = "BrainrotInfoUI"
		clonedUi.Parent = parentInstance
		BillboardManager.Track(clonedUi)
		ui = clonedUi
	end
	print("ui", ui)
	if not ui then
		return
	end
	ui.Adornee = adornee
	local offsetY = if model then ModelBillboardOffsetTool.GetVisualOffsetY(model, adornee, 1) else 2
	ui.StudsOffset = Vector3.new(0, offsetY, 0)

	local controller = ui:FindFirstChild("ControllerFrame")
	if not controller then
		return
	end

	local nameLabel = controller:FindFirstChild("NameText") :: TextLabel?
	local levelText = controller:FindFirstChild("LevelText") :: TextLabel?
	local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
	local sellPriceText = controller:FindFirstChild("SellPriceText") :: TextLabel?

	if nameLabel then
		nameLabel.Text = brainrotData.name_t or ""
		if qualityCfg then
			nameLabel.TextColor3 = qualityCfg.textColor
		end
	end
	if levelText then
		levelText.Visible = true
		TranslationTool.CustomAutoLocalizeTextLabel(levelText, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { tostring(level) })
		if qualityCfg then
			levelText.TextColor3 = qualityCfg.textColor
		end
	end
	if abilityText then
		abilityText.Visible = true
		local ability = GameConfig.GetBrainrotAbility(brainrotData.baseAbility, level)
		local abilityStr = NumberExtension.FormatBigNumberAA(ability)
		TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
	end
	if sellPriceText then
		sellPriceText.Visible = false
	end

	local shouldHide = hideTimers == true
	local timerTextLabel = controller:FindFirstChild("TimerText") :: TextLabel?
	local timerImgLabel = controller:FindFirstChild("TimerImg") :: ImageLabel?
	if timerTextLabel then
		timerTextLabel.Visible = not shouldHide
	end
	if timerImgLabel then
		timerImgLabel.Visible = not shouldHide
	end
end

local function CreateDisplayModel(tool: Tool, brainrotId: number): (Model?, BasePart?)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil, nil
	end
	local config = GameConfig.BrainrotIdMap[brainrotId]
	if not config then
		return nil, nil
	end
	local sourceModel = GameConfig.FindModelByResourceName(actualModels, config.resourceName)
	if not sourceModel or not sourceModel:IsA("Model") then
		warn(
			"[LittleElfChestOpenAnimationManager] Reward brainrot model not found:",
			config.resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(config.resourceName), ", ")
		)
		return nil, nil
	end

	local oldModel = tool:FindFirstChild("OpenAnimDisplayModel")
	if oldModel then
		oldModel:Destroy()
	end

	local visualModel = sourceModel:Clone()
	visualModel.Name = "OpenAnimDisplayModel"
	local root = visualModel.PrimaryPart or visualModel:FindFirstChild("RootPart") or visualModel:FindFirstChildWhichIsA("BasePart")
	if not root or not root:IsA("BasePart") then
		visualModel:Destroy()
		return nil, nil
	end

	for _, part in ipairs(visualModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			part.Massless = true
			part.CanQuery = false
			part.CanTouch = false
		end
	end

	visualModel:PivotTo(handle.CFrame)
	visualModel.Parent = tool

	local motor = Instance.new("Motor6D")
	motor.Name = "OpenAnimVisualMotor"
	motor.Part0 = handle
	motor.Part1 = root
	motor.C0 = CFrame.new(0, 1.2, 0)
	motor.Parent = handle

	return visualModel, root
end

local function PickRandomEntry(pool: { any }, lastId: number?): any?
	if #pool <= 0 then
		return nil
	end
	local randomEntry = pool[math.random(1, #pool)]
	if #pool > 1 and lastId then
		while randomEntry.itemId == lastId do
			randomEntry = pool[math.random(1, #pool)]
		end
	end
	return randomEntry
end

local function CreateAnchoredModelFromConfig(folder: Folder, resourceName: string, parentInst: Instance, modelName: string, targetCFrame: CFrame): (Model?, BasePart?)
	local sourceModel = GameConfig.FindModelByResourceName(folder, resourceName)
	if not sourceModel or not sourceModel:IsA("Model") then
		warn(
			"[LittleElfChestOpenAnimationManager] Anchored model source not found:",
			resourceName,
			"candidates:",
			table.concat(GameConfig.GetResourceNameCandidates(resourceName), ", ")
		)
		return nil, nil
	end
	local model = sourceModel:Clone()
	model.Name = modelName
	local root = model.PrimaryPart or model:FindFirstChild("RootPart") or model:FindFirstChildWhichIsA("BasePart")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil, nil
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	model:PivotTo(targetCFrame)
	model.Parent = parentInst
	return model, root
end

local function PlayInWorld(uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number, originCFrame: CFrame)
	local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
	local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
	if not chestConfig or not rewardPool or #rewardPool == 0 then
		return
	end
	local container = Instance.new("Folder")
	container.Name = "OpenChestAnim_" .. uid
	container.Parent = workspace

	local throwCFrame = originCFrame * CFrame.new(0, 0, -ChestThrowForwardDistance)
	local chestModel, chestRoot = CreateAnchoredModelFromConfig(actualChests, chestConfig.resourceName, container, "WorldChestModel", throwCFrame)
	if not chestModel or not chestRoot then
		container:Destroy()
		return
	end

	local yDriver = Instance.new("NumberValue")
	yDriver.Value = 0
	local yawDriver = Instance.new("NumberValue")
	-- 丢出时的随机旋转（绕 Y 轴）
	yawDriver.Value = math.rad(math.random(-120, 120))

	local function UpdateChestPivot()
		if chestModel and chestModel.Parent then
			chestModel:PivotTo(throwCFrame * CFrame.Angles(0, yawDriver.Value, 0) * CFrame.new(0, yDriver.Value, 0))
		end
	end

	local yConn = yDriver:GetPropertyChangedSignal("Value"):Connect(UpdateChestPivot)
	local yawConn = yawDriver:GetPropertyChangedSignal("Value"):Connect(UpdateChestPivot)
	UpdateChestPivot()

	-- 丢出下落 + 随机自转
	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = yawDriver.Value + math.rad(math.random(-120, 120)),
	})
	TweenProperty(yDriver, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	-- 落地挤压
	TweenModelScale(chestModel, 1, 0.85, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenModelScale(chestModel, 0.85, 1, 0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- 落地后：左右旋转蹦跶两下
	local leftYaw = math.rad(math.random(25, 50))
	local rightYaw = -leftYaw
	local smallUp1 = 0.55
	local smallUp2 = 0.45

	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = leftYaw })
	TweenProperty(yDriver, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = smallUp1 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = rightYaw })
	TweenProperty(yDriver, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = smallUp2 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	-- 正反方向：大跳旋转两下
	local bigYaw = math.rad(math.random(120, 160))
	local bigUp1 = 1.0
	local bigUp2 = 0.85

	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigYaw })
	TweenProperty(yDriver, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigUp1 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = -bigYaw })
	TweenProperty(yDriver, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = bigUp2 })
	TweenPropertyNoWait(yawDriver, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
	TweenProperty(yDriver, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = -0.2 })

	-- 缩小到 0：开始随机 brainrot 展示
	TweenModelScale(chestModel, 1, TinyScale, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	yConn:Disconnect()
	yawConn:Disconnect()
	yDriver:Destroy()
	yawDriver:Destroy()

	local displayModel: Model? = nil
	local displayRoot: BasePart? = nil
	local lastId: number? = nil
	local function ShowOne(brainrotId: number, stayAsFinal: boolean)
		local brainrotData = GameConfig.BrainrotIdMap[brainrotId]
		if not brainrotData then
			return
		end
		if displayModel then
			displayModel:Destroy()
			displayModel = nil
			displayRoot = nil
		end
		displayModel, displayRoot = CreateAnchoredModelFromConfig(actualModels, brainrotData.resourceName, container, "WorldBrainrotModel", throwCFrame * CFrame.new(0, 1.2, 0))
		if not displayModel or not displayRoot then
			return
		end
		-- 随机展示的 rewardPool 不需要倒计时 UI
		CreateOrUpdateInfoUI(container, displayRoot, brainrotId, chestLevel, displayModel, not stayAsFinal)
		TweenModelScale(displayModel, TinyScale, 1, 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if stayAsFinal then
			TweenModelScale(displayModel, 1, 1.15, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenModelScale(displayModel, 1.15, 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.wait(0.08)
			-- 最终模型消失也要缩放
			TweenModelScale(displayModel, 1, TinyScale, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			displayModel:Destroy()
			displayModel = nil
			displayRoot = nil
		else
			task.wait(0.05)
			TweenModelScale(displayModel, 1, TinyScale, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end

	for _ = 1, RandomCount do
		local randomEntry = PickRandomEntry(rewardPool, lastId)
		if not randomEntry then
			break
		end
		local randomId = randomEntry.itemId
		lastId = randomId
		ShowOne(randomId, false)
	end
	ShowOne(finalBrainrotId, true)
	if container and container.Parent then
		container:Destroy()
	end
end

function LittleElfChestOpenAnimationManager.Play(tool: Tool?, uid: string, chestConfigId: number, chestLevel: number, finalBrainrotId: number, fallbackCFrame: CFrame?)
	if playingUidMap[uid] then
		return
	end
	playingUidMap[uid] = true

	local ok = pcall(function()
		if not tool or not tool.Parent then
			if fallbackCFrame then
				PlayInWorld(uid, chestConfigId, chestLevel, finalBrainrotId, fallbackCFrame)
			end
			return
		end

		local chestConfig = GameConfig.LittleElfChestIdMap[chestConfigId]
		local rewardPool = GameConfig.LittleElfChestRewardPoolMap[chestConfigId]
		if not chestConfig or not rewardPool or #rewardPool == 0 then
			return
		end

		local chestModel = tool:FindFirstChild("VisualModel")
		local handle = tool:FindFirstChild("Handle")
		local visualMotor = handle and handle:FindFirstChild("VisualMotor")
		if not chestModel or not chestModel:IsA("Model") or not visualMotor or not visualMotor:IsA("Motor6D") then
			return
		end

		-- 落地 -> 挤压(用缩放近似) -> 双段弹跳
		TweenProperty(visualMotor, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })
		TweenModelScale(chestModel, 1, 0.85, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenModelScale(chestModel, 0.85, 1, 0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenProperty(visualMotor, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = CFrame.new(0, 1.15, 0) })
		TweenProperty(visualMotor, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })
		TweenProperty(visualMotor, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = CFrame.new(0, 0.75, 0) })
		TweenProperty(visualMotor, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = CFrame.new(0, 0.2, 0) })

		-- 宝箱缩小到接近0
		TweenModelScale(chestModel, 1, TinyScale, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

		local lastId: number? = nil
		for _ = 1, RandomCount do
			if not tool.Parent then
				return
			end
			local randomEntry = PickRandomEntry(rewardPool, lastId)
			if not randomEntry then
				return
			end
			local randomId = randomEntry.itemId
			lastId = randomId

			local showModel, root = CreateDisplayModel(tool, randomId)
			if not showModel or not root then
				continue
			end

			-- 随机展示的 rewardPool 不需要倒计时 UI
			CreateOrUpdateInfoUI(tool, root, randomId, chestLevel, showModel, true)
			TweenModelScale(showModel, TinyScale, 1, 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			task.wait(0.05)
			TweenModelScale(showModel, 1, TinyScale, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			showModel:Destroy()
		end

		-- 最终定格模型
		local finalModel, finalRoot = CreateDisplayModel(tool, finalBrainrotId)
		if finalModel and finalRoot then
			-- 最终定格展示允许倒计时 UI
			CreateOrUpdateInfoUI(tool, finalRoot, finalBrainrotId, chestLevel, finalModel, true)
			TweenModelScale(finalModel, TinyScale, 1.15, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenModelScale(finalModel, 1.15, 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)

	if not ok then
		warn("[LittleElfChestOpenAnimationManager] Play failed")
	end

	playingUidMap[uid] = nil
end

return LittleElfChestOpenAnimationManager
