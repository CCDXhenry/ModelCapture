--!strict
local runService = game:GetService("RunService")

local BillboardManager = {}
type TrackedBillboardInfo = {
	controllerFrame: Frame?,
	uiScale: UIScale?,
	designX: number,
	designY: number,
	lastAbsX: number,
	lastAbsY: number,
	lastScale: number,
	active: boolean,
	dirty: boolean,
	enabledConn: RBXScriptConnection?,
	ancestryConn: RBXScriptConnection?,
	absSizeConn: RBXScriptConnection?,
	destroyConn: RBXScriptConnection?,
}

local trackedUIs: { [BillboardGui]: TrackedBillboardInfo } = {}
local activeUIs: { BillboardGui } = {}
local activeIndexMap: { [BillboardGui]: number } = {}
local updateAccumulator = 0
local activeCursor = 0

local UPDATE_INTERVAL = 0.017
local SCALE_EPSILON = 0.001
local MAX_UPDATES_PER_TICK = 160

local function IsGuiActive(gui: BillboardGui): boolean
	return gui.Parent ~= nil and gui.Enabled
end

local function AddActiveGui(gui: BillboardGui)
	if activeIndexMap[gui] ~= nil then
		return
	end
	table.insert(activeUIs, gui)
	activeIndexMap[gui] = #activeUIs
end

local function RemoveActiveGui(gui: BillboardGui)
	local idx = activeIndexMap[gui]
	if idx == nil then
		return
	end
	local lastIdx = #activeUIs
	local lastGui = activeUIs[lastIdx]
	if idx ~= lastIdx then
		activeUIs[idx] = lastGui
		activeIndexMap[lastGui] = idx
	end
	activeUIs[lastIdx] = nil
	activeIndexMap[gui] = nil
	if activeCursor > #activeUIs then
		activeCursor = 0
	end
end

local function SetActiveState(gui: BillboardGui, info: TrackedBillboardInfo, active: boolean)
	if info.active == active then
		return
	end
	info.active = active
	if active then
		AddActiveGui(gui)
	else
		RemoveActiveGui(gui)
	end
end

local function ResolveCache(gui: BillboardGui, oldInfo: TrackedBillboardInfo?): TrackedBillboardInfo
	local controllerFrame = gui:FindFirstChild("ControllerFrame") :: Frame?
	local uiScale = controllerFrame and controllerFrame:FindFirstChild("UIScale") :: UIScale?

	local designX = if controllerFrame then controllerFrame.Size.X.Offset else 0
	local designY = if controllerFrame then controllerFrame.Size.Y.Offset else 0
	local lastScale = if oldInfo then oldInfo.lastScale else 1

	return {
		controllerFrame = controllerFrame,
		uiScale = uiScale,
		designX = designX,
		designY = designY,
		lastAbsX = if oldInfo then oldInfo.lastAbsX else 0,
		lastAbsY = if oldInfo then oldInfo.lastAbsY else 0,
		lastScale = lastScale,
		active = if oldInfo then oldInfo.active else false,
		dirty = if oldInfo then oldInfo.dirty else true,
		enabledConn = if oldInfo then oldInfo.enabledConn else nil,
		ancestryConn = if oldInfo then oldInfo.ancestryConn else nil,
		absSizeConn = if oldInfo then oldInfo.absSizeConn else nil,
		destroyConn = if oldInfo then oldInfo.destroyConn else nil,
	}
end

function BillboardManager.Track(gui: BillboardGui)
	local oldInfo = trackedUIs[gui]
	if oldInfo ~= nil then
		if oldInfo.controllerFrame == nil or oldInfo.uiScale == nil then
			trackedUIs[gui] = ResolveCache(gui, oldInfo)
		end
		oldInfo.dirty = true
		SetActiveState(gui, oldInfo, IsGuiActive(gui))
		return
	end

	local info = ResolveCache(gui, nil)
	trackedUIs[gui] = info

	info.enabledConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		local tracked = trackedUIs[gui]
		if tracked == nil then
			return
		end
		tracked.dirty = true
		SetActiveState(gui, tracked, IsGuiActive(gui))
	end)
	info.ancestryConn = gui.AncestryChanged:Connect(function()
		local tracked = trackedUIs[gui]
		if tracked == nil then
			return
		end
		tracked.dirty = true
		SetActiveState(gui, tracked, IsGuiActive(gui))
	end)
	info.absSizeConn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local tracked = trackedUIs[gui]
		if tracked == nil then
			return
		end
		tracked.dirty = true
	end)
	info.destroyConn = gui.Destroying:Connect(function()
		BillboardManager.Untrack(gui)
	end)
	SetActiveState(gui, info, IsGuiActive(gui))
end

function BillboardManager.Untrack(gui: BillboardGui)
	local info = trackedUIs[gui]
	if info == nil then
		return
	end
	trackedUIs[gui] = nil
	RemoveActiveGui(gui)
	if info.enabledConn then
		info.enabledConn:Disconnect()
		info.enabledConn = nil
	end
	if info.ancestryConn then
		info.ancestryConn:Disconnect()
		info.ancestryConn = nil
	end
	if info.absSizeConn then
		info.absSizeConn:Disconnect()
		info.absSizeConn = nil
	end
	if info.destroyConn then
		info.destroyConn:Disconnect()
		info.destroyConn = nil
	end
end

local function UpdateUIScales()
	local activeCount = #activeUIs
	if activeCount <= 0 then
		return
	end
	local updateCount = math.min(activeCount, MAX_UPDATES_PER_TICK)
	for _ = 1, updateCount do
		activeCursor += 1
		if activeCursor > #activeUIs then
			activeCursor = 1
		end
		local gui = activeUIs[activeCursor]
		local info = trackedUIs[gui]
		if info == nil then
			RemoveActiveGui(gui)
			continue
		end
		local shouldActive = IsGuiActive(gui)
		if shouldActive ~= info.active then
			SetActiveState(gui, info, shouldActive)
		end
		if not shouldActive then
			continue
		end

		local controllerFrame = info.controllerFrame
		local uiScale = info.uiScale
		if controllerFrame == nil or uiScale == nil or controllerFrame.Parent == nil or uiScale.Parent == nil then
			local refreshed = ResolveCache(gui, info)
			trackedUIs[gui] = refreshed
			info = refreshed
			controllerFrame = info.controllerFrame
			uiScale = info.uiScale
		end

		if controllerFrame == nil or uiScale == nil then
			continue
		end

		if info.designX <= 0 or info.designY <= 0 then
			continue
		end

		local absX = gui.AbsoluteSize.X
		local absY = gui.AbsoluteSize.Y
		local absChanged = absX ~= info.lastAbsX or absY ~= info.lastAbsY
		if not info.dirty and not absChanged then
			continue
		end

		info.lastAbsX = absX
		info.lastAbsY = absY
		local targetScale = math.min(absX / info.designX, absY / info.designY)
		if math.abs(targetScale - info.lastScale) > SCALE_EPSILON then
			uiScale.Scale = targetScale
			info.lastScale = targetScale
		end
		info.dirty = false
	end
end

runService.RenderStepped:Connect(function(deltaTime: number)
	updateAccumulator += deltaTime
	if updateAccumulator < UPDATE_INTERVAL then
		return
	end
	updateAccumulator = 0
	UpdateUIScales()
end)

return BillboardManager
