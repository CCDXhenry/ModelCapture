--!strict
-- BackpackFrame.local.luau
-- 负责渲染 Brainrot 背包队列 UI (现已迁移至 LobbyFrame.BottomButtonsFrame)

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))
local BackpackInputManager = require(clientScripts:WaitForChild("BackpackInputManager"))

-- UI 引用
local localPlayer = players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local gameScreenGui = playerGui:WaitForChild("GameScreenGui")
local lobbyFrame = gameScreenGui:WaitForChild("LobbyFrame")
local bottomButtonsFrame: Frame = lobbyFrame:WaitForChild("BottomButtonsFrame") :: Frame
local toolButtonTemplate: ImageButton = bottomButtonsFrame:WaitForChild("ToolButton") :: ImageButton
toolButtonTemplate.Visible = false

-- 常量
local NormalSlotColor: Color3 = Color3.fromRGB(20, 20, 30)
local EquippedSlotColor: Color3 = Color3.fromRGB(40, 35, 10)
local SlotTweenInfo: TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- 状态
local activeSlots: { ImageButton } = {}
local currentEquippedIndex: number = 0

-- 获取手持 Tool 的 UID
local function GetEquippedUid(): string?
	local character = localPlayer.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child:GetAttribute("BrainrotUID")
		end
	end
	return nil
end

-- 根据 ConfigId 获取图标
local function GetIconForConfigId(configId: number, itemType: number?): string
	local typeVal = itemType or GameConfig.ItemType.Brainrot
	if typeVal == GameConfig.ItemType.Coil then
		local coilConfig = GameConfig.CoilIdMap[configId]
		if coilConfig and coilConfig.iconImageId and coilConfig.iconImageId ~= "" then
			return coilConfig.iconImageId
		end
		-- Default icon for coils if missing
		return "rbxassetid://16865598960"
	else
		local brainrotConfig = GameConfig.BrainrotIdMap[configId]
		if brainrotConfig and brainrotConfig.iconImageId and brainrotConfig.iconImageId ~= "" then
			return brainrotConfig.iconImageId
		end
	end
	return "rbxassetid://0"
end

-- 根据 ConfigId 获取名称
local function GetNameForConfigId(configId: number, itemType: number?): string
	local typeVal = itemType or GameConfig.ItemType.Brainrot
	if typeVal == GameConfig.ItemType.Coil then
		local coilConfig = GameConfig.CoilIdMap[configId]
		if coilConfig then
			return coilConfig.name_t or "???"
		end
	else
		local brainrotConfig = GameConfig.BrainrotIdMap[configId]
		if brainrotConfig then
			return brainrotConfig.name_t or "???"
		end
	end
	return "???"
end

-- 根据 ConfigId 获取线圈描述
local function GetCoilDescription(configId: number): string
	local coilConfig = GameConfig.CoilIdMap[configId]
	if coilConfig and coilConfig.description and coilConfig.description ~= "" then
		return coilConfig.description
	end
	return ""
end

-- 获取分辨色
local function GetQualityColor(quality: number): Color3
	local qualityCfg = GameConfig.BrainrotQualityConfig[quality]
	if qualityCfg then
		return qualityCfg.textColor
	end
	return Color3.fromRGB(255, 255, 255)
end

local function GetDisplayQuality(item: GameConfig.BrainrotQueueItem): number
	local typeVal = item.itemType or GameConfig.ItemType.Brainrot
	if typeVal == GameConfig.ItemType.Coil then
		local coilConfig = GameConfig.CoilIdMap[item.configId]
		if coilConfig and coilConfig.quality then
			return coilConfig.quality
		end
	end
	return item.quality
end

