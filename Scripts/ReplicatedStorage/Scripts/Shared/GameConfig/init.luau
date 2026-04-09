--!strict
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local BrainrotDataModule = require(script:FindFirstChild("BrainrotData"))
local UpgradeShopDataModule = require(script:FindFirstChild("UpgradeShopData"))
local CoilDataModule = require(script:FindFirstChild("CoilData"))
local LittleElfChestDataModule = require(script:FindFirstChild("LittleElfChestData"))
local RebirthDataModule = require(script:FindFirstChild("RebirthData"))
local ShopBundleConfigurationDataModule = require(script:FindFirstChild("ShopBundleConfigurationData"))
local ShopBundleDataModule = require(script:FindFirstChild("ShopBundleData"))

--游戏版本
GameConfig.GameVersion = "1.0.1"
--本次AB测试版本
GameConfig.ABTestVersion = "1.0.0"
--玩家存档数据版本
GameConfig.PlayerSaveInfoDataVersion = 0
--正式版游戏id
GameConfig.GameId = 9971505831

if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 106064553761864
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 73637948383969
else
	--游戏场景
	GameConfig.GamePlaceId = 17432470623
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 18733054561
end

--通行证id
GameConfig.GamePassId = {}

--通行证价格
GameConfig.GamePassPrice = {}

GameConfig.CoinIconImage = "rbxassetid://138756794615498"
GameConfig.RbImage = "rbxassetid://116949418469040"
GameConfig.DecelerationOnImage = "rbxassetid://114216336762183"
GameConfig.DecelerationOffImage = "rbxassetid://113696020530948"
GameConfig.DecelerationButtonShowSpeed = 40

-- Guide（仅两条：Brainrot 拾取+放置；50 金币后升砖块）
GameConfig.GuideType = {
	None = 0,
	TutorialBrainrotPickup = 1,
	TutorialBrainrotPlace = 2,
	TutorialBricksLobby = 3,
	TutorialBricksShop = 4,
	-- 队列里有 Brainrot 但已收回 Tool：指引点击底部槽位重新装备
	TutorialBrainrotPlaceSlot = 5,
	-- 已在岛上拾取但未到主岛 Ground：先引导岛屿传送环
	TutorialBrainrotIslandTeleport = 6,
}

GameConfig.GuideStepKey = {
	BricksIntroFinished = "BricksIntroFinished",
	BrainrotPlaceFinished = "BrainrotPlaceFinished",
}

GameConfig.GuideBricksIntroMinCoin = 50

GameConfig.GuideWorldAnchorName = {
	UpgradeShop = "UpgradeShop",
}

GameConfig.GuideTextKeyMap = {
	[GameConfig.GuideType.TutorialBrainrotPickup] = "GuideTutorialBrainrotPickup",
	[GameConfig.GuideType.TutorialBrainrotPlace] = "GuideTutorialBrainrotPlace",
	[GameConfig.GuideType.TutorialBrainrotPlaceSlot] = "GuideTutorialBrainrotPlaceSlot",
	[GameConfig.GuideType.TutorialBricksLobby] = "GuideTutorialBricksLobby",
	[GameConfig.GuideType.TutorialBricksShop] = "GuideTutorialBricksShop",
	[GameConfig.GuideType.TutorialBrainrotIslandTeleport] = "GuideTutorialBrainrotIslandTeleport",
}

GameConfig.GuideAssetName = {
	UiFrame = "GuideFrame",
	ModelArrow = "GuideArrow",
}

GameConfig.GuideArrowYOffset = 4
-- 放置引导 Beam 终点：每个空展台 PlaceModel*.Booth.BoothModel 中取离玩家最近的一个（homeSlot 随玩家变化）
GameConfig.GuidePlacementBoothPath = {
	BoothFolderName = "Booth",
	BoothModelName = "BoothModel",
	CollectPartName = "CollectPart",
}

--六次方群组id
GameConfig.SixcubeGroupId = 33977495

--奖励信息
export type RewardInfo = {
	rewardType: number,
	rewardId: number,
	rewardCount: number,
	rewardSource: number?,
	rewardLv: number?,
	productIndex: number?,
}

--奖励类型
GameConfig.RewardType = {
	Currency = 1, --货币
	Brainrot = 2, --宠物
	Coil = 3, --线圈
	LittleElfChest = 4, --小精灵宝箱
}

--货币类型
GameConfig.CurrencyType = {
	Coin = 1, --金币
}

-- 技能类型
GameConfig.SkillType = {
	WalkSpeed = 1, -- 行走速度
	MaxBricks = 2, -- 最大容量
	HomeLevel = 3, -- 家园等级
	RebirthLevel = 4, -- 重生等级
}

-- 物品类型
GameConfig.ItemType = {
	Brainrot = 1,
	Coil = 2,
	LittleElfChest = 3,
}

