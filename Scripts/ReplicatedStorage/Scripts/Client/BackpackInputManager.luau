--!strict
-- BackpackInputManager
-- 监听数字键 1-9，切换手持 Brainrot

local BackpackInputManager = {}

local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local localPlayer = players.LocalPlayer

-- 数字键映射
local KeyIndexMap: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

-- 获取当前装备的 Tool
local function GetEquippedTool(): Tool?
	local character = localPlayer.Character
	if not character then return nil end
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Tool") then
			return obj :: Tool
		end
	end
	return nil
end

-- 切换指定索引的 Tool
function BackpackInputManager.ToggleTool(index: number)
	local character = localPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then return end

	local queue = ClientGameInfo.GetBrainrotQueue()
	if not queue or not queue[index] then return end

	local targetItem = queue[index]
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	-- 在 Backpack 或 Character 中找对应 UID 的 Tool
	local targetTool: Tool? = nil
	local searchTargets = { backpack, character }
	for _, container in ipairs(searchTargets) do
		if targetTool then break end
		for _, obj in ipairs(container:GetChildren()) do
			if obj:IsA("Tool") and obj:GetAttribute("BrainrotUID") == targetItem.uid then
				targetTool = obj :: Tool
				break
			end
		end
	end

	if not targetTool then
		warn("[BackpackInputManager] No Tool found for uid", targetItem.uid, "at index", index)
		return
	end

	-- 判断是否已装备
	local equippedTool = GetEquippedTool()
	if equippedTool == targetTool then
		-- 已装备 -> 卸装
		humanoid:UnequipTools()
		if _G.BackpackFrameManager then
			(_G.BackpackFrameManager :: any).SetEquippedIndex(0)
		end
	else
		-- 装备目标 Tool
		humanoid:EquipTool(targetTool)
		if _G.BackpackFrameManager then
			(_G.BackpackFrameManager :: any).SetEquippedIndex(index)
		end
	end
end

local inputDebounceTime = 0.2
local lastInputTime = 0

function BackpackInputManager.Init()
	pcall(function()
		local starterGui = game:GetService("StarterGui")
		starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		local index = KeyIndexMap[input.KeyCode]
		if index then
			local now = tick()
			if now - lastInputTime < inputDebounceTime then return end
			lastInputTime = now
			
			BackpackInputManager.ToggleTool(index)
		end
	end)
	--print("[BackpackInputManager] Initialized, listening keys 1-9 with debounce")
end

return BackpackInputManager
