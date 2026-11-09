# v0.5 玩法深化设计：弹道样式、僚机分工、波次曲线与炸弹掉落

> 状态：设计稿（未实现）。分支 `feat/gameplay-depth`，基线 v0.4.2。
> 原则：在既有战斗循环上做**保守增量**，不重写；数值全部落在单一出处；程序化绘制与批绘制不退化。
> 建议版本号：内容 PR 合入后 bump 到 `0.5.0`（`pubspec.yaml`、README 版本表与下载链接），是否 bump 由实现者决定；**不要改 CI 签名/密钥**。

---

## 1. 目标与非目标

### 目标

1. **弹道六级各有辨识度**：每一级在外观（颜色、长短、粗细、光晕）与手感（穿透、单发伤害、命中半径）上都有可感知差异，不再只是"更多一样的青白光束"。
2. **僚机分工**：仍最多 2 架，但左右僚机外观与射击模式不同（速射 vs 重炮）。
3. **波次曲线**：前 3 波是教学（少而慢、逐个引入机制），后期加压（更陡的血量曲线 + 额外编队），且不破坏每日挑战修正。
4. **炸弹获取**：掉落规则成文并集中到单一出处——精英保底、Boss 保证、炸弹 pity、库存上限。
5. **顺带**：基于审计微调通用掉落权重；修正 `player_weapon.dart` 过期注释。

### 非目标

- 不新增每日挑战模式，不联网，不新增音频/图片资源。
- 不改僚机上限（保持 `Player.maxWingmen = 2`，HUD/文案/测试无需联动）。
- 不改玩家火力等级上限（6）、`maxBombs`（3）、连击规则、Boss 弹幕库、敌机移动。
- 不引入玩家弹对象池（现状也没有，见 §10）；不改两趟弹幕收集结构。

---

## 2. 现状审计（以真实代码为准）

| 项 | 现状 | 出处 |
| --- | --- | --- |
| 弹道表 | `kPlayerWeaponPatterns[1..6]`，仅 `PlayerShot(offsetX, angle)`；弹数 1/2/4/5/7/9 | `player_weapon.dart` |
| 子弹属性 | 一律 `radius: 3.4, damage: 1, kind` 缺省 0、无穿透 | `appendPlayerShots` |
| 过期注释 | `/// 五级弹道`，实际六级（索引 0 占位） | `player_weapon.dart:14` |
| 射击间隔 | `kBaseFireInterval 0.15 − 0.008·(lv−1)`，急速 ×0.62；名义 DPS 6.7/14.1/29.9/39.7/59.3/81.8 | `playerFireInterval` |
| 玩家弹渲染 | `_drawBullets` 一次遍历写三层：辉光 `_dots`（r8, α0.28）、弹体 `_capsules`（半长4/宽6）、弹芯白色 `_capsules`（半长2.9/宽2.2）；**不看 `kind`**，且只用竖直胶囊（斜射弹也竖着画） | `battle_field_component.dart:419` |
| 敌弹渲染 | 第二趟遍历，`kEnemyBulletColors[kind]` 分桶；`BulletKind` 已用 0–5 | `battle_visuals.dart:259`、`battle_types.dart:62` |
| 批绘制预算 | 现有测试：240 弹（玩家 kind 0）`rawPointsCalls ≤ 12` | `test/battle_render_batch_test.dart:122` |
| 玩家弹碰撞 | `_collidePlayerShots`：命中即 `bullet.dead = true`，`break` | `battle_controller.dart:665` |
| 僚机 | 左右各一（`side = wingmen.isOdd ? -1 : 1` → **第一架在左翼，第二架在右翼**），同外观；单发、`kWingmanFireInterval 0.36`、伤害 1、半径 3、外张角 0.06 | `_collectPowerUp`、`appendWingmanShots` |
| 掉落权重 | `powerUpKindForRoll`：weapon 36 / shield 20 / bomb 12 / star 11 / rapid 11 / wingman 10（累计阈值硬编码在函数里） | `battle_tuning.dart:118` |
| 掉落流程 | 非 Boss：`_rng.nextDouble() < dropChance×dropScale` 或 `_dropPity ≥ 20`，掉落时再 roll 一次种类；Boss：三个独立随机 roll（可能三个 star），并清 pity | `_killEnemy`、`_dropAt` |
| 炸弹 | 开局 `Player.bombs = 2`（字面量写在类里）、上限 3、满额折算 `kBombCapScore 200`；**没有任何炸弹专属保证** | `battle_types.dart:192` |
| 挑战修正 | `scarcity.dropScale = 0.62` 只乘非 Boss 的**单次掉率**；通用 pity 与 Boss 三掉不受影响 | `daily_challenge.dart`、`_killEnemy` |
| 难度曲线 | `waveDifficulty = 1 + 0.09·(wave−1)` 线性无上限；`enemyFireIntervalScale = 1/√难度`；`_spawnEnemy` 再乘 `challengeModifier.enemyHpScale` | `battle_tuning.dart:71` |
| 编队 | V 形侦察 `3+(tier+1)%3`、横排侦察 `3+tier%3`；第 1 波共 9 架侦察机；战斗机≥2、轰炸机≥3、无人机≥4、精英+截击≥5、再加战斗机≥7、堡垒≥8、轰炸机≥9 | `wave_director.dart` |
| 门槛实况 | 第 4/8/12… 波是 Boss 波，故 `tier≥4` 实际第 5 波才出无人机；`tier≥8` 实际第 9 波才出堡垒 | `bossWave = wave % 4 == 0` |
| 单一出处现状 | 拾取效果 `pickup_rules.dart`；玩法说明 `rules_text.dart`（`supplyHints` 长度被 `rules_text_test` 约束为 `PowerUpKind.values.length`） | — |