-- model_get 埋点 get_source
GameConfig.ModelGetSource = {
	Island = 1,
	LittleElfChest = 2,
	Shop = 3,
	PlayerGift = 4,
}

-- 玩家间赠送（ProximityPrompt + Remote）；关闭时不显示提示且服务端拒绝流程
GameConfig.EnablePlayerGift = false

-- 线圈类型
GameConfig.CoilType = {
	Speed = 1, --速度
	DoubleJump = 2, --多段跳
	Gravity = 3, --重力
}

--游戏提示缓动方式
GameConfig.GameTipTweenType = {
	FlyUp = 1, --向上飞
	Twinkle = 2, --闪烁
	StayFlyUp = 3, --停留一段时间后向上飞
	FlyUpTwinkle = 4, --向上飞后闪烁
	Twinkle2 = 5,
}

--物品数量改变原因
GameConfig.ItemCountChangeReason = {
	--获得
	GainFromGMCommand = 1001, --GM命令获得
	GainFromPurchase = 1002, --内购获得
	GainFromSellModel = 1003, --出售模型获得
	GainFromCollect = 1004, --收集获得
	GainFromClaimModelYield = 1005, --领取模型收益获得

	--消耗
	SpendOnUpgradeBrainrot = 2001, --升级宠物
	SpendOnUpgradeHome = 2002, --升级家园
	SpendOnUpgradeWalkSpeed = 2003, --升级行走速度
	SpendOnUpgradeMaxBricks = 2004, --升级最大砖块数
}
-- 配置信息 (对应 BrainrotData.json)
export type BrainrotData = {
	id: number,
	name_t: string,
	resourceName: string,
	iconImageId: string,
	quality: number,
	baseAbility: number,
}

local RECOVERY = 0.8
local MAX_PAYBACK = 60 -- ← 唯一速节奏参数（秒）
local COST_RATE = 1.3

-- 第 n 级每秒收益（纯 n，严格递增）
function GameConfig.GetBrainrotAbility(baseAbility: number, level: number): number
	local linear = level + baseAbility - 1
	local expo = math.ceil(baseAbility * (1.2 ^ (level - 1)))
	return math.max(linear, expo)
end

-- 从 n 级升到 n+1 级的费用（回本 ≤ T 秒）
function GameConfig.GetBrainrotUpgradeCost(baseAbility: number, level: number): number
	local basePaybackTime = 5
	local maxPaybackTime = 600
	-- 1. 动态回本封顶时间 T(n) = min(5 + 2 * n, 600)
	local paybackTime = math.min(basePaybackTime + 2 * level, maxPaybackTime)

	-- 2. 系统期望重生次数 kexp(n) = (n-10) / 10 (向下取整)
	local expectedRebirthCount = math.max(math.floor((level-10) / 10),0)

	-- 3. 系统期望倍率 Mexp(n) = RebirthMult(kexp(n))
	local expectedMultiplier = 1
	if expectedRebirthCount > 0 then
		local maxRebirthId = if GameConfig.Rebirth then #GameConfig.Rebirth else 0
		local index = math.min(expectedRebirthCount, maxRebirthId)
		local rebirthConfig = GameConfig.RebirthMap[index]
		if rebirthConfig then
			expectedMultiplier = rebirthConfig.collectMultiple
		end
	end

	-- 4. 最终升级价格 UpgradeCost(n) = min(BASE_INCOME * 5 * 1.3^(n-1), BaseIncome(target_lv) * Mexp(n) * T(n))
	local raw = baseAbility * basePaybackTime * (COST_RATE ^ (level - 1))
	local nextIncome = GameConfig.GetBrainrotAbility(baseAbility, level + 1)
	local cap = nextIncome * expectedMultiplier * paybackTime

	return math.ceil(math.min(raw, cap))
end

-- 第 n 级的出售价格（等比级数闭合式 + 安全封顶）
function GameConfig.GetBrainrotSellPrice(baseAbility: number, level: number): number
	local geoSum = baseAbility * (COST_RATE ^ (level - 1) - 1) / (COST_RATE - 1)
	local capSum = MAX_PAYBACK * GameConfig.GetBrainrotAbility(baseAbility, level) * 2
	local sellBase = baseAbility * 10
	return math.ceil(sellBase + RECOVERY * math.min(geoSum, capSum))
end

-- 背包队列条目 (存盘)
export type BrainrotQueueItem = {
	-- 唯一实例ID (防止重复移除)
	uid: string,
	-- 物品类型 (1: Brainrot, 2: Coil)
	itemType: number,
	-- 宠物配置ID
	configId: number,
	-- 品质
	quality: number,
	-- 等级
	level: number,

	-- === 临时用途：商店/活动发放奖励的提示分组信息 ===
	-- 仅用于客户端在 UpdateBrainrotQueue 时判断是否需要播放“获得奖励”提示。
	-- 注意：该信息会随背包队列一起持久化，因此客户端必须通过“新uid”增量逻辑避免重复触发。
	grantTipKey: string?,
	grantExpectedCount: number?,
	grantShopBundleId: number?,
}

