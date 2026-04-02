--!strict
local PlayerInteractManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local players = game:GetService("Players")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))

function PlayerInteractManager.Init()
	-- 监听玩家加入并为其创建交互按钮
	players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			if hrp then
				local attachment = Instance.new("Attachment")
				attachment.Name = "PlayerInteractAttachment"
				attachment.Parent = hrp

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "PlayerInteractPrompt"
				prompt.ActionText = "Gift"
				prompt.ObjectText = player.Name
				prompt.KeyboardKeyCode = Enum.KeyCode.G
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 10
				-- 服务端开启，客户端负责基于条件本地隐藏
				prompt.Enabled = true
				prompt.Parent = attachment

				prompt.Triggered:Connect(function(triggerPlayer: Player)
					-- triggerPlayer 是发送方，player 是接收方
					if triggerPlayer.UserId == player.UserId then return end
					
					local senderChar = triggerPlayer.Character
					local receiverChar = player.Character
					if not senderChar or not receiverChar then return end

					local function GetActiveBrainrot(plr: Player): Instance?
						local char = plr.Character
						if not char then return nil end
						local tool = char:FindFirstChildOfClass("Tool")
						if tool and tool:GetAttribute("BrainrotUID") then return tool :: Instance end
						local carrying = char:FindFirstChild("CarryingBrainrot")
						if carrying and carrying:GetAttribute("BrainrotUID") then return carrying :: Instance end
						return nil
					end

					local senderBrainrot = GetActiveBrainrot(triggerPlayer)
					local receiverBrainrot = GetActiveBrainrot(player)
					
					-- 条件：发送方有宠物，接收方没有宠物
					if senderBrainrot and not receiverBrainrot then
						local configId = senderBrainrot:GetAttribute("ConfigId") :: number?
						if not configId then return end
						
						local brainrotConfig = GameConfig.BrainrotIdMap[configId]
						if not brainrotConfig then return end

						-- 触发发送方打开 UI
						NetMsg.FireNotifyShowGiftConfirm(triggerPlayer, player.UserId, player.Name, senderBrainrot.Name, brainrotConfig.name_t or "")
					end
				end)
			end
		end)
	end)
	
	-- 监听客户端确认送礼请求
	NetMsg.ConnectRequestSendGift(function(player: Player, targetPlayerId: number, brainrotInstanceId: string)
		local targetPlayer = players:GetPlayerByUserId(targetPlayerId)
		if not targetPlayer then return end
		
		local senderChar = player.Character
		local receiverChar = targetPlayer.Character
		if not senderChar or not receiverChar then return end

		local function GetActiveBrainrot(plr: Player): Instance?
			local char = plr.Character
			if not char then return nil end
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and tool:GetAttribute("BrainrotUID") then return tool end
			local carrying = char:FindFirstChild("CarryingBrainrot")
			if carrying and carrying:GetAttribute("BrainrotUID") then return carrying end
			return nil
		end

		local senderBrainrot = GetActiveBrainrot(player)
		local receiverBrainrot = GetActiveBrainrot(targetPlayer)

		if senderBrainrot and not receiverBrainrot then
			local configId = senderBrainrot:GetAttribute("ConfigId") :: number?
			if configId then
				local brainrotConfig = GameConfig.BrainrotIdMap[configId]
				if brainrotConfig then
					local brainrotName = brainrotConfig.name_t or ""
					-- 将请求发给接收方
					NetMsg.FireNotifyReceiveGiftRequest(targetPlayer, player.UserId, player.Name, brainrotName, 1)
				end
			end
		end
	end)

	-- 监听接收方响应请求
	NetMsg.ConnectRequestRespondGift(function(player: Player, senderId: number, isAccepted: boolean)
		local sender = players:GetPlayerByUserId(senderId)
		if not sender then return end
		
		if not isAccepted then
			NetMsg.FireNotifyGiftResult(sender, false, "Refused")
			return
		end

		local senderChar = sender.Character
		local receiverChar = player.Character
		if not senderChar or not receiverChar then return end
		
		local function GetActiveBrainrot(plr: Player): Instance?
			local char = plr.Character
			if not char then return nil end
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and tool:GetAttribute("BrainrotUID") then return tool end
			local carrying = char:FindFirstChild("CarryingBrainrot")
			if carrying and carrying:GetAttribute("BrainrotUID") then return carrying end
			return nil
		end

		local senderBrainrot = GetActiveBrainrot(sender)

		if senderBrainrot then
			local configId = senderBrainrot:GetAttribute("ConfigId") :: number?
			local level = senderBrainrot:GetAttribute("Level") :: number? or 1
			local quality = senderBrainrot:GetAttribute("Quality") :: number? or 1

			if configId then
				local brainrotConfig = GameConfig.BrainrotIdMap[configId]
				if brainrotConfig then
					local uid = senderBrainrot:GetAttribute("BrainrotUID") :: string?
					if not uid then return end
					
					if senderBrainrot:IsA("Tool") then
						if not BrainrotQueueManager.RemoveItem(sender, uid) then
							NetMsg.FireNotifyGiftResult(sender, false, "Failed")
							NetMsg.FireNotifyGiftResult(player, false, "Failed")
							return
						end
					else
						-- CarryingBrainrot，利用实体做锁
						if not senderBrainrot.Parent then return end
					end
					-- 销毁发送方Tool/Carrying
					senderBrainrot:Destroy()
					-- 接收方自动装备
					local success = BrainrotQueueManager.AddItem(player, configId, quality, level, true, nil, false)
					if success then
						NetMsg.FireNotifyGiftResult(sender, true, "Success")
						NetMsg.FireNotifyGiftResult(player, true, "Success")
						print("[PlayerInteractManager] Gift transferred from", sender.Name, "to", player.Name, "configId:", configId)
					else
						warn("[PlayerInteractManager] Gift AddItem failed (queue full?) for", player.Name)
						NetMsg.FireNotifyGiftResult(sender, false, "Failed")
						NetMsg.FireNotifyGiftResult(player, false, "Failed")
					end
					return
				end
			end
		end

		-- 条件不满足
		NetMsg.FireNotifyGiftResult(sender, false, "Failed")
		NetMsg.FireNotifyGiftResult(player, false, "Failed")
	end)
end

return PlayerInteractManager
