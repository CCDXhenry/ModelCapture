--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer
if localPlayer == nil then
	warn("[GuideFrame] LocalPlayer is nil at module load")
end
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local tweenService: TweenService = game:GetService("TweenService")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local guideFrame: Frame = script.Parent
guideFrame.AnchorPoint = Vector2.new(0.5, 0.5)

local fingerImage: ImageLabel = guideFrame:WaitForChild("FingerImage") :: ImageLabel
local fingerImageScale: UIScale = fingerImage:WaitForChild("UIScale") :: UIScale
local operationTypeValue: IntValue = guideFrame:WaitForChild("OperationType") :: IntValue

local FINGER_PULSE_MIN_SCALE = 0.78
local FINGER_PULSE_TWEEN_INFO: TweenInfo =
	TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FINGER_CLONE_NAME = "GuideFingerClone"
local FINGER_ZINDEX_BOOST = 50

local fingerPulseTween: Tween? = nil
local fingerClone: ImageLabel? = nil

local function StopGuideAni()
	if fingerPulseTween ~= nil then
		fingerPulseTween:Cancel()
		fingerPulseTween = nil
	end
	if fingerClone ~= nil then
		fingerClone:Destroy()
		fingerClone = nil
	end
	fingerImage.Visible = false
	fingerImageScale.Scale = 1
end

local function StartPulseOnScale(scaleObj: UIScale)
	if fingerPulseTween ~= nil then
		fingerPulseTween:Cancel()
		fingerPulseTween = nil
	end
	scaleObj.Scale = 1
	fingerPulseTween = tweenService:Create(scaleObj, FINGER_PULSE_TWEEN_INFO, { Scale = FINGER_PULSE_MIN_SCALE })
	fingerPulseTween:Play()
end

-- 将 FingerImage 克隆到 target 子级，在目标局部中心做缩放动画
local function MountFingerCloneUnder(target: GuiObject)
	StopGuideAni()
	local clone = fingerImage:Clone()
	clone.Name = FINGER_CLONE_NAME
	clone.Visible = true
	--clone.AnchorPoint = Vector2.new(0.5, 0.5)
	--clone.Position = UDim2.fromScale(0.5, 0.5)
	clone.ZIndex = target.ZIndex + FINGER_ZINDEX_BOOST
	clone.Parent = target
	fingerImage.Visible = false
	fingerClone = clone
	local scale = clone:WaitForChild("UIScale") :: UIScale
	StartPulseOnScale(scale)
end

local function IsGuiVisibleChain(gui: GuiObject): boolean
	local current: Instance? = gui
	while current ~= nil and current:IsA("GuiObject") do
		if not (current :: GuiObject).Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- BottomButtonsFrame 下仅 Brainrot 槽位可引导去放置展台：按队列找第一个 Brainrot 对应的 Slot_i
local function FindLobbyBrainrotSlotButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local screenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
	if screenGui == nil then
		return nil
	end
	local lobby = screenGui:FindFirstChild("LobbyFrame") :: Frame?
	if lobby == nil then
		return nil
	end
	local bottom = lobby:FindFirstChild("BottomButtonsFrame") :: Frame?
	if bottom == nil then
		return nil
	end
	local queue = ClientGameInfo.GetBrainrotQueue()
	for i, item in ipairs(queue) do
		if (item.itemType or GameConfig.ItemType.Brainrot) ~= GameConfig.ItemType.Brainrot then
			continue
		end
		local byName = bottom:FindFirstChild("Slot_" .. i)
		if byName and byName:IsA("GuiButton") then
			return byName
		end
		for _, child in bottom:GetChildren() do
			if child:IsA("GuiButton") then
				local slotIndex = child:GetAttribute("slotIndex") :: number?
				if slotIndex == i then
					return child :: GuiButton
				end
			end
		end
	end
	return nil
end