-- 玩家拥有的宠物信息 (存档)
export type BrainrotInfo = {
	-- 唯一实例ID
	instanceId: string,
	-- 宠物配置ID
	configId: number,
	-- 等级
	level: number,
	-- 获取时间
	acquireTime: number,
}

GameConfig.Brainrots = BrainrotDataModule
GameConfig.BrainrotNameMap = {} :: { [string]: BrainrotData }
GameConfig.BrainrotIdMap = {} :: { [number]: BrainrotData }

for _, config in pairs(BrainrotDataModule) do
	GameConfig.BrainrotNameMap[config.resourceName] = config
	GameConfig.BrainrotIdMap[config.id] = config
end

local function BuildResourceNameCandidates(resourceName: string): { string }
	local candidateMap: { [string]: boolean } = {}
	local candidates: { string } = {}

	local function addCandidate(name: string)
		if name == "" or candidateMap[name] then
			return
		end
		candidateMap[name] = true
		table.insert(candidates, name)
	end

	addCandidate(resourceName)
	addCandidate((string.gsub(resourceName, "_", " ")))
	addCandidate((string.gsub(resourceName, " ", "_")))
	return candidates
end

function GameConfig.GetResourceNameCandidates(resourceName: string): { string }
	return BuildResourceNameCandidates(resourceName)
end

function GameConfig.FindModelByResourceName(folder: Instance?, resourceName: string): Model?
	if not folder or resourceName == "" then
		return nil
	end

	for _, candidateName in ipairs(BuildResourceNameCandidates(resourceName)) do
		local found = folder:FindFirstChild(candidateName)
		if found and found:IsA("Model") then
			return found
		end
	end

	return nil
end

export type CoilData = {
	id: number,
	coilType: number,
	speedValue: number,
	extraJumps: number,
	gravitationalValue: number,
	modelRes: string,
	name_t: string,
	description_t: string,
	iconImageId: string,
	quality: number,
}

GameConfig.Coils = CoilDataModule
GameConfig.CoilNameMap = {} :: { [string]: CoilData }
GameConfig.CoilIdMap = {} :: { [number]: CoilData }

for _, config in pairs(CoilDataModule) do
	GameConfig.CoilNameMap[config.modelRes] = config
	GameConfig.CoilIdMap[config.id] = config
end

-- LittleElfChest 配置
export type LittleElfChestData = {
	id: number,
	name_t: string,
	resourceName: string,
	iconImageId: string,
	quality: number,
}

GameConfig.LittleElfChests = LittleElfChestDataModule
GameConfig.LittleElfChestNameMap = {} :: { [string]: LittleElfChestData }
GameConfig.LittleElfChestIdMap = {} :: { [number]: LittleElfChestData }

for _, config in pairs(LittleElfChestDataModule) do
	GameConfig.LittleElfChestNameMap[config.resourceName] = config
	GameConfig.LittleElfChestIdMap[config.id] = config
end

-- 岛屿配置
export type IslandData = {
	id: number,
	islandName: string,
	itemMinLv: number,
	itemMaxLv: number,
	rebirthCount: number,
	brainrotGenerateCount: number,
	littleElfChestGenerateCount: number,

	-- 岛屿地震配置（从 GameConfig.Earthquake 拆分）
	floatBlockDropCountJudge: number?,
	dropRecoverDelayMin: number?,
	dropRecoverDelayMax: number?,
}

local IslandConfigurationDataModule = require(script:FindFirstChild("IslandConfigurationData"))
GameConfig.IslandConfigMap = {} :: { [number]: IslandData }
for _, config in pairs(IslandConfigurationDataModule) do
	GameConfig.IslandConfigMap[config.id] = config
end

--=========================================
-- 岛屿地震配置（从 GameConfig.Earthquake 拆分）
--=========================================
export type IslandEarthquakeData = {
	floatBlockDropCountJudge: number,
	DropRecoverDelayMin: number,
	DropRecoverDelayMax: number,
}

local DEFAULT_FLOAT_BLOCK_DROP_COUNT_JUDGE = 1
local DEFAULT_DROP_RECOVER_DELAY_MIN = 2.5
local DEFAULT_DROP_RECOVER_DELAY_MAX = 4.5

GameConfig.IslandEarthquakeConfigMap = {} :: { [number]: IslandEarthquakeData }
for islandId, islandData in pairs(GameConfig.IslandConfigMap) do
	local anyIslandData = islandData :: any

	GameConfig.IslandEarthquakeConfigMap[islandId] = {
		floatBlockDropCountJudge = anyIslandData.floatBlockDropCountJudge or DEFAULT_FLOAT_BLOCK_DROP_COUNT_JUDGE,
		DropRecoverDelayMin = anyIslandData.dropRecoverDelayMin or DEFAULT_DROP_RECOVER_DELAY_MIN,
		DropRecoverDelayMax = anyIslandData.dropRecoverDelayMax or DEFAULT_DROP_RECOVER_DELAY_MAX,
	}
