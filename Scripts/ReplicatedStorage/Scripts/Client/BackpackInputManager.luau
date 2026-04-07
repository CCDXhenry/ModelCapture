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

-- 设为 true 时在找不到 Tool 时输出 warn（复制延迟等导致的短暂缺失为预期情况）
local DebugLogMissingTool = false

local ToolLookupRetryCount = 4
local ToolLookupRetryDelaySec = 0.05

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
	if not character then
		return nil
	end
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Tool") then
			return obj :: Tool
		end
	end
	return nil
end

local function FindToolByUid(uid: string, backpack: Backpack, character: Model): Tool?
	for _, container in ipairs({ backpack, character }) do
		for _, obj in ipairs(container:GetChildren()) do
			if obj:IsA("Tool") and obj:GetAttribute("BrainrotUID") == uid then
				return obj :: Tool
			end
		end
	end
	return nil
end

local function IsCarryingUid(character: Model, uid: string): boolean
	local carrying = character:FindFirstChild("CarryingBrainrot")
	return carrying ~= nil and carrying:GetAttribute("BrainrotUID") == uid
end

-- 切换指定索引的 Tool
function BackpackInputManager.ToggleTool(index: number)
	local character = localPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local queue = ClientGameInfo.GetBrainrotQueue()
	if not queue or not queue[index] then
		return
	end

	local targetItem = queue[index]
	if IsCarryingUid(character, targetItem.uid) then
		return
	end

	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local targetTool: Tool? = nil
	for attempt = 1, ToolLookupRetryCount do
		targetTool = FindToolByUid(targetItem.uid, backpack, character)
		if targetTool then
			break
		end
		if attempt < ToolLookupRetryCount then
			task.wait(ToolLookupRetryDelaySec)
		end
	end

	if not targetTool then
		if DebugLogMissingTool then
			warn("[BackpackInputManager] No Tool found for uid", targetItem.uid, "at index", index)
		end
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
		if gameProcessed then
			return
		end
		local index = KeyIndexMap[input.KeyCode]
		if index then
			local now = tick()
			if now - lastInputTime < inputDebounceTime then
				return
			end
			lastInputTime = now

			BackpackInputManager.ToggleTool(index)
		end
	end)
	--print("[BackpackInputManager] Initialized, listening keys 1-9 with debounce")
end

return BackpackInputManager
