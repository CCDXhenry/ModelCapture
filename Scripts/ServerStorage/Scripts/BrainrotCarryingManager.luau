--!strict
local BrainrotCarryingManager = {}

local HttpService = game:GetService("HttpService")

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local brainrotIslandManagerRef: any? = nil

-- 用注入方式获取岛屿倒计时管理器，避免这里运行时 require 导致循环依赖
function BrainrotCarryingManager.SetBrainrotIslandManager(manager: any)
	brainrotIslandManagerRef = manager
end

function BrainrotCarryingManager.StartCarrying(player: Player, newBrainrot: Instance): Instance?
	local character = player.Character
	if not character then return nil end
	
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return nil end

	-- 替换机制：如果头上已经有，互换新旧模型坐标
	local oldCarrying = character:FindFirstChild("CarryingBrainrot") :: BasePart?
	local swapTargetCFrame: CFrame? = nil

	if oldCarrying then
		if newBrainrot:IsA("Model") and newBrainrot.PrimaryPart then
			swapTargetCFrame = newBrainrot:GetPivot()
		elseif newBrainrot:IsA("BasePart") then
			swapTargetCFrame = newBrainrot.CFrame
		end

		if swapTargetCFrame then
			local drop = oldCarrying:Clone()
			local itemType = drop:GetAttribute("ItemType") :: number?
			drop.Name = if itemType == GameConfig.ItemType.LittleElfChest then "IslandChest" else "IslandBrainrot"
			-- 移除身上绑定的约束
			for _, child in ipairs(drop:GetChildren()) do
				if child:IsA("WeldConstraint") or child:IsA("Motor6D") then
					child:Destroy()
				end
			end
			
			if drop:IsA("Model") then
				drop:PivotTo(swapTargetCFrame)
			elseif drop:IsA("BasePart") then
				drop.CFrame = swapTargetCFrame
			end
			
			drop.Parent = newBrainrot.Parent or workspace
			
			-- 恢复锚定，使其不会掉下虚空
			if drop:IsA("BasePart") then drop.Anchored = true end
			for _, desc in ipairs(drop:GetDescendants()) do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end

			-- 重新挂载 Interaction（使用注入的岛屿管理器引用）
			if brainrotIslandManagerRef and brainrotIslandManagerRef.SetupBrainrotInteraction then
				brainrotIslandManagerRef.SetupBrainrotInteraction(drop, drop.Parent, swapTargetCFrame.Position, 4)
			end

			-- 旧携带 brainrot 放回岛面：恢复该 uid 倒计时
			local oldUid = drop:GetAttribute("BrainrotUID") :: string?
			if itemType == GameConfig.ItemType.Brainrot and oldUid and brainrotIslandManagerRef and brainrotIslandManagerRef.ResumeBrainrotTimer then
				brainrotIslandManagerRef.ResumeBrainrotTimer(oldUid, drop)
			end
		end
		oldCarrying:Destroy()
	end

	-- 创建新的携带物
	local carryClone = newBrainrot:Clone()
	carryClone.Name = "CarryingBrainrot"
	
	if not carryClone:GetAttribute("BrainrotUID") then
		carryClone:SetAttribute("BrainrotUID", HttpService:GenerateGUID(false))
	end

	-- 新拾取的 brainrot：暂停该 uid 倒计时，并绑定当前携带实例用于 UI 同步
	local newUid = carryClone:GetAttribute("BrainrotUID") :: string?
	local newItemType = carryClone:GetAttribute("ItemType") :: number?
	if newItemType == GameConfig.ItemType.Brainrot and newUid then
		if brainrotIslandManagerRef and brainrotIslandManagerRef.PauseBrainrotTimer then
			brainrotIslandManagerRef.PauseBrainrotTimer(newUid, carryClone)
		end
	end

	-- 清理多余的可交互组件，并解除锚定、取消碰撞以防止卡住人物
	if carryClone:IsA("BasePart") then
		carryClone.Anchored = false
		carryClone.CanCollide = false
		carryClone.Massless = true
	end
	for _, desc in ipairs(carryClone:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
		end
	end

	-- Weld 到玩家头部
	if carryClone:IsA("Model") then
		local root = carryClone.PrimaryPart or carryClone:FindFirstChildWhichIsA("BasePart")
		if root then
			carryClone:PivotTo(head.CFrame * CFrame.new(0, 1.5 + carryClone:GetExtentsSize().Y/2, 0))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = root
			weld.Parent = carryClone
		end
	elseif carryClone:IsA("BasePart") then
		carryClone.CFrame = head.CFrame * CFrame.new(0, 1.5 + carryClone.Size.Y/2, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = carryClone
		weld.Parent = carryClone
	end

	carryClone.Parent = character
	return carryClone
end

function BrainrotCarryingManager.StopCarrying(player: Player)
	local character = player.Character
	if character then
		local carrying = character:FindFirstChild("CarryingBrainrot")
		if carrying then
			carrying:Destroy()
		end
	end
end

function BrainrotCarryingManager.GetCarryingBrainrot(player: Player): Instance?
	local character = player.Character
	if character then
		return character:FindFirstChild("CarryingBrainrot")
	end
	return nil
end

return BrainrotCarryingManager
