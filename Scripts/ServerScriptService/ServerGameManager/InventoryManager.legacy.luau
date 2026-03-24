--!strict
local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local BrainrotQueueManager = require(serverScripts:FindFirstChild("BrainrotQueueManager"))
local ServerMsg = require(serverScripts:FindFirstChild("ServerMsg"))

local InventoryManager = {}

--[监听服务端消息] 加载玩家背包 Tool 道具模型
function InventoryManager.Init()
	ServerMsg.ConnectLoadBackpackTools(function(player: Player)
		BrainrotQueueManager.LoadPlayerQueue(player)
	end)
end

InventoryManager.Init()

return InventoryManager
