--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClientScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Client")

local ClientGameInfo = require(ClientScripts:WaitForChild("ClientGameInfo"))
local ClientMsg = require(ClientScripts:WaitForChild("ClientMsg"))
local UIManager = require(ClientScripts:WaitForChild("UIManager"))

local ShopClientManager = {}

-- Removed unused getSkillData and getLevel

local function updatePrompts()
	local playerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not playerInfo then
		return
	end

	-- SellBrainrotPrompt logic removed from updatePrompts since it uses a UI now.
end

function ShopClientManager.Init()
	local upgradeShop = Workspace:WaitForChild("UpgradeShop", 10)
	if not upgradeShop then
		warn("UpgradeShop not found in Workspace")
		return
	end

	local rootPart = upgradeShop:WaitForChild("RootPart")

	local openShopAttachment = rootPart:WaitForChild("OpenShopAttachment", 5)
	if openShopAttachment then
		local prom = openShopAttachment:WaitForChild("ProximityPrompt") :: ProximityPrompt
		prom.Triggered:Connect(function()
			UIManager.OpenWindow(UIManager.WindowId.UpgradeShop)
		end)
	else
		warn("OpenShopAttachment not found in UpgradeShop/RootPart")
	end

	-- Robust SellShop initialization
	task.spawn(function()
		local sellShop = nil
		while not sellShop do
			sellShop = Workspace:FindFirstChild("SellShop")
			if not sellShop then
				task.wait(1)
			end
		end

		local sellRootPart = nil
		while not sellRootPart do
			sellRootPart = sellShop:FindFirstChild("rootpart") or sellShop:FindFirstChild("RootPart") or sellShop.PrimaryPart
			if not sellRootPart then
				task.wait(1)
			end
		end

		local openSellAttachment = nil
		while not openSellAttachment do
			openSellAttachment = sellRootPart:FindFirstChild("OpenShopAttachment")
			if not openSellAttachment then
				task.wait(1)
			end
		end

		local sellShopProm = openSellAttachment:WaitForChild("ProximityPrompt", 10) :: ProximityPrompt?
		if sellShopProm then
			sellShopProm.Triggered:Connect(function()
				UIManager.OpenWindow(UIManager.WindowId.SellShop)
			end)
		end
	end)

	-- Listen for character changes to update SellBrainrotPrompt
	local function onCharacter(char: Model)
		local function update()
			updatePrompts()
		end
		char.ChildAdded:Connect(update)
		char.ChildRemoved:Connect(update)
		update()
	end
	game.Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if game.Players.LocalPlayer.Character then
		onCharacter(game.Players.LocalPlayer.Character)
	end

	-- Listen for data changes to update ActionText
	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function(skillType, level)
		updatePrompts()
	end)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		updatePrompts()
	end)

	-- Initial update
	updatePrompts()
end

return ShopClientManager
