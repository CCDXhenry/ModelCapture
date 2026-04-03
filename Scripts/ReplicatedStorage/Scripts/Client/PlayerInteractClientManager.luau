--!strict
local PlayerInteractClientManager = {}

local players = game:GetService("Players")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))

local localPlayer = players.LocalPlayer

-- 常量定义
local FAILURE_TIPS_COLOR = Color3.fromRGB(255, 0, 0) -- 红色
local FAILURE_TIPS_DURATION = 3

local function HasBrainrot(character: Model?): boolean
	if not character then return false end
	if character:FindFirstChild("CarryingBrainrot") then return true end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("BrainrotUID") then return true end
	return false
end

local function UpdateInteractionPrompts()
	local localCharacter = localPlayer.Character
	local hasLocalBrainrot = if GameConfig.EnablePlayerGift then HasBrainrot(localCharacter) else false
	
	for _, otherPlayer in ipairs(players:GetPlayers()) do
		if otherPlayer.Character then
			local hrp = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local attachment = hrp:FindFirstChild("PlayerInteractAttachment")
				if attachment then
					local prompt = attachment:FindFirstChild("PlayerInteractPrompt") :: ProximityPrompt?
					if prompt then
						if otherPlayer.UserId == localPlayer.UserId then
							prompt.Enabled = false
							continue
						end
						if not GameConfig.EnablePlayerGift then
							prompt.Enabled = false
							continue
						end
						local hasOtherBrainrot = HasBrainrot(otherPlayer.Character)
						local canGift = hasLocalBrainrot and not hasOtherBrainrot
						prompt.Enabled = canGift
						if canGift then
							TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, GameTexts.GiftAction.source, GameTexts.GiftAction.key)
						end
					end
				end
			end
		end
	end
end

function PlayerInteractClientManager.Init()
	-- 定期检查状态更新 ProximityPrompt 的可见性
	runService.Heartbeat:Connect(function()
		UpdateInteractionPrompts()
	end)

	if GameConfig.EnablePlayerGift then
		NetMsg.ConnectNotifyShowGiftConfirm(function(targetPlayerId: number, targetPlayerName: string, brainrotInstanceId: string, giftName: string)
			ClientMsg.FireShowGiftConfirmPopup(targetPlayerId, targetPlayerName, brainrotInstanceId, giftName)
		end)

		NetMsg.ConnectNotifyReceiveGiftRequest(function(senderId: number, senderName: string, brainrotName: string, brainrotLevel: number)
			ClientMsg.FireShowGiftRequestPopup(senderId, senderName, brainrotName, brainrotLevel)
		end)

		NetMsg.ConnectNotifyGiftResult(function(isSuccess: boolean, message: string?)
			if not isSuccess then
				local source = string.gsub(GameTexts.GiftFailedFormat.source, "{1}", message or "error")
				ClientMsg.FireShowTopTipText(source, FAILURE_TIPS_COLOR, FAILURE_TIPS_DURATION, {message or "error"}, GameTexts.GiftFailedFormat.key)
			end
		end)
	end
end

return PlayerInteractClientManager
