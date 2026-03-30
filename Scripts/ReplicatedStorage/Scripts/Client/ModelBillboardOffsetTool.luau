--!strict
local ModelBillboardOffsetTool = {}

local DefaultPadding = 0.8
local DefaultAnchorName = "BillboardAnchor"

local function GetAnchorWorldY(model: Model, anchorName: string): number?
	local anchorInstance = model:FindFirstChild(anchorName, true)
	if not anchorInstance then
		return nil
	end

	if anchorInstance:IsA("Attachment") then
		return anchorInstance.WorldPosition.Y
	end

	if anchorInstance:IsA("BasePart") then
		return anchorInstance.Position.Y
	end

	return nil
end

local function GetModelMaxY(model: Model): number?
	local maxY: number? = nil
	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		local halfSize = descendant.Size * 0.5
		local cf = descendant.CFrame
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local cornerPos = cf:PointToWorldSpace(Vector3.new(halfSize.X * sx, halfSize.Y * sy, halfSize.Z * sz))
					if maxY == nil or cornerPos.Y > maxY then
						maxY = cornerPos.Y
					end
				end
			end
		end
	end

	return maxY
end

function ModelBillboardOffsetTool.GetVisualOffsetY(model: Model, adornee: BasePart, padding: number?, anchorName: string?): number
	local resolvedPadding = if padding == nil then DefaultPadding else padding
	local resolvedAnchorName = if anchorName == nil or anchorName == "" then DefaultAnchorName else anchorName

	local maxY = GetAnchorWorldY(model, resolvedAnchorName)
	if maxY == nil then
		maxY = GetModelMaxY(model)
	end

	if maxY == nil then
		return resolvedPadding + 2
	end

	return math.max(0, maxY - adornee.Position.Y) + resolvedPadding
end

return ModelBillboardOffsetTool
