# v0.7 玩法迭代设计：凝神、擦弹、共鸣与矛击

> 状态：设计稿（待实现）。分支 `feat/gameplay-iteration`，基线 v0.6.0（`3bbb5b7`，`flutter test` 325 项）。
> 发布位置：用户自己的 fork（`qpzm7903/flutter-plane`），不向上游提 PR。
> 原则：v0.6 解决了"满级之后买什么"（成长轴）；v0.7 解决"**怎么打、站在哪**"（操作轴）。不加新补给、不加新敌机、不抬数值上限，只给玩家新的**姿态**与新的**技巧表达**。
> 版本号：实现完成后 bump 到 `0.7.0`（`pubspec.yaml` 的 `version:`、`lib/utils/constants.dart` 的 `AppConstants.version`、README 版本表/下载链接/tag 示例，见 §7、§8）。**不要改 CI 签名与密钥。**
> 表述约定：本文所有"世界像素"指 `kWorldWidth = 400` 的战场坐标；"dp"指屏幕逻辑像素。

---

## 1. 目标与非目标

### 目标

1. **给"站位"一个意义**：目前玩家只会"拖动躲弹 + 自动开火"，**移动速度本身没有任何后果**。v0.7 让"慢"与"快"成为两种有后果的姿态：
   - **静（凝神 Focus）**：放慢/停下 → 判定变小、火力收束、僚机内收、静止蓄能。
   - **动（擦弹 Graze）**：贴着弹幕跑 → 赚分、续连击、给共鸣条供能。
2. **两种资源，两种姿态**：静止蓄 **矛击（Charge Lance）**，运动蓄 **共鸣（Resonance）**；共鸣释放后顺手把矛击充满，形成"擦弹 → 共鸣 → 静 → 动 → 矛击"的节奏环，而不是四个互不相干的功能。
3. **全部手机单手可玩**：没有新增按键。凝神由"手指移动速度"自动判定；共鸣用**双击战场**触发；矛击由"从静到动"的动作自然释放。Windows 补 `Shift`（凝神）与 `R`（共鸣）。
4. **不抬数值**：凝神只改几何（判定/弹道收束），不改每齐射总伤害；擦弹与共鸣只产出**分数与资源**，共鸣不伤敌；矛击是**清线工具**，对 Boss 的伤害刻意很低。
5. **教学窗保持干净**：第 1–2 波完全没有新机制；第 3 波才引入凝神与擦弹（轻量、只增不罚）；第 5 波开放共鸣；第 6 波开放矛击（见 §5.0 解锁表）。
6. **受伤不毁进度**：受伤只扣共鸣条 20 点（不清零），矛击蓄能与擦弹统计完全保留；护盾破碎不扣任何东西（见 §6）。
7. **性能与结构不退化**：不新增对象池之外的每帧分配；擦弹判定并入既有敌弹**单趟**碰撞循环；新增视觉全部走既有 `DotBatch/SegmentBatch` 或每帧 ≤3 次额外 `drawArc/drawCircle`。

### 非目标

- `daily_challenge.dart` **零改动**（§5.9）。`wave_director.dart`、`enemy_weapons.dart`、`boss_catalog.dart`、`enemy_motion.dart`、`bullet_field.dart`、`kPowerUpWeights`、`DropLedger` 逻辑**零改动**。
- 不新增补给种类、不新增敌机类型、不改 Boss 弹幕库与波次编队（`supplyHints()` 长度仍 = `PowerUpKind.values.length` = 7）。
- 不新增成就、存储键、页面、音频/图片/字体资源（共鸣与矛击复用既有 `GameSound`）。
- 不提高 `Player.maxWeaponLevel`(6)、`Player.maxBombs`(3)、`Player.maxWingmen`(3)、`Player.maxOverdrive`(2)。
- 不做极性、1UP、勋章链、Gradius 动力条（理由见 §4）。
- 不引入玩家弹对象池（沿用 v0.6 的取舍）；不改敌弹"两趟收集"绘制结构。

---

## 2. 现状审计（以 v0.6.0 真实代码为准）

| 项 | 现状 | 出处 |
| --- | --- | --- |
| 输入 | 手指相对拖动：`onPointerMove` 把位移乘 `kWorldWidth / _field.width` 交给 `movePlayerBy`；**轻点（down→up 无位移）没有任何作用**；键盘走 `setMoveAxis` 恒速 `kPlayerSpeed = 300`；唯一的 HUD 按钮是炸弹 | `game_page.dart:_onPointerDown/_onPointerMove`、`battle_controller.dart:movePlayerBy/setMoveAxis` |
| 玩家判定 | 固定 `Player.radius = 11`；敌弹用 `Player.radius + bullet.radius` 做扫掠，机体相撞与拾取共用同一半径；敌弹半径 4.2~5 | `battle_types.dart:Player`、`battle_controller.dart:_collideEnemyShots/_collideBodies/_collidePowerUps` |
| 敌弹碰撞 | `_collideEnemyShots` **单趟**遍历 `enemyBullets`，首个命中即 `_hitPlayer()` 并 `break`；`_collideGuard` 排在它之前（卫星先吃弹） | `battle_controller.dart:_collide` |
| 玩家弹 | `appendPlayerShots` 按 `weaponLevel`/`overdrive`/`route` 选表，弹速 `kPlayerBulletSpeed = 560`；`Bullet.pierce` 对普通敌机生效、**Boss 不可穿透**（`bullet.pierce > 0 && !enemy.isBoss`）；`lastHit/prevHit` 去重 | `player_weapon.dart`、`battle_controller.dart:_collidePlayerShots` |
| 弹种 | `BulletKind` 0–14，`isPlayer(kind) = kind == player \|\| kind >= twin`；`_playerShotStyles` 恰 15 项 | `battle_types.dart`、`battle_visuals.dart:_playerShotStyles` |
| 僚机 | 三位：`gale(-1)` / `heavy(+1)` / `guard(0)`；站位 `player.x + side * kWingmanOffsetX(27)`，`wingmanOffsetY(role)`；卫星 `kGuardRadius 15`、能量 12、过热 6 s | `battle_tuning.dart`、`battle_controller.dart:_updateWingmen/_collideGuard` |
| 过载/核心 | `Player.route/overdrive`，`kWeaponRoutes`（散/贯/聚），`DropLedger.coreKills`，核心 `wave >= kOverdriveFromWave(5)` | `battle_tuning.dart`、`pickup_rules.dart` |
| 受伤 | `_hitPlayer`：护盾先挡（`kShieldBreakInvuln 1.1`）；否则 `lives--`、`applyHitPenalty`（先降过载再降火力）、`invuln = kHitInvuln(2)`、清 `kHitClearRadius(100)` 内敌弹 | `battle_controller.dart:_hitPlayer`、`pickup_rules.dart:applyHitPenalty` |
| 计分 | 击破 `spec.score * multiplier * challengeModifier.scoreScale`；连击窗口 `kComboWindow = 2.6`，倍率 ×1–4 | `battle_controller.dart:_killEnemy`、`battle_tuning.dart` |
| 随机数 | 控制器 `_rng` 同时供掉落抽签与 `BattleEffects.burst/explode` 粒子抖动；`WaveDirector` 另有独立种子 | `battle_controller.dart`、`battle_effects.dart:burst` |
| HUD | 紧凑布局 `Positioned(left:10, top:76) _statusStrip`；10 Hz 且仅在 `_hudSignature` 变化时重建；Boss 血条用独立 `ValueListenable<int> bossHp` 避免重建 | `battle_hud.dart`、`battle_controller.dart:_hudSignature/_syncBossHp` |
| 文案 | 补给/连击/路线说明来自 `rules_text.dart`；**但"操作"三行是写死在 `how_to_play.dart` 里的字符串**（单一出处缺口） | `how_to_play.dart:_Section(title:'操作')` |
| 每日挑战 | `ChallengeModifier` 只有数值旋钮（弹速/血量/掉率/分数/生命/起始火力）；控制器照常跑同一套战斗循环 | `daily_challenge.dart` |

**审计结论**：

