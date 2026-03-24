--!strict
local InstanceExtension = {}

function InstanceExtension.SafeWaitForChild(instance: Instance, childName: string, checkStopWaiting: () -> boolean): Instance?
	while true do
		if checkStopWaiting() then
			return nil
		end
		local child: Instance? = instance:FindFirstChild(childName)
		if child ~= nil then
			return child
		end
		task.wait()
	end
end

return InstanceExtension
