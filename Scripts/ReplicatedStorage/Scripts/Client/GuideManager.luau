--!strict
local GuideManager = {}

local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local localPlayer: Player? = players.LocalPlayer
if localPlayer == nil then
	warn("[GuideManager] LocalPlayer is nil at module load")
end
local workspace: Workspace = game:GetService("Workspace")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))

local initialized = false
local lastGuideType = GameConfig.GuideType.None
local guideArrowModel: Model? = nil
local guideArrowStartAttachment: Attachment? = nil
local guideArrowEndAttachment: Attachment? = nil
local lastGuideTypeRefreshAt = 0
local lastArrowTargetRefreshAt = 0
local cachedArrowGuideType = GameConfig.GuideType.None
local cachedArrowTarget: Vector3? = nil
local pickupCandidatesInitialized = false
local pickupCandidatePartMap: { [BasePart]: boolean } = {}

local GUIDE_TYPE_REFRESH_INTERVAL = 0.2
local GUIDE_TARGET_REFRESH_INTERVAL = 0.2
local InitPickupCandidates: () -> ()

local function ApplyGuideArrowPartPhysics(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
end

local function ApplyGuideArrowPhysics(root: Instance)
	if root:IsA("BasePart") then
		ApplyGuideArrowPartPhysics(root)
	end
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			ApplyGuideArrowPartPhysics(inst)
		end
	end
end

local function HasBrainrotPlacedOnHome(info: GameConfig.ClientLocalPlayerInfo): boolean
	for _, placed in info.homeInfo.placedModels do
		if GameConfig.BrainrotIdMap[placed.configId] ~= nil then
			return true
		end
	end
	return false
end

local function CountCarryingBrainrotsInQueue(info: GameConfig.ClientLocalPlayerInfo): number
	local n = 0
	for _, item in info.brainrotQueue do
		if item.itemType == GameConfig.ItemType.Brainrot then
			n += 1
		end
	end
	return n
end

local function IsLocalPlayerCarryingBrainrot(): boolean
	if localPlayer == nil then
		return false
	end
	local character = localPlayer.Character
	if character == nil then
		return false
	end
	return character:FindFirstChild("CarryingBrainrot") ~= nil
end

local function HasEquippedBrainrotTool(): boolean
	if localPlayer == nil then
		return false
	end
	local character = localPlayer.Character
	if character == nil then
		return false
	end
	local queue = ClientGameInfo.GetBrainrotQueue()
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			local uid = child:GetAttribute("BrainrotUID")
			if uid ~= nil then
				local uidStr = tostring(uid)
				for _, item in queue do
					if item.uid == uidStr and (item.itemType or GameConfig.ItemType.Brainrot) == GameConfig.ItemType.Brainrot then
						return true
					end
				end
			end
		end
	end
	return false
end

local function IsBricksIntroFinished(info: GameConfig.ClientLocalPlayerInfo): boolean
	return info.guideProgressInfo.guideStepDoneMap[GameConfig.GuideStepKey.BricksIntroFinished] == true
end

local function IsBrainrotPlaceFinished(info: GameConfig.ClientLocalPlayerInfo): boolean
	return info.guideProgressInfo.guideStepDoneMap[GameConfig.GuideStepKey.BrainrotPlaceFinished] == true
end

local function ResolveNearestEmptyPlotPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	local slotModel = if homesFolder then homesFolder:FindFirstChild(info.homeSlot) :: Model? else nil
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local fallbackPos: Vector3? = nil

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr and plot:IsA("Model") then
					local pointIndex = tonumber(idxStr)
					if pointIndex ~= nil and info.homeInfo.placedModels[tostring(pointIndex)] == nil then
						local rootPart = plot:FindFirstChild("RootPart") :: BasePart?
						if rootPart then
							local placeAtt = rootPart:FindFirstChild("PlaceAttachment")
							local pos: Vector3
							if placeAtt and placeAtt:IsA("Attachment") then
								pos = placeAtt.WorldPosition
							else
								pos = rootPart.Position
							end
							if fallbackPos == nil then
								fallbackPos = pos
							end
							if origin ~= nil then
								local dist = (pos - origin).Magnitude
								if dist < bestDist then
									bestDist = dist
									bestPos = pos
								end
							end
						end
					end
				end
			end
		end
	end
	return bestPos or fallbackPos
end

local function GetWorldPositionFromInstance(inst: Instance): Vector3?
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

-- 放置引导终点：在所有空展台中找 PlaceModel*.Booth.BoothModel，取离 HRP 最近的世界坐标
local function ResolvePlacementBoothWorldPosition(info: GameConfig.ClientLocalPlayerInfo): Vector3?
	if info.homeSlot == nil or info.homeSlot == "" then
		return nil
	end
	local homesFolder = workspace:FindFirstChild("PlayersHome")
	if homesFolder == nil then
		return nil
	end
	local slotModel = homesFolder:FindFirstChild(info.homeSlot)
	if slotModel == nil then
		return nil
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil

	local path = GameConfig.GuidePlacementBoothPath
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local fallbackPos: Vector3? = nil

	for _, floor in ipairs(slotModel:GetChildren()) do
		if string.match(floor.Name, "^Lv%d+$") then
			for _, plot in ipairs(floor:GetChildren()) do
				local idxStr = string.match(plot.Name, "^PlaceModel(%d+)$")
				if idxStr and plot:IsA("Model") then
					local pointIndex = tonumber(idxStr)
					if pointIndex ~= nil and info.homeInfo.placedModels[tostring(pointIndex)] == nil then
						local boothFolder = plot:FindFirstChild(path.BoothFolderName)
						local boothModel = if boothFolder then boothFolder:FindFirstChild(path.BoothModelName) else nil
						if boothModel == nil then
							continue
						end
						local pos = GetWorldPositionFromInstance(boothModel)
						if pos == nil then
							continue
						end
						if fallbackPos == nil then
							fallbackPos = pos
						end
						if origin ~= nil then
							local dist = (pos - origin).Magnitude
							if dist < bestDist then
								bestDist = dist
								bestPos = pos
							end
						end
					end
				end
			end
		end
	end
	if bestPos ~= nil then
		return bestPos
	end
	if fallbackPos ~= nil then
		return fallbackPos
	end
	return ResolveNearestEmptyPlotPosition(info)
end

local function ResolvePickupBrainrotTarget(): Vector3?
	if not pickupCandidatesInitialized then
		InitPickupCandidates()
	end
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local origin = if hrp then hrp.Position else nil
	if origin == nil then
		return nil
	end
	local bestPart: BasePart? = nil
	local bestDist = math.huge
	for part in pairs(pickupCandidatePartMap) do
		if part.Parent == nil then
			pickupCandidatePartMap[part] = nil
			continue
		end
		local configId = part:GetAttribute("ConfigId") :: number?
		if configId ~= nil then
			local itemType = part:GetAttribute("ItemType") :: number?
			if itemType == nil or itemType == GameConfig.ItemType.Brainrot then
				local dist = (part.Position - origin).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestPart = part
				end
			end
		end
	end
	if bestPart then
		return bestPart.Position
	end
	return nil
end

local function ResolveUpgradeShopWorldPosition(): Vector3?
	local name = GameConfig.GuideWorldAnchorName.UpgradeShop
	local inst = workspace:FindFirstChild(name)
	if inst == nil then
		return nil
	end
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function ResolveWorldTargetForGuide(guideType: number): Vector3?
	if guideType == GameConfig.GuideType.TutorialBrainrotPlace or guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot then
		local info = ClientGameInfo.GetLocalPlayerInfo()
		if info == nil then
			return nil
		end
		return ResolvePlacementBoothWorldPosition(info)
	elseif guideType == GameConfig.GuideType.TutorialBrainrotPickup then
		return ResolvePickupBrainrotTarget()
	elseif guideType == GameConfig.GuideType.TutorialBricksLobby then
		return ResolveUpgradeShopWorldPosition()
	end
	return nil
end

local function GetLocalPlayerHrp(): BasePart?
	if localPlayer == nil then
		return nil
	end
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function UpdateAttachmentsRotation()
	local startAttachment = guideArrowStartAttachment
	local endAttachment = guideArrowEndAttachment
	if startAttachment == nil or endAttachment == nil then
		return
	end
	local rotation: CFrame = CFrame.new(startAttachment.Position, endAttachment.Position)
		:ToWorldSpace(CFrame.Angles(0, 0, math.rad(90))).Rotation
	startAttachment.CFrame = rotation + startAttachment.Position
	endAttachment.CFrame = rotation + endAttachment.Position
end

local function UpdateGuideArrow()
	if guideArrowModel == nil or guideArrowStartAttachment == nil or guideArrowEndAttachment == nil then
		return
	end
	local guideType = ClientGameInfo.GetCurrentGuideType()
	local needsWorldArrow = guideType == GameConfig.GuideType.TutorialBrainrotPickup
		or guideType == GameConfig.GuideType.TutorialBrainrotPlace
		or guideType == GameConfig.GuideType.TutorialBrainrotPlaceSlot
		or guideType == GameConfig.GuideType.TutorialBricksLobby
	if not needsWorldArrow then
		guideArrowModel.Parent = nil
		return
	end
	local hrp = GetLocalPlayerHrp()
	if hrp == nil then
		guideArrowModel.Parent = nil
		return
	end
	local now = os.clock()
	if cachedArrowGuideType ~= guideType or now - lastArrowTargetRefreshAt >= GUIDE_TARGET_REFRESH_INTERVAL then
		lastArrowTargetRefreshAt = now
		cachedArrowGuideType = guideType
		cachedArrowTarget = ResolveWorldTargetForGuide(guideType)
	end
	local target = cachedArrowTarget
	if target == nil then
		guideArrowModel.Parent = nil
		return
	end
	local startPos = hrp.Position
	local endPos = target + Vector3.new(0, GameConfig.GuideArrowYOffset, 0)
	guideArrowStartAttachment.WorldCFrame = CFrame.new(startPos)
	guideArrowEndAttachment.WorldCFrame = CFrame.new(endPos)
	UpdateAttachmentsRotation()
	guideArrowModel.Parent = workspace
end

local function ResolveGuideType(): number
	local info = ClientGameInfo.GetLocalPlayerInfo()
	if info == nil then
		return GameConfig.GuideType.None
	end

	if not HasBrainrotPlacedOnHome(info) and not IsBrainrotPlaceFinished(info) then
		if CountCarryingBrainrotsInQueue(info) > 0 then
			if IsLocalPlayerCarryingBrainrot() then
				return GameConfig.GuideType.TutorialBrainrotPlace
			end
			if not HasEquippedBrainrotTool() then
				return GameConfig.GuideType.TutorialBrainrotPlaceSlot
			end
			return GameConfig.GuideType.TutorialBrainrotPlace
		end
		if IsLocalPlayerCarryingBrainrot() then
			return GameConfig.GuideType.TutorialBrainrotPlace
		end
		return GameConfig.GuideType.TutorialBrainrotPickup
	end

	if IsBricksIntroFinished(info) then
		return GameConfig.GuideType.None
	end

	local coin = info.currencies["1"] or 0
	if coin >= GameConfig.GuideBricksIntroMinCoin and info.shopInfo.maxBricksLevel <= 1 then
		if UIManager.IsWindowShowing(UIManager.WindowId.UpgradeShop) then
			return GameConfig.GuideType.TutorialBricksShop
		end
		return GameConfig.GuideType.TutorialBricksLobby
	end

	return GameConfig.GuideType.None
end

local function RefreshGuideType()
	local now = os.clock()
	if now - lastGuideTypeRefreshAt < GUIDE_TYPE_REFRESH_INTERVAL then
		return
	end
	lastGuideTypeRefreshAt = now
	local currentGuideType = ResolveGuideType()
	if currentGuideType == lastGuideType then
		return
	end
	lastGuideType = currentGuideType
	ClientGameInfo.SetCurrentGuideType(currentGuideType)
end

local function ForceRefreshGuideType()
	lastGuideTypeRefreshAt = 0
	RefreshGuideType()
end

InitPickupCandidates = function()
	if pickupCandidatesInitialized then
		return
	end
	local islandsFolder = workspace:FindFirstChild("Islands")
	if islandsFolder == nil then
		return
	end
	pickupCandidatesInitialized = true
	for _, desc in islandsFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = true
		end
	end
	islandsFolder.DescendantAdded:Connect(function(desc: Instance)
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = true
		end
	end)
	islandsFolder.DescendantRemoving:Connect(function(desc: Instance)
		if desc:IsA("BasePart") then
			pickupCandidatePartMap[desc] = nil
		end
	end)
end

local function TryCreateArrowModel()
	local modelsFolder = replicatedStorage:FindFirstChild("Models")
	if modelsFolder == nil then
		return
	end
	local template = modelsFolder:FindFirstChild(GameConfig.GuideAssetName.ModelArrow)
	if template == nil then
		warn("[GuideManager] GuideArrow model not found:", GameConfig.GuideAssetName.ModelArrow)
		return
	end
	if not (template:IsA("Model") or template:IsA("BasePart")) then
		warn("[GuideManager] GuideArrow root must be Model or BasePart, got", template.ClassName)
		return
	end

	local clone = template:Clone()
	local container: Model
	if clone:IsA("Model") then
		container = clone :: Model
		container.Name = "ClientGuideArrow"
	else
		local rootPart = clone :: BasePart
		rootPart.Name = "GuideArrowRoot"
		container = Instance.new("Model")
		container.Name = "ClientGuideArrow"
		rootPart.Parent = container
	end

	local beam = container:FindFirstChild("ArrowBeam", true)
	local startAtt = container:FindFirstChild("StartAttachment", true)
	local endAtt = container:FindFirstChild("EndAttachment", true)
	if not (beam and beam:IsA("Beam") and startAtt and startAtt:IsA("Attachment") and endAtt and endAtt:IsA("Attachment")) then
		warn("[GuideManager] GuideArrow needs ArrowBeam, StartAttachment, EndAttachment in hierarchy")
		container:Destroy()
		return
	end

	beam.Attachment0 = startAtt
	beam.Attachment1 = endAtt
	beam.Enabled = true

	ApplyGuideArrowPhysics(container)

	guideArrowModel = container
	guideArrowStartAttachment = startAtt
	guideArrowEndAttachment = endAtt
end

function GuideManager.Init()
	if initialized then
		return
	end
	if localPlayer == nil then
		warn("[GuideManager] Init skipped: LocalPlayer is nil")
		return
	end
	initialized = true

	TryCreateArrowModel()
	InitPickupCandidates()

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerInventoryUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectLocalPlayerSkillLevelUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectBrainrotQueueUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectPlayerHomeInfoUpdate(function(playerId: number)
		local lp = localPlayer
		if lp and playerId == lp.UserId then
			ForceRefreshGuideType()
		end
	end)

	ClientMsg.ConnectLocalPlayerCurrencyUpdate(function()
		ForceRefreshGuideType()
	end)

	ClientMsg.ConnectCloseWindow(function()
		ForceRefreshGuideType()
	end)

	NetMsg.ConnectNotifyGuideProgressInfo(function(guideProgressInfo: GameConfig.GuideProgressSaveInfo)
		ClientGameInfo.UpdateGuideProgressInfo(guideProgressInfo)
	end)

	runService.RenderStepped:Connect(function()
		RefreshGuideType()
		UpdateGuideArrow()
	end)
end

return GuideManager
