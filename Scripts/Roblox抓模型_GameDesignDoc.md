# Roblox 抓模型 - 完整游戏设计与系统架构文档

## 一、 核心玩法与游戏循环

本游戏的核心玩法围绕“探索-收集-建造-收益”四个环节展开。玩家通过消耗资源铺设道路前往未知岛屿，收集模型带回基地（Home），将其放置在展台上产生挂机收益，最终利用收益强化自身能力或扩建基地。

### 玩家核心操作流程图

```text
[玩家 Home]
   │
   ▼
[进入海面] ──(自动消耗背包砖块)──▶ [铺设砖块路]
   │                                  │
   ▼                                  ▼
(无砖/踩空)                        [成功抵达岛屿]
   │                                  │
[落水重生] <──────────────────────────┘
   │                                  │
   │                                  ▼
   │                              [探索岛屿]
   │                                  │
   │                                  ▼
   │                           [发现目标模型]
   │                                  │
   │                                  ▼
   │                          [按下互动键拾取] ──▶ (模型存入玩家背包)
   │                                  │
   │                                  ▼
   └───────────── 使用岛屿[快速传送点] ────────┘
                                      │
                                      ▼
                               [返回 玩家Home]
```

---

## 二、 核心机制设计

### 1. 铺砖与跑酷机制 (Paving)
* **自动铺设：** 玩家在海面上移动时，系统自动检测前方路况并消耗玩家背包中的砖块资源，在脚下生成实体砖块。
* **资源耗尽：** 若玩家砖块用尽且未到达安全区（岛屿），将因无路可走掉入海中，触发重生并返回 Home。
* **坍塌机制（PVP竞速抢夺元素）：**
  * 铺设的砖块拥有默认生命周期（如10秒），时间到自动销毁。
  * **加速坍塌：** 当非铺设者（其他玩家）踩踏该砖块时，砖块生命周期加速流逝（例如直接扣除5秒寿命），增加跑酷抢夺的博弈趣味性。

### 2. 模型收集与背包 (Inventory)
* **拾取：** 玩家靠近岛屿上的模型，通过互动键将其移入背包。
* **容量限制：** 玩家的背包模型数量及可携带砖块容量初期有限制，需通过后续升级扩容。

### 3. Home 个人基地 (Home System)
* **展台放置：** Home 中设有固定的模型放置点，玩家可将背包中的模型放置其上。
* **挂机收益：** 放置的模型会根据其稀有度和等级，每秒源源不断地产生金币收益。
* **模型管理：** 玩家可消耗金币对已放置的模型进行【升级】（提升每秒收益），或进行【出售】（销毁模型回收部分资金）。
* **地产扩建：** 玩家可消耗大量金币升级 Home 的层数，解锁更多的模型放置点。

### 4. 商店与成长 (Shop)
玩家在 Home 领取的金币收益，可在全局商店系统中购买强大的永久增益属性：
* **移动速度：** 提升 WalkSpeed，跑酷抵达岛屿的时间更短，更难被其他玩家坑害。
* **砖块上限：** 提升单次出海可携带的砖块最大数量，从而能够探索更远的稀有岛屿。

---

## 三、 系统架构与模块划分

```text
=================================================================================
                            ROBLOX 抓模型 - 系统架构图
=================================================================================

                ┌───────────────────────────────────────────┐
                │          [全局游戏状态与数据中心]         │
                │     (玩家数据、金币、背包清单、全局配置)  │
                └─────────────────────┬─────────────────────┘
                                      │ 数据读写同步
      ┌───────────────────────────────┼───────────────────────────────┐
      │                               │                               │
      ▼                               ▼                               ▼
+--------------------+      +--------------------+          +--------------------+
|  👨 玩家模块       |      |  🏝️ 场景模块       |          |  🛒 商店模块       |
+--------------------+      +--------------------+          +--------------------+
| ▫️ 移动控制系统    |      | ▫️ 海面与死亡判定  |          | ▫️ 移动速度升级    |
| ▫️ 互动事件射线检测|      | ▫️ 岛屿与模型生成  |          | ▫️ 砖块上限增加    |
| ▫️ 背包(模型管理)  |      | ▫️ 传送点工作流    |          | ▫️ Home面积扩建    |
| ▫️ 砖块消耗与铺设  |      | ▫️ 砖块衰减与坍塌  |          +--------------------+
+--------------------+      +--------------------+                    │ 
      │ 1│      ▲ 2                 │                                 │
      │  │      │                   │ 3                               │
      │  └──────┼───────────────────┘                                 │
      │         │                                                     │ 6
      │         │  4                                                  │
      │ 放置/   │ 领取                                                │ 解锁
      │ 取出    │ 收益                                                │ 放置点
      ▼         │                                                     ▼
+------------------------------------------------------------------------+
|  🏠 Home模块 (玩家个人基地实例化区域)                                  |
+------------------------------------------------------------------------+
| ▫️ 模型放置点管理 : 校验状态，展示玩家放入的模型实体                   |
| ▫️ 核心收益计算引擎: 根据模型类型/等级每秒产出金币，累积至储蓄池       |
| ▫️ 放置模型互动区 : 提供靠近升级(提升收益/s) 与 出售(回收销毁) 的UI面板|
+------------------------------------------------------------------------+
```