1. 每一次躲弹都是"二元"的——要么被打中，要么什么都没发生。"差一点"没有回报，所以玩家没有理由主动靠近弹幕。
2. 玩家的移动速度没有任何后果，**慢速精操是被浪费掉的输入维度**。
3. 轻点屏幕是一个完全空闲的输入通道，适合挂一个低频、高价值的动作。
4. 敌弹碰撞已经是单趟循环，擦弹可以零额外遍历地并进去。
5. `_rng` 被特效共用——新特效如果也消耗 `_rng`，会让"擦弹多的玩家"和"擦弹少的玩家"在同一击破序列下掉出不同补给，破坏"补给只由击破数/种子决定"的可预测性（§5.7 规避）。

---

## 3. 竞品启发与方案选型

> 说明：以下对各作品的描述只取**公认的核心设计骨架**，不照搬数值；"采纳/改造/拒绝"均针对本项目约束（程序化 Canvas、单指移动、自动开火、无手柄按键）。

| 参考作品 | 它做对了什么 | v0.7 的处理 |
| --- | --- | --- |
| **东方 Project（Touhou）** | 按住 Shift **集中**：减速 + **极小判定点** + 弹道收束；**擦弹**（Graze）给分、给灵力。判定点可见，玩家因此愿意贴着弹幕飞。 | **采纳为核心**。手机没有 Shift，改成"**手指移动速度低于阈值 = 凝神**"（Windows 另补 `Shift`）。判定点缩小、弹道收束、判定点可见全部保留。擦弹拆成"分 + 连击续命 + 共鸣供能"。 |
| **怒首领蜂 DoDonPachi** | **Hyper**：蓄满后**手动**开启的强化阶段，核心体验是"主动冲进弹幕、把弹幕变成分数"。 | **采纳骨架、改造实现**：共鸣 = 蓄满后**手动**触发（双击）；触发时把身边的弹幕**吞噬转分**。**拒绝**长时间的"Hyper 状态 + 全局强化"（会变成又一个数值 buff，且与过载/急速叠加失控）。 |
| **虫姬 Mushihimesama** | 慢速密集弹 + 小判定 + "近身有回报"，把风险做成**明码标价**。 | **采纳"风险标价"思路**：擦弹带 = 命中半径外再加 14 世界像素；越敢贴越快蓄满共鸣。**不照搬**其 Abnormal/Kakusei 等多层子系统。 |
| **R-Type** | **蓄力波动炮**：放弃一段时间的连发换一发穿透全屏的重击；Force 吸附/分离。 | **采纳蓄力，改造触发方式**：自动开火不能"按住蓄力"，所以改成"**静止蓄力 → 起手移动释放**"（手感类似拉弓松手）。**拒绝 Force 吸附/分离**（需要独立按键与全新实体，且与僚机/卫星职责重叠）。 |
| **沙罗曼蛇 / Gradius** | **Options（僚机）**与**编队切换**；动力条（Power meter）自选升级。 | **采纳"编队随姿态变化"**：凝神时左右僚机内收 35%（Touhou 的 familiars 同理），无需按键。**拒绝动力条选择**：那是菜单式决策，v0.6 的"核心循环切换 + 走位接取"已解决选择问题，且单手不适合暂停式选择。 |
| **雷电 Raiden** | 勋章链（Medals）+ 主武器**切换/升级**的取舍（散射 vs 激光）。 | **部分采纳**：擦弹与共鸣吞噬都会刷新连击窗口（"链不断"的追逐感）。**拒绝勋章链**：需要新增掉落物/更多拾取分支，会冲击 `DropLedger` 与前期教学。 |
| **1942** | 最小规则集 + "翻滚"保命。 | 作为**反面参照**：我们已有炸弹/护盾作为保命手段，不再加第三种无敌机制；共鸣只给 1.0 s 无敌，作为"触发动作的代价抵消"，而非保命手段。 |
| **Sky Force（天空力量）** | 手游友好：**能量条清晰可见**，大招一键触发，成长安全。 | **采纳**：共鸣条在 HUD 常驻可见，蓄满脉冲提示；触发手势零学习成本。 |
| **Phoenix 2** | 能量/超级武器的**长按/点触**触发，单指友好。 | **采纳"点触触发大招"**：双击战场 = 共鸣，与"拖动 = 移动"在手势上互不冲突。 |
| **微信飞机大战** | 极简：拖动 + 点炸弹，道具限时强化。 | **反向参照**：它的"限时强化叠加"是我们要避开的路径；我们的新系统都是**姿态与资源**，不是更多的限时 buff。 |
| **斑鸠 Ikaruga** | 极性（黑白吸收/反弹）。 | **拒绝**：我们的敌弹没有属性，做极性等于把所有敌弹重新着色并重写 Boss 弹幕，是硬塞，不是自然生长（§4）。共鸣的"吞噬"只是转分，不是极性吸收。 |

### 选型结论：四个系统，两个轴

```
              ┌──────────── 静（凝神 Focus）────────────┐
              │ 判定缩小 · 弹道收束 · 僚机内收            │
              │ 静止蓄能 → 【矛击 Charge Lance】          │
              └───────────────┬─────────────────────────┘
        起手移动 = 释放矛击      │      共鸣触发后矛击瞬间满蓄
              ┌───────────────┴─────────────────────────┐
              │ 动（擦弹 Graze）                          │
              │ 赚分 · 续连击 · 供能 → 【共鸣 Resonance】  │
              └──────────── 双击战场 = 吞噬弹幕 ───────────┘
```

| 编号 | 系统 | 灵感 | 性质 |
| --- | --- | --- | --- |
| S1 | **凝神 Focus** | Touhou Shift、Gradius options 编队 | 姿态：自动判定，改几何不改伤害 |
| S2 | **擦弹 Graze** | Touhou、DoDonPachi、虫姬 | 风险标价：分 + 续连击 + 供能 |
| S3 | **共鸣 Resonance** | DoDonPachi Hyper、Sky Force 能量条 | 主动技：蓄满后双击，吞噬转分 |
| S4 | **矛击 Charge Lance** | R-Type 波动炮 | 交替开火：静止蓄能，起手释放 |

---

## 4. 被拒绝的方向与理由

| 方向 | 结论 | 理由 |
| --- | --- | --- |
| **极性（Ikaruga）** | 拒绝 | 题材不诚实：敌机/敌弹没有颜色属性，Boss 三套弹幕（`buildBossBarrage`）都按单色设计。硬塞需要重绘全部敌弹、重写碰撞分支，且与"护盾/卫星吸收一切敌弹"语义冲突。 |
| **新敌机行为（护盾机、俯冲自爆、母舰）** | 拒绝（本版） | 会改 `wave_director.dart` 与 `enemy_*.dart`，每日挑战共用同一波次，等于间接改了挑战；且新工具（凝神/擦弹/矛击）已能在现有**堡垒环形弹**（`fortress`，慢速 radial）与 **Boss 三套弹幕**里充分发挥——它们本来就是"留缝隙的慢密弹"，正好是擦弹教学场。留作 v0.7.x 的延伸：若矛击需要"目标"，可再引入护盾机。 |
| **手动 Focus 按钮 / 第二个 HUD 按钮** | 拒绝 | 单手拖动时拇指无法离开屏幕去按另一个按钮；速度自动判定零学习成本。 |
| **全局 Hyper 状态（持续数秒的全面强化）** | 拒绝 | 会与过载路线、急速射击叠成"更大的数字"；违反"不要只抬数值"。共鸣是**瞬发**吞噬 + 1 s 无敌。 |
| **勋章链 / 连锁计分（Raiden）** | 拒绝 | 需要新拾取物，冲击 `DropLedger`、`kPowerUpWeights` 与前四波教学。只保留"擦弹/吞噬刷新连击窗口"这一个钩子。 |
| **Gradius 动力条（升级自选）** | 拒绝 | 菜单式选择，破坏单手流畅；v0.6 核心循环切换已覆盖。 |
| **R-Type Force 吸附/分离** | 拒绝 | 需要独立按键 + 新实体，与僚机/卫星重叠。 |
| **1UP / 续命（计分加命）** | 拒绝 | 计分里**没有**阈值钩子（`Player.maxLives = 5`，生命只来自开局）；为一个功能新增分数里程碑与存档语义不划算。 |
| **全新战役结构 / 改写每日挑战** | 拒绝 | 非目标。每日挑战自动继承新系统（§5.9），无需改动。 |
| **子弹时间（凝神真的让世界变慢）** | 拒绝 | 会改变所有敌弹速度，破坏 `challengeModifier.enemyBulletSpeedScale` 的语义与固定步长逻辑的可预期性。凝神只改**玩家侧**。 |