**审计结论**：①弹道的"视觉层"与"数据层"都没有 kind 维度；②Boss 掉落与炸弹完全靠运气；③第 1 波敌机偏多（9 架侦察）而第 12 波以后血量曲线与满级火力（≈82 DPS）相比偏平；④通用权重里 star 偏低、bomb 作为"随机池主力"偏高（既然要有专属保证渠道）。

---

## 3. 子弹等级设计

### 3.1 新增数据维度

- `PlayerShot` 增加 `kind / damage / radius / pierce`（均有默认值，旧构造向后兼容），用命名构造表达预设：`PlayerShot.twin(x)`、`.needle(x, angle)`、`.lance(x, {damage, pierce})`、`.nova(x)`。
- `Bullet` 增加 `int pierce`（可变，默认 0）与 `Enemy? lastHit`（穿透防重复命中，仅玩家弹使用）。敌弹零额外开销（两个字段默认值）。
- `BulletKind` 增加玩家弹种与僚机弹种：

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `BulletKind.player`（已有） | 0 | 脉冲弹（1 级） |
| `twin` | 6 | 双联弹（薄荷绿，长细胶囊） |
| `needle` | 7 | 裂波针（天蓝，短细，斜射扇面） |
| `lance` | 8 | 穿甲矛（冰白，长粗，穿透） |
| `nova` | 9 | 新星矛（6 级中路，最粗最亮，带拖尾） |
| `galeBolt` | 10 | 疾风僚机弹（轻） |
| `heavyBolt` | 11 | 重炮僚机弹（重） |

`BulletKind` 增加 `static bool isPlayer(int kind) => kind == player || kind >= twin;`。配色约束：玩家弹只用**冷色 + 白芯**且保持**胶囊形**；敌弹仍是暖色/紫色**圆点**，形状+色相双重区分，避免密集弹幕里误认。

### 3.2 六级弹道表

偏移与角度**沿用现表不变**（`player_weapon_test` 里按 x 偏移、对称、恒速的断言继续成立），只扩展 kind/伤害/穿透。弹速仍统一 `kPlayerBulletSpeed`（不新增 speedScale，减少测试变动）。

| 级 | 弹数 | 组成（offsetX / angle） | 半径 | 单发伤害 | 穿透 | 视觉 kind / 颜色意图 | 手感 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 中路 `0/0` | 3.4 | 1 | 0 | `player`(0)：青辉光 + 青白弹体（**与现版完全一致**） | 起手脉冲，单线 |
| 2 | 2 | `±5 / 0` | 3.2 | 1 | 0 | `twin`(6)：薄荷绿，细长胶囊 | 并行双联，覆盖面略宽 |
| 3 | 4 | 双联 `±6/0` ×2；裂波针 `±11 / ∓0.16`（外张） | 3.2 / 3.0 | 1 | 0 | 薄荷绿 + 天蓝针 | 出现扇面，开始"清边路" |
| 4 | 5 | **穿甲矛** `0/0`；双联 `±7/0`；针 `±13 / ±0.17` | 3.6 / 3.2 / 3.0 | 矛 2，其余 1 | 矛 1 | 冰白长矛居中 + 绿 + 蓝 | 首次出现穿透：纵向排列的杂兵一发穿两 |
| 5 | 7 | 矛 `0/0`；双联 `±8/0`；针 `±13 / ±0.14`、`±16 / ±0.30` | 同上 | 矛 2，其余 1 | 矛 1 | 同 4 级，外圈扇面更宽 | 中路重击 + 宽扇面 |
| 6 | 9 | **新星矛** `0/0`；副矛 `±9/0`；针 `±14/±0.13`、`±18/±0.28`、`±21/±0.43` | 4.2 / 3.6 / 3.0 | 新星 2，副矛 1，针 1 | 新星 1，副矛 1 | 新星：青白最粗最亮 + 拖尾；副矛冰白；针天蓝（**不再有薄荷绿**） | 三矛并进 + 六针宽扇，整体色调从绿转冰蓝，一眼可辨"满级" |

**名义 DPS（单目标、全中）**：

| 级 | 每轮伤害 | 间隔(s) | 名义 DPS | 现版 | 变化 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 0.150 | 6.7 | 6.7 | 0 |
| 2 | 2 | 0.142 | 14.1 | 14.1 | 0 |
| 3 | 4 | 0.134 | 29.9 | 29.9 | 0 |
| 4 | 6 | 0.126 | 47.6 | 39.7 | +20% |
| 5 | 8 | 0.118 | 67.8 | 59.3 | +14% |
| 6 | 10 | 0.110 | 90.9 | 81.8 | +11% |