end

-- 岛屿刷怪配置
export type IslandSpawnerData = {
	id: number,
	itemType: number,
	itemId: number,
	weight: number,
}

local IslandSpawnerDataModule = require(script:FindFirstChild("IslandSpawnerData"))
GameConfig.IslandSpawnerMap = {} :: { [number]: { IslandSpawnerData } }
for _, config in pairs(IslandSpawnerDataModule) do
	local islandId = config.id
	if not GameConfig.IslandSpawnerMap[islandId] then
		GameConfig.IslandSpawnerMap[islandId] = {}
	end
	table.insert(GameConfig.IslandSpawnerMap[islandId], config)
end

-- 小精灵宝箱奖励池配置 (对应 LittleElfChestRewardPoolData.luau)
export type LittleElfChestRewardPoolData = {
	id: number,
	itemType: number,
	itemId: number,
	weight: number,
}

local LittleElfChestRewardPoolDataModule = require(script:FindFirstChild("LittleElfChestRewardPoolData"))
GameConfig.LittleElfChestRewardPoolMap = {} :: { [number]: { LittleElfChestRewardPoolData } }
for _, config in pairs(LittleElfChestRewardPoolDataModule) do
	local chestId = config.id
	if not GameConfig.LittleElfChestRewardPoolMap[chestId] then
		GameConfig.LittleElfChestRewardPoolMap[chestId] = {}
	end
	table.insert(GameConfig.LittleElfChestRewardPoolMap[chestId], config)
end

-- 重生配置 (对应 RebirthData.luau)
export type RebirthData = {
	id: number,
	count: number,
	collectMultiple: number,
	brickLv: number,
	speedLv: number,
}

GameConfig.Rebirth = RebirthDataModule
GameConfig.RebirthMap = {} :: { [number]: RebirthData }
for _, config in pairs(RebirthDataModule) do
	GameConfig.RebirthMap[config.id] = config
end

-- 宠物质量配置 (已迁移到 GameConfig.BrainrotQualityConfig)

--品质
GameConfig.BrainrotQualityConfig = {
	[1] = {
		rarity = "Common",
		image = "rbxassetid://16865599320",
		textColor = Color3.fromRGB(255, 255, 255),
	},
	[2] = {
		rarity = "Uncommon",
		image = "rbxassetid://16865599320",
		textColor = Color3.fromRGB(73, 230, 0),
	},
	[3] = {
		rarity = "Rare",
		image = "rbxassetid://16865599122",
		textColor = Color3.fromRGB(0, 255, 217),
	},
	[4] = {
		rarity = "Epic",
		image = "rbxassetid://16865598960",
		textColor = Color3.fromRGB(30, 144, 255),
	},
	[5] = {
		rarity = "Legendary",
		image = "rbxassetid://16865598826",
		textColor = Color3.fromRGB(255, 0, 255),
	},
	[6] = {
		rarity = "Mythical",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(136, 0, 255),
	},
	[7] = {
		rarity = "Cosmic",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(255, 0, 68),
	},
	[8] = {
		rarity = "Secret",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(255, 136, 0),
	},
	[9] = {
		rarity = "Celestial",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(255, 234, 1),
	},
}

--RobuxIcon文本
GameConfig.RobuxIconText = "\u{E002}"

GameConfig.BrainrotQualityTextMap = {
	[1] = "QualityCommon",
	[2] = "QualityUncommon",
	[3] = "QualityRare",
	[4] = "QualityEpic",
	[5] = "QualityLegendary",
	[6] = "QualityMythical",
	[7] = "QualityCosmic",
	[8] = "QualitySecret",
	[9] = "QualityCelestial",
}

-- 等级文字颜色：以 BrainrotLevelTierSize 为步长；等级为 30 的倍数且 >=30 时升入下一档（floor(level/30)+1），颜色与 BrainrotQualityConfig 同索引对齐；超出最高档沿用最后一档
GameConfig.BrainrotLevelTierSize = 30

local brainrotQualityMaxTierForLevelColor = 0
for tierKey in pairs(GameConfig.BrainrotQualityConfig) do
	if type(tierKey) == "number" and tierKey > brainrotQualityMaxTierForLevelColor then
		brainrotQualityMaxTierForLevelColor = tierKey
	end
end

GameConfig.BrainrotLevelTierTextColors = {} :: { [number]: Color3 }
for tier = 1, brainrotQualityMaxTierForLevelColor do
	local qc = GameConfig.BrainrotQualityConfig[tier]
	if qc then
		GameConfig.BrainrotLevelTierTextColors[tier] = qc.textColor
	end
end

