--!strict
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local BrainrotData = require(script:FindFirstChild("BrainrotData"))
local UpgradeShopData = require(script:FindFirstChild("UpgradeShopData"))
local CoilData = require(script:FindFirstChild("CoilData"))
local LittleElfChestData = require(script:FindFirstChild("LittleElfChestData"))
local RebirthData = require(script:FindFirstChild("RebirthData"))

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
	rewardSource: number,
}

--奖励类型
GameConfig.RewardType = {
	Currency = 1, --货币
	Brainrot = 2, --宠物
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

GameConfig.Brainrots = BrainrotData
GameConfig.BrainrotNameMap = {} :: { [string]: BrainrotData }
GameConfig.BrainrotIdMap = {} :: { [number]: BrainrotData }

for _, config in pairs(BrainrotData) do
	GameConfig.BrainrotNameMap[config.resourceName] = config
	GameConfig.BrainrotIdMap[config.id] = config
end

export type CoilInfo = {
	id: number,
	coilType: number,
	speedValue: number,
	extraJumps: number,
	gravitationalValue: number,
	modelRes: string,
	name_t: string,
	description: string,
	iconImageId: string,
}

GameConfig.Coils = CoilData
GameConfig.CoilNameMap = {} :: { [string]: CoilInfo }
GameConfig.CoilIdMap = {} :: { [number]: CoilInfo }

for _, config in pairs(CoilData) do
	GameConfig.CoilNameMap[config.modelRes] = config
	GameConfig.CoilIdMap[config.id] = config
end

GameConfig.LittleElfChests = LittleElfChestData
GameConfig.LittleElfChestNameMap = {} :: { [string]: any }
GameConfig.LittleElfChestIdMap = {} :: { [number]: any }

for _, config in pairs(LittleElfChestData) do
	GameConfig.LittleElfChestNameMap[config.resourceName] = config
	GameConfig.LittleElfChestIdMap[config.id] = config
end

-- 重生配置
GameConfig.Rebirth = RebirthData
GameConfig.RebirthMap = {} :: { [number]: any }
for _, config in pairs(RebirthData) do
	GameConfig.RebirthMap[config.id] = config
end

-- 宠物质量配置 (已迁移到 GameConfig.BrainrotQualityConfig)

--宠物品质
GameConfig.BrainrotQualityConfig = {
	[1] = {
		rarity = "Common",
		image = "rbxassetid://16865599320",
		textColor = Color3.fromRGB(255, 255, 255),
	},
	[2] = {
		rarity = "Rare",
		image = "rbxassetid://16865599122",
		textColor = Color3.fromRGB(136, 255, 0),
	},
	[3] = {
		rarity = "Epic",
		image = "rbxassetid://16865598960",
		textColor = Color3.fromRGB(212, 0, 255),
	},
	[4] = {
		rarity = "Legend",
		image = "rbxassetid://16865598826",
		textColor = Color3.fromRGB(250, 59, 1),
	},
	[5] = {
		rarity = "Mythic",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(253, 203, 1),
	},
	[6] = {
		rarity = "Mythic",
		image = "rbxassetid://16865598729",
		textColor = Color3.fromRGB(253, 203, 1),
	},
}
--=========================================
-- 抓模型 (Catch Model) 核心数值配置
--=========================================

-- 1. 玩家铺砖逻辑
GameConfig.Paving = {
	BasePlaceCooldown = 0.2, -- 单位: 秒/块
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

GameConfig.Shop = {
	WalkSpeed = UpgradeShopData[1],
	MaxBricks = UpgradeShopData[2],
	HomeLevel = UpgradeShopData[3],
}

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
			rebirthLevel = 1,
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
