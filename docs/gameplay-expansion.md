# v0.6 玩法扩展设计：火力过载路线、进化核心与护卫卫星

> 状态：设计稿（未实现）。分支 `feat/gameplay-expansion`，基线 v0.5.0（`flutter test` 282 项）。
> 发布位置：用户自己的 fork（`qpzm7903/flutter-plane`），不向上游提 PR。
> 原则：在 v0.5 的数据驱动结构上**加一条成长轴**，不重写战斗循环；数值只写在单一出处；程序化 Canvas、批绘制、对象池与两趟弹幕收集不退化。
> 版本号：实现完成后 bump 到 `0.6.0`（`pubspec.yaml` 的 `version:`、README 版本表/下载链接/tag 示例，见 §7、§8）。**不要改 CI 签名与密钥。**

---

## 1. 目标与非目标

### 目标

1. **满级之后仍有成长**：火力 6 级、僚机 2 架之后，后续的火力/僚机补给不再只折算分数，而是进入新的成长轴。
2. **一个实质性新系统，不是抬高上限**：
   - **火力过载路线（Overdrive Route）**：6 级后分化为 散射 / 贯穿 / 聚能 三条路线，每条 2 阶，三条路线的**强项和短板不同**，需要玩家取舍。
   - **进化核心（Evolution Core）**：新补给，颜色与字样循环切换，玩家用走位在想要的路线上接取——**无需弹窗选择**，手机上单手可玩。
   - **护卫卫星（Guard Satellite）**：第三个僚机位，不开火，吸收敌弹，能量耗尽后过热冷却。
3. **后期奖励新路径，早期仍教学**：第 1–4 波完全看不到新内容；进化核心 `wave >= 5` 才会出现。
4. **风险回报成立**：受伤先降一阶过载（延续"受伤掉级"），护盾能保护过载；换路线有代价。
5. **性能与可读性不退化**：新增 3 个玩家弹种，仍走 `DrawBatch` 分桶；HUD 在 320 dp 宽的手机上不溢出。

### 非目标

- 不新增每日挑战模式或修正；`daily_challenge.dart` **零改动**（§5.3）。
- 不做弹窗式的路线选择、不暂停游戏、不加新页面。
- 不做僚机进化阶（疾风/重炮升级）、不做超过 3 个僚机位（理由见 §3）。
- 不提高 `Player.maxWeaponLevel`（保持 6）与 `Player.maxBombs`（保持 3）。
- 不新增音频/图片/字体资源；不联网；不改 Boss 弹幕库、敌机移动、波次编队与难度曲线（只留调节旋钮，见 §9）。
- 不引入玩家弹对象池（现状没有；见 §9 风险）；不改敌弹两趟收集结构。
- 不新增成就（避免动存储键；可作为 v0.6.1 的后续项）。

> 关于任务描述里"第 1 波不要 L10"：这里按"第 1 波不出现任何新机制（核心、过载路线、卫星）"实现，并由测试覆盖（§8）。

---

## 2. 现状审计（以 v0.5.0 真实代码为准）

| 项 | 现状 | 出处 |
| --- | --- | --- |
| 火力等级 | `Player.weaponLevel`，`maxWeaponLevel = 6`；弹道表 `kPlayerWeaponPatterns[0..6]` | `battle_types.dart:221`、`player_weapon.dart:39` |
| 满级折算 | `applyPickup` 的 `weapon` 分支：满级后只给 `kWeaponCapScore = 300` 分；僚机满编给 `kWingmanCapScore = 250` | `pickup_rules.dart:32`、`:59` |
| 受伤掉级 | `_hitPlayer` 里 `weaponLevel = max(1, weaponLevel - kWeaponLossPerHit)`，规则散在控制器里 | `battle_controller.dart:755` |
| 僚机 | `Player.maxWingmen = 2`；`WingmanRole { gale, heavy }`；`Wingman.role => side < 0 ? gale : heavy`；出生侧写死为 `player.wingmen.isOdd ? -1 : 1`（**只适用于 2 个位置**） | `battle_types.dart:222-237`、`battle_controller.dart:603` |
| 僚机更新 | `_updateWingmen` 按 `wing.side * kWingmanOffsetX` 与固定 `kWingmanOffsetY` 追随，射击读 `kWingmanSpecs[wing.role]!`（对新角色会 null 崩溃，需改） | `battle_controller.dart:358` |
| 掉落 | `DropLedger.rollKill/bossDrops`：随机池 `kPowerUpWeights`（6 种，合计 100）、通用 pity、炸弹 pity、精英保底；Boss 三连掉：左=按需、中=炸弹、右=随机 | `pickup_rules.dart:76`、`battle_tuning.dart:133` |
| Boss 左侧链 | `weaponLevel < 5 ? weapon : wingmen < maxWingmen ? wingman : shield` | `pickup_rules.dart:124` |
| 穿透 | `Bullet.pierce` + `Bullet.lastHit`（单引用）；Boss 不可穿透；穿透上限 1 | `battle_types.dart:321`、`battle_controller.dart:647` |
| 玩家弹渲染 | `_drawBullets` 一次遍历写三层；样式表 `_playerShotStyles` 按 `kind` 索引（当前 0–11），未知 kind 回退脉冲 | `battle_field_component.dart:419`、`battle_visuals.dart:322` |
| 补给渲染 | `_drawPowerUps` 用 `kPowerUpArgb[item.kind]` 与 `kPowerUpLabels[item.kind]![0]` 画 21×21 方块 + 单字标签 | `battle_field_component.dart:472` |
| HUD | `hudStatsFor` 的"火力"条目只显示 `weaponLevel`；紧凑波次面板另写了一份 `'火力 ${weaponLevel}'`；`_hudSignature` 只含 `weaponLevel` 与 `wingmen` | `hud_stats.dart:44`、`battle_hud.dart:271`、`battle_controller.dart:309` |
| 文案 | `supplyHints()` 长度被 `rules_text_test` 约束为 `PowerUpKind.values.length`；`how_to_play.dart` 只渲染 `rules_text` 的列表 | `rules_text.dart:20`、`rules_text_test.dart:18` |
| 批绘制预算 | 现测：kind 0 的 240 弹 ≤ 12；12 种 kind 同屏 ≤ 40；满级弹道 + 双僚机 + 150 敌弹 ≤ 20（混色 ≤ 24），且 `circleCalls == 4` | `battle_render_batch_test.dart:145/187/253` |

### 审计发现（驱动本次设计）

1. **满级之后火力不再成长，而且 4→6 级对"单个目标"几乎没有增长。** 把目标放在枪口前 300 px、半径 18 px（横向命中阈值约 ±21 px），逐级统计一轮齐射能打到的伤害（"ST"）：

   | 级 | 1 | 2 | 3 | 4 | 5 | 6 |
   | --- | --- | --- | --- | --- | --- | --- |
   | 一轮总伤害 | 1 | 2 | 4 | 6 | 8 | 10 |
   | ST（300 px 单目标） | 1 | 2 | 2 | 4 | 4 | 4 |
   | ST-DPS（ST ÷ 间隔） | 6.7 | 14.1 | 14.9 | 31.7 | 33.9 | 36.4 |

   4→6 级新增的弹全是外圈裂波针，只增加覆盖，几乎不增加对 Boss/堡垒的输出。这正是"后期无法再成长"的体感来源，也是新路线要补的缺口：**路线要给出 ST 增长，或用覆盖换取别的收益**。
