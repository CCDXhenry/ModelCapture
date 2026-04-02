--!strict
local HomeManager = {}

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local HttpService = game:GetService("HttpService")

-- 从展台拾取：直接进入背包队列，不经过头顶搬运
function HomeManager.OnRequestPickupHomeModel(player: Player, pointIndex: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo then
		return
	end

	local model = playerInfo.homeInfo.placedModels[tostring(pointIndex)]
	if not model then
		warn("[HomeManager] OnRequestPickupHomeModel failed: no model at point", pointIndex)
		return
	end

	local brainrotData = GameConfig.BrainrotIdMap[model.configId]
	if not brainrotData then
		return
	end

	-- 检查背包是否已满
	if #playerInfo.brainrotQueue >= GameConfig.BrainrotQueue.MaxCapacity then
		warn("[HomeManager] OnRequestPickupHomeModel: brainrotQueue full for", player.Name)
		return
	end

	-- 检查手上是否有拿着的 Tool / Carrying
	local function GetActiveBrainrot(plr: Player): Instance?
		local char = plr.Character
		if not char then return nil end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool and tool:GetAttribute("BrainrotUID") then
			if tool:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
				return tool
			end
			return nil
		end
		local carrying = char:FindFirstChild("CarryingBrainrot")
		if carrying and carrying:GetAttribute("BrainrotUID") then
			if carrying:GetAttribute("ItemType") == GameConfig.ItemType.Brainrot then
				return carrying
			end
			return nil
		end
		return nil
	end

	local heldBrainrot = GetActiveBrainrot(player)

	if heldBrainrot then
		-- 如果手里有东西，执行替换：
		local heldConfigId = tonumber(heldBrainrot:GetAttribute("ConfigId"))
		local heldQuality = tonumber(heldBrainrot:GetAttribute("Quality")) or 1
		local heldLevel = tonumber(heldBrainrot:GetAttribute("Level")) or 1
		local heldUid = heldBrainrot:GetAttribute("BrainrotUID") :: string?

		if heldConfigId and heldUid then
			-- 扣除手里的物品
			if heldBrainrot:IsA("Tool") then
				if not BrainrotQueueManager.RemoveItem(player, heldUid) then return end
			else
				if not heldBrainrot.Parent then return end
			end

			-- 保存展台旧物品数据
			local oldConfigId = model.configId
			local oldLevel = (model :: any).level or 1
			local oldQuality = (model :: any).quality or 1

			-- 销毁手里拿的
			heldBrainrot:Destroy()

			-- 把手里扣掉的放到展台上
			local heldQualityCfg = GameConfig.BrainrotQualityConfig[heldQuality]
			local defaultQualityCfg = GameConfig.BrainrotQualityConfig[1]
			local newPlacedData = {
				configId = heldConfigId,
				level = heldLevel,
				quality = heldQuality,
				instanceId = heldUid or HttpService:GenerateGUID(false),
				rarity = if heldQualityCfg then heldQualityCfg.rarity else if defaultQualityCfg then defaultQualityCfg.rarity else "Common",
			}
			ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, newPlacedData :: any)

			-- 把手里的替换为展台原来的并直接装备
			if BrainrotQueueManager.AddItem(player, oldConfigId, oldQuality, oldLevel, true, nil, false) then
				AnalyticsTool.LogModelHold(player, oldConfigId, oldLevel)
			end

			print(string.format("[HomeManager] Player %s swapped held brainrot (%d) with display point %d (%d)", player.Name, heldConfigId, pointIndex, oldConfigId))
			return
		end
	end

	-- 如果未触发互换走原本收取路径
	-- 1. 从展台移除数据
	local configId = model.configId
	local level = (model :: any).level or 1
	local quality = (model :: any).quality or 1
	ServerGameInfo.UpdatePlayerPlacedModel(player, pointIndex, nil :: any)

	-- 2. 直接入背包队列（自动创建 Tool 并存盘）并自动装备
	if BrainrotQueueManager.AddItem(player, configId, quality, level, true, nil, false) then
		AnalyticsTool.LogModelHold(player, configId, level)
	end
	print("[HomeManager] Player", player.Name, "picked up model from point", pointIndex, "into backpack queue")
end

function HomeManager.RestoreHomeModel(player: Player, brainrot: Instance)
	local fromHomeSlot = brainrot:GetAttribute("FromHomeSlot")
	local fromPointIndex = brainrot:GetAttribute("FromPointIndex") :: number?
	local originalDataJson = brainrot:GetAttribute("OriginalData")

	if not fromHomeSlot or not fromPointIndex or not originalDataJson then
		brainrot:Destroy()
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if not playerInfo or playerInfo.homeSlot ~= fromHomeSlot then
		brainrot:Destroy()
		return
	end

	local ok, originalData = pcall(function()
		return HttpService:JSONDecode(originalDataJson)
	end)

	if ok and originalData then
		ServerGameInfo.UpdatePlayerPlacedModel(player, fromPointIndex, originalData)
		print("[HomeManager] Restored brainrot to slot", fromHomeSlot, "point", fromPointIndex)
	end

	brainrot:Destroy()
end

return HomeManager
