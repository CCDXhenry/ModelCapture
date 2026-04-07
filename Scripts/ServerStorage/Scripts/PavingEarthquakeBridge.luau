--!strict
-- 连接 PavingManager（ServerScriptService 下的 Script）与 EarthquakeManager（ModuleScript）。
-- Script 无法被 require，铺砖回收逻辑通过此桥由 PavingManager 注册。

local releasePavedBrickAfterEarthquake: ((Part) -> ())? = nil
local onEarthquakeDropBrick: ((Part) -> ())? = nil
local getEarthquakeProtectedPavedBricks: (() -> { [Part]: true })? = nil
local refreshProtectedPavedBrickAfterEarthquake: ((Part) -> ())? = nil
-- 由 PavingManager 注册：遍历其 activeBricks 登记在册的铺砖 Part（地震标记/掉落队列用，避免扫 Workspace.PavedBricks）
local forEachActivePavedBrickForEarthquake: ((callback: (Part) -> ()) -> ())? = nil

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

function M.RegisterForEachActivePavedBrickForEarthquake(handler: (callback: (Part) -> ()) -> ())
	forEachActivePavedBrickForEarthquake = handler
end

-- 若铺砖模块已注册，返回 true；否则返回 false（调用方可兜底扫文件夹）。
function M.ForEachActivePavedBrickForEarthquake(callback: (Part) -> ()): boolean
	if forEachActivePavedBrickForEarthquake then
		forEachActivePavedBrickForEarthquake(callback)
		return true
	end
	return false
end

return M
