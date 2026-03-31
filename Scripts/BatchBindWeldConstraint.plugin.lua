--!strict
local selection = game:GetService("Selection")
local changeHistoryService = game:GetService("ChangeHistoryService")

local toolbar = plugin:CreateToolbar("Model Tools")
local button = toolbar:CreateButton(
	"BatchBindWeldConstraint",
	"Safely bind selected models without offset",
	"rbxassetid://4458901886"
)
button.ClickableWhenViewportHidden = true
local diagnoseButton = toolbar:CreateButton(
	"DiagnoseModelJoints",
	"Diagnose selected models without any modification",
	"rbxassetid://4458901886"
)
diagnoseButton.ClickableWhenViewportHidden = true
local normalizeButton = toolbar:CreateButton(
	"NormalizeModelRootVfx",
	"世界AABB底面中心 Pivot + RootPart + Vfx；全 Part 无碰撞；以 Root 为核心补焊连通",
	"rbxassetid://4458901886"
)
normalizeButton.ClickableWhenViewportHidden = true

-- 根部件 / 包围盒标准化（通用，不改动子层级）
local BrainrotNormWeldNamePrefix = "BrainrotNormWeld_"
local NormRootPartSize = Vector3.new(0.2, 0.2, 0.2)
local NormMinBoundingAxis = 1e-4
local NormStarWeldNameInfix = "StarToRoot_"
local ReservedGeometryExcludeNames: { [string]: boolean } = {
	RootPart = true,
	VfxInstance = true,
	FakeRootPart = true,
}

local function getBasePartList(root: Instance): { BasePart }
	local basePartList: { BasePart } = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(basePartList, descendant)
		end
	end
	return basePartList
end