function GameConfig.GetBrainrotLevelTierTextColor(level: number): Color3
	local safeLevel = math.max(1, math.floor(level))
	-- 1–29 档 1；30–59 档 2；…（30/60/… 整除点算升档，不用 ceil）
	local tierIndex = math.floor(safeLevel / GameConfig.BrainrotLevelTierSize) + 1
	tierIndex = math.min(tierIndex, brainrotQualityMaxTierForLevelColor)
	local c = GameConfig.BrainrotLevelTierTextColors[tierIndex]
	return if c then c else Color3.new(1, 1, 1)
end

--=========================================
-- 抓模型 (Catch Model) 核心数值配置
--=========================================

-- 1. 玩家铺砖逻辑
GameConfig.Paving = {
	BaseCollapseTime = 10, -- 砖块生命周期: 10秒
	SteppedPenalty = 5, -- 被其他玩家踩踏一次扣5秒寿命
	MinCollapseTime = 0.5, -- 被踩踏后的保底存活时间（容错）
	BackBricksMaxVisual = 100, -- 玩家背部最多显示的砖块模型数量
	BrickSize = Vector3.new(4, 1, 4), -- 砖块尺寸
	MaxBatchSize = 15, -- 单次包最大砖块数
	LocalPredictTTL = 1.5, -- 本地预测砖块存在时间
	BatchInterval = 0.06, -- 客户端常态打包发送间隔（高吞吐，约16.7Hz）
	-- 常态与地震统一为高吞吐参数，减少非地震与地震手感差异
	MaxPendingBatchesDuringEarthquake = 8,
	BatchIntervalDuringEarthquake = 0.06,
	MaxInterpolationSteps = 5, -- 最大插值步数，防止长距离瞬移导致卡顿
	MaxInterpolationStepsAtHighSpeed = 10, -- 高速下提高插值步数上限
	HighSpeedLookaheadMaxFactor = 2.2, -- 高速下前瞻倍率上限
	FirstBrickForceQueueCooldown = 0.12, -- 首块兜底强制入队最短间隔
	BatchAckTimeout = 0.9, -- 批回执超时判定（秒）
	MaxPendingBatches = 8, -- 客户端最多允许在途批次数（高吞吐背压上限）
	OutOfBricksSupportTime = 1.2, -- 无砖时对脚下已拥有砖的保底续命时间
	OutOfBricksSupportRenewThreshold = 0.35, -- 无砖保底续命触发阈值（相对 BaseCollapseTime）
	OutOfBricksSupportRequestInterval = 0.12, -- 客户端无砖保底续命请求间隔
	DeathThreshold = -10, -- 死亡触发高度阈值 (相对于 SEA_LEVEL)
	DeathRescueProductId = 3567697241, -- 翅膀援助购买产品ID
	PavingDistanceLimit = 30, -- 距离玩家超过此距离则不让铺
	StationaryRenewalThreshold = 0.9, -- 剩余寿命低于 70% 时才允许原地续期
	StationaryRenewalMaxRemainingTime = 1, -- 原地续期最大剩余时间
	StationaryRenewalInterval = 0.2, -- 原地续期检测间隔 (加快响应)
	RebirthProductId = 3567723594, -- 付费重生产品ID
	-- StartTrigger 补砖请求最小间隔（防刷 Remote）；过大会导致快速经过时漏补
	StartTriggerRefillCooldown = 0.15,
	-- Ground：Touch 触发 FireRequestStartPaving 的最小间隔（用于 UI 砖数与服务端同步）
	GroundTouchRefillCooldown = 0.15,
	-- Ground：在地面站立时周期性请求补砖，刷新 UI 携带砖数（秒）
	GroundPollRefillInterval = 2,
	-- Ground 补砖区兜底竖直射线的向下长度（stud）；需覆盖跳跃/多段跳高度，避免起跳后服务端拒补
	RefillSurfaceRayLength = 80,
	-- 脚底世界 Y 低于 SEA_LEVEL 超过该 stud 时禁止海平面铺砖（坑底 Start 等在 FallSafePit 外时仍生效）；可按关卡微调
	NoPaveWhenFeetBelowSeaStuds = 3,
}

GameConfig.PavingRejectReason = {
	InvalidPayload = "InvalidPayload",
	BatchTooLarge = "BatchTooLarge",
	NotVector3 = "NotVector3",
	SafeZoneBlocked = "SafeZoneBlocked",
	FloatBlockBlocked = "FloatBlockBlocked",
	HeightMismatch = "HeightMismatch",
	DistanceLimit = "DistanceLimit",
	OutOfBricks = "OutOfBricks",
	OccupiedByOther = "OccupiedByOther",
	ServerBackpressure = "ServerBackpressure",
	FallSafePitBlocked = "FallSafePitBlocked",
}

-- 升级家园 HomePart.InfoUI 显示距离（水平距离；<=隐藏，>显示）
GameConfig.UpgradeHomeInfoUIDistanceLimit = 40