---

## 5. 新系统详细设计

### 5.0 总览：状态、解锁与单一出处

**解锁波次**（`battle_tuning.dart`，全部走同一张表，波次门槛 = 唯一开关；把某项设为 `999` 即整体关闭，便于 A/B 回退）：

```dart
const int kFocusFromWave = 3;      // 凝神 + 擦弹（轻量，只增不罚）
const int kGrazeFromWave = 3;
const int kResonanceFromWave = 5;  // 与核心同波开放，但第 4 波 Boss 已能蓄满
const int kChargeFromWave = 6;     // 矛击最晚开放
```

| 波次 | 玩家看到什么 |
| --- | --- |
| 1–2 | 与 v0.6.0 **逐帧一致**（测试保证） |
| 3–4（含第 4 波 Boss） | 凝神（判定点出现、弹道收束）+ 擦弹（分、续连击、共鸣条开始蓄）；共鸣条可见但不可释放。此窗口只有"贴近 = 有小奖励"，没有任何惩罚机制 |
| 5 | 共鸣可释放（条满时 HUD 提示"双击共鸣"）；同时核心开始掉落（v0.6 既有） |
| 6+ | 矛击开放（静止蓄能环出现） |

> 第 3 波才开始的理由：前两波仅有侦察机/战斗机，弹幕稀疏，玩家还在学拖动与炸弹；第 3 波首次出现轰炸机三连散射，是自然的"第一次擦弹"。

**新增状态**（`Player`，`battle_types.dart`；全部随 `Player` 重建而归零，`start()` 无需额外清理）：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `focus` | `double` 0..1 | 凝神强度，连续量（渲染/几何插值用） |
| `moveSpeed` | `double` | 平滑后的移动速度（世界像素/秒） |
| `slowTime` | `double` | 连续"慢速"累计时长（进入凝神的延迟判定） |
| `focused` | `bool` | 凝神开关（带滞回），`focus` 朝它逼近 |
| `charge` | `double` 0..1 | 矛击蓄能 |
| `resonance` | `double` 0..`kResonanceMax` | 共鸣条 |
| `double get hitRadius` | getter | `lerp(Player.radius, kFocusHitRadius, focus)`；**仅**敌弹与机体相撞使用，拾取仍用 `Player.radius` |

`BattleController` 新增：`int grazes`（本局擦弹总数，`start()` 清零）、`ValueListenable<int> resonanceMeter`（千分比，参照 `bossHp` 的 10 Hz 同步，HUD 条不拖着整棵 HUD 重建）。

**纯规则新文件** `lib/game/battle/stance_rules.dart`（与 `pickup_rules.dart` 同级，数值全部取自 `battle_tuning`）：

```dart
/// 推进凝神状态；返回本步是否应该释放矛击（凝神 → 起手移动的那一帧）。
bool updateStance(Player p, double dt,
    {required double moved, required bool held, required int wave});

/// 擦弹账本：令牌桶限速 + 总数统计，随局重置（同 DropLedger.clearRun 习惯）。
class GrazeLedger {
  int total = 0;
  double tokens = kGrazeBucketCapacity;
  void refill(double dt);                     // tokens += kGrazeTokensPerSec * dt，封顶
  /// 记入一次擦弹；被限速时返回 0（子弹仍被标记，不重复结算）。
  double credit(Player p, {required int wave});   // 返回增加的共鸣点数
  void clearRun();
}

bool canResonate(Player p, int wave);          // wave >= kResonanceFromWave && resonance >= kResonanceCost
```

### 5.1 S1 凝神 Focus

**一句话**：手指放慢或松开 → 战机进入凝神：判定点缩小并显形，弹道向机头收束，僚机内收，并开始为矛击蓄能。

#### 判定规则（`updateStance`）

输入：本步位移 `moved`（世界像素，控制器累计拖动位移 + 键盘位移）、`held`（Windows `Shift` 按住）、`wave`。

```
unlocked = wave >= kFocusFromWave
instant  = moved / dt
moveSpeed += (instant - moveSpeed) * min(1, dt * kMoveSpeedSmoothing)     // 指数平滑，吸收手指抖动
slow     = moveSpeed < (focused ? kFocusExitSpeed : kFocusEnterSpeed)     // 滞回：进 42，出 80
slowTime = slow ? slowTime + dt : 0
want     = unlocked && (held || slowTime >= kFocusEnterDelay)
releaseLance = unlocked && wave>=kChargeFromWave && focused && !want && charge >= 1   // 见 §5.4
focused  = want
focus   += clamp(((want ? 1 : 0) - focus), -kFocusFallRate*dt, kFocusRiseRate*dt)
```

- **滞回**：进入阈值 42 世界像素/秒（约 42 dp/s，拇指静止时的微抖在 0–10 之间），退出阈值 80；避免在阈值附近闪烁。
- **进入延迟** `kFocusEnterDelay = 0.12 s`：拖动起手/收手的一瞬间不抖动切换。
- **松开手指**：没有位移 → 速度趋 0 → 自然进入凝神。开局未解锁前 `focus` 恒 0。
- **键盘**：`Shift` 按住 = `held`；同时 `setMoveAxis` 的有效速度乘 `kFocusKeySpeedScale = 0.45`（135 世界像素/秒），与 Touhou 手感一致。

#### 效果（只改几何，不改总伤害）

| 效果 | 公式 | 落点 |
| --- | --- | --- |
| 判定半径 | `hitRadius = lerp(11, kFocusHitRadius = 6.5, focus)`；对 4.2 半径的敌弹，命中距离 15.2 → 10.7（命中面积 -51%） | `_collideEnemyShots`、`_collideBodies` 用 `player.hitRadius`；`_collidePowerUps` **不变** |
| 弹道收束 | 每颗子弹 `offsetX *= 1 - kFocusSqueezeX * focus`（0.5），`angle *= 1 - kFocusSqueezeAngle * focus`（0.6）；矛击不受影响 | `appendPlayerShots`（`player_weapon.dart`）读 `player.focus`，`focus = 0` 时与 v0.6 逐字节一致 |
| 僚机内收 | 左右僚机目标 `x = player.x + side * kWingmanOffsetX * (1 - kFocusWingmanSqueeze * focus)`（0.35 → 17.6） | `_updateWingmen`；卫星 `side == 0` 不受影响 |
| 蓄能 | 见 §5.4 | — |
| 擦弹增益减半 | 见 §5.2（凝神擦弹每次 +2，运动擦弹每次 +4） | `GrazeLedger.credit` |

**设计取舍**：

- 收束使"站定打 Boss"的有效 DPS 明显更高（针弹不再散到 Boss 两侧）——这正是 Touhou/弹幕射击的标准回报；代价是**覆盖面**（对付多机编队变差，散射路线收束后失去最大优势）。因此凝神是"选择"：对 Boss 站桩，对杂兵队形保持运动。
- **每齐射总伤害不变**：测试断言 `sum(damage)` 在 `focus = 0` 与 `focus = 1` 下相等（§9）。
- 凝神期间**仍然会被击中**，只是更难。敌弹密集的区域站定蓄矛本身就是风险。

#### 视觉

- `focus > 0.05` 时在机身中心绘制**判定点**：白色实心圆 `r = 2.4`，外圈环 `r = hitRadius + 1.5`，路线色（无路线用 `kPlayerTrim`），透明度 `= focus`。
- `focus > 0.5` 时叠一圈淡的**擦弹带**（`r = Player.radius + kGrazeBand`，笔宽 0.8，透明度 `0.18 * focus`），告诉玩家"这个圈就是擦弹范围"。
- 全部在 `_drawPlayer` 内用复用的 `_fill/_stroke` 画，**最多 3 次 `drawCircle`**。

### 5.2 S2 擦弹 Graze

