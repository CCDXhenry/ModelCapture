--!strict
local PlayerSaveInfoVersionUpdateTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
--local PlayerSaveInfoVersionUpdate1 = require(script:FindFirstChild("PlayerSaveInfoVersionUpdate1"))

local PlayerSaveInfoVersionUpdateFunctionList: {[number]: (playerSaveInfo: any) -> ()} = {
	--[1] = PlayerSaveInfoVersionUpdate1,
}

function PlayerSaveInfoVersionUpdateTool.Update(playerSaveInfo: any)
	if playerSaveInfo.dataVersion >= GameConfig.PlayerSaveInfoDataVersion then
		return
	end
	for dataVersion: number = playerSaveInfo.dataVersion + 1, GameConfig.PlayerSaveInfoDataVersion do
		local success: boolean, errMsg: string? = pcall(function()
			PlayerSaveInfoVersionUpdateFunctionList[dataVersion](playerSaveInfo)
		end)
		if not success then
			warn("[PlayerSaveInfoVersionUpdateTool] Update", dataVersion, "failed:", errMsg)
		end
	end
end

return PlayerSaveInfoVersionUpdateTool