-- 家园展台 PlaceModel.InfoUI / 放置 VisualModel 上 BrainrotInfoUI 的 Billboard 竖直 padding（Studs）
GameConfig.HomePlaceModelInfoUIBillboardPadding = 0.5
GameConfig.HomePlaceModelInfoUIBillboardOffsetY = 5

-- 地震系统配置
GameConfig.Earthquake = {
	IntervalMin = 10, -- 两次地震最短间隔
	IntervalMax = 12, -- 两次地震最长间隔
	Duration = 5, -- 单次地震总时长
	CooldownAfterEnd = 2, -- 地震结束后冷却
	MinPlayersToTrigger = 1, -- 最少在线人数

	-- 客户端表现参数
	IntenseShakeAmplitude = 0.45, -- 强烈抖动振幅
	IntenseShakeFrequency = 48, -- 强烈抖动频率
	PreFallIntenseDuration = 0.2, -- 掉落前强抖时长
	FallDuration = 0.25, -- 下落时长
	RiseDuration = 1.15, -- 回浮时长
	FallOffsetY = 30, -- 下沉高度（海平面以下）
	WarningSeconds = 0, -- 地震来临前预警时长（秒）
	-- 玩家砖震落后销毁延迟（应与客户端强抖+下落总时长接近）
	PavedBrickDestroyDelayAfterDrop = 1.15,

	-- 标记表现（地震开始时将要掉落的块染色&抖动）
	MarkedBrickColor = Color3.fromRGB(255, 0, 25),
	-- 标记阶段透明度（0～1，客户端）；浮块与铺砖可分别配置
	MarkedFloatBlockTransparency = 0.5,
	MarkedPavedBrickTransparency = 0.5,
	MarkedShakeAmplitude = 0.6, -- FloatBlock 标记抖动振幅（客户端）
	MarkedShakeFrequency = 48, -- FloatBlock 标记抖动频率（客户端）
	MarkedPavedShakeAmplitude = 0.22, -- 砖块标记抖动振幅（客户端，单独更缓）
	MarkedPavedShakeFrequency = 13, -- 砖块标记抖动频率（客户端，单独更缓）

	-- 地震结束后执行掉落总时窗（全部块在该时长内执行完）
	DropExecuteWindowSeconds = 1.0,

	-- 纯表现断裂（客户端碎片颗粒/假碎片）
	FractureShardLifeTime = 0.5, -- 假碎片持续时间（秒）
	FractureShardPerBlock = 5, -- 每个块生成假碎片数量（小型视觉开销）

	-- 地震时本地镜头抖动（CameraOffset，避免移动锚固平台导致与服务器物理不同步穿模）
	ScreenShakeAmplitude = 0,
	ScreenShakeFrequency = 0,
}

-- 2. 模型与收益逻辑 (已废弃 GameConfig.Models，现在由 BrainrotData.json 驱动)
export type ModelRarity = "Common" | "Rare" | "Epic" | "Legend"

-- 3. 背包初始状态
GameConfig.Inventory = {
	InitialModelCapacity = 5,
	InitialBricksCapacityLevel = 1, -- 初始容量等级，而非初始砖块数
}

-- Brainrot 背包队列配置
GameConfig.BrainrotQueue = {
	MaxCapacity = 9, -- 背包最多容纳 9 个 Brainrot
}

-- Island spawned Brainrot 的独立倒计时（秒）
-- 倒计时结束时该 brainrot 消失并触发岛上随机补刷。
GameConfig.BrainrotRefreshCountdownSeconds = 150

-- 商店配置
export type UpgradeShopData = {
	id: number,
	name_t: string,
	maxLevel: number,
	abilityList: { number },
	upgradeCostList: { number },
}

export type ShopBundleConfigurationData = {
	id: number,
	type: number,
	canRepurchased: number,
	nameColor: { number },
	productId1: number,
	productId2: number,
	productId3: number,
	price1: number,
	price2: number,
	price3: number,
	beforeDiscountPrice2: number,
	beforeDiscountPrice3: number,
	name_t: string,
	sortId: number,
	bgIconId: string,
	-- 非 0：受 PolicyService.ArePaidRandomItemsRestricted 约束的付费随机类 bundle
	arePaidRandomItemsRestricted: number,
}

export type ShopBundleData = {
	config: ShopBundleConfigurationData,
	rewards: { RewardInfo },
}

local transformedShopData: { [number]: UpgradeShopData } = {}
for _, entry in pairs(UpgradeShopDataModule) do
	local skillType = entry.type
	if not transformedShopData[skillType] then
		transformedShopData[skillType] = {
			id = skillType,
			name_t = entry.name_t,
			maxLevel = 0,
			abilityList = {},
			upgradeCostList = {},
		}
	end
	local target = transformedShopData[skillType]
	target.abilityList[entry.lv] = entry.ability
	target.upgradeCostList[entry.lv] = entry.upgradeCost
	target.maxLevel = math.max(target.maxLevel, entry.lv)