2. **僚机位置被写死成两个**：出生侧、`Wingman.role`、`_updateWingmen` 都假定 `side ∈ {-1, 1}`，第三位需要显式的 `wingmanSideFor(count)`（§4.4）。
3. **`kWingmanSpecs[wing.role]!` 对没有射击参数的角色会崩溃**——卫星不开火，必须在 `_updateWingmen` 里先分流。
4. **`PowerUpKind` 在多处被当作"全集"**：`kPowerUpLabels/Colors/Argb`、`applyPickup` 的 switch、`supplyHints` 长度断言、`battle_tuning_test` 的"全部类型都能掉落"。新增 `core` 必须同时补齐（§8 列明）。
5. **玩家弹预算有余量**：6 级 + 双僚机实测约 18 次 `drawRawPoints`，新增 3 个弹种且同屏最多再多 3 个种类，预算上调是可控的（§4.6）。

---

## 3. 方案选型与理由

### 候选评估

| 候选 | 价值 | 成本/风险 | 结论 |
| --- | --- | --- | --- |
| A. 线性 L7–L8（继续加弹、加伤害） | 低：只是上限 +2，玩家没有选择 | 弹数膨胀 → 碰撞与绘制压力；难平衡 | 否 |
| B. 满级后路线分支（散射/贯穿/聚能） | **高**：强项不同、可重复游玩、补上审计发现 1 的 ST 缺口 | 中：新弹种 + 路线状态；选择 UI 是风险点 | **做**（用"核心循环变色"代替弹窗，§4.2） |
| C. 僚机进化阶（疾风/重炮升级） | 中 | 高：每架僚机 × 阶数 = 新状态矩阵，渲染/文案/测试成倍 | 否，留作后续（§9） |
| D. 僚机第三位 | 中高：满编之后仍有新东西；位置增长是玩家最容易理解的成长 | 低-中：需要把"两侧"假设改成显式出生侧 | **做**，但第三位做成**防御角色**（§4.4），与 B 的输出成长正交 |
| E. 超武限时 / 超级炸弹 / 分数倍率 | 低-中：是"一次性爆发"，不改变构筑 | 中：新计时器、新 UI | 否 |
| F. 卫星"绕机旋转" | 中 | 吸收效率不稳定（见下），难解释 | 否，改为固定前置位 |
| G. 弹窗选路线 | 清晰 | 要暂停、改输入、改测试；手机上打断节奏 | 否 |

### 为什么是 B + D + 一个新补给

- 用户建议的组合是"火力超限进化 + 僚机进化/第三位 + 1 个新补给或满级转化"。本方案恰好对应：**B（火力）+ D（第三位）+ 进化核心（新补给，同时承担"满级火力补给转化"）**。
- 三者共用一个叙事——"满级之后的奖励是新路径"——而不是五个互不相关的系统。
- 两条成长轴**正交**：路线管输出形态，卫星管生存。互相之间无依赖，可以分步合入、分步回滚。
- 核心循环变色的选择机制：沿用街机经典的"循环胶囊"手感，选择发生在**走位**里；颜色 + 字形双重编码（对色弱友好）；不需要任何新输入、不暂停、不新增页面。
- 卫星取"前置固定位"而不是"绕机旋转"：敌弹绝大多数从上方来，卫星位于机头前方 34 px 时对正上方来弹的拦截最稳定；绕机旋转时切线速度约 90 px/s，一发子弹被拦下的概率只有环周的一小段，玩家无法预判。

### 明确不做

僚机进化阶、第 4 个僚机位、弹窗选路线、绕机旋转卫星、限时超武、超级炸弹、新的 Boss 机制——见 §9。

---

## 4. 新系统详细设计

### 4.1 数据与状态

**新增类型**（`battle_types.dart`）：

```dart
enum WeaponRoute { fan, pierce, focus }       // 散射 / 贯穿 / 聚能

class Player {
  // ...既有字段不变
  WeaponRoute? route;       // 当前路线；overdrive == 0 时恒为 null
  int overdrive = 0;        // 过载阶数 0..maxOverdrive；> 0 时 weaponLevel 必为 maxWeaponLevel
  int get fireTier => weaponLevel + overdrive;   // HUD 展示用：1..8
  static const int maxOverdrive = 2;
  static const int maxWingmen = 3;               // 原 2
}

enum WingmanRole { gale, heavy, guard }          // 新增 guard

class Wingman {
  // ...
  WingmanRole get role =>
      side < 0 ? WingmanRole.gale : side == 0 ? WingmanRole.guard : WingmanRole.heavy;
  double energy = 0;     // 仅卫星使用：当前能量
  double overheat = 0;   // 仅卫星使用：剩余过热冷却（秒）
}

enum PowerUpKind { weapon, shield, bomb, star, rapid, wingman, core }  // core 追加在末尾

class BulletKind {
  // ...既有
  static const int fanBolt = 12, rail = 13, focusBolt = 14;
  // isPlayer 保持 kind == player || kind >= twin，无需改动
}

class Bullet {
  // ...
  Enemy? lastHit;
  Enemy? prevHit;        // 新增：贯穿 2 次需要记住最近两个命中目标
}
```

**不变量**（由 `applyPickup` / `applyHitPenalty` 维护，测试断言）：

1. `overdrive > 0` ⇒ `weaponLevel == Player.maxWeaponLevel` 且 `route != null`。
2. `overdrive == 0` ⇒ `route == null`。
3. `wingmen ∈ [0, 3]`；第 1/2/3 个僚机的 `side` 依次为 `-1 / +1 / 0`。

### 4.2 进化核心（新补给 `PowerUpKind.core`）

#### 外观与循环

- 方块外观沿用现有 21×21 圆角方块，**外加一圈慢速旋转的外环**（半径 19，宽 1.4）与"核"的区分：普通补给没有外环。
- 路线由**拾取时的 `PowerUp.age`** 决定，不加任何字段、不抽随机数：

```dart
// battle_tuning.dart
const double kCoreCycleSeconds = 0.9;
WeaponRoute coreRouteAt(double age) =>
    WeaponRoute.values[(age / kCoreCycleSeconds).floor() % WeaponRoute.values.length];
```

- 方块边框、外环、标签颜色随当前路线变化，标签字形用路线单字（**散 / 贯 / 聚**），一个循环 2.7 s；补给从 y≈50 落到屏底约 11 s（`PowerUp.vy = 62`），玩家有约 4 个循环的时间选择。
- 文本缓存键是 `文本 + 颜色 + 字号`，3 个路线字形只会产生 3 个 `TextPainter`，不会每帧新建。

#### 拾取规则（`applyPickup(PowerUpKind.core, player, multiplier:, route:)`）

`route` 由控制器传入 `coreRouteAt(item.age)`。

| 当前状态 | 结果 | 提示文本 / 颜色 |
| --- | --- | --- |
| `weaponLevel < 6` | 等价于火力补给：`weaponLevel++`（核心永不浪费） | `火力 N 级` |
| 6 级，`overdrive == 0` | `route = r`，`overdrive = 1` | `散射进化 Ⅰ`（路线色） |
| `overdrive > 0`，同路线，`overdrive < 2` | `overdrive++` | `散射进化 Ⅱ` |
| `overdrive == 2`，同路线 | 折算 `kCoreCapScore = 400` 分（> 火力满级的 300，因为更难拿到） | `+400` |
| `overdrive > 0`，**不同**路线 | `route = r`，`overdrive = max(1, overdrive - 1)`（**转向降一阶**） | `转向 贯穿` |

> 转向代价的理由：让"接到错色核心"有成本，但与"受伤降一阶"相同量级，不会毁掉一局；同时让玩家有动机**等到想要的颜色**而不是见核心就吃。

#### 来源（单一出处：`pickup_rules.dart` 的 `resolveDrop` 与 `DropLedger.bossDrops`）