增幅刻意随级递减，且穿透只对"纵向成列"目标额外增益；后期用 §5 更陡的血量曲线对冲。**所有伤害/穿透/半径只写在 `kPlayerWeaponPatterns`**，不在别处复制。

### 3.3 穿透规则（碰撞层）

只改 `_collidePlayerShots`，规则：

1. 命中前先跳过 `identical(enemy, bullet.lastHit)`（同一架敌机的后续帧重叠不重复结算）。
2. 命中 → `_damageEnemy` + `spark`。
3. 若 `bullet.pierce > 0 && !enemy.isBoss`：`pierce--`，`lastHit = enemy`，**`continue`**（同帧可继续检测下一架）。
4. 否则 `bullet.dead = true; break;`（与现版一致）。

要点：**Boss 不可被穿透**（矛打 Boss 命中即消散，避免大判定圈上的多帧叠伤与"穿过 Boss 再打后面"）；穿透上限固定为 1，所以单个 `lastHit` 引用足够，不需要集合。不分配新对象。

### 3.4 渲染（批绘制保持，玩家弹仍"一次遍历"）

在 `battle_visuals.dart` 增加：

```dart
class PlayerShotStyle {
  final int glowArgb, bodyArgb, coreArgb;
  final double glowRadius, glowAlpha;    // glowAlpha 取 0.25 / 0.375（DrawBatch 8 档量化）
  final double bodyHalf, bodyWidth, coreHalf, coreWidth;
  final double bodyK, coreK;             // = half / kPlayerBulletSpeed，预计算
  final int tailDots;                    // 0 或 2：沿弹道反向的拖尾点
}
PlayerShotStyle playerShotStyle(int kind); // 定长 List 按 kind 索引，未知回退脉冲
```

`_drawBullets` 玩家弹部分改为：

```
for bullet in playerBullets:
  s = playerShotStyle(bullet.kind)
  _dots.add(s.glowArgb, x, y, s.glowRadius, s.glowAlpha)          // 下层
  _segments.add(s.bodyArgb, x - vx*s.bodyK, y - vy*s.bodyK,
                x + vx*s.bodyK, y + vy*s.bodyK, s.bodyWidth, 1)   // 中层（沿速度方向，斜射弹终于是斜的）
  _segmentsTop.add(s.coreArgb, …coreK…, s.coreWidth, 1)           // 上层
  (tailDots>0) 沿 (-vx,-vy) 方向追加 2 个递减 _dots
flush 顺序：_dots → _segments → _segmentsTop
```

- 用 `SegmentBatch`（任意方向）替代竖直 `CapsuleBatch`；`vx=0` 时输出与现版逐像素一致。新增一个 `_segmentsTop` 实例，保证"所有弹体在下、所有弹芯在上"的层级不随 kind 混乱。
- 无 `sqrt`：方向向量用 `vx·half/kPlayerBulletSpeed` 近似（僚机弹速 540，长度偏差 <4%，肉眼不可辨）。
- 配色（ARGB 常量，辉光/弹体/弹芯）：

| kind | 辉光 | 弹体 | 弹芯 | 辉光半径 | 弹体 半长×宽 | 弹芯 半长×宽 |
| --- | --- | --- | --- | --- | --- | --- |
| 0 脉冲 | `4FD1FF` | `B7F4FF` | `FFFFFF` | 8 | 4 × 6 | 2.9 × 2.2（沿用现值） |
| 6 双联 | `2ED9A0` | `7CFFC4` | `FFFFFF` | 6 | 5.5 × 4.2 | 4 × 1.6 |
| 7 裂波针 | `5C8CFF` | `8FB4FF` | `E6F0FF` | 5.5 | 4.5 × 3.2 | 3.2 × 1.4 |
| 8 穿甲矛 | `9FE8FF` | `E4FBFF` | `FFFFFF` | 10 | 11 × 5.2 | 9 × 2.2 |
| 9 新星矛 | `4FD1FF` | `CFF8FF` | `FFFFFF` | 13 | 13 × 7.5 | 11 × 3.2，`tailDots=2` |
| 10 疾风 | `9BFFEA` | `9BFFEA` | `FFFFFF` | 4.5 | 3.5 × 2.6 | 2.4 × 1.1 |
| 11 重炮 | `5C8CFF` | `8FB8FF` | `FFFFFF` | 8 | 6 × 5.4 | 4.5 × 2.0 |

- **绘制调用预算**：`DrawBatch` 按（颜色, 线宽）分桶，调用数 = 非空桶数。6 级 + 双僚机同屏约 5 个 kind → 预计 ≤ 18 次 `drawRawPoints`（对比逐颗绘制数百次）。现有 kind-0 场景测试 `≤ 12` **保持不变**；新增两个预算测试，见 §9。
- 命中火花：保持 `0xFFB7F4FF` 常量（可选打磨：矛/新星命中额外一次 `spark`，不新增粒子类型）。

---

## 4. 僚机样式

仍最多 2 架；**按出生侧分工**（第一架必在左翼，第二架必在右翼，所以"只有一架"时玩家得到的是稳定的疾风僚机，第二架补上重炮）。

