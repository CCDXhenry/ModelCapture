--!strict

local function RetryAsync(func:() -> ...any, attemptLimit: number, retryDelay: number): (boolean, ...any)
	local attemptIndex: number = 0
	local success: boolean
	local resultValues: {any}
	while true do
		resultValues = {pcall(func)}
		success = table.remove(resultValues, 1) :: boolean
		attemptIndex += 1
		if success or attemptIndex == attemptLimit then
			break
		end
		task.wait(retryDelay)
	end
	return success, table.unpack(resultValues)
end

return RetryAsync