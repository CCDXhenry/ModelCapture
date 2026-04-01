--!strict
local UIManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UserInutExtension = require(coreClientScripts:FindFirstChild("UserInutExtension"))
local uiOriginsFolder: Folder = replicatedStorage:FindFirstChild("UI") :: Folder
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local GameSoundManager = require(clientScripts:FindFirstChild("GameSoundManager"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")

local ModalTransparency = 0.3
local ButtonHoveredScale: number = 1.1 --按钮鼠标移入放大
local ButtonPressedScale: number = 0.9 --按钮按下缩小
local ButtonInteractionTweenInfo: TweenInfo = TweenInfo.new(0.1) --按钮交互动画缓动信息

UIManager.WindowId = {
	UpgradeShop = "UpgradeShopFrame",
	SellShop = "SellShopFrame",
	Rebirth = "RebirthFrame",
	StoreBundle = "StoreBundleFrame",
}

type WindowConfig = {
	FrameName: string,
	scriptName: string,
	isModal: boolean,
}
local WindowConfigs: { [string]: WindowConfig } = {
	[UIManager.WindowId.UpgradeShop] = {
		FrameName = "UpgradeShopFrame",
		scriptName = "UpgradeShopFrame",
		isModal = true,
	},
	[UIManager.WindowId.SellShop] = {
		FrameName = "SellShopFrame",
		scriptName = "SellShopFrame",
		isModal = false,
	},
	[UIManager.WindowId.Rebirth] = {
		FrameName = "RebirthFrame",
		scriptName = "RebirthFrame",
		isModal = true,
	},
	[UIManager.WindowId.StoreBundle] = {
		FrameName = "StoreBundleFrame",
		scriptName = "StoreBundleFrame",
		isModal = true,
	},
}

local addedWindows: { [string]: GuiBase2d? } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton

local function CheckModalButtonVisible()
	local topModalWindow: GuiBase2d?
	for windowId, window in addedWindows do
		if not window then continue end
		local config = WindowConfigs[windowId]
		if config.isModal then
			if topModalWindow == nil then
				topModalWindow = window
			else
				-- Compare ZIndex if both are GuiObjects, otherwise heuristic
				local currentZ = if window:IsA("GuiObject") then window.ZIndex else 0
				local topZ = if (topModalWindow :: any):IsA("GuiObject") then (topModalWindow :: any).ZIndex else 0
				if currentZ > topZ then
					topModalWindow = window
				end
			end
		end
	end
	if topModalWindow == nil then
		modalButton.Visible = false
	else
		modalButton.Visible = true
		if (topModalWindow :: any):IsA("GuiObject") then
			modalButton.ZIndex = (topModalWindow :: any).ZIndex - 1
		end
	end
end

--给按钮加点击和悬停缩放效果
local function ApplyButtonEffects(button: GuiButton)
	--如果按钮不需要交互效果
	if not button:GetAttribute("HasInteractionEffect") then
		return
	end
	--确保按钮有UIScale
	local uiScale: UIScale? = button:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		return
	end
	local normalScale: number = uiScale.Scale
	local hoveredScale: number = ButtonHoveredScale * normalScale
	local pressedScale: number = ButtonPressedScale * normalScale
	local mouseEnterTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = hoveredScale })
	local mouseLeaveTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local clickTween1: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = pressedScale })
	local clickTween2: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	clickTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
		clickTween2:Play()
	end)
	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		local inputTypeString: string?, _: Enum.UserInputType = UserInutExtension.GetInputType()
		if inputTypeString == UserInutExtension.InputTypeString.Keyboard_Mouse then
			mouseEnterTween:Play()
		end
	end)
	button.MouseLeave:Connect(function()
		local inputTypeString: string?, _: Enum.UserInputType = UserInutExtension.GetInputType()
		if inputTypeString == UserInutExtension.InputTypeString.Keyboard_Mouse then
			mouseLeaveTween:Play()
		end
	end)
	button.Activated:Connect(function(inputObject: InputObject, clickCount: number)
		clickTween1:Play()
	end)
end

local function ApplyButtonClickSound(button: GuiButton)
	if button:GetAttribute("ButtonClickSoundBound") then
		return
	end
	button:SetAttribute("ButtonClickSoundBound", true)
	button.Activated:Connect(function()
		if button:GetAttribute("SkipButtonClickSound") then
			return
		end
		GameSoundManager.PlayButtonClickSound()
	end)