| 项 | 左翼 · 疾风（`WingmanRole.gale`） | 右翼 · 重炮（`WingmanRole.heavy`） |
| --- | --- | --- |
| 外观 | **沿用现有 `wingmanHullPath`**、青绿 `9BFFEA` 描边 | 新增 `wingmanHeavyHullPath`：更宽的梯形机身 + 两根炮管；描边 `8FB8FF`，尾焰偏蓝 |
| 射击 | 间隔 0.24 s，伤害 0.8，弹半径 2.8，外张角 0.06 | 间隔 0.60 s，伤害 2.0，弹半径 4.0，外张角 0.04 |
| 弹种 | `galeBolt`(10)：细短青绿 | `heavyBolt`(11)：粗长蓝白 |
| 名义 DPS | 3.33 | 3.33（现版每架 2.78，+20%） |
| 手感 | 频繁轻点，扫杂兵 | 低频重击，快速压低战斗机/轰炸机血量（2 发点掉侦察机） |

- 重炮初始 `cooldown = 0.2`，与疾风错开节拍，避免同帧齐射。
- 数据只在 `battle_tuning.dart`：新增 `enum WingmanRole`（放 `battle_types.dart`，`Wingman.role => side < 0 ? gale : heavy`）与 `const Map<WingmanRole, WingmanSpec> kWingmanSpecs`（`fireInterval / damage / radius / spreadAngle / bulletKind / initialCooldown`）。**删除**被 spec 取代的 `kWingmanFireInterval`、`kWingmanBulletDamage`、`kWingmanSpreadAngle`（弹速 `kWingmanBulletSpeed 540` 保留为共用常量），实现时 grep 全仓替换。
- `appendWingmanShots` 与 `_updateWingmen` 都改读 `kWingmanSpecs[wing.role]`；站位常量（`kWingmanOffsetX/Y`、`kWingmanFollowLerp`）不变。
- `_drawWingmen` 按 role 取 `WingmanVisual`（hull path、填充/描边/尾焰颜色），在 `battle_visuals.dart` 里作 `kWingmanVisuals`；仍逐架绘制（最多 2 架，无需批绘制）。
- 受伤只掉火力等级、不掉僚机——保持现状。

---

## 5. 波次难度曲线调整

### 5.1 `waveDifficulty` 分段（`battle_tuning.dart`）

```dart
const double kEarlyDifficultyStep = 0.05;  // 进入第 2、3 波
const double kWaveDifficultyStep  = 0.09;  // 沿用：进入第 4–12 波
const double kLateDifficultyStep  = 0.12;  // 进入第 13 波起
const int kEarlyWaveLast = 3;
const int kLateWaveFrom  = 13;
// 难度 = 1 + Σ 每波进入时的步长
```

| 波 | 1 | 2 | 3 | 4(Boss) | 5 | 8(Boss) | 9 | 12(Boss) | 13 | 16(Boss) | 20 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 现版 | 1.00 | 1.09 | 1.18 | 1.27 | 1.36 | 1.63 | 1.72 | 1.99 | 2.08 | 2.35 | 2.71 |
| 新版 | 1.00 | 1.05 | 1.10 | 1.19 | 1.28 | 1.55 | 1.64 | 1.91 | 2.03 | 2.39 | 2.87 |

- 首个 Boss（第 4 波）血量 −6%；第 16 波起比现版更硬，抵消满级火力与穿透的增益。
- `enemyFireIntervalScale` 保持 `1/√难度`，增加下限 `kEnemyFireScaleFloor = 0.55`（防止极后期射速失控；20 波时 1/√2.87≈0.59，尚未触底）。
- 每日挑战：`enemyHpScale` 仍在 `_spawnEnemy` 里乘 `waveDifficulty(wave)`，`enemyBulletSpeedScale` 乘弹速——**挑战代码零改动**。

### 5.2 编队改动（`wave_director.dart`，同一 `_buildFormation`）

**教学段（第 1–3 波）**

| 波 | 现版 | 新版 |
| --- | --- | --- |
| 1 | V 5 + 横排 4 = 9 架侦察机 | **V 3 + 横排 3 = 6 架侦察机**（只教"移动 + 自动开火"，无敌弹） |
| 2 | 侦察 8 + 战斗机 2 | 侦察 8 + **战斗机 1**（直线，首次遇到敌弹） |
| 3 | 侦察 7 + 战斗机 2 + 轰炸机 1 | 不变（第 2 架战斗机与轰炸机登场） |

实现：`vCount = tier <= 1 ? 3 : 3 + (tier + 1) % 3`，`lineCount = tier <= 1 ? 3 : 3 + tier % 3`；`tier == 2` 只生成第一架战斗机。

**中期（第 5–11 波）**：门槛不变（无人机/精英/截击机 ≥5，堡垒 ≥8 即首现第 9 波）。

**后期加压（新增，按 tier 门槛叠加，`x` 仍经 `add` 里的 34 边距钳制）**

