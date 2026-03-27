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
GameConfig.GameVersion = "1.0.0"
--本次AB测试版本
GameConfig.ABTestVersion = "1.0.0"
--玩家存档数据版本
GameConfig.PlayerSaveInfoDataVersion = 0
--正式版游戏id
GameConfig.GameId = 6376748064
if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 17432470623
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 18733054561
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

--六次方群组id
GameConfig.SixcubeGroupId = 33977495

--奖励信息
export type RewardInfo = {
	rewardType: number,
	rewardId: number,
	rewardCount: number,
	rewardSource: number?,
	rewardLv: number?,
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

-- 线圈类型
GameConfig.CoilType = {
	Speed = 1,
	DoubleJump = 2,
	Gravity = 3,
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

--第 n 级每秒收益（纯 n 计算）
function GameConfig.GetBrainrotAbility(baseAbility: number, level: number): number
	local linear = level + baseAbility - 1
	local expo = math.ceil(baseAbility * (1.2 ^ (level - 1)))
	return math.max(linear, expo)
end

-- 从第 n 级升到 n+1 级的费用
function GameConfig.GetBrainrotUpgradeCost(baseAbility: number, level: number): number
	local raw = baseAbility * math.pow(1.3, level - 1)
	local cap = 10 * GameConfig.GetBrainrotAbility(baseAbility, level + 1)
	return math.ceil(math.min(raw, cap))
end

-- 第 n 级的出售价格
function GameConfig.GetBrainrotSellPrice(baseAbility: number, level: number): number
	local geoSum = baseAbility * (math.pow(1.3, level - 1) - 1) / (1.3 - 1)
	local capSum = 10 * GameConfig.GetBrainrotAbility(baseAbility, level) * 2
	local recovery = 0.8
	return math.ceil(baseAbility * 10 + recovery * math.min(geoSum, capSum))
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

export type CoilData = {
	id: number,
	coilType: number,
	speedValue: number,
	extraJumps: number,
	gravitationalValue: number,
	modelRes: string,
	name_t: string,
	description: string,
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
}

local IslandConfigurationDataModule = require(script:FindFirstChild("IslandConfigurationData"))
GameConfig.IslandConfigMap = {} :: { [number]: IslandData }
for _, config in pairs(IslandConfigurationDataModule) do
	GameConfig.IslandConfigMap[config.id] = config
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
		textColor = Color3.fromRGB(168, 230, 163),
	},
	[3] = {
		rarity = "Rare",
		image = "rbxassetid://16865599122",
		textColor = Color3.fromRGB(0, 255, 0),
	},
	[4] = {
		rarity = "Epic",
		image = "rbxassetid://16865598960",
		textColor = Color3.fromRGB(30, 144, 255),
	},
	[5] = {
		rarity = "Legendary",
		image = "rbxassetid://16865598826",
		textColor = Color3.fromRGB(128, 0, 128),
	},
	[6] = {
		rarity = "Mythical",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(75, 0, 130),
	},
	[7] = {
		rarity = "Cosmic",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(255, 165, 0),
	},
	[8] = {
		rarity = "Secret",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(255, 215, 0),
	},
	[9] = {
		rarity = "Celestial",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(240, 230, 140),
	},
}

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
	BatchInterval = 0.1, -- 客户端打包发送间隔（10Hz）
	MaxInterpolationSteps = 5, -- 最大插值步数，防止长距离瞬移导致卡顿
	DeathThreshold = -10, -- 死亡触发高度阈值 (相对于 SEA_LEVEL)
	DeathRescueProductId = 3561975643, -- 翅膀援助购买产品ID (TODO: 修改实际ID)
	StartActivationRange = 5, -- 修改：从 1 增加到 5，确保护跑时有足够的重合区域。
	PavingDistanceLimit = 30, -- 距离玩家超过此距离则不让铺
	StationaryRenewalThreshold = 0.7, -- 剩余寿命低于 70% 时才允许原地续期
	StationaryRenewalInterval = 0.2, -- 原地续期检测间隔 (加快响应)
	RebirthProductId = 3562550008, -- 付费重生产品ID
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
	productId: number,
	price: number,
	name_t: string,
	sortId: number,
	bgIconId: string,
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
		}
		table.insert(bundle.rewards, rewardInfo)
	end
end

-- 商店付费配置（内购商品ID：后续由你替换真实数值）
export type ShopPaidConfig = {
	WalkSpeed10ProductId: number,
	MaxBricks10ProductId: number,
}

GameConfig.ShopPaid = {
	WalkSpeed10ProductId = 3563778722,
	MaxBricks10ProductId = 3563778785,
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
}

--玩家设置信息
export type SettingInfo = {
	--背景音乐音量
	bgmVolume: number,
	--音效音量
	soundEffectVolume: number,
	--是否开启震动
	vibrationOn: boolean,
}
--玩家配置信息
export type PlayerConfigInfo = {}

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
		},
		ownedGamePassList = {},
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
	}
end

--客户端自己的玩家信息
export type ClientLocalPlayerSaveInfo = {
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },

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
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,

	-- [抓模型] 运行时瞬态数据
	carriedInfo: PlayerCarriedInfo,
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
