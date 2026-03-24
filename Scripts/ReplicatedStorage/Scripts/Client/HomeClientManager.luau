--!strict
local players = game:GetService("Players")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local proximityPromptService = game:GetService("ProximityPromptService")
local scripts = replicatedStorage:WaitForChild("Scripts")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local TranslationTool = require(coreScripts:WaitForChild("Client"):WaitForChild("TranslationTool"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))

local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))

local actualModels = replicatedStorage:WaitForChild("Models"):FindFirstChild("Brainrots")
local HomeClientManager = {}
local homesFolder = workspace:WaitForChild("PlayersHome")

local slotStateCache: { [string]: { active: boolean, homeInfo: any?, isLocalPlayer: boolean? } } = {}
local floorModelsCache: { [string]: { [number]: Model } } = {}
local FLOOR_HEIGHT = 32.6
local MAX_FLOOR_COUNT = 3 -- 最大楼层上限
local function GetPlotsPerFloor(slotModel: Model): number
	local lv1 = slotModel:FindFirstChild("Lv1")
	if not lv1 then
		return 6
	end -- Fallback
	local count = 0
	for _, child in ipairs(lv1:GetChildren()) do
		if child.Name:match("^PlaceModel%d+$") then
			count += 1
		end
	end
	return if count > 0 then count else 6
end
local pendingUpdates = {}
local promptToPlotMap: { [ProximityPrompt]: { pointIndex: number, slotName: string } } = {}
local isLocalHoldingBrainrot = false

-- Forward declarations
local UpdateHomeVisuals, ClearHomeVisuals

local function ApplySlotVisuals(slotName: string)
	local state = slotStateCache[slotName]
	if state and state.active then
		UpdateHomeVisuals(slotName, state.homeInfo, state.isLocalPlayer or false)
	else
		ClearHomeVisuals(slotName)
	end
end

-- Helper to update prompt visibility/text without full plot refresh
local function SetPromptState(attachment: Attachment?, visible: boolean, isOccupied: boolean, plotIndex: number, currentSlotName: string)
	if not attachment then
		return
	end
	local prompt = attachment:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = visible
		promptToPlotMap[prompt] = { pointIndex = plotIndex, slotName = currentSlotName }
		if isOccupied then
			TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.PickUpBrainrot.source, GameTexts.PickUpBrainrot.key)
		else
			TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.PlaceAction.source, GameTexts.PlaceAction.key)
		end
	end
	local billboard = attachment:FindFirstChildOfClass("BillboardGui")
	if billboard then
		billboard.Enabled = visible
		BillboardManager.Track(billboard)
	end
end