end

-- upgradeCostList[L] 表示从 L 级升到 L+1 的消耗；最高等级行上的 upgradeCost 不应存在，
-- 否则服务端会认为还能升到 L+1，而 abilityList[L+1] 不存在，表现为满级属性读成 1 级或其它回退值。
for _, target in pairs(transformedShopData) do
	if target.maxLevel > 0 then
		target.upgradeCostList[target.maxLevel] = nil
	end
end

GameConfig.Shop = {
	WalkSpeed = transformedShopData[GameConfig.SkillType.WalkSpeed],
	MaxBricks = transformedShopData[GameConfig.SkillType.MaxBricks],
	HomeLevel = transformedShopData[GameConfig.SkillType.HomeLevel],
}

GameConfig.ShopBundleById = {} :: { [number]: ShopBundleData }
GameConfig.ShopBundleList = {} :: { number }
for _, config: ShopBundleConfigurationData in pairs(ShopBundleConfigurationDataModule) do
	GameConfig.ShopBundleById[config.id] = {
		config = config,
		rewards = {},
	}
	table.insert(GameConfig.ShopBundleList, config.id)
end
table.sort(GameConfig.ShopBundleList, function(idA, idB)
	local configA = GameConfig.ShopBundleById[idA]
	local configB = GameConfig.ShopBundleById[idB]
	if configA == nil or configB == nil then
		return idA < idB
	end
	if configA.config.sortId == configB.config.sortId then
		return configA.config.id < configB.config.id
	end
	return configA.config.sortId < configB.config.sortId
end)
for _, rewardEntry in pairs(ShopBundleDataModule) do
	local bundle = GameConfig.ShopBundleById[rewardEntry.id]
	if bundle then
		local rewardInfo: RewardInfo = {
			rewardType = rewardEntry.rewardType,
			rewardId = rewardEntry.rewardId,
			rewardCount = rewardEntry.rewardCount,
			rewardLv = rewardEntry.rewardLv,
			productIndex = rewardEntry.productIndex or 1,
		}
		table.insert(bundle.rewards, rewardInfo)
	end
end

-- 商店付费配置（内购商品ID）
export type ShopPaidConfig = {
	WalkSpeed10ProductId: number,
	MaxBricks10ProductId: number,
	BrainrotUpgrade3ProductId: number,
}

GameConfig.ShopPaid = {
	WalkSpeed10ProductId = 3567697343,
	MaxBricks10ProductId = 3567697394,
	BrainrotUpgrade3ProductId = 3568879048,
} :: ShopPaidConfig

-- 实体模型信息
export type ModelInfo = {
	-- 唯一实例ID
	instanceId: string,
	-- 模型配置ID
	configId: number,
	-- 稀有度
	rarity: ModelRarity,
	-- 等级
	level: number,
	-- 未领取收益
	unclaimedYield: number?,
	-- 当前未领取收益开始累积的 Unix 秒（埋点 duration_sec = 领取时刻 - 本值；重连后仍有效）
	yieldAccrueStartUnix: number?,
	-- 旧版：按秒累加计数（仅用于读档迁移，新逻辑请用 yieldAccrueStartUnix）
	yieldAccruedSeconds: number?,
}

--玩家设置信息
export type SettingInfo = {
	--背景音乐音量
	bgmVolume: number,
	--音效音量
	soundEffectVolume: number,
	--是否开启震动
	vibrationOn: boolean,
	--是否开启减速（锁定为1级速度）
	decelerationOn: boolean,
}
--玩家配置信息
export type PlayerConfigInfo = {
	-- PolicyService:GetPolicyInfoForPlayerAsync → ArePaidRandomItemsRestricted
	arePaidRandomItemsRestricted: boolean,
}

-- [抓模型] 持久化背包信息 (存档用)
export type PlayerInventorySaveInfo = {
	models: { ModelInfo },
}

-- [抓模型] 宠物信息 (存档用)
export type BrainrotInventoryInfo = {
	ownedBrainrots: { [string]: BrainrotInfo }, -- instanceId -> BrainrotInfo
	equippedBrainrots: { string }, -- instanceId 列表
	brainrotUsingNumMax: number,
}

-- [抓模型] 运行时搬运信息 (瞬态，不存盘)
export type PlayerCarriedInfo = {
	bricks: number, -- 当前背上的砖块数量
}

export type GuideProgressSaveInfo = {
	guideStepDoneMap: { [string]: boolean },
	appearedGuideTypeInfo: { [string]: boolean },
}

