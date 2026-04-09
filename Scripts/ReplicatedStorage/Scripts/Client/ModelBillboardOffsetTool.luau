--!strict
local ModelBillboardOffsetTool = {}

local DefaultPadding = 0.8
local DefaultAnchorName = "BillboardAnchor"
local DefaultVfxInstanceName = "VfxInstance"

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

local function GetBasePartMaxWorldY(part: BasePart): number
	local halfSize = part.Size * 0.5
	local cf = part.CFrame
	local maxY = -math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local cornerY = cf:PointToWorldSpace(Vector3.new(halfSize.X * sx, halfSize.Y * sy, halfSize.Z * sz)).Y
				if cornerY > maxY then
					maxY = cornerY
				end
			end
		end
	end
	return maxY
end

local function GetModelMaxY(model: Model): number?
	local maxY: number? = nil
	for _, descendant in ipairs(model:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		local partMax = GetBasePartMaxWorldY(descendant)
		if maxY == nil or partMax > maxY then
			maxY = partMax
		end
	end

	return maxY
end

function ModelBillboardOffsetTool.GetVisualOffsetY(model: Model, adornee: BasePart, padding: number?, anchorName: string?): number
	local resolvedPadding = if padding == nil then DefaultPadding else padding
	local resolvedAnchorName = if anchorName == nil or anchorName == "" then DefaultAnchorName else anchorName

	local maxY: number? = nil
	local vfx = model:FindFirstChild(DefaultVfxInstanceName, true)
	if vfx and vfx:IsA("BasePart") then
		maxY = GetBasePartMaxWorldY(vfx)
	else
		maxY = GetAnchorWorldY(model, resolvedAnchorName)
		if maxY == nil then
			maxY = GetModelMaxY(model)
		end
	end

	if maxY == nil then
		return resolvedPadding + 2
	end

	return math.max(0, maxY - adornee.Position.Y) + resolvedPadding
end

return ModelBillboardOffsetTool