| 门槛 | 新增 | 延迟 | 说明 |
| --- | --- | --- | --- |
| tier ≥ 11 | 第二架精英机（与首架对侧，`hover`） | 5.8 s | 五连发散射增加一条压迫线 |
| tier ≥ 13 | 第二架截击机（镜像侧，`dive`）；追加 2 架无人机（x=150 / W−150，`chase`） | 4.2 / 4.6 / 4.95 s | 第 13 波起血量曲线也转陡 |
| tier ≥ 17 | 堡垒改为 2 架：x = W/2 ∓ 85，`hover` | 4.9 / 5.4 s | 双环形齐射 |

- 单波敌机总数上限：≤ 28（第 13 波 24 架，第 17 波 24 架）；最大生成延迟 ≤ 6.4 s，与现版节奏同量级。
- `kBetweenWaveGap`、Boss 间隔、Boss 弹幕函数不变。

---

## 6. 炸弹与掉落规则（单一出处）

### 6.1 总览

| 来源 | 规则 | 受 `dropScale` 影响？ |
| --- | --- | --- |
| 单次掉率 | `EnemySpec.dropChance × challenge.dropScale`（clamp 0–1），不变 | **是**（唯一受影响项） |
| 种类权重 | 新表 `kPowerUpWeights`（见 6.2），随机池 | — |
| 通用 pity | 连续未掉落 N 次必掉：**第 1–2 波 N=10，其后 N=20**；pity 掉落若玩家 `weaponLevel < 3` 则直接给火力，否则按权重 roll | 否 |
| 精英保底炸弹 | 精英机/重装堡垒每累计 `kEliteBombEvery = 4` 次击破，下一次该类击破必掉炸弹（库存有空位时） | 否 |
| 炸弹 pity | 非 Boss 击破累计 `bombs == 0 ? 24 : 48` 次未出炸弹，下一次击破必掉炸弹（库存有空位时） | 否 |
| Boss 保证 | 三个补给：**左=火力或僚机或护盾（按需）、中=炸弹（满额则护盾）、右=随机 roll**；`dropChance=1`，不受 `dropScale` 影响（沿用现状） | 否 |
| 库存上限 | `Player.maxBombs = 3` 不变；保底判定看"有无空位"，满额时保底不触发（计数保留，空位出现后兑现），避免掉出只能折算成 200 分的炸弹 | — |

**与 scarcity（补给管制）的关系**：`dropScale` 只缩放"单次掉率"，**保底/保证类机制是底线，不缩放**（延续 `_dropPity` 现状的语义）。同时把随机池 bomb 权重从 12 降到 8，补偿新增的专属渠道，使"补给管制日"的炸弹总量增幅可控。`ChallengeModifier` 与 `daily_challenge.dart` 不改，不复制战斗逻辑。

### 6.2 权重微调（审计顺带）

| 补给 | 现版 | 新版 | 理由 |
| --- | --- | --- | --- |
| weapon | 36 | 34 | 满级后只折算 300 分，略降 |
| shield | 20 | 20 | — |
| bomb | 12 | **8** | 已有专属渠道 |
| star | 11 | 12 | 偏低，补回 |
| rapid | 11 | 14 | 与火力成长协同，提升 |
| wingman | 10 | 12 | 两架满编后折算，略升以免大多数局到不了双僚机 |

合计 100。累计阈值：weapon <0.34、shield <0.54、bomb <0.62、star <0.74、rapid <0.88、其余 wingman。**不做"按需重掷"**（满级 weapon 仍折算分数，保持规则简单）。

### 6.3 炸弹产出预期（未封顶时）

按平均每波 15–18 次击破估算：

- 第 5–8 波周期：精英保底 ≈ 0.75 + 随机 ≈ 0.5 + Boss 1 ≈ **2.2 枚/周期**
- 第 9–12 波周期（精英+堡垒共约 6 次）：≈ 1.5 + 0.55 + 1 ≈ **3.0 枚/周期**
- 第 1–4 波（无精英）：炸弹 pity 与第 4 波 Boss 兜底，约 1–2 枚

验收区间：用固定种子模拟 `DropLedger`，每 Boss 周期 1.5–3.5 枚（见 §9）。

### 6.4 API（`pickup_rules.dart` 为规则出处，数值在 `battle_tuning.dart`）

```dart
/// 掉落账本：集中 pity / 炸弹保底 / 精英计数，战斗控制器只持有一个实例。
class DropLedger {
  int pity = 0, bombPity = 0, eliteKills = 0;
  void reset();

  /// 非 Boss 击破。必须传入两个已抽好的随机数（控制器每次击破固定各抽一次，保证种子可复现）。
  PowerUpKind? rollKill({
    required EnemyKind kind, required int wave, required Player player,
    required double dropScale, required double chanceRoll, required double kindRoll,
  });

  /// Boss 击破：返回从左到右的三个补给，并清零账本。
  List<PowerUpKind> bossDrops(Player player, double kindRoll);
}
```

