--!strict
local ServerMsg = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local bindableEventsFolder: Folder = serverStorage:FindFirstChild("BindableEvents") :: Folder
local playerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("PlayerInfoInit") :: BindableEvent
local loadBackpackToolsEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LoadBackpackTools") :: BindableEvent

--玩家信息初始化
function ServerMsg.FirePlayerInfoInit(player: Player)
	playerInfoInitEvent:Fire(player)
end

function ServerMsg.ConnectPlayerInfoInit(callback: (player: Player) -> ())
	playerInfoInitEvent.Event:Connect(callback)
end

--加载玩家背包 Tool 通知
function ServerMsg.FireLoadBackpackTools(player: Player)
	loadBackpackToolsEvent:Fire(player)
end

function ServerMsg.ConnectLoadBackpackTools(callback: (player: Player) -> ())
	loadBackpackToolsEvent.Event:Connect(callback)
end

return ServerMsg