**一句话**：敌弹飞过命中半径外 14 世界像素的"擦弹带"而没打中你 → 记一次擦弹：得分、刷新连击窗口、给共鸣条供能。

#### 判定

- **擦弹带**：`reach = Player.radius(11) + kGrazeBand(14) + bullet.radius` ≈ 29.2。**固定用满半径 11**，因此凝神（命中半径缩小）时带宽从 14 变成约 18.5——凝神就是为"贴着飞"准备的。
- **每颗敌弹最多擦一次**：`Bullet.grazed` 标记（新增布尔字段）。
- **并入既有单趟循环**：在 `_collideEnemyShots` 的同一次 `for (bullet in enemyBullets)` 中，**先**做原有扫掠命中判定；未命中再用已算好的 `dx, dy` 做 `dx*dx + dy*dy <= reach²` 判断。**禁止新增第二趟遍历。**
- **前置条件**（任一不满足则不结算）：
  - `wave >= kGrazeFromWave`；
  - `player.alive && player.invuln <= 0`（受伤闪烁/护盾破碎后的无敌期内不擦弹，防止"无敌刷分"）；
  - 子弹未 `dead`、未 `grazed`。
- **与卫星的关系**：`_collideGuard` 在前，被卫星吃掉的弹不会再被擦——**卫星会"偷走"正前方的擦弹**。这是有意的取舍：护卫是稳健流，不是分数流。
- **与护盾的关系**：护盾存在时擦弹照常结算（护盾不改变判定，只吸收一次命中）。

#### 回报

| 项 | 数值 | 说明 |
| --- | --- | --- |
| 分数 | `kGrazeScore = 10 × multiplier × challengeModifier.scoreScale` | 与击破同一套倍率/修正，通过新增的 `_scaled(int)` 辅助函数，避免内联公式再抄一遍 |
| 连击续命 | `comboTimer = min(kComboWindow, comboTimer + kGrazeComboExtend(0.25))`，**仅当 `combo > 0`** | 擦弹本身不涨连击数，只延长窗口 |
| 共鸣供能 | 运动（`focus < 0.5`）+`kGrazeGainMoving = 4`；凝神 +`kGrazeGainFocused = 2` | 运动擦弹收益翻倍："舞"比"坐"赚得快 |
| 共鸣条上限 | `kResonanceMax = kResonanceCost = 100` | 满条后继续擦弹只给分和续连击 |
| 限速（令牌桶） | `kGrazeTokensPerSec = 10`，容量 `kGrazeBucketCapacity = 4` | 一圈 40 发环弹同时扫过时，最多当场结算 4 次，之后每秒 10 次；被限速的弹**仍被标记 `grazed`**，不会晚些再补记 |
| 视觉 | 命中点一粒 `grazeSpark`（见 §5.7，不消耗 `_rng`），**不弹飘字**（太密） | — |
| 统计 | `controller.grazes++`，只统计实际结算的次数（被限速丢弃的不计），与分数一致 | HUD 宽屏面板显示累计 |

**校准目标**（`stance_rules_test` 用解析式而非仿真）：运动状态 25 次结算 = 满条；令牌桶下理论最快 2.5 s 满条，真实游戏预计第 3–5 波累计约 40–60 点，第 5–6 波首次满条。

**反作弊自检**：

| 手法 | 为什么不成立 |
| --- | --- |
| 站在堡垒下"吃"环形弹 | 命中半径缩小只有 -51% 面积，且环形弹间隙固定；凝神擦弹只有运动的一半供能；撞到仍扣命 |
| 受伤无敌期刷擦弹 | `invuln > 0` 不结算 |
| 敌弹生成在擦弹带内即擦 | 出生在带内意味着敌机贴脸，必伴随机体相撞扣命；不特殊处理，列入风险 |
| 炸弹清屏刷擦弹 | `useBomb` 直接 `clear()`，不走碰撞 |

### 5.3 S3 共鸣 Resonance

**一句话**：共鸣条满（100）且已到第 5 波 → **双击战场**：以战机为中心 170 世界像素半径内的敌弹被"吞噬"转分，获得 1.0 s 无敌，卫星复位，矛击瞬间满蓄。

#### 触发

- **手势**：双击战场（`Listener` 内识别，不与拖动冲突）。判定参数（`battle_tuning.dart`）：单次轻点 `kTapMaxDuration = 0.18 s`、位移 `kTapMaxTravel = 14 dp`；两次轻点间隔 `kDoubleTapWindow = 0.32 s`；仅追踪第一个指针。判定逻辑抽成纯类 `DoubleTapDetector`（新文件 `lib/game/battle/double_tap.dart`，吃 `Duration` 时间戳与位置，可单测）。
- **键盘**：`R`。
- **前置**：`phase == playing`、`player.alive`、`canResonate(player, wave)`。不满足则静默忽略（不浪费条、不惩罚）。
- **代价自平衡**：双击需要抬手，抬手期间战机静止（正好进入凝神，判定小）+ 1.0 s 无敌，足以覆盖手势本身的空窗。

#### 效果（`BattleController.useResonance()`）

1. `player.resonance = 0`。
2. **吞噬**：遍历 `enemyBullets`，`dist² <= kResonanceRadius²`（170）的全部 `dead = true`；按遍历顺序前 `kResonanceMaxConvert = 60` 发各计分 `kResonanceBulletScore(20) × multiplier × scoreScale`，其余只清除不计分（防止清场后留下"漏网弹"，但封顶刷分）。理论上限：60 × 20 × 4 = 4800，低于单个 Boss 击破（2000 × 4 = 8000）。
3. `player.invuln = max(player.invuln, kResonanceInvuln = 1.0)`（小于 `kShieldBreakInvuln 1.1`，不会盖过护盾破碎）。**不伤敌、不给护盾。**
4. **卫星复位**：对 `role == guard` 的僚机 `energy = kGuardMaxEnergy`、`overheat = 0`。
5. **矛击满蓄**：若 `wave >= kChargeFromWave`，`player.charge = 1`。
6. **连击续命**：`combo > 0` 时 `comboTimer = kComboWindow`。
7. 反馈：`flash = max(flash, 0.2)`、`shake = max(shake, 10)`、`_emit(BattleEvent.resonance)`、吞噬火花（最多 12 粒，朝战机方向汇聚）、一个 `ParticleKind.ring` 扩散环、飘字 `共鸣 吞噬 ×n  +score`。

#### 与既有系统的交互

| 系统 | 交互 |
| --- | --- |
| **炸弹** | 互补不重叠：炸弹 = 全屏清弹 + 全屏伤害、有限库存；共鸣 = 局部吞噬 + 零伤害、无限但需用擦弹赚。炸弹清掉的弹不产生擦弹/共鸣点。可连续使用，互不影响。 |
| **护盾** | 共鸣不叠加护盾；护盾在时照常使用，无冲突。护盾破碎无敌 1.1 s 内 `invuln > 0`，共鸣只会把 `invuln` 抬到 `max(...)`，不缩短。 |
| **护卫卫星** | 共鸣 = 卫星的"强制冷却"：过热中的卫星立即复位。这让"卫星过热 → 擦弹蓄条 → 共鸣复位"成为稳健流的闭环。 |
| **过载路线** | 共鸣本身不区分路线；但它把矛击充满，而**矛击按路线分化**（§5.4），因此路线选择会改变"共鸣之后"的打法。受伤降过载的规则不变。 |
| **进化核心 / DropLedger** | 无交互：共鸣不产生掉落、不动 `coreKills`；吞噬的弹不算击破。矛击击杀走既有 `_killEnemy → rollKill`，视同普通击破。 |

### 5.4 S4 矛击 Charge Lance

**一句话**：凝神期间静止蓄能 1.5 s；当你从静止**起手移动**的那一刻，战机向前射出一道穿透所有普通敌机的光矛。

> 与 R-Type 的区别：这里**主炮永不停火**，矛击是叠加在自动开火上的"清线工具"，不是替代；单发伤害刻意很低（对 Boss 只有 14），目的是"一条线上串杀一队杂兵 / 在弹幕里割一条路"，不是新的 DPS 来源。

#### 状态机