---

## 四、 核心数值配置 (GameConfig)

```lua
local GameConfig = {}

--=========================================
-- 1. 玩家铺砖逻辑
--=========================================
GameConfig.Paving = {
    BasePlaceCooldown = 0.2, -- 单位: 秒/块
    BaseCollapseTime = 10,   -- 砖块生命周期: 10秒
    SteppedPenalty = 5,      -- 被其他玩家踩踏一次扣5秒寿命
    MinCollapseTime = 0.5,   -- 被踩踏后的保底存活时间（容错）
}

--=========================================
-- 2. 模型与收益逻辑
--=========================================
GameConfig.Models = {
    Rarities = {
        Common = { BaseYield_Sec = 1,   BaseSellValue = 10 },
        Rare   = { BaseYield_Sec = 5,   BaseSellValue = 50 },
        Epic   = { BaseYield_Sec = 20,  BaseSellValue = 250 },
        Legend = { BaseYield_Sec = 100, BaseSellValue = 1500 },
    },
    Upgrade = {
        MaxLevel = 10,
        YieldBuffPerLevel = 0.5, -- 每升一级收益增加50%
        BaseCost = 100,          -- 初始升级消耗
        CostMultiplier = 1.6,    -- 升级消耗倍率指数递增
    }
}

--=========================================
-- 3. 背包初始状态
--=========================================
GameConfig.Inventory = {
    InitialModelCapacity = 5,
    InitialBricks = 50,
}

--=========================================
-- 4. Shop / Home 升级经济系统
--=========================================
GameConfig.Home = {
    Levels = {
        [1] = { Cost = 0,       MaxPoints = 4 },
        [2] = { Cost = 2000,    MaxPoints = 12 },
        [3] = { Cost = 10000,   MaxPoints = 24 },
        [4] = { Cost = 50000,   MaxPoints = 40 },
    }
}

GameConfig.Shop = {
    WalkSpeed = {
        MaxLevel = 25, BaseSpeed = 16, SpeedIncrement = 0.8,
        BaseCost = 50, CostMultiplier = 1.15,
    },
    MaxBricks = {
        MaxLevel = 40, BaseAmount = 50, AmountIncrement = 15,
        BaseCost = 30, CostMultiplier = 1.20,
    }
}

return GameConfig
```

---

## 五、 核心 Lua 代码实现模板

### 1. PavingService.luau (服务端铺砖处理)
```lua
local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)
local PavingService = {}
local activeBricks = {}

function PavingService.PlaceBrick(player, position)
    local brick = Instance.new("Part")
    brick.Size = Vector3.new(4, 1, 4)
    brick.Position = position; brick.Anchored = true
    brick.Parent = workspace.PavedBricks
    
    activeBricks[brick] = { Owner = player, ExpireTime = os.clock() + GameConfig.Paving.BaseCollapseTime }
    
    brick.Touched:Connect(function(hit)
        local character = hit.Parent
        local hitPlayer = game.Players:GetPlayerFromCharacter(character)
        if hitPlayer and hitPlayer ~= player then
            local brickData = activeBricks[brick]
            if brickData then
                local remaining = brickData.ExpireTime - os.clock()
                brickData.ExpireTime = os.clock() + math.max(GameConfig.Paving.MinCollapseTime, remaining - GameConfig.Paving.SteppedPenalty)
                brick.Color = Color3.new(1, 0, 0)
            end
        end
    end)
    return true
end

game:GetService("RunService").Heartbeat:Connect(function()
    local now = os.clock()
    for brick, data in pairs(activeBricks) do
        if now >= data.ExpireTime then
            activeBricks[brick] = nil; brick:Destroy()
        end
    end
end)
return PavingService
```

### 2. HomeService.luau (服务端放置点与收益池)
```lua
local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)
local HomeService = {}
local playerHomes = {}

function HomeService.CreateHome(player, homeModel)
    playerHomes[player] = { Instance = homeModel, PlacedModels = {}, UnclaimedYield = 0, Level = 1 }
end

function HomeService.PlaceModel(player, modelData, pointIndex)
    local home = playerHomes[player]
    if home.PlacedModels[pointIndex] ~= nil then return false end
    home.PlacedModels[pointIndex] = modelData
    return true
end

-- 挂机收益核心引擎
task.spawn(function()
    while task.wait(1) do
        for player, home in pairs(playerHomes) do
            local yieldThicSec = 0
            for _, model in pairs(home.PlacedModels) do
                local base = GameConfig.Models.Rarities[model.Rarity].BaseYield_Sec
                local levelBuff = 1 + (model.Level * GameConfig.Models.Upgrade.YieldBuffPerLevel)
                yieldThicSec += math.floor(base * levelBuff)
            end
            home.UnclaimedYield += yieldThicSec
        end
    end
end)
return HomeService
```

### 3. InventoryService.luau & ShopService.luau 摘要
由服务端负责数据校验，处理角色状态（如容量超限拒绝拾取，改变 `Humanoid.WalkSpeed`），并通过 RemoteEvent 与客户端更新 UI。具体逻辑依赖于游戏的数据存储框架 (如 ProfileService) 的耦合。