核心**不进入** `kPowerUpWeights`（权重表合计仍为 100，`powerUpKindForRoll` 不变，同种子随机序列不变）。核心只通过两条渠道出现：

1. **满级火力转化**：随机池抽到 `weapon` 时，若满足
   `weaponLevel == 6 && overdrive < 2 && wave >= kOverdriveFromWave && coreKills >= kCoreCooldownKills`，改为 `core`，并 `coreKills = 0`。这是"满级火力补给转化"。
2. **Boss 保证链**：Boss 左侧"按需"补给的优先链扩展为（自上而下取第一个满足）：

   | 序 | 条件 | 掉落 |
   | --- | --- | --- |
   | 1 | `weaponLevel < 5` | weapon |
   | 2 | `wingmen < 2` | wingman |
   | 3 | `weaponLevel < 6` | weapon（**新增**：原先这里直接给护盾） |
   | 4 | `wave >= 5 && overdrive == 0` | **core** |
   | 5 | `wingmen < maxWingmen` | wingman（第三位） |
   | 6 | `wave >= 5 && overdrive < maxOverdrive` | **core** |
   | 7 | 其余 | shield |

   Boss 中间槽（炸弹/护盾）与右侧随机槽不变；右侧随机槽的 `weapon` 同样经过 `resolveDrop`（因左侧已把 `coreKills` 清零，不会重复出核心）。

新增常量（`battle_tuning.dart`）：`kOverdriveFromWave = 5`、`kCoreCooldownKills = 30`、`kCoreCycleSeconds = 0.9`、`kCoreCapScore = 400`。

**节奏估算**（第 5–12 波，平均每波 16 次击破、随机掉落约 2.0–2.7 个/波，weapon 占 34%）：

- 随机转化上限约每 2 波一枚（冷却 30 次击破 ≈ 1.9 波）。
- Boss 链在第 8 波给第一枚（若已满级、双僚机），第 12 波给卫星或第二枚。
- 因此 6 级 → 8 阶最早在第 8–10 波，常见在第 12 波前后；`ace`（2 命）与受伤频繁的玩家会更慢——符合"后期奖励"。

### 4.3 三条路线：弹道与数值

共同点：路线只在 `weaponLevel == 6 && overdrive > 0` 时生效，基底是 6 级弹道 `B6`（9 发，一轮总伤害 10）。路线弹种只用**冷色 + 白芯 + 胶囊形**，与敌弹（暖色/紫色圆点）双重区分。

`B6`（沿用 v0.5）：`lance(-9, d1, p1)`、`nova(0, d2, p1)`、`lance(9, d1, p1)`、针 `±14/±0.13`、`±18/±0.28`、`±21/±0.43`。

表中 `dN` = 伤害，`pN` = 穿透次数，`r` = 半径；角度 = 弧度，正值向右（`vx = sin(angle) * speed`）。

#### 路线 1：散射 Fan（`WeaponRoute.fan`）——清场与覆盖，不提高单点伤害

| 阶 | 弹数 | 组成 | 间隔系数 | 一轮总伤害 | ST | ST-DPS | 总 DPS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 6 级基准 | 9 | `B6` | 1.00 | 10 | 4 | 36.4 | 90.9 |
| Ⅰ（L7） | 13 | `B6` + `fanBolt(±23, ±0.58, d1)` + `fanBolt(±27, ±0.76, d1)` | 0.88 | 14 | 4 | 41.3（+14%） | 144.6 |
| Ⅱ（L8） | 15 | Ⅰ + `fanBolt(±31, ±0.94, d1)`，**全部 6 发扇弹 p1** | 0.88 | 16 | 4 | 41.3 | 165.3 |

- 扇面总角度从 ±0.43 扩到 ±0.94（约 ±54°），能覆盖屏幕两侧的无人机、截击机与侧翼编队。
- Ⅰ 阶先拿宽度，Ⅱ 阶让扇弹获得穿透 1：边路杂兵成排时一发穿两。
- 对 Boss 几乎没有增益（扇弹大角度基本打不到中路目标），这是刻意的取舍。

#### 路线 2：贯穿 Pierce（`WeaponRoute.pierce`）——纵向穿线与中路重击

| 阶 | 弹数 | 组成 | 间隔系数 | 一轮总伤害 | ST | ST-DPS |
| --- | --- | --- | --- | --- | --- | --- |
| Ⅰ（L7） | 9 | 中路 `rail(0, d3, p2, r4.2)`、两侧 `rail(±9, d1, p2, r3.6)`、其余 6 根针同 `B6` | 1.00 | 11 | 5 | 45.5（+25%） |
| Ⅱ（L8） | 9 | 中路 `rail(0, d3, p2)`、两侧 `rail(±9, d2, p2)`、针同 `B6` | 1.00 | 13 | 7 | 63.6（+75%） |

- `rail` 取代 `nova/lance` 的位置（同样 3 发），弹数不变，**绘制与碰撞开销不增加**。
- 穿透 2 次 = 一发子弹最多结算 3 个目标（与 v0.5"穿透 1 = 结算 2 个目标"的语义一致）。
- Boss 仍不可被穿透（沿用规则）；贯穿的收益在 Boss 战里来自 ST 增长，而不是穿透。
- 这条路线是"走一条线"的玩法：对成排下落的编队和 Boss 最强，边路较弱。

#### 路线 3：聚能 Focus（`WeaponRoute.focus`）——放弃覆盖换取单点爆发

| 阶 | 弹数 | 组成 | 间隔系数 | 一轮总伤害 | ST | ST-DPS |
| --- | --- | --- | --- | --- | --- | --- |
| Ⅰ（L7） | 5 | `lance(±9, d1, p1)`、`nova(0, d2, p1)`、`focusBolt(±20, ∓0.0666, d1.5)` | 1.20 | 7 | 7 | 53.0（+46%） |
| Ⅱ（L8） | 7 | Ⅰ + `focusBolt(±10, ∓0.0333, d1)` | 1.20 | 9 | 9 | 68.2（+87%） |

- 去掉全部 6 根裂波针，换成**向内汇聚**的聚能弹：从 ±20 / ±10 px 出发，以 `atan(offset / 300)` 向轴线倾斜，在枪口前约 300 px 汇合成一束，之后交叉继续飞行（在 Boss 悬停的 450 px 处仍落在中路 ±10 px 内，所以对 Boss 有效）。
- 总伤害反而低于 6 级基准（7 / 9 < 10）——**聚能用覆盖换集中**，对杂兵编队比 6 级更差，对 Boss/堡垒/精英最强。
- 弹数最少（5/7），渲染与碰撞压力最小。

#### 路线对照与护栏

| 路线 | 强项 | 短板 | ST-DPS 增幅（Ⅰ→Ⅱ） | 总 DPS 相对 6 级 |
| --- | --- | --- | --- | --- |
| 散射 | 覆盖 ±54°，边路与成群小机 | 对 Boss 几乎无增益 | +14% / +14% | +59% / +82% |
| 贯穿 | 纵向成线、中路 ST、与护盾/急速协同 | 边路弱 | +25% / +75% | +10% / +30% |
| 聚能 | Boss/精英/堡垒 ST | 覆盖差、总 DPS 低于 6 级 | +46% / +87% | −42% / −25% |

> "ST" 的定义（测试用同一公式）：目标位于枪口前 `D = 300` px、半径 18 px，横向位置 `lateral = offsetX + tan(angle) * D`，`|lateral| <= 18 + shot.radius` 视为命中；ST = 命中弹的伤害和。

**平衡护栏（测试断言，调参时不得突破）**：