```
解锁：wave >= kChargeFromWave(6)
蓄能：focus >= 0.95 时  charge += dt / kChargeSeconds(1.5)，封顶 1
保持：charge >= 1 后无限期保持（不衰减，凝神期间可随时选择释放时机）
衰减：未满且不在凝神时  charge -= dt * kChargeDecayPerSec(1.2)，下限 0
释放：focused 从 true → false（起手移动）且 charge >= 1  →  appendChargeLance；charge = 0
```

- "什么时候放"成为玩家的决策：**用慢速拖动对准一条线**（慢拖仍属凝神），确认后一个快速甩动即释放。
- 满蓄后就算被打、被无敌、被暂停，都**不会丢**；半蓄时抖动手指只衰减 0.83 s 当量，不会瞬间清零。
- 共鸣会把 `charge` 直接置 1：双击（手指离屏 → 静止 → 凝神）之后，第一次起手移动就会放出矛击。

#### 矛击规格（`battle_tuning.dart`，`player_weapon.dart` 按路线展开）

```dart
class ChargeSpec {
  const ChargeSpec({required this.angles, required this.damage,
      required this.radius, this.cutsBullets = false});
  final List<double> angles;   // 每道光矛的发射角（弧度）
  final double damage, radius;
  final bool cutsBullets;
}
const kChargeLanceSpeed = 760.0;   // 世界像素/秒，大于 kPlayerBulletSpeed
const kChargePierce = 99;          // 普通敌机全穿透；Boss 沿用既有规则（吃一发后弹体消失）
const kChargeSpecDefault = ChargeSpec(angles: [0], damage: 14, radius: 7);
const kChargeSpecs = {
  WeaponRoute.fan:    ChargeSpec(angles: [-0.15, 0, 0.15], damage: 9, radius: 5.5),
  WeaponRoute.pierce: ChargeSpec(angles: [0], damage: 14, radius: 6, cutsBullets: true),
  WeaponRoute.focus:  ChargeSpec(angles: [0], damage: 26, radius: 8),
};
```

| 路线 | 矛击形态 | 取舍 |
| --- | --- | --- |
| 无路线（<5 阶或未过载） | 单道，伤害 14 | 标准清线 |
| **散射** | 三道扇形光矛，各 9 | 覆盖宽，适合横排编队；单目标伤害低 |
| **贯穿** | 单道，14，**切割敌弹**：光矛飞行路径上的敌弹被消除（无分、无擦弹） | 在密集弹幕中**割出一条安全通道**；不吃分 |
| **聚能** | 单道，26，更粗 | 对精英/堡垒/Boss 单点爆发（Boss 26 ≈ 其血量 10% 以内，仍非主 DPS） |

> 数值参考：精英机 `hp 52 × waveDifficulty`，堡垒 84，杂兵 3–26。默认矛击对一排 4 架侦察机（各 3 hp）一次清空；对堡垒只打掉约 1/6。

**切割实现**：`Bullet` 新增 `bool cuts`；`_collidePlayerShots` 中，对 `bullet.cuts` 的矛击额外扫一遍 `enemyBullets`（矛击同屏通常 ≤1 发、存活 <1 s，开销可忽略；**不要对每颗玩家弹都做**）。被切割的弹 `dead = true` + `grazeSpark`，不计分、不计擦弹。

**Boss 规则**：沿用既有 `bullet.pierce > 0 && !enemy.isBoss`——矛击打到 Boss 即消失，仅造成 `damage`。**不要为矛击破例让它多段命中 Boss。**

#### 视觉

- 弹体：新增 `BulletKind.chargeLance = 15`，`_playerShotStyles` 扩到 16 项，样式为暖白金（辉光 `0xFFFFE9A8`，弹体 `0xFFFFFBEA`，长 `bodyHalf ≈ 22`，`tailDots: 3`，`glowAlpha: 0.375`），走既有 `_dots/_segments/_segmentsTop` 批绘制。
- 蓄能环：`_drawPlayer` 内一次 `drawArc(r = 19, sweep = charge * 2π, 笔宽 1.6)`，路线色；满蓄时整圈 + 8 Hz 脉冲 + 两侧各一粒亮点；仅 `charge > 0.02` 时绘制。

### 5.5 四系统联动一览（咬合关系）

| 触发 | 结果 |
| --- | --- |
| 擦弹（运动） | 分数、续连击、共鸣 +4 |
| 擦弹（凝神） | 分数、续连击、共鸣 +2 |
| 凝神 ≥ 0.95 | 矛击蓄能 |
| 共鸣释放 | 吞噬转分、1 s 无敌、卫星复位、矛击满蓄 |
| 起手移动且矛击已满 | 释放矛击（路线分化） |
| 受伤（掉命） | 共鸣 -20、过载 -1（v0.6）；其余保留 |

典型一轮节奏（Boss 战）：运动擦弹蓄满共鸣 → 逼近 Boss 弹幕最密处双击 → 吞噬一圈弹、卫星复位 → 手指已离屏，战机凝神站定，对准 Boss 慢拖微调 → 甩动，矛击射出（聚能路线 26 伤害）→ 再次进入运动。**每一步都有"现在做还是等一等"的选择**，且没有一个步骤只是"数字变大"。

### 5.6 玩家弹几何的单一出处

- `player_weapon.dart` 增加：
  - `appendPlayerShots` 读取 `player.focus` 做收束（§5.1）。
  - `void appendChargeLance(Player player, List<Bullet> out)`：按 `kChargeSpecs[player.overdrive > 0 ? player.route : null] ?? kChargeSpecDefault` 展开；子弹 `kind: BulletKind.chargeLance, pierce: kChargePierce, cuts: spec.cutsBullets, fromPlayer: true`，速度 `kChargeLanceSpeed`，枪口 `player.y - 16`。
- 现有 `kMaxPierce = 2` 测试针对 `kPlayerWeaponPatterns/kOverdrivePatterns`，**矛击不属于这两张表，不触发该护栏**；测试里对矛击另设"穿透 = `kChargePierce`"断言。

### 5.7 特效与随机数（不污染掉落序列）

- `BattleEffects` 新增 **不消耗 `_rng`** 的方法：`grazeSpark(Offset, int color)`（固定 2 粒，方向取自内部递增计数器 `_fx`，如 `angle = _fx++ * 2.399963`）、`absorbBurst(Offset center, Offset from)`（吞噬火花）。
- 目的：**擦弹/共鸣的多少不能改变击破后的补给结果**（补给仍只由击破序列 + `_rng` 位置决定）。测试：固定种子，同一击破脚本，开启/关闭擦弹火花 → 掉落类型序列一致（§9）。
- 粒子仍走既有回收池与 `maxParticles` 上限，不新增分配路径。

### 5.8 引入节奏与教学提示

- 每个系统首次解锁的那一波开场，在既有"第 N 波"飘字下方追加一条一次性提示（`ScorePopup`，y = 0.42 × 战场高，青色），文案来自 `rules_text.dart` 的 `systemHintForWave(int wave) → String?`：
  - 第 3 波：`凝神：放慢移动，判定缩小；贴近弹幕有擦弹加分`
  - 第 5 波：`共鸣条蓄满后双击屏幕：吞噬身边弹幕`
  - 第 6 波：`静止蓄力，起手移动释放矛击`
- 提示只在 `wave == 解锁波` 且为本局首次时触发（控制器内 `int _hintedWave`，`start()` 重置）。

### 5.9 每日挑战

- `daily_challenge.dart` **零 diff**。五个修正全部自然兼容：
  - `barrage`（敌弹 +16% 速度）→ 更多擦弹机会，也更难吞噬后的收尾；`scoreScale` 通过 `_scaled()` 同样作用于擦弹/吞噬分；
  - `ace`（单机突入，2 命）→ 受伤保护规则同样适用；
  - `arsenal`（起始火力 3）→ 凝神/擦弹不受火力等级影响；
  - `armor` / `scarcity` → 矛击清线更有价值 / 卫星复位更有价值。
- 挑战种子只驱动 `WaveDirector`；新系统不使用 `_rng` 做判定，**同一天的战场编队不变**。

---

## 6. 受伤与进度保护

