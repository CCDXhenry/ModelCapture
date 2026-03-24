--!strict
local function PlayerSaveInfoVersionUpdate1(playerSaveInfo: any)
	playerSaveInfo.dataVersion = 1
end

return PlayerSaveInfoVersionUpdate1