1. 同一路线内 ST-DPS 严格递增（Ⅰ < Ⅱ），且都 ≥ 6 级基准。
2. 任意路线任意阶的 ST-DPS ≤ 6 级基准 × 2.0；总 DPS ≤ 6 级基准 × 1.9。
3. 所有弹的 `pierce <= kMaxPierce`（= 2）；Boss 不可穿透。
4. 所有玩家弹种 ≥ 12 的弹在 `playerShotStyle` 里有显式样式（不回退脉冲）。

#### 射击间隔

```dart
// battle_tuning.dart
double playerFireInterval(int weaponLevel, {required bool rapid, WeaponRoute? route}) {
  final base = (kBaseFireInterval - kWeaponFireStepPerLevel * (max(1, weaponLevel) - 1))
      * (route == null ? 1.0 : kWeaponRoutes[route]!.fireIntervalScale);
  return rapid ? base * kRapidFireIntervalScale : base;
}
```

`_updatePlayer` 传入 `route: p.overdrive > 0 ? p.route : null`。既有调用与测试（不传 `route`）行为不变。

#### 路线数据单一出处

```dart
// battle_tuning.dart（颜色与文案只在这里）
class RouteSpec {
  const RouteSpec({
    required this.label,   // 散射 / 贯穿 / 聚能
    required this.glyph,   // 散 / 贯 / 聚
    required this.argb,    // HUD、核心方块、拾取飘字共用
    required this.fireIntervalScale,
    required this.blurb,   // 玩法说明一句话
  });
  final String label, glyph, blurb;
  final int argb;
  final double fireIntervalScale;
}

const Map<WeaponRoute, RouteSpec> kWeaponRoutes = {
  WeaponRoute.fan: RouteSpec(label: '散射', glyph: '散', argb: 0xFF2EF2A8, fireIntervalScale: 0.88, blurb: '…'),
  WeaponRoute.pierce: RouteSpec(label: '贯穿', glyph: '贯', argb: 0xFFB8E6FF, fireIntervalScale: 1.0, blurb: '…'),
  WeaponRoute.focus: RouteSpec(label: '聚能', glyph: '聚', argb: 0xFF8C7BFF, fireIntervalScale: 1.2, blurb: '…'),
};
```

弹道形状表放在 `player_weapon.dart`（沿用"弹道只写在一个地方"）：

```dart
const _kLevel6Shots = [ /* 现有 6 级 9 发，提为常量供 kPlayerWeaponPatterns[6] 与路线共用 */ ];
const int kMaxPierce = 2;

/// 下标 = overdrive - 1。
const Map<WeaponRoute, List<List<PlayerShot>>> kOverdrivePatterns = {
  WeaponRoute.fan:    [[..._kLevel6Shots, /* 4 发 fanBolt */], [..._kLevel6Shots, /* 6 发 fanBolt，p1 */]],
  WeaponRoute.pierce: [[PlayerShot.rail(-9, damage: 1), PlayerShot.rail(0, damage: 3, radius: 4.2), PlayerShot.rail(9, damage: 1), /* 6 针 */], [...]],
  WeaponRoute.focus:  [[PlayerShot.lance(-9, damage: 1), PlayerShot.nova(0), PlayerShot.lance(9, damage: 1), PlayerShot.focus(-20, 0.0666, damage: 1.5), PlayerShot.focus(20, -0.0666, damage: 1.5)], [...]],
};
```

> `PlayerShot.focus(offsetX, angle)` 的 `angle` 符号：**左侧弹（offsetX < 0）倾向右（angle > 0），右侧弹倾向左**，使 `offsetX + tan(angle) * 300 ≈ 0`。
> 新增命名构造：`PlayerShot.fan(x, angle, {pierce = 0})`、`PlayerShot.rail(x, {damage, radius = 3.6, pierce = 2})`、`PlayerShot.focus(x, angle, {damage})`。

`appendPlayerShots` 选表规则：

```dart
final pattern = (player.overdrive > 0 && player.route != null && level == Player.maxWeaponLevel)
    ? kOverdrivePatterns[player.route]![(player.overdrive - 1).clamp(0, Player.maxOverdrive - 1)]
    : kPlayerWeaponPatterns[level];
```

`firstPiercingLevel()` 仍只看 `kPlayerWeaponPatterns`（结果仍为 4），玩法说明里的"4 级起穿透"不变。

#### 碰撞层（`_collidePlayerShots`）

仅两处改动：

```dart
if (enemy.dead || identical(enemy, bullet.lastHit) || identical(enemy, bullet.prevHit)) continue;
...
if (bullet.pierce > 0 && !enemy.isBoss) {
  bullet.pierce--;
  bullet.prevHit = bullet.lastHit;
  bullet.lastHit = enemy;
  continue;
}
```

两个引用恰好够用：穿透 ≤ 2 的子弹在结算第 3 个目标时就会消失，不可能在存活期间再次接触第 1 个目标。持有死亡敌机引用的风险同 v0.5（子弹秒级寿命，随子弹回收释放）。

### 4.4 护卫卫星（第三僚机位）

#### 角色与站位

- 第 3 个僚机的 `side = 0`，`role = WingmanRole.guard`。出生侧统一为：

```dart
// battle_tuning.dart
int wingmanSideFor(int countAfterPickup) => switch (countAfterPickup) { 1 => -1, 2 => 1, _ => 0 };
```

  控制器 `_collectPowerUp` 用它替换 `player.wingmen.isOdd ? -1 : 1`（`battle_controller.dart:603`）。
- 站位在**机头正前方**：`(player.x, player.y - kGuardOffsetY)`，`kGuardOffsetY = 34`。玩家上边界 `kPlayerTopLimit = 44`，所以卫星最高在 `y = 10`，始终在屏内。追随沿用 `kWingmanFollowLerp`，因此有轻微拖尾感。
- 僚机偏移改为按角色取：`double wingmanOffsetY(WingmanRole r) => r == WingmanRole.guard ? -kGuardOffsetY : kWingmanOffsetY;`，`_updateWingmen` 里 `targetX = player.x + wing.side * kWingmanOffsetX`（`side == 0` 时自然等于 `player.x`）。

#### 数值（`battle_tuning.dart`）

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `kGuardOffsetY` | 34 | 机头前方距离 |
| `kGuardRadius` | 15 | 吸收判定半径（再加敌弹半径） |
| `kGuardMaxEnergy` | 12 | 满能量，每吸收一发敌弹消耗 1 |
| `kGuardRegenPerSec` | 0.6 | 就绪状态下的能量回复 |
| `kGuardOverheat` | 6 | 能量耗尽后的过热时长（秒），期间不吸收 |
| `kGuardRestoreEnergy` | 6 | 冷却结束后的恢复量（半管） |
| `kGuardCapScore` | 无 | 第 4 个僚机补给沿用 `kWingmanCapScore = 250` |

卫星**不开火**，因此不进入 `kWingmanSpecs`。`_updateWingmen` 在读取 `kWingmanSpecs[wing.role]!` 之前先分流（审计发现 3）。

#### 状态机

```
         ┌─────────────── energy ≤ 0 ───────────────┐
         ▼                                           │
   [ready]  energy ∈ (0, 12]，regen 0.6/s，吸收敌弹  │
         │                                           │
         └─ 吸收一发：energy -= 1，spark ────────────┘
                        │
                        ▼
   [overheat]  overheat = 6 → 0，不吸收、不回复；结束后 energy = 6，回到 [ready]
```

- 拾取僚机生成卫星时：`energy = kGuardMaxEnergy`，`overheat = 0`。
- 吸收判定（新增 `_collideGuard()`，在 `_collide` 里排在 `_collideEnemyShots` **之前**，保证卫星先于机身接弹）：