`applyHitPenalty(Player)`（`pickup_rules.dart`，既有单一出处）扩展为：

```
1. 过载 > 0：overdrive -= kWeaponLossPerHit；归零则清路线      （v0.6，不变）
   否则：weaponLevel -= kWeaponLossPerHit（下限 1）            （v0.6，不变）
2. 共鸣条 -= kHitResonanceLoss（20），下限 0                    （v0.7 新增，不清零）
3. 其余（矛击蓄能、擦弹统计、令牌桶、僚机、卫星状态）全部保留
```

| 事件 | 共鸣条 | 矛击蓄能 | 过载 | 说明 |
| --- | --- | --- | --- | --- |
| 护盾吸收一次 | 不变 | 不变 | 不变 | `_hitPlayer` 的护盾分支早于 `applyHitPenalty`，不改 |
| 掉命 | -20（≈5 次运动擦弹） | **保留** | -1（v0.6） | 受伤后 `invuln = 2 s` 期间不擦弹，因此共鸣条会"静止" 2 s，之后继续累积 |
| 无敌期内被撞 | 不变 | 不变 | 不变 | `_hitPlayer` 开头已早返回 |
| 游戏结束 | 重开归零 | 重开归零 | 重开归零 | 新建 `Player` |

设计理由：

- 为什么**不清零共鸣条**：DoDonPachi 类 Hyper 被打掉就整条作废，对手游玩家过于苛刻，也会让"攒着不敢用"成为最优策略。扣 20 是"痛但可恢复"。
- 为什么**保留矛击蓄能**：矛击蓄能需要静止 1.5 s，掉命后立即作废等于"双重惩罚"；而且蓄满的矛击本来就是掉命后用来割弹幕脱困的好工具（特别是贯穿路线）。
- 为什么共鸣条与过载**同时**扣：它们是两个独立资源（成长 vs 操作），各扣一点比一个全清更均衡；共鸣扣得很轻（20/100）。
- 已有的 `kHitClearRadius = 100` 清弹保持不变。

---

## 7. HUD / rules_text / README

### 7.1 HUD（320 dp 宽不溢出）

- `hud_stats.dart` 新增纯函数（HUD 与测试共用，保持"数值只在一处格式化"）：

```dart
class HudMeter {
  const HudMeter({required this.visible, required this.ratio,
      required this.ready, required this.label});
  final bool visible, ready;
  final double ratio;      // 0..1
  final String label;      // '共鸣' / '共鸣就绪 · 双击'
}
HudMeter resonanceMeterFor(int permille, int wave);
```

  - `visible = wave >= kGrazeFromWave`（第 3 波起显示条，但第 5 波前不显示"就绪"文案）。
  - `ready = wave >= kResonanceFromWave && permille >= 1000`。
- `battle_hud.dart`：
  - 紧凑布局：把 `Positioned(left: 10, top: 76, child: _statusStrip())` 改为同一个 `Positioned` 里的 `Column(crossAxisAlignment: start, [ _statusStrip(), SizedBox(height: 6), _resonanceMeter() ])`。条宽 `88`、高 `6`，圆角 3，底色 `0x33FFFFFF`，填充色用青绿渐变；就绪时填充变琥珀并 1.2 Hz 脉冲，右侧小字 `双击`（`fontSize 11`）。**总宽仍 ≤ 现有 `_statusStrip` 最大宽度**（5 项满状态），320 dp 测试覆盖。
  - 宽屏布局：`_statusPanel` 底部追加一行 `共鸣` + 同一个条 + 数字 `擦弹 N`（`controller.grazes`）。
  - 条由 `ValueListenableBuilder<int>(valueListenable: controller.resonanceMeter, ...)` 驱动，**不进入 `_hudSignature`**，沿用 Boss 血条的 10 Hz 独立通知模式，擦弹期间不引起整棵 HUD 重建。
  - 条整体 `IgnorePointer`，不吞触摸（仍可拖动）。
- 矛击蓄能与凝神**不上 HUD**——它们在战机身上可见（环与判定点），避免 HUD 再多一个要读的东西。

### 7.2 `rules_text.dart`（单一出处）

- 新增 `List<String> controlHints()`：把 `how_to_play.dart` 里写死的三行"操作"文案迁入，并追加：
  - `拖动屏幕任意位置移动战机，自动连续开火。`
  - `放慢或停下手指进入凝神：判定点缩小、弹道收束。`
  - `共鸣条蓄满后双击屏幕释放共鸣。`
  - `点击右下角炸弹按钮，清空敌弹并重创全场敌机。`
  - `Windows：方向键 / WASD 移动，Shift 凝神，空格或 B 放炸弹，R 共鸣，Esc 暂停。`
- 新增 `List<String> stanceHints()`（"凝神与擦弹"章节）：
  - `凝神：第 $kFocusFromWave 波起，手指放慢或松开自动进入；判定点缩小至 ${kFocusHitRadius}，弹道与僚机向机身收束。`
  - `擦弹：敌弹从判定外 $kGrazeBand 像素内掠过且未命中，得分并延长连击；运动中擦弹比凝神中更快蓄满共鸣条。`
  - `共鸣：第 $kResonanceFromWave 波起，条满后双击屏幕，吞噬身边弹幕转为分数，1 秒无敌并修复卫星。`
  - `矛击：第 $kChargeFromWave 波起，凝神静止 ${kChargeSeconds} 秒蓄满，起手移动时射出穿透光矛；散射三束、贯穿可切割敌弹、聚能单点更重。`
- `routeHints()` 末尾补一行：`受伤会扣除 $kHitResonanceLoss 点共鸣，矛击蓄能保留。`
- 新增 `String? systemHintForWave(int wave)`（§5.8）。
- `supplyHints()` **不变**（7 条）。所有数字均插值取自 `battle_tuning`，沿用现有"数值只有一处出处"约定。
- `how_to_play.dart`：「操作」章节改用 `controlHints()`；新增 `_Section(icon: Icons.center_focus_strong_rounded, title: '凝神与擦弹', lines: stanceHints())`，放在「进化路线」之后、「连击」之前。

### 7.3 README 与版本

- `pubspec.yaml`：`version: 0.7.0`；`lib/utils/constants.dart`：`AppConstants.version = '0.7.0'`。
- README：下载链接、tag 示例改为 `v0.7.0`，tag 信息 `"v0.7.0: 凝神、擦弹、共鸣与矛击"`；版本表新增 `| v0.7.0 | 内容版本：凝神、擦弹、共鸣、矛击 |`；文档链接追加"玩法迭代设计见 [v0.7 玩法迭代设计](docs/gameplay-iteration.md)"；玩法/操作说明补充双击与 Shift/R。
- 测试数量描述以实现后 `flutter test` 实际数量为准（预计 ≥ 365，基线 325）。

---

## 8. 文件级实现清单与顺序

### 8.1 文件清单