`rollKill` 判定顺序：①更新计数（`bombPity++`；精英类 `eliteKills = min(eliteKills+1, kEliteBombEvery)`）→ ②炸弹有空位且（精英类且 `eliteKills ≥ kEliteBombEvery`，或 `bombPity ≥ 阈值`）→ 掉炸弹，并清 `pity/bombPity/eliteKills` → ③否则 `chanceRoll < clamp(dropChance×dropScale)` 或 `pity ≥ dropPityLimitFor(wave)` → 掉落（pity 兜底时按需给火力），`pity = 0`；若结果恰为炸弹同样清 `bombPity/eliteKills` → ④否则 `pity++`，返回 null。

`battle_tuning.dart` 新增：`kStartBombs = 2`（`Player.bombs` 初值改读它，修掉类里的字面量）、`kEliteBombEvery = 4`、`kBombPityKillsEmpty = 24`、`kBombPityKillsHeld = 48`、`kEarlyDropWaves = 2`、`kEarlyDropPityLimit = 10`、`kBossDropOffsetX = 26`、`kPowerUpWeights`、`dropPityLimitFor(int wave)`、`isEliteClass(EnemyKind)`（elite、fortress）。`powerUpKindForRoll(double)` 改为按 `kPowerUpWeights` 累计（保留函数签名，测试只改阈值）。

`applyPickup` 的炸弹分支补 `color: 0xFFFF6B6B`（与补给配色一致，提示更醒目）；其余不变。

---

## 7. 文案 / README / rules_text 同步点

`rules_text.dart`（`supplyHints` 长度必须仍为 6，**只改文字不加条目**，`rules_text_test` 的长度断言继续成立）：

- 火力：`'火力：提升弹道等级，最高 ${Player.maxWeaponLevel} 级；${firstPiercingLevel()} 级起主炮可穿透一架普通敌机。'`；`firstPiercingLevel()` 放 `player_weapon.dart`，由 `kPlayerWeaponPatterns` 推导（不再硬编码 4）。
- 炸弹：`'炸弹：补充一枚全屏炸弹，上限 ${Player.maxBombs} 枚；Boss 必出，精英机/堡垒每 $kEliteBombEvery 次击破必出，炸弹告急时另有保底。'`
- 僚机：`'僚机：左翼疾风僚机速射、右翼重炮僚机重击，最多 ${Player.maxWingmen} 架。'`

`README.md`：

- 特色"完整战斗循环"：六级弹道改述为"六级弹道（脉冲→双联→裂波→穿甲→新星，4 级起主炮可穿透）"。
- 特色"僚机编队"：改为"左翼疾风速射、右翼重炮重击，最多两架"。
- 特色"批绘制与对象池"：玩家弹按弹种分桶，补充"满级弹道加双僚机同屏约 18 次以内绘制调用"（数字以实际测试预算为准）；保留"240 颗弹幕 12 次以内"仅当该基准场景仍成立。
- 玩法第 2、3 条：补给说明与"击破 Boss 掉落三份补给（含必出炸弹）"。
- 测试数量、版本表（若 bump 则新增 `v0.5.0 | 内容版本：…` 行并更新下载链接/示例 tag 命令）。
- `player_weapon.dart` 注释"五级弹道"改为"六级弹道"。

---

## 8. 文件级实现清单

| 文件 | 变更 |
| --- | --- |
| `lib/game/battle/battle_types.dart` | `BulletKind` 增 `twin/needle/lance/nova/galeBolt/heavyBolt` 与 `isPlayer`；`Bullet` 增 `int pierce`、`Enemy? lastHit`；新增 `enum WingmanRole`，`Wingman.role` getter；`Player.bombs` 初值改 `kStartBombs`（注意 types 与 tuning 互相引用，可把初值改为构造时在 `BattleController.start()` 赋值，避免循环依赖——实现者择一） |
| `lib/game/battle/player_weapon.dart` | `PlayerShot` 扩字段与命名构造；重写 `kPlayerWeaponPatterns`（§3.2）；`appendPlayerShots` 把 `kind/damage/radius/pierce` 传进 `Bullet`；`appendWingmanShots` 读 `kWingmanSpecs`；新增 `firstPiercingLevel()`；修注释 |
| `lib/game/battle/battle_tuning.dart` | 难度分段常量与 `waveDifficulty`、`kEnemyFireScaleFloor`；`kPowerUpWeights` + `powerUpKindForRoll`；炸弹/pity 常量、`dropPityLimitFor`、`isEliteClass`；`WingmanSpec` + `kWingmanSpecs`，移除被取代的僚机常量 |
| `lib/game/battle/pickup_rules.dart` | 新增 `DropLedger`（§6.4）；炸弹提示加颜色 |
| `lib/game/battle/wave_director.dart` | 教学段编队、后期加压（§5.2）；其余结构不动 |
| `lib/game/battle/battle_controller.dart` | `_dropPity` → `final DropLedger _drops`，`start()` 里 `reset()`；`_killEnemy` 非 Boss 路径固定抽 `chanceRoll/kindRoll` 后调 `rollKill`，Boss 路径调 `bossDrops` 并按 `x−26 / x / x+26` 放置；`_dropAt` 改为接收 `kind`；`_collidePlayerShots` 加穿透（§3.3）；`_updateWingmen` 读 spec 间隔；`_collectPowerUp` 创建僚机时设置重炮初始冷却 |
| `lib/flame/battle_visuals.dart` | `PlayerShotStyle` + `playerShotStyle(kind)`；`kWingmanVisuals`；保留 `kPlayerBulletGlow/Body` 常量（兼容引用，可标注为脉冲弹配色） |
| `lib/flame/battle_field_component.dart` | `_drawBullets` 玩家弹改按 style 分层（§3.4），新增 `_segmentsTop`；`_drawWingmen` 按 role 取外观与尾焰 |
| `lib/game/ship_geometry.dart` | 新增 `wingmanHeavyHullPath` |
| `lib/game/battle/rules_text.dart` | §7 三处文案 |
| `README.md`、`pubspec.yaml` | §7；若 bump 则 `version: 0.5.0` |