-- Focus on refreshing only interactive prompts (lighter than full refresh)
local function UpdateHomePrompts(slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	local state = slotStateCache[slotName]
	if not slotModel or not state or not state.active then
		return
	end

	local isLocalPlayer = state.isLocalPlayer or false
	local homeInfo = state.homeInfo
	if not homeInfo then
		return
	end

	for _, floor in ipairs(slotModel:GetChildren()) do
		if floor.Name:match("^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local pointIndex = tonumber(plot.Name:match("^PlaceModel(%d+)$"))
				if pointIndex then
					local isOccupied = homeInfo.placedModels[tostring(pointIndex)] ~= nil
					local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
					local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?

					local showPlacePrompt = (not isOccupied and isLocalPlayer and isLocalHoldingBrainrot) or (isOccupied and isLocalPlayer)
					SetPromptState(placeAttachment, showPlacePrompt, isOccupied, pointIndex, slotName)
				end
			end
		end
	end
end

local function ScheduleSlotUpdate(slotName: string)
	if pendingUpdates[slotName] then
		return
	end
	pendingUpdates[slotName] = true
	task.delay(0.2, function()
		if not pendingUpdates[slotName] then
			return
		end
		pendingUpdates[slotName] = nil
		print("[HomeClientManager] Applying visuals for slot", slotName)
		ApplySlotVisuals(slotName)
	end)
end

-- Helper to set visibility/collision for various instance types
local function SetVisuals(inst: Instance, visible: boolean, isPlaceholder: boolean?)
	if inst.Name == "SpawnLocation" then
		return
	end
	if inst:IsA("BasePart") then
		inst.Transparency = if visible then 0 else 1
		inst.CanCollide = visible and not isPlaceholder
	elseif inst:IsA("Decal") then
		inst.Transparency = if visible then 0 else 1
	elseif inst:IsA("ParticleEmitter") or inst:IsA("BillboardGui") or inst:IsA("Texture") or inst:IsA("SurfaceGui") then
		(inst :: any).Enabled = visible
	end
end

-- Handles model placement for a single plot
local function UpdatePlot(folder: Instance, placedData: any?, isLocalPlayer: boolean, slotName: string)
	local modelContainer = folder:FindFirstChild("Model") or folder:FindFirstChild("RootPart")
	local pedestal = folder:FindFirstChild("Booth")

	-- 1. Placeholder Content Visibility (Hide everything in Model/RootPart containers)
	if modelContainer then
		for _, desc in ipairs(modelContainer:GetDescendants()) do
			SetVisuals(desc, false, true)
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		if modelContainer:IsA("BasePart") then
			SetVisuals(modelContainer, false, true)
			modelContainer.Anchored = true
		end
	end

	-- 2. Pedestal Visibility (Always Show)
	if pedestal then
		for _, desc in ipairs(pedestal:GetDescendants()) do
			SetVisuals(desc, true, false)
		end
		if pedestal:IsA("BasePart") then
			SetVisuals(pedestal, true, false)
		end
	end

	-- 3. UI Elements (InfoUI & CollectUI)
	local infoUI = folder:FindFirstChild("InfoUI") :: BillboardGui?
	local collectPart = pedestal and pedestal:FindFirstChild("CollectPart") :: BasePart?
	if collectPart then
		collectPart.Transparency = 1
		collectPart.CanQuery = false
	end
	local collectUI = collectPart and collectPart:FindFirstChild("CollectUI") :: SurfaceGui?

	-- 交互按钮附件 (Place, Sell, Upgrade)
	local rootPart = folder:FindFirstChild("RootPart") :: BasePart?
	local placeAttachment = rootPart and rootPart:FindFirstChild("PlaceAttachment") :: Attachment?
	local sellAttachment = rootPart and rootPart:FindFirstChild("SellAttachment") :: Attachment?
	local lightAttachment = rootPart and rootPart:FindFirstChild("LightAttachment") :: Attachment?
	local lightEmitter = lightAttachment and lightAttachment:FindFirstChildOfClass("ParticleEmitter")

	local upgradePart = pedestal and pedestal:FindFirstChild("UpgradePart") :: BasePart?
	if upgradePart then
		upgradePart.Transparency = 1
		upgradePart.CanCollide = false
	end

	local upgradeUI: SurfaceGui? = nil
	if upgradePart then
		upgradeUI = upgradePart:FindFirstChild("UpgradeUI") :: SurfaceGui?
		if upgradeUI then
			upgradeUI.Adornee = upgradePart
			upgradeUI.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
			upgradePart.Destroying:Connect(function()
				if upgradeUI then
					upgradeUI:Destroy()
				end
			end)
		else
			-- Retrieve it if it was previously moved
			for _, gui in ipairs(players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
				if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
					upgradeUI = gui
					break
				end
			end
		end
	end

	local pointIndex = tonumber(folder.Name:match("^PlaceModel(%d+)$"))

	local function SetButtonVisibility(attachment: Attachment?, visible: boolean)
		if not attachment then
			return
		end
		local prompt = attachment:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = visible
			if pointIndex then
				promptToPlotMap[prompt] = { pointIndex = pointIndex, slotName = slotName }
			end
		end
		local billboard = attachment:FindFirstChildOfClass("BillboardGui")
		if billboard then
			billboard.Enabled = visible
			BillboardManager.Track(billboard)
		end
	end

	-- 只要 BillboardGui 存在就追踪自适应 (即使当前不显示，Enabled 会在 UpdateUIScales 检查)
	if infoUI then
		BillboardManager.Track(infoUI)
	end

	-- 4. Set prompt/UI visibility based on occupancy
	local isOccupied = placedData ~= nil
	local showPlacePrompt = (not isOccupied and isLocalPlayer and isLocalHoldingBrainrot) or (isOccupied and isLocalPlayer)
	if pointIndex then
		SetPromptState(placeAttachment, showPlacePrompt, isOccupied, pointIndex, slotName)
	end

	SetButtonVisibility(sellAttachment, isOccupied and isLocalPlayer)

	if lightEmitter then
		lightEmitter.Enabled = false
	end

	if isOccupied and placedData then
		local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
		if brainrotData then
			local levelIdx = placedData.level or 1
			local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]

			if lightEmitter and qualityCfg then
				lightEmitter.Color = ColorSequence.new(qualityCfg.textColor)
				lightEmitter.Enabled = true
			end

			local sellPrompt = sellAttachment and sellAttachment:FindFirstChildOfClass("ProximityPrompt")
			if sellPrompt then
				local sellPrice = GameConfig.GetBrainrotSellPrice(brainrotData.baseAbility, levelIdx)
				local priceStr = NumberExtension.FormatBigNumberAA(sellPrice)
				TranslationTool.CustomAutoLocalizeProximityPrompt(sellPrompt, GameTexts.SellWithPrice.source, GameTexts.SellWithPrice.key, { priceStr })
			end
		end
	end

	-- 5. Collection Touch Detection (Client-Side)
	if collectPart and not collectPart:GetAttribute("TouchBound") then
		collectPart:SetAttribute("TouchBound", true)
		collectPart.Touched:Connect(function(hit)
			if hit.Parent and hit.Parent == players.LocalPlayer.Character then
				local slotName: string? = nil
				-- Find which slot this collectPart belongs to
				local cur: Instance? = folder
				while cur and cur ~= workspace do
					if cur.Name:match("^Player%d+$") then
						slotName = cur.Name
						break
					end
					cur = cur.Parent
				end

				if slotName then
					local state = slotStateCache[slotName]
					if state and state.homeInfo then
						local pIdx = tonumber(folder.Name:match("^PlaceModel(%d+)$"))
						local targetId = 0
						-- Find owner ID
						if state.isLocalPlayer then
							targetId = players.LocalPlayer.UserId
						else
							for _, p in ipairs(players:GetPlayers()) do
								local info = ClientGameInfo.GetOtherPlayerInfo(p.UserId)
								if info and info.homeSlot == slotName then
									targetId = p.UserId
									break
								end
							end
						end

						if pIdx and targetId ~= 0 then
							NetMsg.FireRequestClaimYield(targetId, pIdx)
						end
					end
				end
			end
		end)
	end

	if placedData and infoUI then
		infoUI.Enabled = true
		local controller = infoUI:FindFirstChild("ControllerFrame")
		local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
		if controller and brainrotData then
			local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
			local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
			local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
			local lvLabel = controller:FindFirstChild("LvLabel") :: TextLabel?

			local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
			if nameLabel then
				nameLabel.Text = brainrotData.name_t or ""
				if qualityCfg then
					nameLabel.TextColor3 = qualityCfg.textColor
				end
			end
			if qualityLabel then
				qualityLabel.Text = if qualityCfg then qualityCfg.rarity else ""
				if qualityCfg then
					qualityLabel.TextColor3 = qualityCfg.textColor
				end
			end
			if lvLabel then
				local lvStr = tostring(placedData.level or 1)
				TranslationTool.CustomAutoLocalizeTextLabel(lvLabel, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { lvStr })
				if qualityCfg then
					lvLabel.TextColor3 = qualityCfg.textColor
				end
			end

			-- 收益与售价逻辑 (根据等级索引列表)
			local levelIdx = placedData.level or 1
			if abilityText then
				local abilityStr = NumberExtension.FormatBigNumberAA(GameConfig.GetBrainrotAbility(brainrotData.baseAbility, levelIdx))
				TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
			end
		end
	elseif infoUI then
		infoUI.Enabled = false
	end

	if collectUI then
		local yield = if placedData then (placedData.unclaimedYield or 0) else 0
		collectUI.Enabled = true -- 始终显示
		local controller = collectUI:FindFirstChild("ControllerFrame")
		local collectText = controller and controller:FindFirstChild("CollectText") :: TextLabel?
		local coinImg = controller and controller:FindFirstChild("CoinImg") :: GuiObject?
		if collectText then
			collectText.Visible = isOccupied
			if isOccupied then
				local yieldStr = NumberExtension.FormatBigNumberAA(yield)
				TranslationTool.CustomAutoLocalizeTextLabel(collectText, yieldStr) -- Plain text, no key
			end
		end
		if coinImg then
			coinImg.Visible = isOccupied
		end
	end

	if upgradeUI then
		upgradeUI.Enabled = isOccupied and isLocalPlayer
		if upgradeUI.Enabled and placedData then
			local clickBtn = upgradeUI:FindFirstChild("ClickButton", true) :: ImageButton?
			if clickBtn then
				local clvLabel = clickBtn:FindFirstChild("LvLabel", true) :: TextLabel?
				local costText = clickBtn:FindFirstChild("CostText", true) :: TextLabel?

				local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
				if brainrotData then
					local currentLevel = placedData.level or 1
					local canUp = true -- Brainrot levels are infinite

					if clvLabel then
						if canUp then
							local curLvStr = tostring(currentLevel)
							local nextLvStr = tostring(currentLevel + 1)
							TranslationTool.CustomAutoLocalizeTextLabel(
								clvLabel,
								GameTexts.UpgradeLevelFormat.source,
								GameTexts.UpgradeLevelFormat.key,
								{ curLvStr, nextLvStr }
							)
						else
							TranslationTool.CustomAutoLocalizeTextLabel(clvLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
						end
					end

					if costText then
						if canUp then
							local upgradePrice = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, currentLevel)
							costText.Text = NumberExtension.FormatBigNumberAA(upgradePrice)
							costText.Visible = true
						else
							costText.Visible = false
						end
					end

					if clickBtn and not clickBtn:GetAttribute("ClickBound") then
						clickBtn:SetAttribute("ClickBound", true)

						UIManager.ApplySurfaceButtonEffects(clickBtn)

						clickBtn.Activated:Connect(function()
							local slotName: string? = nil
							local cur: Instance? = folder
							while cur and cur ~= workspace do
								if cur.Name:match("^Player%d+$") then
									slotName = cur.Name
									break
								end
								cur = cur.Parent
							end

							if slotName then
								local state = slotStateCache[slotName]
								if state and state.homeInfo and state.isLocalPlayer then
									local pIdx = tonumber(folder.Name:match("^PlaceModel(%d+)$"))
									if pIdx then
										local pData = state.homeInfo.placedModels[tostring(pIdx)]
										if pData then
											local pBrainrotData = GameConfig.BrainrotIdMap[pData.configId]
											if pBrainrotData then
												local upCost = GameConfig.GetBrainrotUpgradeCost(pBrainrotData.baseAbility, pData.level)
												local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
												local currentGold = playerInfo and playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
												if currentGold < upCost then
													ClientMsg.FireShowGameTip(
														GameTexts.InsufficientCoin.source,
														GameConfig.GameTipTweenType.FlyUp,
														GameTexts.InsufficientCoin.key
													)
													return
												end
												NetMsg.FireRequestUpgradeModel(pIdx)
											end
										end
									end
								end
							end
						end)
					end
				end
			end
		end
	end

	-- 4. Visual Model Management
	local visualModel = folder:FindFirstChild("VisualModel")
	if placedData then
		if not visualModel or visualModel:GetAttribute("ConfigId") ~= placedData.configId then
			if visualModel then
				visualModel:Destroy()
			end

			local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
			local sourceModel = if brainrotData and actualModels then actualModels:FindFirstChild(brainrotData.resourceName) else nil

			if sourceModel and sourceModel:IsA("Model") and modelContainer then
				local newVisual = sourceModel:Clone()
				newVisual.Name = "VisualModel"
				newVisual:SetAttribute("ConfigId", placedData.configId)

				local targetCFrame = nil
				local placeholder = modelContainer:FindFirstChild("Model")
				if placeholder and placeholder:IsA("Model") then
					targetCFrame = placeholder:GetPivot()
				elseif placeholder and placeholder:IsA("BasePart") then
					targetCFrame = placeholder.CFrame
				else
					targetCFrame = modelContainer:IsA("BasePart") and (modelContainer.CFrame * CFrame.new(0, modelContainer.Size.Y / 2, 0))
						or (modelContainer :: any):GetPivot()
				end

				if targetCFrame then
					newVisual:PivotTo(targetCFrame)
				end

				-- 新生成的宠物模型需要锚固并取消碰撞
				for _, part in ipairs(newVisual:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
					end
				end

				-- Track BrainrotInfoUI in the visual model for scaling
				local brainrotModelRoot = newVisual:FindFirstChild("RootPart") :: BasePart?
				local brainrotUI = brainrotModelRoot and brainrotModelRoot:FindFirstChild("BrainrotInfoUI") :: BillboardGui?
				if brainrotUI then
					BillboardManager.Track(brainrotUI)
				end

				newVisual.Parent = folder
			end
		end

		-- Sync BrainrotInfoUI data
		local brainrotModelRoot = visualModel and visualModel:FindFirstChild("RootPart") :: BasePart?
		local brainrotInfoUI = brainrotModelRoot and brainrotModelRoot:FindFirstChild("BrainrotInfoUI") :: BillboardGui?
		if brainrotInfoUI and placedData then
			brainrotInfoUI.Enabled = true

			local visualModelHeight = if visualModel then (visualModel :: Model):GetExtentsSize().Y else 2
			brainrotInfoUI.StudsOffset = Vector3.new(0, visualModelHeight + 0.5, 0)

			local controller = brainrotInfoUI:FindFirstChild("ControllerFrame")
			local brainrotData = GameConfig.BrainrotIdMap[placedData.configId]
			if controller and brainrotData then
				local nameLabel = controller:FindFirstChild("NameLabel") :: TextLabel?
				local qualityLabel = controller:FindFirstChild("QualityLabel") :: TextLabel?
				local abilityText = controller:FindFirstChild("AbilityText") :: TextLabel?
				local lvLabel = controller:FindFirstChild("LvLabel") :: TextLabel?

				local qualityCfg = GameConfig.BrainrotQualityConfig[brainrotData.quality]
				if nameLabel then
					nameLabel.Text = brainrotData.name_t or ""
					if qualityCfg then
						nameLabel.TextColor3 = qualityCfg.textColor
					end
				end
				if qualityLabel then
					qualityLabel.Text = if qualityCfg then qualityCfg.rarity else ""
					if qualityCfg then
						qualityLabel.TextColor3 = qualityCfg.textColor
					end
				end
				if lvLabel then
					local lvStr = tostring(placedData.level or 1)
					TranslationTool.CustomAutoLocalizeTextLabel(lvLabel, GameTexts.LevelWithNumber.source, GameTexts.LevelWithNumber.key, { lvStr })
					if qualityCfg then
						lvLabel.TextColor3 = qualityCfg.textColor
					end
				end

				local levelIdx = placedData.level or 1
				if abilityText then
					local abilityStr = NumberExtension.FormatBigNumberAA(GameConfig.GetBrainrotAbility(brainrotData.baseAbility, levelIdx))
					TranslationTool.CustomAutoLocalizeTextLabel(abilityText, GameTexts.YieldPerSecond.source, GameTexts.YieldPerSecond.key, { abilityStr })
				end
			end
		end
	else
		if visualModel then
			visualModel:Destroy()
		end
	end

	-- 5. Prompt Visibility Managed via SetButtonVisibility above
end

-- Handles teleport point visuals
local function UpdateTeleportPoint(tpModel: Model, isLocalPlayer: boolean)
	for _, desc in ipairs(tpModel:GetDescendants()) do
		SetVisuals(desc, isLocalPlayer)
		-- if desc:IsA("BasePart") then
		-- 	desc.CanCollide = false
		-- end
	end
end

-- Completely hides a slot (when empty)
function ClearHomeVisuals(slotName: string)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel then
		return
	end

	for _, child in ipairs(slotModel:GetChildren()) do
		local lvStr = child.Name:match("^Lv(%d+)$")
		if lvStr and child:IsA("Model") then
			local lvNum = tonumber(lvStr)
			if lvNum == 1 then
				-- Lv1: Show structural parts, but clear plots
				for _, sub in ipairs(child:GetChildren()) do
					if sub.Name:match("^PlaceModel%d+$") then
						UpdatePlot(sub, nil, false, slotName)
					else
						-- Structural
						for _, desc in ipairs(sub:GetDescendants()) do
							if desc.Name == "StairsPart" then
								SetVisuals(desc, false)
							else
								SetVisuals(desc, true)
							end
						end
						if sub:IsA("BasePart") then
							if sub.Name == "StairsPart" then
								SetVisuals(sub, false)
							else
								SetVisuals(sub, true)
							end
						end
					end
				end
			else
				-- Higher levels: Hide completely
				for _, desc in ipairs(child:GetDescendants()) do
					SetVisuals(desc, false)
				end
			end
		elseif child.Name == "TeleportPoint" then
			UpdateTeleportPoint(child :: Model, false) -- 隐藏传送点 (针对空房)
		end
	end
	-- Clear clones
	if floorModelsCache[slotName] then
		for _, model in pairs(floorModelsCache[slotName]) do
			model:Destroy()
		end
		floorModelsCache[slotName] = nil
	end

	-- Hide UpgradeHome for empty slots
	local upgradeHomeModel = slotModel:FindFirstChild("UpgradeHome") :: Model?
	if upgradeHomeModel then
		for _, desc in ipairs(upgradeHomeModel:GetDescendants()) do
			SetVisuals(desc, false, false)
		end
		--if upgradeHomeModel:IsA("BasePart") then
		--	SetVisuals(upgradeHomeModel, false, false)
		--end
	end
end

-- Updates the visuals for a single player's home slot
function UpdateHomeVisuals(slotName: string, homeInfo: any, isLocalPlayer: boolean)
	local slotModel = homesFolder:FindFirstChild(slotName)
	if not slotModel then
		return
	end

	local lv1 = slotModel:FindFirstChild("Lv1")
	if not lv1 or not lv1:IsA("Model") then
		return
	end

	-- 1. Manage floor clones in cache
	local clones = floorModelsCache[slotName]
	if not clones then
		clones = {}
		floorModelsCache[slotName] = clones
	end

	local plotsPerFloor = GetPlotsPerFloor(slotModel)

	-- Add/Remove clones to match target level
	for i = 2, MAX_FLOOR_COUNT do
		if i <= homeInfo.level then
			if not clones[i] then
				local cloned = lv1:Clone()
				cloned.Name = "Lv" .. i
				local offset = Vector3.new(0, (i - 1) * FLOOR_HEIGHT, 0)
				cloned:PivotTo(lv1:GetPivot() * CFrame.new(offset))
				cloned.Parent = slotModel
				clones[i] = cloned

				-- Rename PlaceModels in the new floor
				for _, child in ipairs(cloned:GetChildren()) do
					local pIdx = tonumber(child.Name:match("^PlaceModel(%d+)$"))
					if pIdx then
						child.Name = "PlaceModel" .. tostring((i - 1) * plotsPerFloor + pIdx)
					end
					-- Important: clear TouchBound so touch events are re-bound for the clone
					for _, desc in ipairs(child:GetDescendants()) do
						if desc.Name == "CollectPart" then
							desc:SetAttribute("TouchBound", nil)
						end
					end
				end
			end
		else
			if clones[i] then
				clones[i]:Destroy()
				clones[i] = nil
			end
		end
	end

	-- 2. Update all floors (Lv1 and Clones)
	for _, child in ipairs(slotModel:GetChildren()) do
		local lvStr = child.Name:match("^Lv(%d+)$")
		if lvStr and child:IsA("Model") then
			local lvNum = tonumber(lvStr)
			if lvNum and lvNum <= homeInfo.level then
				-- Show & Update
				for _, sub in ipairs(child:GetChildren()) do
					if sub.Name:match("^PlaceModel%d+$") then
						local pointIndex = tonumber(sub.Name:match("^PlaceModel(%d+)$"))
						if pointIndex then
							UpdatePlot(sub, homeInfo.placedModels[tostring(pointIndex)], isLocalPlayer, slotName)
						end
					else
						-- Structural visibility
						local homeModel = if sub.Name == "HomeModel" then sub else sub:FindFirstChild("HomeModel")
						if homeModel then
							local ground = homeModel:FindFirstChild("ground")
							local stairs = homeModel:FindFirstChild("StairsPart")
							for _, desc in ipairs(sub:GetDescendants()) do
								if ground and (desc:IsAncestorOf(ground) or desc == ground) then
									SetVisuals(desc, lvNum == 1)
								elseif stairs and (desc:IsAncestorOf(stairs) or desc == stairs) then
									SetVisuals(desc, lvNum < homeInfo.level)
								else
									SetVisuals(desc, true)
								end
							end
						else
							for _, desc in ipairs(sub:GetDescendants()) do
								SetVisuals(desc, true)
							end
						end
						if sub:IsA("BasePart") then
							SetVisuals(sub, true)
						end
					end
				end
			else
				-- Hide (shouldn't happen for clones as they are destroyed above, but for static LvX)
				for _, desc in ipairs(child:GetDescendants()) do
					SetVisuals(desc, false)
				end
			end
		elseif child.Name == "TeleportPoint" then
			UpdateTeleportPoint(child :: Model, isLocalPlayer)
		end
	end

	-- 3. Update UpgradeHome
	local upgradeHomeModel = slotModel:FindFirstChild("UpgradeHome") :: Model?
	if upgradeHomeModel then
		for _, desc in ipairs(upgradeHomeModel:GetDescendants()) do
			SetVisuals(desc, isLocalPlayer, false)
		end

		local upgradePart = upgradeHomeModel:FindFirstChild("UpgradeHome") :: BasePart?
		if upgradePart then
			local upgradeUI: SurfaceGui? = upgradePart:FindFirstChild("UpgradeUI") :: SurfaceGui?
			if upgradeUI then
				upgradeUI.Adornee = upgradePart
				upgradeUI.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
				upgradePart.Destroying:Connect(function()
					if upgradeUI then
						upgradeUI:Destroy()
					end
				end)
			else
				-- 重试从 PlayerGui 获取
				for _, gui in ipairs(players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
					if gui:IsA("SurfaceGui") and gui.Name == "UpgradeUI" and gui.Adornee == upgradePart then
						upgradeUI = gui
						break
					end
				end
			end

			if upgradeUI then
				upgradeUI.Enabled = isLocalPlayer
				if upgradeUI.Enabled then
					local controllerFrame = upgradeUI:FindFirstChild("ControllerFrame") :: Frame?
					local clickBtn = controllerFrame and controllerFrame:FindFirstChild("ClickButton") :: ImageButton?
					if clickBtn then
						local clvLabel = clickBtn:FindFirstChild("LvLabel") :: TextLabel?
						local costText = clickBtn:FindFirstChild("CostText") :: TextLabel?

						local skillData = GameConfig.Shop and GameConfig.Shop.HomeLevel
						if skillData then
							local currentLevel = homeInfo.level or 1
							local canUp = currentLevel < skillData.maxLevel

							if clvLabel then
								if canUp then
									local curLvStr = tostring(currentLevel)
									local nextLvStr = tostring(currentLevel + 1)
									TranslationTool.CustomAutoLocalizeTextLabel(
										clvLabel,
										GameTexts.UpgradeLevelFormat.source,
										GameTexts.UpgradeLevelFormat.key,
										{ curLvStr, nextLvStr }
									)
								else
									TranslationTool.CustomAutoLocalizeTextLabel(clvLabel, GameTexts.MaxLevel.source, GameTexts.MaxLevel.key)
								end
							end

							if costText then
								if canUp then
									local upgradePrice = skillData.upgradeCostList[currentLevel]
									costText.Text = NumberExtension.FormatBigNumberAA(upgradePrice)
									costText.Visible = true
								else
									costText.Visible = false
								end
							end

							if not clickBtn:GetAttribute("ClickBound") then
								clickBtn:SetAttribute("ClickBound", true)
								UIManager.ApplySurfaceButtonEffects(clickBtn)

								clickBtn.Activated:Connect(function()
									local state = slotStateCache[slotName]
									if state and state.homeInfo and state.isLocalPlayer then
										local sData = GameConfig.Shop.HomeLevel
										if sData then
											local cLevel = state.homeInfo.level or 1
											if cLevel < sData.maxLevel then
												local upCost = sData.upgradeCostList[cLevel]
												local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
												local currentGold = playerInfo and playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
												if currentGold < upCost then
													ClientMsg.FireShowGameTip(
														GameTexts.InsufficientCoin.source,
														GameConfig.GameTipTweenType.FlyUp,
														GameTexts.InsufficientCoin.key
													)
													return
												end
												NetMsg.SendRequestUpgradeSkill(GameConfig.SkillType.HomeLevel)
											end
										end
									end
								end)
							end
						end
					end
				end
			end
		end
	end
end

-- Refresh all online players' homes (syncs state)
local function RefreshAllHomes()
	-- Pre-fill all with inactive
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			slotStateCache[child.Name] = { active = false }
		end
	end

	local localInfo: any = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo and localInfo.homeSlot and localInfo.homeSlot ~= "" then
		slotStateCache[localInfo.homeSlot] = { active = true, homeInfo = localInfo.homeInfo, isLocalPlayer = true }
	end

	for _, player in ipairs(players:GetPlayers()) do
		if player.UserId == players.LocalPlayer.UserId then
			continue
		end
		local otherInfo = ClientGameInfo.GetOtherPlayerInfo(player.UserId)
		if otherInfo and otherInfo.homeSlot and otherInfo.homeSlot ~= "" then
			slotStateCache[otherInfo.homeSlot] = { active = true, homeInfo = otherInfo.homeInfo, isLocalPlayer = false }
		end
	end

	-- Apply updates
	for slotName, state in pairs(slotStateCache) do
		ApplySlotVisuals(slotName)
	end
end

local function OnPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= players.LocalPlayer then
		return
	end

	local parent = prompt.Parent
	if not parent then
		return
	end

	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	if parent.Name == "PlaceAttachment" then
		local data = promptToPlotMap[prompt]
		if not data then
			return
		end

		local slotName = data.slotName
		local pointIndex = data.pointIndex

		if slotName ~= playerInfo.homeSlot then
			warn("[HomeClientManager] Unauthorized interaction: not owner of slot", slotName)
			return
		end

		local state = slotStateCache[slotName]
		local isOccupied = state and state.homeInfo and state.homeInfo.placedModels[tostring(pointIndex)] ~= nil

		if isOccupied then
			--print("[HomeClientManager] Firing pickup home model request for plot", pointIndex)
			NetMsg.FireRequestPickupHomeModel(pointIndex)
		else
			--print("[HomeClientManager] Firing place carrying brainrot request for plot", pointIndex)
			NetMsg.FireRequestPlaceCarryingBrainrot(pointIndex)
		end
	elseif parent.Name == "UpgradeAttachment" or parent.Name == "SellAttachment" then
		local data = promptToPlotMap[prompt]
		if not data then
			return
		end

		local slotName = data.slotName
		local pointIndex = data.pointIndex

		-- 1. 检核归属权 (使用注册的信息)
		if slotName ~= playerInfo.homeSlot then
			warn("[HomeClientManager] Unauthorized interaction: not owner of slot", slotName)
			return
		end

		if parent.Name == "UpgradeAttachment" then
			-- 2. 升级检核：金币与等级
			local modelData = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
			if not modelData then
				return
			end

			local brainrotData = GameConfig.BrainrotIdMap[modelData.configId]
			if not brainrotData then
				return
			end

			local cost = GameConfig.GetBrainrotUpgradeCost(brainrotData.baseAbility, modelData.level)
			local currentGold = playerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
			if currentGold < cost then
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.InsufficientCoin.key)
				return
			end

			NetMsg.FireRequestUpgradeModel(pointIndex)
		else
			-- 3. 出售请求
			NetMsg.FireRequestSellModel(pointIndex)
		end
	end
end

function HomeClientManager.Init()
	local isWelded = replicatedStorage:FindFirstChild("BrainrotModelsWelded")
	if not isWelded then
		isWelded = replicatedStorage:WaitForChild("BrainrotModelsWelded", 10)
	end
	if isWelded and not (isWelded :: BoolValue).Value then
		(isWelded :: BoolValue):GetPropertyChangedSignal("Value"):Wait()
	end

	local function UpdateLocalHoldingBrainrotStatus()
		local char = players.LocalPlayer.Character
		local holding = false
		if char then
			local carry = char:FindFirstChild("CarryingBrainrot")
			if carry then
				if carry:GetAttribute("BrainrotUID") and carry:GetAttribute("ItemType") ~= 2 then
					holding = true
				end
			else
				local tool = char:FindFirstChildOfClass("Tool")
				if tool and tool:GetAttribute("BrainrotUID") and tool:GetAttribute("ItemType") ~= 2 then
					holding = true
				end
			end
		end

		if isLocalHoldingBrainrot ~= holding then
			isLocalHoldingBrainrot = holding
			-- Refresh own home slot if active
			local localInfo = ClientGameInfo.GetLocalPlayerInfo()
			if localInfo and localInfo.homeSlot and localInfo.homeSlot ~= "" then
			--	print("[HomeClientManager] Refreshing interaction prompts for slot", localInfo.homeSlot)
				UpdateHomePrompts(localInfo.homeSlot)
			end
		end
	end

	players.LocalPlayer.CharacterAdded:Connect(function(char)
		UpdateLocalHoldingBrainrotStatus()
		char.ChildAdded:Connect(UpdateLocalHoldingBrainrotStatus)
		char.ChildRemoved:Connect(UpdateLocalHoldingBrainrotStatus)
	end)
	if players.LocalPlayer.Character then
		UpdateLocalHoldingBrainrotStatus()
		players.LocalPlayer.Character.ChildAdded:Connect(UpdateLocalHoldingBrainrotStatus)
		players.LocalPlayer.Character.ChildRemoved:Connect(UpdateLocalHoldingBrainrotStatus)
	end

	RefreshAllHomes()
	proximityPromptService.PromptTriggered:Connect(OnPromptTriggered)

	-- Monitor for streaming / replication of parts
	for _, child in ipairs(homesFolder:GetChildren()) do
		if child.Name:match("^Player%d+$") then
			child.DescendantAdded:Connect(function()
				ScheduleSlotUpdate(child.Name)
			end)
		end
	end
	homesFolder.ChildAdded:Connect(function(child)
		if child.Name:match("^Player%d+$") then
			child.DescendantAdded:Connect(function()
				ScheduleSlotUpdate(child.Name)
			end)
			ScheduleSlotUpdate(child.Name)
		end
	end)

	NetMsg.ConnectNotifyPlayerInfoInit(function()
		RefreshAllHomes()
	end)

	NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(function(playerId)
		task.wait()
		local otherInfo = ClientGameInfo.GetOtherPlayerInfo(playerId)
		if otherInfo and otherInfo.homeSlot and otherInfo.homeSlot ~= "" then
			slotStateCache[otherInfo.homeSlot] = { active = true, homeInfo = otherInfo.homeInfo, isLocalPlayer = false }
			ApplySlotVisuals(otherInfo.homeSlot)
		end
	end)

	ClientMsg.ConnectPlayerHomeInfoUpdate(function(playerId, homeSlot, newHomeInfo)
		local isLocal = (playerId == players.LocalPlayer.UserId)
		slotStateCache[homeSlot] = { active = true, homeInfo = newHomeInfo, isLocalPlayer = isLocal }
		ApplySlotVisuals(homeSlot)
	end)

	ClientMsg.ConnectAllPlayersModelYieldsUpdate(function(allYields)
		for playerIdStr, yields in pairs(allYields) do
			local playerId = tonumber(playerIdStr)
			if not playerId then
				continue
			end

			local playerInfo = if playerId == players.LocalPlayer.UserId
				then ClientGameInfo.GetLocalPlayerInfo()
				else ClientGameInfo.GetOtherPlayerInfo(playerId)

			if not playerInfo then
				continue
			end

			-- 更新视图表现
			local homeSlot = playerInfo.homeSlot
			local slotModel = homesFolder:FindFirstChild(homeSlot)
			if slotModel then
				for pointIndexStr, amount in pairs(yields) do
					local plot: Instance? = nil
					-- Search across all floors (Lv1, Lv2, Lv3...)
					for _, floor in ipairs(slotModel:GetChildren()) do
						if floor.Name:match("^Lv%d+$") then
							plot = floor:FindFirstChild("PlaceModel" .. pointIndexStr)
							if plot then
								break
							end
						end
					end

					if plot then
						-- 1. 更新数据缓存 (使其在 ApplySlotVisuals 调用时能拿到最新值)
						if playerInfo.homeInfo and playerInfo.homeInfo.placedModels then
							local pData = playerInfo.homeInfo.placedModels[pointIndexStr]
							if pData then
								pData.unclaimedYield = amount
							end
						end

						local booth = plot:FindFirstChild("Booth")
						local collectPart = booth and booth:FindFirstChild("CollectPart")
						local collectUI = collectPart and collectPart:FindFirstChild("CollectUI") :: SurfaceGui?
						if collectUI then
							local isOccupied = playerInfo.homeInfo.placedModels[pointIndexStr] ~= nil
							collectUI.Enabled = true -- 始终显示
							local controller = collectUI:FindFirstChild("ControllerFrame")
							local collectText = controller and controller:FindFirstChild("CollectText") :: TextLabel?
							local coinImg = controller and controller:FindFirstChild("CoinImg") :: GuiObject?
							if collectText then
								collectText.Visible = isOccupied
								if isOccupied then
									collectText.Text = NumberExtension.FormatBigNumberAA(amount)
								end
							end
							if coinImg then
								coinImg.Visible = isOccupied
							end
						end
					end
				end
			end
		end
	end)
end

-- All UI scaling is now handled by BillboardManager

return HomeClientManager
