--!strict
--[=[
	ShopManager.server.luau
	Handles shop interactions and upgrades.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local scripts = ReplicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local serverScripts = ServerStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))

local ShopManager = {}

--------------------------------------------------------------------------------
-- Logic Functions
--------------------------------------------------------------------------------

function ShopManager.OnUpgradeRequested(player: Player, skillType: number, levelAdd: number)
	local abilityName = if skillType == GameConfig.SkillType.WalkSpeed then "WalkSpeed"
		elseif skillType == GameConfig.SkillType.MaxBricks then "MaxBricks"
		elseif skillType == GameConfig.SkillType.HomeLevel then "HomeLevel"
		else nil
	
	if not abilityName then
		warn("[ShopManager] Invalid skillType:", skillType)
		return
	end

	-- 直接调用数据层的升级接口，内部会处理余额检查和扣费
	local success = ServerGameInfo.UpgradeAbility(player, abilityName, levelAdd)
	if success then
		print(`[ShopManager] {player.Name} successfully upgraded {abilityName} by {levelAdd} levels`)
	else
		print(`[ShopManager] {player.Name} upgrade failed for {abilityName}`)
	end
end

--------------------------------------------------------------------------------
-- Initialization Functions
--------------------------------------------------------------------------------

function ShopManager.Init()
    -- 监听升级请求
	NetMsg.ConnectRequestUpgradeSkill(function(player: Player, skillType: number, levelAdd: number)
		ShopManager.OnUpgradeRequested(player, skillType, levelAdd)
	end)
	
	print("[ShopManager] Initialized")
end

-- Start
ShopManager.Init()

return ShopManager