**不改**：`daily_challenge.dart`、`enemy_weapons.dart`、`boss_catalog.dart`、`bullet_field.dart`、HUD（最大僚机数不变，HUD 只显示"火力 N"/炸弹数）、CI/签名文件。

**建议实施顺序**（每步可独立 `flutter test`）：①类型与数据表 → ②穿透碰撞 + 测试 → ③渲染分层 + 预算测试 → ④僚机 spec/外观 → ⑤`DropLedger` + 控制器接线 → ⑥波次/难度 → ⑦文案/README → ⑧版本号。

---

## 9. 测试计划与验收标准

### 9.1 需要**更新**的现有测试

- `battle_tuning_test`：`waveDifficulty(2)` 为 1.05、`waveDifficulty(11)` 为 1.82（=1+2·0.05+8·0.09）；掉落映射边界改为 0.34/0.54/0.62/0.74/0.88；"全部类型都能掉落"保留。
- `wave_director_test`：第 1 波仅含侦察机且数量为 6；第 2 波战斗机恰 1 架；高波次测试继续成立。
- `pickup_rules_test`：炸弹提示非空仍成立；其余不变。
- `rules_text_test`：`supplyHints` 长度仍为 6，断言新增文案含 `kEliteBombEvery` 与 `firstPiercingLevel()`。
- `player_weapon_test`：**原有 x 偏移/对称/恒速/越界断言应无需修改即通过**（偏移与角度未变）；僚机测试仍成立（出弹点 `y−9`、左负右正）。

### 9.2 新增测试

**player_weapon_test**
- 每级弹数 = 1/2/4/5/7/9；每级 `kind` 集合符合 §3.2；L1 全为 kind 0。
- 4 级起存在 `pierce==1 && damage==2` 的中路弹；3 级及以下全 `pierce==0`；`firstPiercingLevel() == 4`。
- 名义每轮伤害 1/2/4/6/8/10 且 DPS 随级单调不降（用 `playerFireInterval`）；6 级 DPS ≤ 现版 ×1.25。
- 僚机：左翼 `galeBolt`、右翼 `heavyBolt`；左右伤害/半径与 `kWingmanSpecs` 一致；`Wingman.role` 随 `side`。

**battle_controller_test（穿透碰撞，直接塞 `playerBullets`/`enemies`）**
- 穿透矛一帧扫过前后两架敌机：两架都受伤，矛消失。
- 穿透矛连续多帧与同一敌机重叠：只结算一次伤害（`lastHit`）。
- 穿透矛命中 Boss：结算一次后消失，不穿透。
- 非穿透弹行为不变：命中第一架即消失，第二架无伤。
- 穿透矛击杀第一架后继续飞行并命中第二架。
- 玩家弹 `pierce` 不影响敌弹碰撞。

**battle_render_batch_test**
- 原基准（240 弹，kind 0）`rawPointsCalls ≤ 12` 不变。
- 新增"全部 kind 同屏"：12 种 kind 各若干颗，`rawPointsCalls ≤ 40`。
- 新增"现实场景"：6 级弹道 + 双僚机 + 150 敌弹，`rawPointsCalls ≤ 20`；`circleCalls` 仍与弹数无关。
- 斜射弹生成的线段端点不竖直（验证方向向量）；`vx=0` 时端点 x 相等。
- 渲染两僚机角色不抛异常，且 `controller.wingmen` 为空时不绘制。

**pickup_rules_test（`DropLedger`，传入固定 roll，无需随机）**
- `chanceRoll` 极大且无保底：返回 null，`pity` 递增。
- 第 1–2 波 pity=10 触发，第 3 波起 20 触发；`weaponLevel<3` 时 pity 掉落为火力。
- 精英/堡垒第 4 次击破必掉炸弹，普通敌不计入；炸弹满额时不触发且计数保留，`bombs--` 后下一次精英兑现。
- `bombs==0` 时第 24 次非 Boss 击破必掉炸弹，`bombs>0` 为 48。
- `dropScale=0.62` 下：随机掉率下降（`chanceRoll=0.03`、`dropChance 0.04×0.62=0.0248` 不掉），但精英保底、炸弹 pity、通用 pity 照常触发。
- 任何路径产生炸弹都清零 `bombPity/eliteKills`。
- `bossDrops`：三项、中路为炸弹（满额为护盾）、左项按需（`weaponLevel≥5` 且僚机未满→僚机，皆满→护盾）；账本清零。
- 统计验收：固定种子模拟 4 波一周期（按 §6.3 的击破序列），炸弹产出落在 1.5–3.5 枚区间。