-- 创建一个格子
local function CreateSlot(index: number, item: GameConfig.BrainrotQueueItem): ImageButton
	local slot = toolButtonTemplate:Clone()
	slot.Name = "Slot_" .. index
	slot.LayoutOrder = index
	slot.Visible = true
	
	local toolNameText = slot:FindFirstChild("ToolNameText") :: TextLabel
	local toolLvText = slot:FindFirstChild("ToolLvText") :: TextLabel
	local keyCodeText = slot:FindFirstChild("KeyCodeText") :: TextLabel
	local toolIconImage = slot:FindFirstChild("ToolIconImage") :: ImageLabel
	local qualityImage = slot:FindFirstChild("QualityImage") :: ImageLabel
	local equippedImage = slot:FindFirstChild("EquippedImage") :: ImageLabel
	local toolUsageEffectFrame = slot:FindFirstChild("ToolUsageEffectFrame") :: Frame?
	local toolUsageEffectText = if toolUsageEffectFrame then (toolUsageEffectFrame:FindFirstChild("ToolUsageEffectText") :: TextLabel?) else nil
	local isCoil = (item.itemType or GameConfig.ItemType.Brainrot) == GameConfig.ItemType.Coil

	-- 设置图标
	if toolIconImage then
		toolIconImage.Image = GetIconForConfigId(item.configId, item.itemType)
	end
	
	-- 设置名称
	if toolNameText then
		toolNameText.Text = GetNameForConfigId(item.configId, item.itemType)
		local qualityColor = GetQualityColor(GetDisplayQuality(item))
		toolNameText.TextColor3 = qualityColor
	end
	
	-- 设置等级
	if toolLvText then
		local typeVal = item.itemType or GameConfig.ItemType.Brainrot
		if typeVal == GameConfig.ItemType.Coil then
			toolLvText.Text = ""
		else
			toolLvText.Text = "Lv." .. tostring(item.level or 1)
		end
	end

	-- 设置数字索引
	if keyCodeText then
		keyCodeText.Text = tostring(index)
	end
	
	-- 设置品质背景颜色
	if qualityImage then
		qualityImage.ImageColor3 = GetQualityColor(GetDisplayQuality(item))
	end
	
	-- 初始化选中框
	if equippedImage then
		equippedImage.Visible = false
	end

	-- 初始化悬浮描述框
	if toolUsageEffectFrame then
		toolUsageEffectFrame.Visible = false
	end
	if toolUsageEffectText then
		toolUsageEffectText.Text = if isCoil then GetCoilDescription(item.configId) else ""
	end

	-- 存储 uid和索引
	slot:SetAttribute("uid", item.uid)
	slot:SetAttribute("slotIndex", index)
	slot.Parent = bottomButtonsFrame
	
	-- 点击事件 (点击格子装备/卸装)
	slot.Activated:Connect(function()
		BackpackInputManager.ToggleTool(index)
	end)

	slot.MouseEnter:Connect(function()
		if not isCoil then
			return
		end
		if toolUsageEffectFrame then
			toolUsageEffectFrame.Visible = true
		end
	end)

	slot.MouseLeave:Connect(function()
		if toolUsageEffectFrame then
			toolUsageEffectFrame.Visible = false
		end
	end)
	
	return slot
end

-- 刷新每帧状态 (自动高亮)
local function OnRenderStepped()
	local equippedUid = GetEquippedUid()
	local foundIndex = 0
	
	for i, slot in ipairs(activeSlots) do
		local uid = slot:GetAttribute("uid")
		local isEquipped = (uid ~= nil and uid == equippedUid)
		if isEquipped then
			foundIndex = i
		end
		
		local equippedImage = slot:FindFirstChild("EquippedImage") :: ImageLabel?
		if equippedImage then
			if equippedImage.Visible ~= isEquipped then
				equippedImage.Visible = isEquipped
				-- 只有变化时才播放背景动画，节省开销
				tweenService:Create(slot, SlotTweenInfo, {
					BackgroundColor3 = if isEquipped then EquippedSlotColor else NormalSlotColor,
				}):Play()
			end
		end
	end
	
	currentEquippedIndex = foundIndex
end

-- 刷新整个背包 UI
local function RefreshBackpackUI(queue: { GameConfig.BrainrotQueueItem })
	-- 清除旧格子
	for _, slot in ipairs(activeSlots) do
		slot:Destroy()
	end
	activeSlots = {}
	currentEquippedIndex = 0

	-- 创建新格子
	for i, item in ipairs(queue) do
		local slot = CreateSlot(i, item)
		table.insert(activeSlots, slot)
	end

	-- 显示/隐藏整个容器
	bottomButtonsFrame.Visible = #queue > 0
end

-- 公开接口：更新当前装备索引
local BackpackFrameManager = {}

function BackpackFrameManager.SetEquippedIndex(index: number)
	-- 现在主要靠自动检测，这里可作为强制更新状态的占位
	currentEquippedIndex = index
end

function BackpackFrameManager.GetEquippedIndex(): number
	return currentEquippedIndex
end

-- 把 Manager 挂到一个固定的地方供其他脚本访问
-- 由于 BackpackFrame UI 可能被移除，我们挂在 _G 或 LobbyFrame 上
lobbyFrame:SetAttribute("_backpackManagerRef", "BackpackFrameManager")

-- 监听背包更新
ClientMsg.ConnectBrainrotQueueUpdate(function(queue: { GameConfig.BrainrotQueueItem })
	RefreshBackpackUI(queue)
end)

-- 初始化：读取现有队列
ClientMsg.ConnectLocalPlayerInfoInit(function()
	local queue = ClientGameInfo.GetBrainrotQueue()
	RefreshBackpackUI(queue)
end)

-- 如果玩家信息已经初始化，直接刷新
local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo then
	RefreshBackpackUI(localPlayerInfo.brainrotQueue)
end

-- 将 Manager 暴露给 _G
_G.BackpackFrameManager = BackpackFrameManager

-- 绑定心跳检测
runService.RenderStepped:Connect(OnRenderStepped)

