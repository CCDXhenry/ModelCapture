--!strict
-- 连接 PavingManager（ServerScriptService 下的 Script）与 EarthquakeManager（ModuleScript）。
-- Script 无法被 require，铺砖回收逻辑通过此桥由 PavingManager 注册。

local releasePavedBrickAfterEarthquake: ((Part) -> ())? = nil
local onEarthquakeDropBrick: ((Part) -> ())? = nil
local getEarthquakeProtectedPavedBricks: (() -> { [Part]: true })? = nil
local refreshProtectedPavedBrickAfterEarthquake: ((Part) -> ())? = nil

local M = {}

function M.RegisterReleasePavedBrickAfterEarthquake(handler: (Part) -> ())
	releasePavedBrickAfterEarthquake = handler
end

function M.ReleasePavedBrickAfterEarthquake(brick: Part)
	if releasePavedBrickAfterEarthquake then
		releasePavedBrickAfterEarthquake(brick)
	end
end

function M.RegisterOnEarthquakeDropBrick(handler: (Part) -> ())
	onEarthquakeDropBrick = handler
end

function M.OnEarthquakeDropBrick(brick: Part)
	if onEarthquakeDropBrick then
		onEarthquakeDropBrick(brick)
	end
end

function M.RegisterGetEarthquakeProtectedPavedBricks(handler: () -> { [Part]: true })
	getEarthquakeProtectedPavedBricks = handler
end

function M.GetEarthquakeProtectedPavedBricks(): { [Part]: true }
	if getEarthquakeProtectedPavedBricks then
		return getEarthquakeProtectedPavedBricks()
	end
	return {}
end

function M.RegisterRefreshProtectedPavedBrickAfterEarthquake(handler: (Part) -> ())
	refreshProtectedPavedBrickAfterEarthquake = handler
end

function M.RefreshProtectedPavedBrickAfterEarthquake(brick: Part)
	if refreshProtectedPavedBrickAfterEarthquake then
		refreshProtectedPavedBrickAfterEarthquake(brick)
	end
end

return M