| 文件 | 变更 |
| --- | --- |
| `lib/game/battle/battle_tuning.dart` | 新增 §5 全部常量：解锁波次、`kFocus*`、`kMoveSpeedSmoothing`、`kGraze*`、`kResonance*`、`kHitResonanceLoss`、`kCharge*`、`ChargeSpec/kChargeSpecs/kChargeSpecDefault`、`kTapMaxDuration/kTapMaxTravel/kDoubleTapWindow`、`kFocusWingmanSqueeze`。**新增集中在一个 `// ---- 姿态与共鸣` 分区。** |
| `lib/game/battle/battle_types.dart` | `Player`：`focus/moveSpeed/slowTime/focused/charge/resonance` 与 `hitRadius`；`Bullet`：`bool grazed`、`bool cuts`（构造参数 `this.cuts = false`）；`BulletKind.chargeLance = 15`；`BattleEvent` 末尾追加 `lance, resonance`（不得插队，位掩码依赖 index） |
| `lib/game/battle/stance_rules.dart`（新） | `updateStance`、`GrazeLedger`、`canResonate`；纯函数，不依赖 Flame |
| `lib/game/battle/double_tap.dart`（新） | `DoubleTapDetector`：`bool onUp({required Duration downAt, required Duration upAt, required Offset downPos, required Offset upPos})`，内部持有上次轻点时间；参数取自 `battle_tuning` |
| `lib/game/battle/player_weapon.dart` | `appendPlayerShots` 加收束；新增 `appendChargeLance`；`PlayerShot` 不变 |
| `lib/game/battle/pickup_rules.dart` | `applyHitPenalty` 增加共鸣扣减（§6）；其余不动（`DropLedger` 零改动） |
| `lib/game/battle/battle_effects.dart` | `grazeSpark`、`absorbBurst`（不消耗 `_rng`，§5.7） |
| `lib/game/battle/battle_controller.dart` | 字段：`grazes`、`_graze: GrazeLedger`、`_moveAccum`、`_focusHeld`、`_hintedWave`、`resonanceMeter`（`ValueNotifier`，`dispose` 释放，`_syncBossHp` 旁同步）；`movePlayerBy` 累计位移；`setMoveAxis`+键盘位移累计、`setFocusHeld(bool)`；`_updatePlayer` 接入 `updateStance`/矛击释放/开火；`_updateWingmen` 内收；`_collideEnemyShots` 用 `hitRadius` 并并入擦弹；`_collideBodies` 用 `hitRadius`；`_collidePlayerShots` 加切割；`useResonance()`；`_scaled(int)`；`_updateWaves` 开场提示；`start()` 清 `grazes/_graze/_moveAccum/_hintedWave`；`_hitPlayer` 不再另写扣减（经 `applyHitPenalty`） |
| `lib/game/battle/rules_text.dart` | `controlHints`、`stanceHints`、`systemHintForWave`、`routeHints` 末行 |
| `lib/game/battle/battle_keys.dart` | `isFocusKey`（`ShiftLeft/ShiftRight`）、`isResonanceKey`（`R`）；`kBattleHandledKeys` 加入这三个键 |
| `lib/pages/game_page.dart` | `_onPointerDown/_onPointerUp` 接入 `DoubleTapDetector`，仅第一个指针；`_onKey` 调用 `setFocusHeld`、`useResonance`；`onPointerUp` 现有清 `_dragLast` 保持 |
| `lib/flame/battle_visuals.dart` | `_playerShotStyles` 扩到 16 项（索引 15 = 矛击）；其余不动 |
| `lib/flame/battle_field_component.dart` | `_drawPlayer`：判定点、擦弹带、蓄能环；`_soundOf` 映射 `lance → GameSound.shoot`、`resonance → GameSound.powerUp`（复用，**不新增音频**）；先读 `_drawParticles` 的 `ring` 分支确认可复用 |
| `lib/pages/widgets/hud_stats.dart` | `HudMeter`、`resonanceMeterFor` |
| `lib/pages/widgets/battle_hud.dart` | 紧凑/宽屏的共鸣条；`ValueListenableBuilder`；就绪脉冲 |
| `lib/pages/widgets/how_to_play.dart` | 操作章节改用 `controlHints()`；新增「凝神与擦弹」章节 |
| `lib/utils/constants.dart`、`pubspec.yaml`、`README.md` | 版本 0.7.0 与文档链接（§7.3） |
| `lib/game/challenge/daily_challenge.dart` | **零改动**（验收见 §9.5） |

### 8.2 建议顺序（每步可独立 `flutter analyze && flutter test`）

1. **常量与类型**：`battle_tuning.dart`、`battle_types.dart`（含 `Bullet.grazed/cuts`、`BulletKind.chargeLance`、`BattleEvent`）。同步修 `_playerShotStyles` 长度，使既有测试仍绿。
2. **纯规则**：`stance_rules.dart`、`double_tap.dart`、`applyHitPenalty`、`appendPlayerShots` 收束、`appendChargeLance`；配套单测。
3. **控制器接线**：`_updatePlayer`/`_collide*`/`useResonance`/`_hitPlayer`；输入 API（`setFocusHeld`、`movePlayerBy` 累计）。
4. **特效**：`battle_effects.dart` 两个不用 `_rng` 的方法。
5. **渲染**：`battle_visuals.dart`、`battle_field_component.dart`。
6. **输入页面**：`battle_keys.dart`、`game_page.dart`。
7. **HUD 与文案**：`hud_stats.dart`、`battle_hud.dart`、`rules_text.dart`、`how_to_play.dart`。
8. **版本与文档**：`pubspec.yaml`、`constants.dart`、`README.md`；实现完成后在本文末尾补「实现偏差」与「审查结论」两节（同 v0.6 惯例）。

---

## 9. 测试计划与验收

### 9.1 需要更新的既有测试

| 测试 | 原因 | 修改 |
| --- | --- | --- |
| `battle_render_batch_test.dart` | 弹种增至 16 种 | 循环 `kind < 16`；预算在现有基础上最多 +3 次 draw call（判定点/擦弹带/蓄能环），用实测值收紧 |
| `battle_keys_test.dart` | 处理键集合变化 | 补 `ShiftLeft/ShiftRight/R` 断言 |
| `home_page_test.dart` | 玩法说明弹窗更长 | 滚动后再点关闭 |
| `rules_text_test.dart` | 新增文案函数 | 补断言；`supplyHints` 长度仍 = 7 |
| `pickup_rules_test.dart` | `applyHitPenalty` 扩展 | 现有断言不变，新增共鸣扣减用例 |
| `battle_hud_test.dart` | 新条 | 320 dp 满状态不溢出 + 条可见/就绪 |

`player_weapon_test`（`focus = 0` 时与 v0.6 完全一致）、`daily_challenge_test`、`wave_director_test`、`battle_visuals_test` 不应需要修改。

### 9.2 新增测试

**凝神**（`stance_rules_test.dart`）
- 解锁门槛：`wave < 3` 时 `focus` 恒 0；`held = true` 也不触发。
- 滞回：速度在 42~80 之间时保持当前状态；进入需持续 `kFocusEnterDelay`；从快到慢与从慢到快各一次。
- 松开手指（`moved = 0`）→ 约 0.12 s 后 `focused = true`，`focus` 在 `1/kFocusRiseRate` 内升到 1。
- `hitRadius` 端点值：`focus = 0 → 11`，`focus = 1 → 6.5`；拾取仍用 11。
- **每齐射总伤害**：对 `kPlayerWeaponPatterns[1..6]` 与 `kOverdrivePatterns`，`focus = 0` 与 `focus = 1` 的 `sum(damage)` 相等；`focus = 1` 时所有 `|offsetX|`、`|angle|` 严格不大于 `focus = 0`。
- 僚机内收：`focus = 1` 时 `|wing.x - player.x|` 收敛到 `27 × 0.65`，卫星不受影响。

**擦弹**（`battle_controller_test.dart` 新 group）
- 一发敌弹位于擦弹带内、命中半径外 → 恰好结算一次，`grazes == 1`，`bullet.grazed == true`；下一帧不重复。
- `invuln > 0`、`wave < 3`、`player.alive == false` 均不结算。
- 命中优先：敌弹命中仍走 `_hitPlayer`，且同一发弹不先被擦。
- 运动 +4、凝神（`focus >= 0.5`）+2；满条封顶 100。
- 限速：一次放置 20 发环形弹在带内 → 当帧结算 ≤ 4；之后 1 s 内最多 +10；被限速的弹被标记、不补记。
- 分数 = `10 × multiplier × scoreScale`（用 `ChallengeModifier.barrage` 构造的控制器验证 ×1.1）。
- 连击续命：`combo = 5, comboTimer = 1` 擦弹后增加 0.25 且不超过 `kComboWindow`；`combo = 0` 时不变。
- 卫星"偷弹"：卫星在前时，同一发弹被吸收而不擦弹。
- `useBomb` 清弹不增加 `grazes`/共鸣条。

**共鸣**
- 门槛：`wave < 5` 或 `resonance < 100` 调用 `useResonance()` 无任何效果（条不变、无无敌）。
- 满条触发：条归零；半径 170 内敌弹全部消失，半径外保留；前 60 发计分、其余只清除；总分 = `n × 20 × multiplier × scoreScale`。
- `invuln = max(invuln, 1.0)`；已有 2 s 无敌时不缩短；护盾值不变；不伤敌（敌机血量不变）。
- 卫星复位：过热中的卫星 `overheat == 0 && energy == kGuardMaxEnergy`。
- 矛击满蓄：`wave >= 6` 时 `charge == 1`；`wave 5` 时不变。
- 与炸弹互不干扰：先炸后共鸣、先共鸣后炸，状态一致。
- 连击窗口被刷新。