```dart
for (final bullet in enemyBullets) {
  if (bullet.dead) continue;
  if (!circlesOverlapXY(bullet.x, bullet.y, bullet.radius, guard.x, guard.y, kGuardRadius)) continue;
  bullet.dead = true;
  _effects.spark(Offset(bullet.x, bullet.y), routeless teal color);
  if ((guard.energy -= 1) <= 0) { guard.overheat = kGuardOverheat; break; }
}
```

  复杂度 O(敌弹数)，只在卫星存在、就绪、玩家存活时执行；敌弹单步位移 ≤ 约 5 px，小于判定半径，不需要扫掠。
- 与既有规则的关系：护盾/受伤/炸弹/`kHitClearRadius` 清弹均不改；卫星不会替玩家承担碰撞伤害，也不吸收敌机机体撞击。
- 为什么不无限强：Boss 一轮弹幕常有 20+ 发；12 点能量只够挡掉其中一部分，之后 6 s 过热，玩家需要靠走位。

#### 第三位的意义

- 满编（2 架）之后，僚机补给不再只折分：第 3 次拾取召唤卫星，第 4 次才折分。
- 它不增加输出，因此不会和路线系统争夺同一个"强度预算"；对 `barrage`（敌弹 +16% 速度）日子尤其有价值。

### 4.5 受伤规则（`applyHitPenalty`，`pickup_rules.dart` 单一出处）

```dart
/// 受伤后的火力惩罚：先降过载阶数，其次降火力等级。僚机与卫星不受影响。
void applyHitPenalty(Player player) {
  if (player.overdrive > 0) {
    player.overdrive = max(0, player.overdrive - kWeaponLossPerHit);
    if (player.overdrive == 0) player.route = null;
    return;
  }
  player.weaponLevel = max(1, player.weaponLevel - kWeaponLossPerHit);
}
```

`_hitPlayer` 把 `player.weaponLevel = math.max(1, …)` 一行换成 `applyHitPenalty(player)`。语义：L8 → L7 → L6 → L5，每次受伤降一级，**统一以"一阶/一级"为单位**；护盾先挡一次伤害，因此护盾也保护过载。路线在过载降到 0 时清除，下一枚核心重新选择。

### 4.6 视觉与渲染

#### 新增玩家弹种（`battle_visuals.dart` 的 `_playerShotStyles` 扩到 15 项）

构造参数顺序同现有：辉光 / 弹体 / 弹芯 ARGB，辉光半径，弹体半长×宽，弹芯半长×宽，可选 `glowAlpha`、`tailDots`。

| kind | 名称 | 辉光 | 弹体 | 弹芯 | 辉光半径 | 弹体 半长×宽 | 弹芯 半长×宽 | 其他 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12 | `fanBolt` | `2EF2A8` | `8CFFD6` | `F0FFFA` | 6 | 6 × 3.6 | 4.5 × 1.4 | — |
| 13 | `rail` | `B8E6FF` | `F2FBFF` | `FFFFFF` | 11 | 16 × 5.4 | 14 × 2.2 | `glowAlpha 0.375`，`tailDots 3` |
| 14 | `focusBolt` | `8C7BFF` | `C4BBFF` | `FFFFFF` | 7 | 8 × 4.6 | 6 × 1.8 | `glowAlpha 0.375` |

- 辉光透明度只取 0.25 / 0.375（`DrawBatch` 8 档量化），沿用 v0.5 的合桶方式。
- `rail` 是全局最长的弹体（半长 16），拖尾 3 点，在密集画面里一眼可辨"贯穿线"；`focusBolt` 的汇聚轨迹本身就是识别特征。
- 路线色（`kWeaponRoutes[..].argb`）与对应弹种的辉光色一致（测试断言）。

#### 绘制调用预算

`DrawBatch` 按（颜色, 线宽）分桶。路线弹种只替换 6 级弹种的一部分：

- 散射 Ⅱ 同屏玩家弹种：nova、lance、needle、fanBolt + 疾风 + 重炮 = 6 种。
- 贯穿：rail、needle + 两僚机 = 4 种；聚能：lance、nova、focusBolt + 两僚机 = 5 种。

预算（测试里写死，实测后以实际值收紧）：

| 场景 | 现有上限 | v0.6 上限 |
| --- | --- | --- |
| 240 颗 kind 0 | ≤ 12 | ≤ 12（不变） |
| 所有 kind 同屏（0–14 共 15 种） | ≤ 40（12 种） | ≤ 48 |
| 6 级 + 双僚机 + 150 单类敌弹 | ≤ 20 | ≤ 20（不变） |
| **散射 Ⅱ + 三僚机 + 150 单类敌弹** | — | ≤ 26 |
| 同上，三类混合敌弹 | ≤ 24 | ≤ 30 |

`circleCalls`：双僚机场景仍为 4；加入卫星后，卫星**不使用圆**（六边形路径 + 弧线，见下），所以三僚机场景 `circleCalls` 为 4（若实现改动了僚机的圆绘制，以测试里的显式值为准）。

#### 卫星外观（`_drawWingmen` 内按 role 分流）

- 机体：新增 `wingmanGuardHullPath`（`ship_geometry.dart`，半径 6 的六边形），青绿描边 `2EF2A8`，内填 `0E3B4F`。
- 能量环：半径 11 的圆弧，扫角 = `energy / kGuardMaxEnergy * 2π`；颜色青绿，能量 < 4 变琥珀色；用既有 `_stroke` 画一次 `drawArc`。
- 过热：机体变暗灰，环改为 4 Hz 闪烁的断续灰弧，让玩家知道"这几秒没保护"。
- 吸收反馈：命中时用既有 `_effects.spark` 青色火花，不新增粒子类型。

#### 玩家机体的路线标识

`_drawPlayer`：`overdrive > 0` 时描边色从 `kPlayerTrim` 换成路线色；`overdrive == 2` 再在两翼各加一条短线（共 2 次 `drawLine`，在已有 `_stroke` 状态下完成）。不新增 Path，不新增每帧对象。

#### 核心补给外观（`_drawPowerUps`）

对 `kind == core`：`argb = kWeaponRoutes[coreRouteAt(item.age)]!.argb`，标签用 `glyph`，另画一圈外环（`_stroke`，`drawCircle`）。其余补给的路径完全不变。

---

## 5. 与 DropLedger / 受伤掉级 / 每日挑战的交互

### 5.1 DropLedger

| 点 | 设计 |
| --- | --- |
| 新字段 | `int coreKills`（距上次核心掉落的非 Boss 击破数，上限 `kCoreCooldownKills`） |
| `reset()` | **不清 `coreKills`**（`reset()` 在炸弹掉落时调用，不应影响核心节奏）；新增 `clearRun()`：`reset()` + `coreKills = kCoreCooldownKills`，控制器 `start()` 改调它（开局即"就绪"） |
| `rollKill` | 开头 `if (coreKills < kCoreCooldownKills) coreKills++`；炸弹分支优先级不变；通用分支得到 `result` 后过 `resolveDrop(result, player, wave)` |
| `resolveDrop` | `weapon` + 满级 + 未满阶 + `wave >= kOverdriveFromWave` + `coreKills >= kCoreCooldownKills` ⇒ `core` 并 `coreKills = 0`；否则原样返回 |
| `bossDrops` | 签名改为 `bossDrops(Player player, double kindRoll, {int wave = kOverdriveFromWave})`；左槽按 §4.2 的 7 级链；链选出 `core` 时 `coreKills = 0`；右槽随机结果同样过 `resolveDrop` |
| 随机数 | **不新增抽签**：非 Boss 击破仍固定抽 2 个随机数；核心路线由 `age` 决定。同种子同操作的掉落序列确定性不变 |
| pity | `pityDrop && weaponLevel < 3 → weapon` 不变；保底不会变成核心（因为 `weaponLevel < 3`） |
| 炸弹经济 | 不改 `kPowerUpWeights`、不改炸弹保底，§6.3 的产出区间不变 |

