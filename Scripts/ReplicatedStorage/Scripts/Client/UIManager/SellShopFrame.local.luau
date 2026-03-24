local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")

local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientMsg = require(clientScripts:WaitForChild("ClientMsg"))
local UIManager = require(clientScripts:WaitForChild("UIManager"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local thisFrame = script.Parent :: BillboardGui
local windowId = thisFrame:GetAttribute("WindowId") :: string

thisFrame.AlwaysOnTop = true

local controllerFrame = thisFrame:WaitForChild("ControllerFrame") :: Frame
local uiScale = controllerFrame:FindFirstChildOfClass("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Parent = controllerFrame
end

local rowFrame1 = controllerFrame:WaitForChild("RowFrame1") :: Frame
local sellButton = rowFrame1:WaitForChild("ImageButton") :: ImageButton

local rowFrame2 = controllerFrame:WaitForChild("RowFrame2") :: Frame
local closeButton = rowFrame2:WaitForChild("ImageButton") :: ImageButton

local player = game.Players.LocalPlayer
local camera = Workspace.CurrentCamera

local sellShopModel = Workspace:FindFirstChild("SellShop") :: Model?
local rootPart = nil

if sellShopModel then
	rootPart = sellShopModel:FindFirstChild("RootPart") or sellShopModel:FindFirstChild("rootpart") or sellShopModel.PrimaryPart
end

-- Button Hover Effects
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function ApplyHoverEffect(button: ImageButton)
	local originalPosition = button.Position
	local originalColor = button.ImageColor3
	local hoverColor = Color3.new(originalColor.R * 0.8, originalColor.G * 0.8, originalColor.B * 0.8)
	local hoverPosition = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset + 10, originalPosition.Y.Scale, originalPosition.Y.Offset)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO, {
			Position = hoverPosition,
			ImageColor3 = hoverColor
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_INFO, {
			Position = originalPosition,
			ImageColor3 = originalColor
		}):Play()
	end)
end

ApplyHoverEffect(sellButton)
ApplyHoverEffect(closeButton)

-- Open/Close buttons logic
closeButton.Activated:Connect(function()
	UIManager.CloseWindow(windowId)
end)

sellButton.Activated:Connect(function()
	local character = player.Character
	if not character then return end
	local carryingBrainrot = character:FindFirstChild("CarryingBrainrot")
	local equippedTool = character:FindFirstChildOfClass("Tool")
	
	if not carryingBrainrot and not (equippedTool and equippedTool:GetAttribute("BrainrotUID")) then
		ClientMsg.FireShowGameTip(GameTexts.InsufficientBrainrot.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.InsufficientBrainrot.key)
		return
	end

	NetMsg.FireRequestSellCarryingBrainrot()
	UIManager.CloseWindow(windowId)
end)

local function OnCloseWindow(id: string)
	if id == windowId then
		BillboardManager.Untrack(thisFrame)
		thisFrame:Destroy()
	end
end
ClientMsg.ConnectCloseWindow(OnCloseWindow)


-- Track the UI for adaptive scaling
BillboardManager.Track(thisFrame)

-- Handle Proxy Attachment for positioning
local proxyAttachment = nil

-- RenderStepped to update UI position and check distance
local connection = RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		return
	end

	local charPrimary = character.PrimaryPart
	if not charPrimary then
		return
	end

	-- Close window if too far from SellShop
	if rootPart then
		local distance = (charPrimary.Position - rootPart.Position).Magnitude
		if distance > 15 then -- Close distance threshold
			UIManager.CloseWindow(windowId)
			return
		end
	end

	-- Create or handle proxy attachment for stable pinning
	if not proxyAttachment or proxyAttachment.Parent ~= charPrimary then
		proxyAttachment = charPrimary:FindFirstChild("SellShopUI_Attachment") :: Attachment?
		if not proxyAttachment then
			proxyAttachment = Instance.new("Attachment")
			proxyAttachment.Name = "SellShopUI_Attachment"
			proxyAttachment.Parent = charPrimary
		end
		thisFrame.Adornee = proxyAttachment
	end

	-- Logic to keep it on the "right side" of the character relative to CAMERA perspective
	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector

	-- Update attachment local position to keep it 6 studs right and 0.5 up from character center
	-- from the player's camera view.
	proxyAttachment.Position = charPrimary.CFrame:VectorToObjectSpace(right * 6 + up * 0.5)
end)

thisFrame.Destroying:Connect(function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if proxyAttachment then
		proxyAttachment:Destroy()
	end
	BillboardManager.Untrack(thisFrame)
end)