local function FindLobbyAddButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local screenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
	if screenGui == nil then
		return nil
	end
	local lobby = screenGui:FindFirstChild("LobbyFrame") :: Frame?
	if lobby == nil then
		return nil
	end
	local maxBricks = lobby:FindFirstChild("MaxBricksFrame") :: Frame?
	if maxBricks == nil then
		return nil
	end
	local btn = maxBricks:FindFirstChild("AddButton")
	if btn and btn:IsA("GuiButton") then
		return btn
	end
	return nil
end

local function FindUpgradeShopMaxBricksButton(): GuiButton?
	if localPlayer == nil then
		return nil
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui == nil then
		return nil
	end
	local screenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
	if screenGui == nil then
		return nil
	end
	local shopFrame = screenGui:FindFirstChild("UpgradeShopFrame", true) :: Frame?
	if shopFrame == nil then
		return nil
	end
	local scroll = shopFrame:FindFirstChild("ScrollingFrame") :: ScrollingFrame?
	if scroll == nil then
		return nil
	end
	local row = scroll:FindFirstChild("UpgradeMaxBricksFrame1") :: Frame?
	if row == nil then
		return nil
	end
	local imgBtn = row:FindFirstChild("ImageButton")
	if imgBtn and imgBtn:IsA("GuiButton") then
		return imgBtn
	end
	return nil
end

local function RefreshGuideFrame()
	if localPlayer == nil then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo == nil then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	local guideType = ClientGameInfo.GetCurrentGuideType()
	if guideType == GameConfig.GuideType.None then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	operationTypeValue.Value = guideType

	if guideType == GameConfig.GuideType.TutorialBrainrotPickup then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotPlace then
		guideFrame.Visible = false
		StopGuideAni()
		return
	end

	if guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		local slotBtn = FindLobbyBrainrotSlotButton()
		if slotBtn == nil or not IsGuiVisibleChain(slotBtn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(slotBtn)
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialBricksLobby then
		local btn = FindLobbyAddButton()
		if btn == nil or not IsGuiVisibleChain(btn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(btn)
		guideFrame.Visible = false
		return
	end

	if guideType == GameConfig.GuideType.TutorialBricksShop then
		local btn = FindUpgradeShopMaxBricksButton()
		if btn == nil or not IsGuiVisibleChain(btn) then
			guideFrame.Visible = false
			StopGuideAni()
			return
		end
		MountFingerCloneUnder(btn)
		guideFrame.Visible = false
		return
	end

	guideFrame.Visible = false
	StopGuideAni()
end

guideFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not guideFrame.Visible then
		-- 砖块引导时手指克隆在按钮子级，仅隐藏 guideFrame，不能销毁克隆
		local t = ClientGameInfo.GetCurrentGuideType()
		if t == GameConfig.GuideType.TutorialBricksLobby
			or t == GameConfig.GuideType.TutorialBricksShop
			or t == GameConfig.GuideType.TutorialBrainrotPlaceSlot
		then
			return
		end
		StopGuideAni()
	end
end)

ClientMsg.ConnectLocalPlayerInfoInit(function()
	RefreshGuideFrame()
end)

ClientMsg.ConnectCurrentGuideTypeChanged(function()
	RefreshGuideFrame()
end)

local function UpdateFingerOnTrackedButton(resolveButton: () -> GuiButton?)
	local btn = resolveButton()
	if btn == nil or not IsGuiVisibleChain(btn) then
		return
	end
	if fingerClone == nil or fingerClone.Parent ~= btn then
		MountFingerCloneUnder(btn)
	end
end

runService.RenderStepped:Connect(function()
	if localPlayer == nil then
		return
	end
	local t = ClientGameInfo.GetCurrentGuideType()
	if t == GameConfig.GuideType.TutorialBricksLobby or t == GameConfig.GuideType.TutorialBricksShop then
		UpdateFingerOnTrackedButton(function()
			if t == GameConfig.GuideType.TutorialBricksLobby then
				return FindLobbyAddButton()
			end
			return FindUpgradeShopMaxBricksButton()
		end)
	elseif t == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		UpdateFingerOnTrackedButton(FindLobbyBrainrotSlotButton)
	end
end)

RefreshGuideFrame()
