--!strict
local DataStoreTool = {}

local AttemptLimit: number = 5
local RetryDelay: number = 1

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))

function DataStoreTool.SafeGet(dataStore: GlobalDataStore, key:string, options: DataStoreGetOptions?): (boolean, ...any)
	return RetryAsync(function()
		return dataStore:GetAsync(key, options)
	end, AttemptLimit, RetryDelay)
end

function DataStoreTool.SafeSet(dataStore: GlobalDataStore, key:string, value: any, forceSave: boolean?, userIds: {number}?, 
	metadata: {[string]: any}?): (boolean, ...any)
	local startSaveTime: number = os.time()
	return RetryAsync(function()
		return dataStore:UpdateAsync(key, function(currentValue: any, dataStoreKeyInfo: DataStoreKeyInfo?)
			if not forceSave and dataStoreKeyInfo ~= nil and dataStoreKeyInfo.UpdatedTime / 1000 > startSaveTime then
				return nil
			end
			return value, userIds, metadata
		end)
	end, AttemptLimit, RetryDelay)
end

function DataStoreTool.SafeUpdate(dataStore: GlobalDataStore, key: string,
	trnasformFunction: (currentValue: any, dataStoreKeyInfo: DataStoreKeyInfo?) -> (any, {number}, {[string]: any}), 
	userIds: {number}, metadata: {[string]: any}): (boolean, ...any)
	return RetryAsync(function()
		return dataStore:UpdateAsync(key, trnasformFunction)
	end, AttemptLimit, RetryDelay)
end

function DataStoreTool.SafeGetSorted(orderedDataStore: OrderedDataStore, ascending: boolean, pageSize: number,
	minValue: any, maxValue: any): (boolean, any)
	return RetryAsync(function()
		return orderedDataStore:GetSortedAsync(ascending, pageSize, minValue, maxValue)
	end, AttemptLimit, RetryDelay)
end

function DataStoreTool.SafeAdvanceToNextPageAsync(pages: DataStorePages): (boolean, any)
	return RetryAsync(function()
		return pages:AdvanceToNextPageAsync()
	end, AttemptLimit, RetryDelay)
end

function DataStoreTool.SafeRemove(dataStore: GlobalDataStore, key:string): (boolean, any)
	return RetryAsync(function()
		return dataStore:RemoveAsync(key)
	end, AttemptLimit, RetryDelay)
end

return DataStoreTool
