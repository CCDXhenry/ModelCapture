--!strict
-- 由 PavingClientManager 写入：本地玩家是否重叠 Ground 补砖区（与 IsLocalCharacterOnRefillZone Ground 一致）。
-- LobbyFrame 等 UI 读取以控制 MaxBricksFrame2 可见性。

local ClientGroundZoneState = {}

local inGroundRefillZone = false
local changedEvent = Instance.new("BindableEvent")

function ClientGroundZoneState.SetLocalInGroundRefillZone(value: boolean)
	if inGroundRefillZone == value then
		return
	end
	inGroundRefillZone = value
	changedEvent:Fire(value)
end

function ClientGroundZoneState.GetLocalInGroundRefillZone(): boolean
	return inGroundRefillZone
end

function ClientGroundZoneState.ConnectChanged(callback: (inGround: boolean) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

return ClientGroundZoneState