### 5.2 受伤掉级

见 §4.5。其他关联：

- 护盾、`kHitInvuln`、`kHitClearRadius`、`kShieldBreakInvuln` 不变。
- 受伤**不丢僚机与卫星**（延续现状）；卫星的能量/过热状态原样保留。
- 玩家死亡（`_gameOver`）不改。

### 5.3 每日挑战

`daily_challenge.dart` **零 diff**。逐条核对：

| 修正 | 交互 |
| --- | --- |
| `barrage`（敌弹速度 ×1.16） | 卫星对此日更有价值；吸收判定半径 15 + 弹半径 > 单步位移，无穿透漏判 |
| `armor`（敌机血量 ×1.22） | 路线的 ST 增长可部分对冲；聚能/贯穿此日更有吸引力 |
| `scarcity`（`dropScale = 0.62`） | 只缩放"单次掉率"；核心的两条渠道：随机转化受影响（weapon 掉得更少），Boss 链**不受影响**，所以保证拿到核心；`coreKills` 按击破数累计，不受 `dropScale` 影响 |
| `ace`（初始 2 命） | 过载降阶是缓冲：L8 → L7 → L6 之后才开始真正损失火力等级 |
| `arsenal`（开局 3 级） | 更快到 6 级，但核心有 `wave >= 5` 门槛，不会在教学段出现 |

没有新增 `ChallengeModifier` 字段，没有复制任何战斗逻辑；`_spawnEnemy`、`_updateBoss` 对 `challengeModifier` 的读取不变。

---

## 6. HUD / rules_text / README 同步点

### 6.1 HUD（手机可读）

- `hud_stats.dart` 的"火力"条目：
  - `overdrive == 0`：保持 `shortValue = '${weaponLevel}'`、`fullValue = '${weaponLevel} 级'`（既有 `hud_stats_test` 无需改）。
  - `overdrive > 0`：`shortValue = '${fireTier}${glyph}'`（如 `7聚`），`fullValue = '${fireTier} 级 · ${label}'`（如 `7 级 · 聚能`）；图标颜色换成路线色。
- 抽出一个函数 `String firepowerLabel(Player p)`（放在 `hud_stats.dart`）：`'火力 6'` 或 `'火力 7 · 聚能'`；`battle_hud.dart:271` 的波次面板改用它，**不再自己拼接**，两处不会数值不一致。
- `僚机` 条目随 `player.wingmen` 自动显示 `×3`；卫星能量只画在战场里，不进 HUD（避免 10Hz 刷新）。
- `_hudSignature` 增加 `player.overdrive` 与 `player.route?.index`（卫星能量不进指纹）。
- **窄屏验证**：紧凑状态条（生命 ×5、炸弹 ×3、火力 `7聚`、僚机 `×3`、急速 `12s`）估算宽度 ≈ 266 dp（5 个图标+文字、4 个 12 dp 间距、20 dp 内边距），小于 320 dp 屏宽减去左边距 10；widget 测试以 320 dp 宽实测并断言无溢出。若实测溢出，把状态条改为 `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft)`，不改信息量。
- 补给方块上的路线字形 11 px 粗体，沿用既有标签字号，不另外放大。

### 6.2 `rules_text.dart`（`supplyHints` 长度必须 = `PowerUpKind.values.length` = 7）

```dart
List<String> supplyHints() => [
  '火力：提升弹道等级，最高 ${Player.maxWeaponLevel} 级；${firstPiercingLevel()} 级起主炮可穿透一架普通敌机。',
  '进化核心：满级后出现，字样与颜色循环切换，在想要的路线上接取；同路线升阶（最多 ${Player.maxOverdrive} 阶），换路线降一阶；第 $kOverdriveFromWave 波起，Boss 必出。',
  '护盾：展开能量罩，抵挡一次伤害。',
  '炸弹：…（不变）',
  '僚机：左翼疾风速射、右翼重炮重击，第三架为护卫卫星，吸收敌弹但会过热；最多 ${Player.maxWingmen} 架。',
  '分数：立即获得额外得分。',
  '急速：限时提升射速。',
];

/// 过载路线：文案取自 kWeaponRoutes，颜色/名称不在这里重复。
List<String> routeHints() => [
  for (final route in WeaponRoute.values) '${kWeaponRoutes[route]!.label}：${kWeaponRoutes[route]!.blurb}',
  '受伤先降一阶过载，再降火力等级；护盾可保护过载。',
];
```

`how_to_play.dart` 增加一个 `_Section(icon: Icons.account_tree_rounded, title: '进化路线', lines: routeHints())`，放在"补给"之后。弹窗本身已可滚动。

### 6.3 README 与版本

- 特色"完整战斗循环"：改为"六级弹道……，6 级后可通过**进化核心**分化为散射 / 贯穿 / 聚能三条路线（各 2 阶）"。
- 特色"僚机编队"：改为"左翼疾风速射、右翼重炮重击，第三位为护卫卫星，最多三架"。
- 特色"批绘制与对象池"：预算数字以新测试实测值为准（§4.6 表）。
- 玩法第 2 条补给：加入进化核心与卫星；第 3 条 Boss 掉落：说明"满级后左槽按需给核心/卫星"。
- 版本表新增 `v0.6.0 | 内容版本：火力过载路线、进化核心、护卫卫星`；下载链接与 tag 示例改为 `v0.6.0`。
- 测试数量：以实现完成后 `flutter test` 实际数量为准（预计 320+，基线 282）。
- 文档说明中引用 `docs/gameplay-expansion.md`。

---

## 7. 文件级实现清单与建议顺序

### 7.1 文件清单