end
--专门给SurfaceGui或其他需要平滑状态过渡加背景变暗的按钮使用的特效
function UIManager.ApplySurfaceButtonEffects(button: GuiButton)
	local uiScale: UIScale = (button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")) :: UIScale
	if uiScale.Parent ~= button then
		uiScale.Parent = button
	end

	local normalScale: number = 1
	local hoveredScale: number = ButtonHoveredScale * normalScale
	local pressedScale: number = ButtonPressedScale * normalScale
	local smoothTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local normalBg = button.BackgroundColor3
	local hoveredBg = Color3.new(math.clamp(normalBg.R * 0.8, 0, 1), math.clamp(normalBg.G * 0.8, 0, 1), math.clamp(normalBg.B * 0.8, 0, 1))

	local isImage = button:IsA("ImageButton")
	local normalImg = isImage and (button :: ImageButton).ImageColor3 or Color3.new(1, 1, 1)
	local hoveredImg = Color3.new(math.clamp(normalImg.R * 0.8, 0, 1), math.clamp(normalImg.G * 0.8, 0, 1), math.clamp(normalImg.B * 0.8, 0, 1))

	local isHovering = false
	local isPressed = false

	local function UpdateState()
		local targetScale = normalScale
		local targetBg = normalBg
		local targetImg = normalImg

		if isPressed then
			targetScale = pressedScale
			targetBg = hoveredBg
			targetImg = hoveredImg
		elseif isHovering then
			targetScale = hoveredScale
			targetBg = hoveredBg
			targetImg = hoveredImg
		end

		tweenService:Create(uiScale, smoothTweenInfo, { Scale = targetScale }):Play()

		local colorProps: any = { BackgroundColor3 = targetBg }
		if isImage then
			colorProps.ImageColor3 = targetImg
		end
		tweenService:Create(button, smoothTweenInfo, colorProps):Play()
	end

	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		local inputTypeString = UserInutExtension.GetInputType()
		if inputTypeString == UserInutExtension.InputTypeString.Keyboard_Mouse then
			isHovering = true
			UpdateState()
		end
	end)

	button.MouseLeave:Connect(function()
		isHovering = false
		isPressed = false
		UpdateState()
	end)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isPressed = true
			UpdateState()
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isPressed = false
			UpdateState()
		end
	end)
end

local function ClampCanvasPosition(scrollingFrame: ScrollingFrame, targetCanvasPosition: Vector2): Vector2
	local scrollingDirection = scrollingFrame.ScrollingDirection
	local allowHorizontal = scrollingDirection == Enum.ScrollingDirection.X or scrollingDirection == Enum.ScrollingDirection.XY
	local maxX = if allowHorizontal then math.max(0, scrollingFrame.AbsoluteCanvasSize.X - scrollingFrame.AbsoluteWindowSize.X) else 0
	local maxY = math.max(0, scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y)
	return Vector2.new(math.clamp(targetCanvasPosition.X, 0, maxX), math.clamp(targetCanvasPosition.Y, 0, maxY))
end

function UIManager.BindScrollingFrameDragScroll(scrollingFrame: ScrollingFrame)
	if scrollingFrame:GetAttribute("DragScrollBound") then
		return
	end
	scrollingFrame:SetAttribute("DragScrollBound", true)
	scrollingFrame.ElasticBehavior = Enum.ElasticBehavior.Never

	local isDragging = false
	local dragInput: InputObject? = nil
	local dragStartPosition = Vector2.zero
	local canvasStartPosition = Vector2.zero

	local function StopDrag()
		isDragging = false
		dragInput = nil
	end

	local function UpdateDrag(currentInput: InputObject)
		if not isDragging then
			return
		end
		local currentPosition = Vector2.new(currentInput.Position.X, currentInput.Position.Y)
		local delta = currentPosition - dragStartPosition
		local targetCanvasPosition = canvasStartPosition - delta
		scrollingFrame.CanvasPosition = ClampCanvasPosition(scrollingFrame, targetCanvasPosition)
	end

	scrollingFrame.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end
		isDragging = true
		dragInput = input
		dragStartPosition = Vector2.new(input.Position.X, input.Position.Y)
		canvasStartPosition = scrollingFrame.CanvasPosition
	end)

	scrollingFrame.InputEnded:Connect(function(input: InputObject)
		if not isDragging then
			return
		end
		if dragInput == input then
			StopDrag()
		end
	end)

	userInputService.InputChanged:Connect(function(input: InputObject, _gameProcessedEvent: boolean)
		if not isDragging then
			return
		end
		if dragInput == nil then
			return
		end
		if dragInput.UserInputType == Enum.UserInputType.MouseButton1 then
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			UpdateDrag(input)
			return
		end
		if input == dragInput then
			UpdateDrag(input)
		end
	end)

	userInputService.InputEnded:Connect(function(input: InputObject, _gameProcessedEvent: boolean)
		if not isDragging then
			return
		end
		if dragInput == nil then
			return
		end
		if dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1 then
			StopDrag()
			return
		end
		if input == dragInput then
			StopDrag()
		end
	end)

	scrollingFrame.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			StopDrag()
		end
	end)