local function removeBrainrotNormWelds(model: Model)
	local legacyPrefix = "AutoWeld_BrainrotNorm_"
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Weld") then
			local name = descendant.Name
			local isNewPrefix = string.sub(name, 1, #BrainrotNormWeldNamePrefix) == BrainrotNormWeldNamePrefix
			local isLegacyPrefix = string.sub(name, 1, #legacyPrefix) == legacyPrefix
			if isNewPrefix or isLegacyPrefix then
				descendant:Destroy()
			end
		end
	end
end

local function removeLegacyAutoWelds(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Weld") then
			local shouldRemove = descendant.Name == "AutoWeld"
				or descendant.Name == "AutoWeld_ComponentBridge"
				or descendant.Name == "AutoWeld_RootBridge"
			if shouldRemove then
				descendant:Destroy()
			end
		elseif descendant:IsA("WeldConstraint") then
			if descendant.Name == "AutoWeldConstraint" then
				descendant:Destroy()
			end
		end
	end
end

local function collectGeometryBaseParts(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not ReservedGeometryExcludeNames[descendant.Name] then
			table.insert(list, descendant)
		end
	end
	return list
end

local function pickLargestBasePartByVolume(partList: { BasePart }): BasePart?
	local bestPart: BasePart? = nil
	local bestVolume = -1
	for _, part in ipairs(partList) do
		local size = part.Size
		local volume = size.X * size.Y * size.Z
		if volume > bestVolume then
			bestVolume = volume
			bestPart = part
		end
	end
	return bestPart
end

local function snapshotAnchoredState(partList: { BasePart }): { [BasePart]: boolean }
	local map: { [BasePart]: boolean } = {}
	for _, part in ipairs(partList) do
		map[part] = part.Anchored
	end
	return map
end

local function restoreAnchoredState(anchoredMap: { [BasePart]: boolean })
	for part, anchored in anchoredMap do
		if part.Parent ~= nil then
			part.Anchored = anchored
		end
	end
end

local function applyNormShellPartProperties(part: BasePart, anchoredDuringEdit: boolean)
	part.Anchored = anchoredDuringEdit
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Transparency = 1
	part.CastShadow = true
end

local function destroyDirectChildShellParts(model: Model)
	local oldRoot = model:FindFirstChild("RootPart")
	if oldRoot and oldRoot:IsA("BasePart") then
		oldRoot:Destroy()
	end
	local oldVfx = model:FindFirstChild("VfxInstance")
	if oldVfx and oldVfx:IsA("BasePart") then
		oldVfx:Destroy()
	end
end

-- 世界轴对齐 AABB（用各 Part 的 OBB 角点展开），用于「水平中心 + 最低 Y」的底面中心
local function getWorldAabbMinMaxFromParts(parts: { BasePart }): (Vector3?, Vector3?)
	if #parts == 0 then
		return nil, nil
	end
	local inf = math.huge
	local minV = Vector3.new(inf, inf, inf)
	local maxV = Vector3.new(-inf, -inf, -inf)
	for _, part in ipairs(parts) do
		-- 使用 ExtentsCFrame/ExtentsSize 可正确覆盖 PivotOffset 与 MeshPart 几何包围盒
		local partAny = part :: any
		local cf = (partAny.ExtentsCFrame or part.CFrame) :: CFrame
		local size = (partAny.ExtentsSize or part.Size) :: Vector3
		local hx = size.X * 0.5
		local hy = size.Y * 0.5
		local hz = size.Z * 0.5
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local cornerWorld = (cf * CFrame.new(sx * hx, sy * hy, sz * hz)).Position
					minV = Vector3.new(
						math.min(minV.X, cornerWorld.X),
						math.min(minV.Y, cornerWorld.Y),
						math.min(minV.Z, cornerWorld.Z)
					)
					maxV = Vector3.new(
						math.max(maxV.X, cornerWorld.X),
						math.max(maxV.Y, cornerWorld.Y),
						math.max(maxV.Z, cornerWorld.Z)
					)
				end
			end
		end
	end
	return minV, maxV
end

local function setNonCollideForAllBaseParts(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
end

local function removeInvalidAndAutoConstraints(model: Model): number
	local cleanedCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") then
			local weldConstraintAny = descendant :: any
			local isInvalid = weldConstraintAny.Part0 == nil or weldConstraintAny.Part1 == nil
			local isAuto = descendant.Name == "AutoWeldConstraint"
			if isInvalid or isAuto then
				descendant:Destroy()
				cleanedCount += 1
			end
		elseif descendant:IsA("Weld") then
			local weldAny = descendant :: any
			local isInvalid = weldAny.Part0 == nil or weldAny.Part1 == nil
			local isAuto = descendant.Name == "AutoWeld"
			if isInvalid or isAuto then
				descendant:Destroy()
				cleanedCount += 1
			end
		end
	end
	return cleanedCount
end

local function setAnchoredForAll(parts: { BasePart }, anchored: boolean)
	for _, part in ipairs(parts) do
		part.Anchored = anchored
	end
end

local function buildAdjacencyMap(model: Model, partList: { BasePart }): { [BasePart]: { BasePart } }
	local partInModelMap: { [BasePart]: boolean } = {}
	local adjacencyMap: { [BasePart]: { BasePart } } = {}
	for _, part in ipairs(partList) do
		partInModelMap[part] = true
		adjacencyMap[part] = {}
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 and partInModelMap[part0] and partInModelMap[part1] then
				table.insert(adjacencyMap[part0], part1)
				table.insert(adjacencyMap[part1], part0)
			end
		end
	end
	return adjacencyMap
end

local function collectConnectedComponent(startPart: BasePart, adjacencyMap: { [BasePart]: { BasePart } }, visitedMap: { [BasePart]: boolean }): { BasePart }
	local component: { BasePart } = {}
	local queue: { BasePart } = { startPart }
	visitedMap[startPart] = true
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		table.insert(component, current)
		for _, neighbor in ipairs(adjacencyMap[current]) do
			if not visitedMap[neighbor] then
				visitedMap[neighbor] = true
				table.insert(queue, neighbor)
			end
		end
	end
	return component
end

local function getAssemblyComponents(model: Model, partList: { BasePart }): { { BasePart } }
	local adjacencyMap = buildAdjacencyMap(model, partList)
	local visitedMap: { [BasePart]: boolean } = {}
	local components: { { BasePart } } = {}
	for _, part in ipairs(partList) do
		if not visitedMap[part] then
			local component = collectConnectedComponent(part, adjacencyMap, visitedMap)
			table.insert(components, component)
		end
	end
	return components
end

local function isSingleAssembly(model: Model, partList: { BasePart }): boolean
	return #getAssemblyComponents(model, partList) <= 1
end

-- 直接全量星型焊接到 RootPart（稳定，不依赖 AutoWeld_ComponentBridge）
local function ensureAllPartsStarWeldedToRoot(model: Model, rootPart: BasePart): number
	local addedCount = 0
	local index = 0
	for _, part in ipairs(getBasePartList(model)) do
		if part ~= rootPart and part.Name ~= "VfxInstance" then
			index += 1
			local starWeld = Instance.new("Weld")
			starWeld.Name = BrainrotNormWeldNamePrefix .. NormStarWeldNameInfix .. tostring(index)
			starWeld.Part0 = rootPart
			starWeld.Part1 = part
			starWeld.C0 = rootPart.CFrame:ToObjectSpace(part.CFrame)
			starWeld.C1 = CFrame.new()
			starWeld.Parent = rootPart
			addedCount += 1
		end
	end
	return addedCount
end

local function ensureRootAndFakeRootConnected(model: Model, rootPart: BasePart): boolean
	local fakeRootPart = model:FindFirstChild("FakeRootPart")
	if not fakeRootPart or not fakeRootPart:IsA("BasePart") or fakeRootPart == rootPart then
		return false
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if (part0 == rootPart and part1 == fakeRootPart) or (part0 == fakeRootPart and part1 == rootPart) then
				return false
			end
		end
	end

	local bridgeWeld = Instance.new("Weld")
	bridgeWeld.Name = "AutoWeld_RootBridge"
	bridgeWeld.Part0 = rootPart
	bridgeWeld.Part1 = fakeRootPart
	bridgeWeld.C0 = rootPart.CFrame:ToObjectSpace(fakeRootPart.CFrame)
	bridgeWeld.C1 = CFrame.new()
	bridgeWeld.Parent = rootPart
	return true
end

local function hasRootFakeRootConnection(model: Model, rootPart: BasePart): boolean
	local fakeRootPart = model:FindFirstChild("FakeRootPart")
	if not fakeRootPart or not fakeRootPart:IsA("BasePart") then
		return true
	end
	if fakeRootPart == rootPart then
		return true
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if (part0 == rootPart and part1 == fakeRootPart) or (part0 == fakeRootPart and part1 == rootPart) then
				return true
			end
		end
	end
	return false
end

local function getInvalidConstraintCount(model: Model): number
	local invalidCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			local jointAny = descendant :: any
			if jointAny.Part0 == nil or jointAny.Part1 == nil then
				invalidCount += 1
			end
		end
	end
	return invalidCount
end

local function diagnoseModel(model: Model): (boolean, string)
	local partList = getBasePartList(model)
	if #partList == 0 then
		return false, "无 BasePart"
	end

	local rootPart = model.PrimaryPart
	if not rootPart then
		rootPart = model:FindFirstChild("RootPart") :: BasePart?
	end
	if not rootPart then
		rootPart = partList[1]
	end
	if not rootPart then
		return false, "未找到 RootPart"
	end

	local invalidConstraintCount = getInvalidConstraintCount(model)
	local singleAssembly = isSingleAssembly(model, partList)
	local rootFakeConnected = hasRootFakeRootConnection(model, rootPart)
	local hasFakeRoot = model:FindFirstChild("FakeRootPart") ~= nil
	local jointCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			jointCount += 1
		end
	end

	return true, string.format(
		"诊断: parts=%d joints=%d invalidJoints=%d singleAssembly=%s hasFakeRoot=%s rootFakeConnected=%s root=%s",
		#partList,
		jointCount,
		invalidConstraintCount,
		tostring(singleAssembly),
		tostring(hasFakeRoot),
		tostring(rootFakeConnected),
		rootPart.Name
	)
end

local function bindModelWeld(model: Model): (boolean, string)
	local partList = getBasePartList(model)
	if #partList <= 1 then
		return false, "BasePart 数量不足"
	end

	local rootPart = model.PrimaryPart
	if not rootPart then
		rootPart = model:FindFirstChild("RootPart") :: BasePart?
	end
	if not rootPart then
		rootPart = partList[1]
		model.PrimaryPart = rootPart
	end
	if not rootPart then
		return false, "未找到可用 RootPart"
	end

	local originalAnchoredMap: { [BasePart]: boolean } = {}
	for _, part in ipairs(partList) do
		originalAnchoredMap[part] = part.Anchored
	end
	setAnchoredForAll(partList, true)

	local ok, resultMessage = pcall(function()
		local cleanedCount = removeInvalidAndAutoConstraints(model)
		local bridgeAdded = ensureRootAndFakeRootConnected(model, rootPart)
		local createdBridgeCount = 0

		-- 只做“最小连接修复”：每个断开的装配体只补一条桥接，不焊死所有零件，保留原有关节体系
		local components = getAssemblyComponents(model, partList)
		if #components > 1 then
			local rootComponentIndex = 1
			for componentIndex, component in ipairs(components) do
				for _, part in ipairs(component) do
					if part == rootPart then
						rootComponentIndex = componentIndex
						break
					end
				end
			end
			local rootComponent = components[rootComponentIndex]
			local rootBridgePart = rootPart
			for _, component in ipairs(components) do
				if component ~= rootComponent then
					local targetPart = component[1]
					local weld = Instance.new("Weld")
					weld.Name = "AutoWeld_ComponentBridge"
					weld.Part0 = rootBridgePart
					weld.Part1 = targetPart
					weld.C0 = rootBridgePart.CFrame:ToObjectSpace(targetPart.CFrame)
					weld.C1 = CFrame.new()
					weld.Parent = rootBridgePart
					createdBridgeCount += 1
				end
			end
		end

		if not isSingleAssembly(model, partList) then
			error("绑定后仍存在多装配体，已中止，请检查模型原始关节")
		end

		return string.format(
			"新增 %d 个组件桥接, 清理 %d 个失效/旧约束%s",
			createdBridgeCount,
			cleanedCount,
			bridgeAdded and ", 已补 RootPart-FakeRootPart 连接" or ""
		)
	end)

	for _, part in ipairs(partList) do
		part.Anchored = originalAnchoredMap[part]
	end

	if not ok then
		return false, tostring(resultMessage)
	end
	return true, resultMessage
end

local function normalizeModelRootAndVfx(model: Model): (boolean, string)
	removeBrainrotNormWelds(model)
	removeLegacyAutoWelds(model)
	destroyDirectChildShellParts(model)

	local geometryParts = collectGeometryBaseParts(model)
	if #geometryParts == 0 then
		return false, "无几何 BasePart（已排除保留名 RootPart/VfxInstance/FakeRootPart）"
	end

	local partList = getBasePartList(model)
	local originalAnchoredMap = snapshotAnchoredState(partList)
	setAnchoredForAll(partList, true)

	local stepOk, stepResult = pcall(function(): string
		local minV, maxV = getWorldAabbMinMaxFromParts(geometryParts)
		if not minV or not maxV then
			error("无法计算世界轴对齐包围盒")
		end
		local aabbSize = maxV - minV
		if
			aabbSize.X < NormMinBoundingAxis
			or aabbSize.Y < NormMinBoundingAxis
			or aabbSize.Z < NormMinBoundingAxis
		then
			error("包围盒尺寸过小")
		end
		-- 世界 AABB 底面中心（水平中心 + 最低 Y），保留原模型 Pivot 的朝向
		local bottomCenterWorld =
			Vector3.new((minV.X + maxV.X) * 0.5, minV.Y, (minV.Z + maxV.Z) * 0.5)
		local oldPivot = model:GetPivot()
		local ox, oy, oz = oldPivot:ToOrientation()
		model:PivotTo(CFrame.new(bottomCenterWorld) * CFrame.fromOrientation(ox, oy, oz))

		local rootPart = Instance.new("Part")
		rootPart.Name = "RootPart"
		rootPart.Size = NormRootPartSize
		applyNormShellPartProperties(rootPart, true)
		rootPart.CFrame = model:GetPivot()
		rootPart.Parent = model
		model.PrimaryPart = rootPart

		model.PrimaryPart = nil
		rootPart.Parent = nil
		local geometryForVfx = collectGeometryBaseParts(model)
		local vminVfx, vmaxVfx = getWorldAabbMinMaxFromParts(geometryForVfx)
		if not vminVfx or not vmaxVfx then
			error("无法计算 Vfx 包围盒")
		end
		rootPart.Parent = model
		model.PrimaryPart = rootPart

		local vfxSize = vmaxVfx - vminVfx
		if
			vfxSize.X < NormMinBoundingAxis
			or vfxSize.Y < NormMinBoundingAxis
			or vfxSize.Z < NormMinBoundingAxis
		then
			error("Vfx 包围盒尺寸过小")
		end
		local vfxCenterWorld =
			Vector3.new((vminVfx.X + vmaxVfx.X) * 0.5, (vminVfx.Y + vmaxVfx.Y) * 0.5, (vminVfx.Z + vmaxVfx.Z) * 0.5)
		-- RootPart 必须位于 Vfx 包围盒的中心最低点（GUI 挂点依赖）
		local rootBottomCenterWorld = Vector3.new(vfxCenterWorld.X, vminVfx.Y, vfxCenterWorld.Z)
		rootPart.CFrame = CFrame.new(rootBottomCenterWorld) * CFrame.fromOrientation(ox, oy, oz)

		local vfxPart = Instance.new("Part")
		vfxPart.Name = "VfxInstance"
		vfxPart.Size = vfxSize
		vfxPart.CFrame = CFrame.new(vfxCenterWorld)
		applyNormShellPartProperties(vfxPart, true)
		vfxPart.Parent = model

		local geometryAfter = collectGeometryBaseParts(model)
		local mainPart = pickLargestBasePartByVolume(geometryAfter)
		if not mainPart then
			error("无法选取主连接件")
		end

		local rootToMain = Instance.new("Weld")
		rootToMain.Name = BrainrotNormWeldNamePrefix .. "RootToMain"
		rootToMain.Part0 = rootPart
		rootToMain.Part1 = mainPart
		rootToMain.C0 = rootPart.CFrame:ToObjectSpace(mainPart.CFrame)
		rootToMain.C1 = CFrame.new()
		rootToMain.Parent = rootPart

		local vfxWeld = Instance.new("Weld")
		vfxWeld.Name = BrainrotNormWeldNamePrefix .. "VfxToRoot"
		vfxWeld.Part0 = rootPart
		vfxWeld.Part1 = vfxPart
		vfxWeld.C0 = rootPart.CFrame:ToObjectSpace(vfxPart.CFrame)
		vfxWeld.C1 = CFrame.new()
		vfxWeld.Parent = rootPart

		return "Pivot/RootPart/Vfx 与规范 Weld 已建立"
	end)

	for _, part in ipairs(getBasePartList(model)) do
		if originalAnchoredMap[part] == nil then
			part.Anchored = false
		end
	end
	restoreAnchoredState(originalAnchoredMap)

	local rootShell = model:FindFirstChild("RootPart")
	if rootShell and rootShell:IsA("BasePart") then
		rootShell.Anchored = false
	end
	local vfxShell = model:FindFirstChild("VfxInstance")
	if vfxShell and vfxShell:IsA("BasePart") then
		vfxShell.Anchored = false
	end

	if not stepOk then
		return false, tostring(stepResult)
	end

	setNonCollideForAllBaseParts(model)

	local rootAfter = model:FindFirstChild("RootPart")
	if not rootAfter or not rootAfter:IsA("BasePart") then
		return false, "标准化后未找到 RootPart"
	end

	local partListAfter = getBasePartList(model)
	setAnchoredForAll(partListAfter, true)
	local starAdded = 0
	local starOk, starErr = pcall(function()
		starAdded = ensureAllPartsStarWeldedToRoot(model, rootAfter)
	end)
	for _, part in ipairs(partListAfter) do
		local saved = originalAnchoredMap[part]
		if saved ~= nil then
			part.Anchored = saved
		else
			part.Anchored = false
		end
	end
	local rootShell2 = model:FindFirstChild("RootPart")
	if rootShell2 and rootShell2:IsA("BasePart") then
		rootShell2.Anchored = false
	end
	local vfxShell2 = model:FindFirstChild("VfxInstance")
	if vfxShell2 and vfxShell2:IsA("BasePart") then
		vfxShell2.Anchored = false
	end

	if not starOk then
		return false, "Root 星型焊接失败: " .. tostring(starErr)
	end

	if not isSingleAssembly(model, getBasePartList(model)) then
		return false, "星型焊接后仍存在多装配体"
	end

	return true, (stepResult :: string) .. string.format("; 无碰撞已统一; Root 星型焊接=%d", starAdded)
end

local function getSelectedModels(): { Model }
	local selectedList = selection:Get()
	local modelList: { Model } = {}
	for _, instance in ipairs(selectedList) do
		if instance:IsA("Model") then
			table.insert(modelList, instance)
		end
	end
	return modelList
end

local function runBatchBind()
	local modelList = getSelectedModels()

	if #modelList == 0 then
		warn("[BatchBindWeldConstraint] 请先选中至少一个 Model")
		return
	end

	changeHistoryService:SetWaypoint("BatchBindWeldConstraint_Begin")

	local successCount = 0
	for _, model in ipairs(modelList) do
		local ok, message = bindModelWeld(model)
		if ok then
			successCount += 1
			print(string.format("[BatchBindWeldConstraint] %s: %s", model:GetFullName(), message))
		else
			warn(string.format("[BatchBindWeldConstraint] %s: %s", model:GetFullName(), message))
		end
	end

	changeHistoryService:SetWaypoint("BatchBindWeldConstraint_End")
	print(string.format("[BatchBindWeldConstraint] 完成，处理 Model %d/%d", successCount, #modelList))
end

local function runDiagnose()
	local modelList = getSelectedModels()
	if #modelList == 0 then
		warn("[DiagnoseModelJoints] 请先选中至少一个 Model")
		return
	end

	local successCount = 0
	for _, model in ipairs(modelList) do
		local ok, message = diagnoseModel(model)
		if ok then
			successCount += 1
			print(string.format("[DiagnoseModelJoints] %s: %s", model:GetFullName(), message))
		else
			warn(string.format("[DiagnoseModelJoints] %s: %s", model:GetFullName(), message))
		end
	end
	print(string.format("[DiagnoseModelJoints] 完成，诊断 Model %d/%d（无改动）", successCount, #modelList))
end

local function runNormalizeRootVfx()
	local modelList = getSelectedModels()
	if #modelList == 0 then
		warn("[NormalizeModelRootVfx] 请先选中至少一个 Model")
		return
	end

	changeHistoryService:SetWaypoint("NormalizeModelRootVfx_Begin")

	local successCount = 0
	for _, model in ipairs(modelList) do
		local ok, message = normalizeModelRootAndVfx(model)
		if ok then
			successCount += 1
			print(string.format("[NormalizeModelRootVfx] %s: %s", model:GetFullName(), message))
		else
			warn(string.format("[NormalizeModelRootVfx] %s: %s", model:GetFullName(), message))
		end
	end

	changeHistoryService:SetWaypoint("NormalizeModelRootVfx_End")
	print(string.format("[NormalizeModelRootVfx] 完成，处理 Model %d/%d", successCount, #modelList))
end

button.Click:Connect(runBatchBind)
diagnoseButton.Click:Connect(runDiagnose)
normalizeButton.Click:Connect(runNormalizeRootVfx)