**矛击**
- `wave < 6` 不蓄能；`focus >= 0.95` 才蓄能，1.5 s 满蓄。
- 满蓄后保持不衰减；未满且移动时按 1.2/s 衰减，下限 0。
- 释放：仅在 `focused` 由真到假的那一步、且 `charge >= 1` 时 `updateStance` 返回 `true` 并清零；控制器随之追加矛击弹。
- 规格：四条路线的光矛数量/角度/伤害/半径与表一致；`pierce == kChargePierce`；`kind == chargeLance`。
- 穿透：一列 4 架侦察机被一发默认矛击全部击破；Boss 只吃一发（弹体消失）。
- 切割（贯穿）：光矛路径上的敌弹被清除且不计分/不擦弹；非贯穿路线不切割。
- 受伤不丢蓄能（见 §9.3）。

**输入**
- `DoubleTapDetector`：两次合规轻点（<0.18 s、位移 <14 dp、间隔 <0.32 s）→ 触发；超时/位移过大/间隔过长 → 不触发；触发后需重新两击；第二指针被忽略。
- `game_page_test`：模拟双击，条满时触发共鸣；拖动过程不触发。
- 键盘：Shift 按住进入凝神且移动速度 ×0.45；松开恢复；`R` 触发共鸣。

### 9.3 受伤与进度保护

- 掉命：`resonance` 减 20、下限 0；`charge`、`grazes`、令牌桶、僚机与卫星状态不变；`overdrive` 仍按 v0.6 先降。
- 护盾吸收：`resonance`/`charge` 完全不变。
- 无敌期内被撞：无任何变化。
- `lives == 0` 的 `_gameOver` 正常。

### 9.4 与 v0.6 共存

- 过载三路线 × 两阶：`appendPlayerShots` 在 `focus = 0` 时与 v0.6 表逐项一致（弹数/伤害/角度/穿透）；路线 DPS 护栏测试不变且通过。
- `DropLedger` 全部既有测试不变；`kPowerUpWeights` 合计 100 且仍是原六种。
- `applyPickup(core)` 链、Boss 七级链、`coreKills` 行为不变。
- **随机性隔离**：固定种子与固定击破脚本，分别在"零擦弹"与"大量擦弹+共鸣"下运行，掉落类型序列一致（证明新特效不消耗 `_rng`）。
- **前四波教学窗**：固定种子跑完第 1–2 波，状态与 v0.6.0 快照一致（`focus == 0`、`resonance == 0`、玩家弹几何不变）；第 3–4 波 `charge` 恒 0、共鸣不可释放；`powerUps` 中无新类型。
- 卫星/护盾/炸弹既有测试（`battle_controller_test` 的 v0.6 分组）全部保持原样通过。

### 9.5 渲染、HUD 与回归

- 渲染预算：同屏 16 种玩家弹 + 150 敌弹 + 三僚机 + 凝神 + 蓄能环，draw call 不超过 §9.1 实测上限；`circleCalls` 不因新增判定点翻倍增长。
- HUD：`resonanceMeterFor` 边界（0 / 999 / 1000 / wave 2 / wave 4 / wave 5）；320 dp 满状态（5 项 + 条）无溢出；条不吞触摸（`IgnorePointer`）。
- 文案：`stanceHints/controlHints` 中的数字与 `battle_tuning` 常量一致（测试里插值比较，不硬写）。
- **零改动验收**：`git diff --stat main -- lib/game/challenge/daily_challenge.dart lib/game/battle/wave_director.dart lib/game/battle/enemy_weapons.dart lib/game/battle/boss_catalog.dart lib/game/battle/enemy_motion.dart lib/game/battle/bullet_field.dart` 输出为空。
- 版本一致：`pubspec.yaml`、`AppConstants.version`、README 下载链接/tag 示例/版本表均为 0.7.0。

### 9.6 验收标准（人工 + 自动）

1. `flutter analyze` 无问题；`flutter test` 全绿，预计 ≥ 365 项（基线 325）。
2. 第 1–2 波与 v0.6.0 逐帧行为一致；第 3 波首次出现轰炸机散射时玩家能自发擦弹并看到共鸣条增长。
3. 单手：全程只用一根手指能完成"拖动 → 停手凝神 → 双击共鸣 → 甩动释放矛击"；不需要碰炸弹之外的任何按钮。
4. 人工验证凝神手感：不拖动时判定点出现，拖动加速时判定点平滑消失，阈值附近无闪烁。
5. 人工验证 Boss 战：站定凝神明显提升对 Boss 的输出但也明显更危险；共鸣吞噬后战机不会立刻中弹（1 s 无敌）。
6. 设备验收（保留项）：320 dp 手机与 120 Hz 设备上的帧时间与 v0.6.0 对照（性能回退 ≤ 10%），无法在自动测试中确认，按 v0.6 惯例保留为设备验收。

---

## 10. 风险与不做事项

### 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| **自动凝神误触**：玩家本想慢速闪避却被判定为凝神（收束火力） | 凝神只改几何且判定点更小，对生存是正收益；阈值常量集中在 `battle_tuning`，可调；滞回 + 进入延迟 + 指数平滑 |
| **凝神 + Boss = 站桩过强** | 收束提高对 Boss 的有效输出是 Touhou 标准回报；对杂兵队形则相反；`kFocusSqueezeX/Angle` 为旋钮；总伤害不变由测试守住；如实测过强，先下调收束，不动判定 |
| **擦弹被刷**（贴脸、站在堡垒下） | 令牌桶限速、`invuln` 内不结算、凝神供能减半；爆发上限由共鸣吞噬封顶 60 发 |
| **双击误触**（抬手重握） | 有 0.18 s/14 dp 的合规轻点约束 + 0.32 s 窗口 + 仅在条满且第 5 波后生效；触发有 1 s 无敌兜底 |
| **共鸣"不够强"/"太强"** | 无伤害，只转分 + 复位卫星 + 充矛；分数上限 4800/次 < Boss 击破；`kResonanceRadius/Cost/MaxConvert` 皆为旋钮 |
| **矛击蓄能要静止，弹幕下根本蓄不满** | 这是有意的风险回报；共鸣可直接充满；最晚第 6 波才开放，且杂兵波内有静止窗口 |
| **新增判定在敌弹循环里拖慢 120 Hz** | 并入既有单趟循环，只多一次 dist² 比较；矛击切割仅对 ≤1 发矛击做额外扫描；渲染预算测试守护 |
| **`Bullet` 多两个布尔字段内存增加** | 可忽略（敌弹同屏 ≤ ~300 发）；不引入弹池，保持 v0.6 取舍 |
| **HUD 在 320 dp 溢出** | 条宽固定 88 dp，纳入 `battle_hud_test` 320 dp 满状态用例 |
| **新手看不懂** | 解锁波一次性提示（§5.8）+ 玩法说明弹窗新章节；判定点/擦弹带/蓄能环在战机上可见 |
| **双击与 Web/桌面鼠标行为不同** | 用 `Listener` 的 pointer 事件统一处理，鼠标左键等价单指；`R` 键作为兜底 |

### 明确不做（本版）

- 新补给种类、新敌机（护盾机/俯冲自爆/母舰）、极性、1UP、勋章链、Gradius 动力条、Force、子弹时间。
- 成就与存档字段（"累计擦弹 N 次""共鸣吞噬 N 发"可作为 v0.7.1 成就，需改 `storage_service` 与成就页，另议）。
- 结算页显示擦弹/共鸣统计（`controller.grazes` 已提供数据，UI 另议）。
- 擦弹音效（过密）；矛击/共鸣只复用现有音效。
- 任何对 `daily_challenge.dart` 的修改。

---

## 实现偏差

（实现完成后补记。）

## 验证与审查结果

（实现完成后补记：`flutter analyze`、`flutter test` 项数、零改动文件 diff、版本一致性、审查结论。）