export type PlayerSaveInfo = {
	--数据版本
	dataVersion: number,
	--首次进入游戏的时间
	firstEnterTime: number,
	--首次进入游戏的版本
	firstEnterVersion: string,
	--玩家累计游戏时间
	gameTime: number,
	--玩家累计登录天数
	loginDays: number,
	--玩家最后在线日期时间戳
	lastOnlineDateUTC: number,
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },

	--已拥有的商店捆绑奖励（用于不可复购遮罩）
	ownedShopBundleMap: { [number]: boolean },

	-- [抓模型] 玩家货币 (Key为币种ID的字符串)
	currencies: { [string]: number },
	-- [抓模型] 背包信息 (持久化)
	inventoryInfo: PlayerInventorySaveInfo,
	-- [抓模型] 基地信息
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	-- [抓模型] 商店升级信息
	shopInfo: {
		walkSpeedLevel: number,
		maxBricksLevel: number,
		rebirthLevel: number,
	},
	-- [抓模型] 宠物信息
	brainrotsInfo: BrainrotInventoryInfo,
	-- [Brainrot背包] Brainrot 队列 (存盘)
	brainrotQueue: { BrainrotQueueItem },
	-- 引导进度
	guideProgressInfo: GuideProgressSaveInfo,
	-- 已发现过的岛屿 id（生涯首次到达，用于埋点）
	discoveredIslandIds: { [string]: boolean }?,
}

export type PlayerInfo = PlayerSaveInfo & {
	--玩家信息是否发生变化
	playerInfoChanged: boolean,
	--本次上线时间
	timeOfThisLogin: number,
	--玩家的国家/地区
	countryRegion: string,
	--玩家最后在线日期
	lastOnlineDate: DateTimeExtension.DateTimeTable,
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
	-- [抓模型] 基地玩家槽位
	homeSlot: string,

	-- [抓模型] 运行时瞬态数据
	carriedInfo: PlayerCarriedInfo,
	-- 最近一次脚下判定为有效岛屿的 id（用于 player_death 等；默认 1）
	lastArrivedIslandId: number,
}

--内购订单信息
export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}

--默认玩家存档
function GameConfig.CreateDefaultPlayerSaveInfo(): PlayerSaveInfo
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	return {
		dataVersion = GameConfig.PlayerSaveInfoDataVersion,
		firstEnterTime = DateTime.now().UnixTimestamp,
		firstEnterVersion = GameConfig.GameVersion,
		gameTime = 0,
		loginDays = 1,
		lastOnlineDateUTC = DateTime.fromUniversalTime(nowDate.Year, nowDate.Month, nowDate.Day).UnixTimestamp,
		settingInfo = {
			bgmVolume = 1,
			soundEffectVolume = 1,
			vibrationOn = true,
			decelerationOn = false,
		},
		ownedGamePassList = {},
		ownedShopBundleMap = {},
		currencies = {
			["1"] = 0, -- 默认初始化金币
		},
		inventoryInfo = {
			models = {},
		},
		homeInfo = {
			level = 1,
			placedModels = {},
		},
		shopInfo = {
			walkSpeedLevel = 1,
			maxBricksLevel = GameConfig.Inventory.InitialBricksCapacityLevel,
			rebirthLevel = 0,
		},
		brainrotsInfo = {
			ownedBrainrots = {},
			equippedBrainrots = {},
			brainrotUsingNumMax = 3, -- 默认最大携带3只
		},
		brainrotQueue = {},
		guideProgressInfo = {
			guideStepDoneMap = {},
			appearedGuideTypeInfo = {},
		},
		discoveredIslandIds = {},
	}
end

--客户端自己的玩家信息
export type ClientLocalPlayerSaveInfo = {
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },

	--已拥有的商店捆绑奖励（用于不可复购遮罩）
	ownedShopBundleMap: { [number]: boolean },

	-- [抓模型] 玩家货币 (Key为币种ID的字符串)
	currencies: { [string]: number },
	-- [抓模型] 背包信息
	inventoryInfo: PlayerInventorySaveInfo,
	-- [抓模型] 基地信息
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	-- [抓模型] 商店升级信息
	shopInfo: {
		walkSpeedLevel: number,
		maxBricksLevel: number,
		rebirthLevel: number,
	},
	-- [抓模型] 宠物信息
	brainrotsInfo: BrainrotInventoryInfo,
	-- [抓模型] Brainrot 背包队列 (存盘)
	brainrotQueue: { BrainrotQueueItem },
	-- [抓模型] 基地玩家槽位
	homeSlot: string,
	-- 引导进度
	guideProgressInfo: GuideProgressSaveInfo,
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,

	-- [抓模型] 运行时瞬态数据
	carriedInfo: PlayerCarriedInfo,
	-- 当前引导类型（客户端）
	currentGuideType: number,
}

--客户端其他玩家信息
export type ClientOtherPlayerSaveInfo = {
	homeSlot: string,
	homeInfo: {
		level: number,
		placedModels: { [string]: ModelInfo },
	},
	rebirthLevel: number?,
}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

return GameConfig