end

function UIManager.BindDragScrollForDescendants(root: Instance)
	if root:IsA("ScrollingFrame") then
		UIManager.BindScrollingFrameDragScroll(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ScrollingFrame") then
			UIManager.BindScrollingFrameDragScroll(descendant)
		end
	end
end

--初始化
function UIManager.Init(gameScreenGuiNew: ScreenGui)
	gameScreenGui = gameScreenGuiNew
	if gameScreenGui == nil then
		return
	end
	--模态按钮
	modalButton = Instance.new("ImageButton")
	modalButton.Name = "ModalButton"
	modalButton.Modal = true
	modalButton.BackgroundColor3 = Color3.new(0, 0, 0)
	modalButton.BackgroundTransparency = ModalTransparency
	modalButton.AutoButtonColor = false
	modalButton.Size = UDim2.fromScale(1, 1)
	modalButton.Parent = gameScreenGui
	modalButton.Visible = false
	--按钮交互效果
	local uiParents: { Instance } = { workspace, gameScreenGui }
	for uiParentIndex: number, uiParent: Instance in uiParents do
		uiParent.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
				ApplyButtonClickSound(descendant)
			end
			if descendant:IsA("ScrollingFrame") then
				UIManager.BindScrollingFrameDragScroll(descendant)
			end
		end)
		for descendantIndex: number, descendant: Instance in uiParent:GetDescendants() do
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
				ApplyButtonClickSound(descendant)
			end
			if descendant:IsA("ScrollingFrame") then
				UIManager.BindScrollingFrameDragScroll(descendant)
			end
		end
	end
end

--非窗口方式创建界面
function UIManager.CreateFrame(frameName: string, scriptName: string?, frameParent: GuiBase2d?, ZIndex: number?): GuiBase2d
	local frame = (uiOriginsFolder:FindFirstChild(frameName) :: GuiBase2d):Clone()
	if scriptName ~= nil then
		local frameScrip: LocalScript = script:FindFirstChild(scriptName):Clone()
		frameScrip.Parent = frame
	end
	if frameParent == nil then
		frame.Parent = if frame:IsA("BillboardGui") and gameScreenGui then gameScreenGui.Parent else gameScreenGui
	else
		frame.Parent = frameParent
	end
	UIManager.BindDragScrollForDescendants(frame)
	if ZIndex ~= nil and frame:IsA("GuiObject") then
		frame.ZIndex = ZIndex
	end
	return frame
end

--打开窗口
function UIManager.OpenWindow(windowId: string)
	if gameScreenGui == nil or gameScreenGui.Parent == nil then
		return
	end
	local window = addedWindows[windowId]
	if window == nil then
		local windowConfig: WindowConfig = WindowConfigs[windowId]
		local origin = uiOriginsFolder:FindFirstChild(windowConfig.FrameName)
		if not origin or not origin:IsA("GuiBase2d") then
			return
		end
		window = origin:Clone()
		if not window then
			return
		end
		-- Parent to PlayerGui if BillboardGui, otherwise ScreenGui
		window.Parent = if window:IsA("BillboardGui") then gameScreenGui.Parent else gameScreenGui
		UIManager.BindDragScrollForDescendants(window)
		window:SetAttribute("WindowId", windowId)
		local windowScriptOrigin = script:FindFirstChild(windowConfig.scriptName)
		if windowScriptOrigin then
			local windowScript = windowScriptOrigin:Clone()
			windowScript.Parent = window
		end
		addedWindows[windowId] = window
		local addedWindowCount: number = 0
		for _, _ in addedWindows do
			addedWindowCount += 1
		end
		if window:IsA("GuiObject") then
			window.ZIndex = 100 + addedWindowCount * 2
		end
		CheckModalButtonVisible()
	end
end

--窗口是否展示中
function UIManager.IsWindowShowing(windowId: string): boolean
	local window = addedWindows[windowId]
	return window ~= nil
end

--关闭窗口
function UIManager.CloseWindow(windowId: string)
	local window = addedWindows[windowId]
	if window then
		ClientMsg.FireCloseWindow(windowId)
		addedWindows[windowId] = nil
		CheckModalButtonVisible()
	end
end

--关闭所有窗口
function UIManager.CloseAllWindow()
	for windowId, window in pairs(addedWindows) do
		ClientMsg.FireCloseWindow(windowId)
	end
	table.clear(addedWindows)
	CheckModalButtonVisible()
end

return UIManager
