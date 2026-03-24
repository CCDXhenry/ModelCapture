--!strict
local runService = game:GetService("RunService")

local BillboardManager = {}
local trackedUIs: { [BillboardGui]: boolean } = {}

function BillboardManager.Track(gui: BillboardGui)
	trackedUIs[gui] = true
end

function BillboardManager.Untrack(gui: BillboardGui)
	trackedUIs[gui] = nil
end

local function UpdateUIScales()
	for gui, _ in pairs(trackedUIs) do
		if not gui.Parent then
			trackedUIs[gui] = nil
			continue
		end

		if not gui.Enabled then
			continue
		end

		local controllerFrame = gui:FindFirstChild("ControllerFrame") :: Frame?
		local uIScale = controllerFrame and controllerFrame:FindFirstChild("UIScale") :: UIScale?
		if uIScale and controllerFrame then
			-- Calculate scale based on AbsoluteSize (which changes with distance) vs DesignSize
			uIScale.Scale = math.min(gui.AbsoluteSize.X / controllerFrame.Size.X.Offset, gui.AbsoluteSize.Y / controllerFrame.Size.Y.Offset)
		end
	end
end

runService.RenderStepped:Connect(UpdateUIScales)

return BillboardManager