| 文件 | 变更 |
| --- | --- |
| `lib/game/battle/battle_types.dart` | `WeaponRoute`；`Player.route/overdrive/fireTier/maxOverdrive`，`maxWingmen = 3`；`WingmanRole.guard`，`Wingman.role` 支持 `side == 0`，新增 `energy/overheat`；`PowerUpKind.core`（追加在末尾）与 `kPowerUpLabels[core] = '核心'`；`BulletKind.fanBolt/rail/focusBolt`；`Bullet.prevHit` |
| `lib/game/battle/battle_tuning.dart` | `RouteSpec` 与 `kWeaponRoutes`；`playerFireInterval(..., route:)`；`kOverdriveFromWave/kCoreCooldownKills/kCoreCycleSeconds/kCoreCapScore`；`coreRouteAt`；`wingmanSideFor`；`wingmanOffsetY`；`kGuard*` 常量 |
| `lib/game/battle/player_weapon.dart` | `PlayerShot.fan/rail/focus`；`_kLevel6Shots`；`kMaxPierce`；`kOverdrivePatterns`；`appendPlayerShots` 选表；`appendWingmanShots` 不处理卫星（调用方已分流） |
| `lib/game/battle/pickup_rules.dart` | `applyPickup` 增加 `core` 分支与 `route:` 参数，僚机第三位提示；`resolveDrop`；`DropLedger.coreKills/clearRun`、`bossDrops` 7 级链与 `wave:` 参数；`applyHitPenalty` |
| `lib/game/battle/battle_controller.dart` | `_collectPowerUp`：`wingmanSideFor`、核心路线 `coreRouteAt(item.age)`、卫星初始能量；`_updateWingmen`：卫星分流（追随、回复、过热倒计时）；新增 `_collideGuard()` 并接入 `_collide`；`_collidePlayerShots`：`prevHit`；`_hitPlayer`：`applyHitPenalty`；`_updatePlayer`：`playerFireInterval(route:)`；`_hudSignature`：加入 `overdrive/route`；`_killEnemy`：`bossDrops(..., wave: wave)`；`start()`：`_drops.clearRun()` |
| `lib/flame/battle_visuals.dart` | `_playerShotStyles` 扩到 15 项；`kPowerUpColors[core]`（占位色，实际按路线色绘制）；`kGuardVisual` |
| `lib/flame/battle_field_component.dart` | `_drawPowerUps` 核心分支；`_drawWingmen` 卫星分流（六边形 + 能量弧 + 过热闪烁）；`_drawPlayer` 路线描边与阶 2 翼线 |
| `lib/game/ship_geometry.dart` | `wingmanGuardHullPath` |
| `lib/pages/widgets/hud_stats.dart` | 火力条目带路线；`firepowerLabel` |
| `lib/pages/widgets/battle_hud.dart` | 波次面板改用 `firepowerLabel`（必要时状态条加 `FittedBox`） |
| `lib/pages/widgets/how_to_play.dart` | 新增"进化路线"小节 |
| `lib/game/battle/rules_text.dart` | §6.2 文案与 `routeHints()` |
| `README.md`、`pubspec.yaml` | §6.3；`version: 0.6.0` |
| `docs/gameplay-expansion.md` | 实现完成后在末尾追加"实现偏差与审查"（体例同 `gameplay-depth.md` §11） |

**不改**：`lib/game/challenge/daily_challenge.dart`、`wave_director.dart`、`enemy_weapons.dart`、`boss_catalog.dart`、`bullet_field.dart`、`battle_effects.dart`、CI/签名文件。

### 7.2 建议顺序（每步可独立 `flutter analyze && flutter test`）

1. **类型与常量**：`battle_types.dart`、`battle_tuning.dart`（含 `kWeaponRoutes`、`coreRouteAt`、`wingmanSideFor`、`kGuard*`）。先修编译、修因 `PowerUpKind.core` 与 `maxWingmen = 3` 导致的既有测试（§8.1）。
2. **弹道与碰撞**：`player_weapon.dart` 的路线表与选表；`prevHit` 碰撞；对应测试。
3. **拾取规则**：`applyPickup(core)`、`applyHitPenalty`、`resolveDrop`、`DropLedger` 扩展；纯函数测试为主。
4. **控制器接线**：核心拾取、`_hitPlayer`、`start()`、HUD 指纹。
5. **卫星**：`_updateWingmen` 分流、`_collideGuard`、状态机测试。
6. **渲染**：弹种样式 → 核心外观 → 卫星 → 玩家路线描边；批绘制预算测试。
7. **HUD 与文案**：`hud_stats`、`battle_hud`、`rules_text`、`how_to_play`；窄屏测试。
8. **README 与版本号**：`pubspec.yaml` → `0.6.0`，README 版本表/下载链接/tag 示例。

---

## 8. 测试计划与验收

### 8.1 需要更新的既有测试

| 测试 | 原因 | 修改 |
| --- | --- | --- |
| `battle_controller_test.dart:230` 僚机拾取 | `maxWingmen` 变 3，`hasLength(maxWingmen)` 时角色应为 `[gale, heavy, guard]` | 更新期望 |
| `battle_controller_test.dart:702` 最多两架 | 循环 2 次后 `wingmen == maxWingmen` 不再成立；`side` 应为 `[-1, 1, 0]` | 循环 `maxWingmen` 次，再拾取 1 次仍 +250 分 |
| `pickup_rules_test.dart:132` Boss 左槽 | 链新增"`weaponLevel < 6` → weapon"，原期望 `[shield, shield, weapon]` 在 `weaponLevel = 5` 下不再成立 | 把前置改为 `weaponLevel = 6, overdrive = 2, wingmen = maxWingmen` 再断言护盾 |
| `battle_tuning_test.dart:89` 全部类型都能掉落 | `core` 不在随机池 | 断言 `PowerUpKind.values.where((k) => k != PowerUpKind.core)` |
| `rules_text_test.dart` | 长度自动变 7；新增 `进化核心` 与卫星文案断言 | 补断言 |
| `battle_render_batch_test.dart` | 全 kind 场景扩到 15 种、预算上调 | 循环 `kind < 15`，上限 ≤ 48 |

`player_weapon_test`、`hud_stats_test`、`daily_challenge_test`、`battle_visuals_test`（`PowerUpKind.values` 都有颜色）无需改动，只要 `kPowerUpColors[core]` 已补。

### 8.2 新增测试

**`player_weapon_test`**

- 3 条路线 × 2 阶：弹数 = 13/15、9/9、5/7；一轮总伤害 = 14/16、11/13、7/9；`kind` 集合符合 §4.3。
- 用 `lateral = offsetX + tan(angle) * 300` 计算 ST：基准 4；散射 4/4；贯穿 5/7；聚能 7/9。ST-DPS 同路线严格递增，且护栏 2（≤ 基准 × 2.0，总 DPS ≤ 基准 × 1.9）。
- 聚能汇聚几何：所有 `focusBolt` 满足 `|offsetX + tan(angle) * 300| < 1`，且左侧弹 `angle > 0`、右侧弹 `angle < 0`。
- 所有玩家弹 `pierce <= kMaxPierce`；`overdrive == 0` 时仍走 `kPlayerWeaponPatterns`（回归）；`weaponLevel < 6` 时即使 `overdrive > 0` 也走基础表（防御性）。
- `firstPiercingLevel() == 4` 不变。
- `playerFireInterval(6, rapid: false, route: …)` 等于基准 × `fireIntervalScale`；不传 `route` 与旧值一致。

**`pickup_rules_test`**

- `core` 拾取全表：`weaponLevel < 6` → 升级；6 级 → `overdrive 1` 与路线；同路线 → 2；满阶同路线 → +400 分；异路线 → 路线切换、阶数 `max(1, n-1)`。
- 不变量 1–2 在所有序列后成立（随机序列 + 不变量断言）。
- `applyHitPenalty`：`overdrive 2 → 1 → 0(route=null) → weaponLevel 5 → …`，`weaponLevel` 最低 1；僚机数不变。
- `resolveDrop`：`wave < 5` 不转化；`weaponLevel < 6` 不转化；`overdrive == 2` 不转化；`coreKills < 30` 不转化；满足时转化并清零；转化后 30 次击破内再次抽到 weapon 不转化。
- `DropLedger`：`rollKill` 不额外消耗随机数（参数仍只有两个）；`reset()` 不清 `coreKills`，`clearRun()` 设为就绪；炸弹掉落清空 `bombPity/eliteKills` 不影响 `coreKills`。
- `bossDrops` 7 级链逐级断言（含 `wave < 5` 时跳过核心）；中间槽/右槽不变。
- 统计验收：固定种子模拟第 5–12 波击破序列（满级、双僚机、无受伤），核心总数落在 2–5 枚区间。
- `applyPickup(wingman)`：第 3 次拾取出卫星提示；第 4 次折分 250。

**`battle_controller_test`**