**battle_controller_test（掉落接线）**
- 击破 Boss 后 `powerUps.length == 3`，x 分别为 `x−26 / x / x+26`，中间为炸弹（有空位时）。
- 同种子同操作重复两次掉落序列完全一致（每次非 Boss 击破固定抽 2 个随机数）。
- 挑战 `scarcity` 与普通战斗跑同一击破脚本：精英第 4 次击破两者都出炸弹。

**wave_director_test（曲线）**
- 第 13 波含 ≥2 架截击机、≥4 架无人机、≥2 架精英；第 17 波含 2 架堡垒；每波总数 ≤ 28、最大延迟 ≤ 6.4 s、所有 `x ∈ [34, W−34]`。
- 同种子两次生成的队列完全一致（确定性，保护每日挑战同种子同战场）。

### 9.3 验收标准

1. `flutter analyze` 零告警，`flutter test` 全绿。
2. 1→6 级逐级升级，肉眼可区分：颜色/长短/粗细至少两项不同；6 级相对 5 级明显换色并出现拖尾。
3. 穿透仅 4 级起、仅对非 Boss、每颗至多穿一次；同一敌机不被同一发多帧重复结算。
4. 左右僚机外观、弹种、节奏可区分；总数仍 ≤ 2；HUD 与 `rules_text` 数字来自常量。
5. 第 1 波 6 架侦察机无敌弹；第 1–3 波只出现侦察机、战斗机与轰炸机；第 13/17 波按 §5.2 加压且单波 ≤ 28 架。
6. 炸弹：Boss 必出；精英类每 4 次必出；`bombs==0` 时 24 次内必出；库存永不超过 3；`scarcity` 日单次掉率仍 −38%。
7. 渲染预算符合 §9.2；真机/桌面 120Hz 档下 6 级弹道 + 密集弹幕无明显掉帧（对比 v0.4.2 同场景，帧时间回退 ≤ 10%）。
8. README 与 `rules_text` 无过期数字；`daily_challenge.dart` 无 diff。

---

## 10. 风险与不做的事项

**风险与缓解**

| 风险 | 缓解 |
| --- | --- |
| 穿透让纵向成列的杂兵被秒，挑战"重装舰队"血量 +22% 与之叠加难以预估 | 穿透上限 1、不穿 Boss；DPS 增幅 ≤ +20% 并随级递减；后期血量曲线加陡；验收含 TTK 手测 |
| 玩家弹与敌弹视觉混淆 | 玩家弹仅冷色+白芯+胶囊形；敌弹暖色/紫色圆点；颜色表集中在 `battle_visuals.dart` 便于调整 |
| 弹种增多导致绘制调用上升 | 沿用 `DrawBatch` 分桶；辉光透明度取 8 档量化值；预算有测试护栏；同色同宽自动合桶 |
| 新增 `Enemy? lastHit` 持有死亡敌机引用 | 子弹生命周期很短（秒级），随子弹回收即释放；不做额外清理 |
| 掉落改动影响每日挑战同种子可复现 | 非 Boss 击破固定抽 2 个随机数；`_rng` 同时被特效使用，属既有耦合，新增分支不改变抽取次数；同一天依旧同战场（但与 v0.4.2 的当天战场不同，属预期） |
| `types ↔ tuning` 循环引用（`Player.bombs` 初值） | 允许改为在 `start()` 赋值；或把 `kStartBombs` 放进 `battle_types.dart` 并由 tuning 引用 |
| 保底叠加让 scarcity 日偏松 | 保底不缩放是有意设计；随机池 bomb 权重已降；若实测偏松，只需调 `kEliteBombEvery` 一个常量 |

**明确不做**

- 不新增每日挑战模式/修正；不为挑战复制战斗逻辑；不联网。
- 不提高僚机上限、不加僚机损失/复活机制；不提高 `maxBombs`。
- 不做玩家弹对象池（现状不存在，收益不明确）；不改敌弹两趟收集结构；不新增音效、图片、字体。
- 不做"按需重掷"掉落、不做穿透 >1、不做穿 Boss、不引入弹速分级。
- 不动 CI 流水线、签名与密钥；不重写 Boss 弹幕。

---

## 11. 实现偏差与审查

实现提交：`b2da515`（相对设计稿）。

1. `wave_director.dart` 在编队组装后按 delay 排序，避免较晚条目阻塞较早增援；不影响同种子确定性。
2. 渲染预算：kind-0 基准仍 ≤12；满级弹道+双僚机+单类敌弹场景满足设计 ≤20；三类混合敌弹实测约 23 次 `drawRawPoints`（略超设计「现实场景」的 20，仍远低于逐颗绘制）。
3. 120Hz 真机帧时间对比未在本机验证。

审查结论（Claude，对照 §3–§9）：穿透、DropLedger 顺序、僚机角色、波次门槛、`daily_challenge.dart` 无 diff、关键测试覆盖均符合设计；无必须修 bug。协调方已本地验证 `flutter analyze` 零告警、`flutter test` 282 全绿。

REVIEW_PASS