- 贯穿 2 次：一发 `p2` 子弹一帧扫过三架敌机，三架都受伤，子弹消失；连续多帧与第一架重叠不重复结算（`prevHit`）；第三架命中后消失。
- `p2` 子弹命中 Boss 一次即消失。
- 核心拾取：把 `PowerUp(kind: core)` 放在玩家位置，`age` 取 0 / 0.9 / 1.8 对应 fan/pierce/focus；断言 `player.route`、`overdrive`、飘字文本与颜色。
- 受伤：`overdrive 2` 受伤后变 1，`weaponLevel` 仍为 6；护盾先抵挡。
- 第三僚机：`side == 0`，位置在玩家正上方约 34 px；不射击（`playerBullets` 无来自它的弹）；第 4 次拾取 +250。
- 卫星吸收：在卫星位置塞 N 发敌弹，N ≤ 12 时全部消失、玩家不受伤、`energy` 减 N；第 12 发后 `overheat == 6`；过热期间敌弹穿过；6 s 后 `energy == 6` 恢复吸收；就绪时 `energy` 按 0.6/s 回复且不超上限。
- 卫星先于机身接弹：同一帧卫星与玩家都在弹的路径上时，玩家不扣命。
- 重新开始：`overdrive == 0`、`route == null`、僚机/卫星清空、`_drops.coreKills` 就绪。
- 同种子同脚本的掉落序列两次一致（含核心转化）。
- 每日挑战：`scarcity` 与普通战斗跑同一击破脚本，Boss 链都产出核心；`arsenal` 开局 3 级，第 4 波以内没有核心。
- 第 1–4 波（含 Boss 波）不会掉出 `core`，不会出现过载路线。

**`battle_render_batch_test`**

- §4.6 的预算表全部场景；`circleCalls` 在三僚机场景不超过既有断言。
- 散射 Ⅱ + 三僚机 + 150 敌弹渲染不抛异常；`wingmen` 为空时不画卫星。
- 路线弹种使用各自样式（`playerShotStyle(12/13/14)` 不等于脉冲样式）；`rail` 的 `tailDots == 3`。
- 核心补给：渲染不抛异常；3 个路线字形文本缓存数量 ≤ 3（`cachedTextPainters` 不随帧数增长）。

**`hud_stats_test` / `battle_hud_test`**

- `overdrive > 0` 时 `shortValue` / `fullValue` / 图标色；`overdrive == 0` 回归。
- 3 僚机 + 急速 + `7聚` 在 320 dp 宽 `tester.binding.setSurfaceSize` 下无溢出（`tester.takeException() == null`）。
- 紧凑波次面板与状态条的火力文本一致（均来自 `firepowerLabel`）。

**`battle_visuals_test`**

- `kPowerUpColors` 覆盖全部 `PowerUpKind`；`kWeaponRoutes[route].argb` 等于对应弹种的辉光色。

**`rules_text_test`**

- `supplyHints()` 含 `Player.maxOverdrive`、`kOverdriveFromWave`、`Player.maxWingmen`；`routeHints()` 含三个路线名称，文案来自 `kWeaponRoutes`。

### 8.3 验收标准

1. `flutter analyze` 零告警，`flutter test` 全绿（预计 320+ 项）。
2. 第 1–4 波不出现核心、路线与卫星；首次核心最早出现在第 5 波之后（含 Boss 链：第 8 波）。
3. 6 级后接取核心进入过载：HUD 火力变为 `7聚` 等形式，机体描边变为路线色；三条路线的弹道在 3 秒内肉眼可区分（颜色、形状、覆盖角度至少两项不同）。
4. 路线数值满足 §4.3 护栏；Ⅱ 阶相对 6 级的 ST-DPS：散射 +14%、贯穿 +75%、聚能 +87%，没有一条路线在所有场景同时最优（聚能总 DPS 低于 6 级，散射对 Boss 无增益，贯穿边路弱）。
5. 受伤：L8 → L7 → L6 → L5；护盾保护过载；僚机与卫星不受伤害影响。
6. 卫星：满编后第 3 次僚机补给召唤；能量 12、过热 6 s、恢复半管，行为与 §4.4 一致；过热可见。
7. 核心：颜色与字样每 0.9 s 循环；在 320 dp 屏上字形清晰；转向降一阶、满阶折分 400。
8. 绘制预算符合 §4.6；真机/桌面 120 Hz 档下，散射 Ⅱ + 急速 + 三僚机 + 密集弹幕，帧时间相对 v0.5.0 同场景回退 ≤ 10%（本机无法验证时在"实现偏差"里如实记录）。
9. `daily_challenge.dart` 无 diff；`kPowerUpWeights` 与随机序列不变；README、`rules_text`、HUD 的数字都来自常量，无过期数字。
10. `pubspec.yaml` 与 README 版本均为 `0.6.0`。

---

## 9. 风险与不做事项

### 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| **散射 Ⅱ 子弹数过多**：15 发/0.0968 s ≈ 155 发/s，急速时 ≈ 250 发/s，同屏玩家弹峰值约 200 | 扇弹大角度很快出界被回收；碰撞有包围盒预判；性能验收（§8.3-8）；仍无玩家弹对象池——若实测 GC 抖动，先考虑给 `Bullet` 做简单回收池（独立 PR）。降级旋钮：让外圈扇弹每两轮发射一次，或把散射间隔系数从 0.88 调回 1.0 |
| **核心颜色误接** | 转向只降一阶，不清路线；字形 + 颜色双编码；核心下落 ≈ 11 s，循环 4 次 |
| **路线强度失衡**（尤其贯穿 Ⅱ +75% ST） | 调参只改 `PlayerShot` 伤害与 `kWeaponRoutes.fireIntervalScale`；护栏测试保证不越过 2.0×；后期难度旋钮见下 |
| **后期过强**：L8 叠加急速/护盾后，波次 17+ 变得太容易 | 已有旋钮 `kLateDifficultyStep`（0.12，可调到 0.14）与 `kCoreCooldownKills`（30，可调大）；不预先加新敌机机制 |
| **卫星过强/过弱** | 全部数值在 `kGuard*`；最容易调的是 `kGuardMaxEnergy` 与 `kGuardOverheat` |
| **卫星挡视线** | 六边形半径仅 6 px，位于机头前 34 px；描边与玩家同风格；后续可加"玩家设置里关闭卫星光环"，本版不做 |
| **`PowerUpKind` 全集假设漏改** | §2 审计发现 4 与 §8.1 已逐项列出；`battle_visuals_test`/`rules_text_test`/`pickup_rules_test` 都按 `values` 遍历，漏改会直接失败 |
| **`maxWingmen` 影响多个测试** | §8.1 列明；其余测试均引用 `Player.maxWingmen` 常量，自动跟随 |
| **`Bullet.prevHit` 持有死亡敌机** | 同 v0.5 的 `lastHit`，子弹秒级寿命，无需额外清理 |
| **同种子可复现** | 无新增随机抽签；核心路线由 `age` 决定；`wingmanSideFor` 与卫星状态均为确定性 |
| **紧凑 HUD 溢出** | 估算 266 dp；窄屏测试；兜底 `FittedBox` |

### 明确不做

- 僚机进化阶（疾风/重炮升级）：状态矩阵 × 渲染 × 文案 × 测试成倍增长；若玩家反馈卫星之外仍缺僚机成长，v0.7 再评估。
- 第 4 个及以上僚机位；卫星绕机旋转；卫星开火或承担碰撞伤害。
- 弹窗/暂停式路线选择；"重置路线"按钮；路线间无损切换。
- 限时超武、超级炸弹、分数倍率补给。
- 修改 Boss 弹幕、敌机编队、难度曲线（只保留旋钮）；新增成就；新增音效/图片/字体。
- 修改 `daily_challenge.dart` 或为挑战复制战斗逻辑；联网。
- 动 CI 流水线、签名与密钥。
