# v0.8 设计师打磨通：让已有的系统被读懂、被信任、值得冒险

> 状态：设计稿（待实现）。分支 `feat/designer-pass`，基线 v0.7.0（`18c3739`，`flutter test` 409 项）。
> 发布位置：用户自己的 fork（`qpzm7903/flutter-plane`），不向上游提 PR。
> 版本号：实现完成后 bump 到 `0.8.0`（`pubspec.yaml` 的 `version:`、`lib/utils/constants.dart` 的 `AppConstants.version`、README 下载链接 / tag 示例 / 版本表，见 §9）。**不要改 CI 签名与密钥。**
> 表述约定：「世界像素」指 `kWorldWidth = 400` 的战场坐标；「手算」指本文用 `player_weapon.dart` / `battle_tuning.dart` 的真实常量推算、**没有跑仿真**的数字，实现时必须由 §11 的测试复核，不得当作已验证事实。
> 对玩家的承诺：v0.8 是**打磨通**——深化并澄清凝神 / 擦弹 / 共鸣 / 矛击 / 进化核心 / 护卫卫星这六样**已有**东西，不是再平行堆四个新系统。本文最多引入 **1 个**新的玩家可见想法（§6），且已用 §3 的诊断证明调参与协同填不了那个洞。

---

## 1. 设计师诊断：用玩家的话说，v0.7 哪里错、哪里不清

以下每一条都对应真实代码，不是印象。

| # | 玩家会这么说 | 真实原因 |
| --- | --- | --- |
| 1 | 「我就是停下来看了一眼，火力怎么突然缩成一条线了？」 | `stance_rules.dart:updateStance`：低于 `kFocusEnterSpeed = 42` 持续 `kFocusEnterDelay = 0.12 s` 就进凝神，`focus` 以 `kFocusRiseRate = 6` 上升（约 0.17 s 满），而弹道收束 `appendPlayerShots` 直接乘 `focus`。从「停一下」到「火力形状变了」不到 0.3 s，且**没有任何过渡提示**。 |
| 2 | 「我明明在动，火力还是缩着。」 | 退出阈值 `kFocusExitSpeed = 80`（滞回带 42–80 太宽）：以 60 世界像素/秒的速度慢拖，仍被判为凝神。Boss 巡航平均约 54、峰值约 85 世界像素/秒（`enemy_motion.dart:hoverBoss`，振幅 118、角频率 0.72），**慢速跟随 Boss 全程不会离开凝神**。 |
| 3 | 「打 Boss 站着不动又稳又强，为什么还要动？」 | 凝神 = 判定半径 11→6.5（命中面积 -51%）+ 弹道收束 + 免费蓄矛 + 僚机内收。唯一的代价是擦弹收益减半，而 Boss 战只有几秒（见 §3.2）。**风险更低、回报还更高**——违反风险回报。 |
| 4 | 「擦弹到底在奖励我什么？我看不见那个圈。」 | 擦弹带只在 `focus > 0.5` 时才画（`battle_field_component.dart:_drawPlayer`）。而奖励**最高**的是「运动中擦弹」（共鸣 +4、凝神 +2），也就是说最该被看见的状态恰恰没有圈。 |
| 5 | 「我双击想放共鸣，结果一屏幕空气就把条花掉了。」 | `useResonance()` 只要条满就清零、吃掉全部收益，**没有最小收益保护**；`DoubleTapDetector.onUp` 只检查每一次轻点自己的时长与位移，**不检查两次轻点之间的距离**，重新握机时的两次落指也可能凑成双击。 |
| 6 | 「矛击我从来蓄不满。」 | 要 `focus ≥ 0.95` 连续 1.5 s（`kChargeSeconds`），而冲刺闪避时按 `kChargeDecayPerSec = 1.2` 扣蓄能——一次 0.3 s 的冲刺扣掉约 0.36，相当于白蓄 0.54 s。弹幕里「停」与「闪」交替，净蓄能趋近于 0。 |
| 7 | 「蓄满了，然后呢？它会打到哪？」 | 矛击没有任何瞄准提示；释放音效与普通射击是同一个（`battle_field_component.dart:_soundOf`：`lance → GameSound.shoot`），共鸣复用拾取音 `powerUp`。**最有仪式感的两个动作，在听觉上与日常无差别。** |
| 8 | 「共鸣就绪我没注意到，等我看 HUD 已经过了。」 | 就绪信号只在左上小条（`_ResonanceBar`，宽 88 dp）；战机身上没有任何就绪信号。弹幕里没人看角落。 |
| 9 | 「共鸣为什么卫星又亮了？」 | 共鸣复位卫星（`wing.energy = kGuardMaxEnergy; overheat = 0`）是静默发生的，飘字只写「共鸣 吞噬 ×n」。**一次有价值的协同没有被说出来。** |
| 10 | 「冒险和保守赚的一样多。」 | 擦弹分 `kGrazeScore = 10` 与续命 `kGrazeComboExtend = 0.25` 不区分姿态；只有共鸣供能区分（4 / 2）。同一个「运动 vs 凝神」决策，三条产出只有一条响应。 |

**一句话诊断**：v0.7 的机制本身是对的（滞回、令牌桶、单趟碰撞、护进度的受伤规则都不要动），错在三处——
1. **凝神对「无意识的慢」与「有意识的静」一视同仁**，且代价（火力形状改变）没有被预告；
2. **「静」在单目标（Boss）上同时是最安全和最强的选择**，「动」的回报只有分数与一条几乎不影响 Boss 战的资源；
3. **所有关键状态（擦弹窗、就绪、蓄满、会打哪、卫星被修好）在密集弹幕里读不出来**。

---

## 2. 透镜下的目标与非目标

### 2.1 七个透镜如何裁剪 v0.7

| 透镜 | 对已有系统的判决 |
| --- | --- |
| **有趣的决策**（Sid Meier） | 凝神 vs 运动、静蓄 vs 擦弹蓄、何时放共鸣、何时放矛——这些是真决策，**保留**；目前塌缩的是「Boss 前站着」这条（§3.2）。装饰性内容：无，不用砍；只合并「同一决策三个产出」（§5.1）。 |
| **自教学**（宫本茂） | 看得见才学得会：擦弹带常显、就绪环上身、矛击瞄准线、两个专属音、一次性飘字讲「为什么」。 |
| **风险回报**（Cave / 东方） | 更险的必须更赚：站桩不再比跟打强（§3.2），冒险共鸣的矛击更重（§6）。 |
| **协同胜过数量**（Blow / 井内） | 不新增系统；让六样东西互相「说话」（§5.2 的协同矩阵），唯一的新想法是一条乘数线。 |
| **MDA / 精通**（LeBlanc / Koster） | 计分钩子拉熟练玩法（§5.1）；短局「再来一局」靠「这把我差一点放出 ×3 矛」这类可复述的瞬间。 |
| **节奏呼吸** | 不改 `wave_director.dart` 与间隔常量；呼吸靠反馈：共鸣无敌 1 s 的闪光、波间空隙天然是静蓄窗口（§4.5）。 |
| **信息设计** | 战机本体就是 HUD：一圈带、一道环、一条线，三个信号都在手指附近，不依赖角落小条。 |

### 2.2 目标

1. 兑现四个手感风险（§3），每个有根因、对策、测试。
2. 让 §1 的 10 条诊断中「看不懂」的条目（4、7、8、9）全部变成「看得懂」。
3. 风险回报收紧（§5.1），并给出**至多一个**记忆点（§6）。
4. 零新补给、零新敌机、零新按键、零新存储键、零新音频**文件**（新增的两个音由 `tone_synth` 在代码里合成）。

### 2.3 非目标（明确不做）

- 不抬 `Player.maxWeaponLevel(6)`、`maxBombs(3)`、`maxWingmen(3)`、`maxOverdrive(2)`。
- 不改 `daily_challenge.dart`（零 diff）、`wave_director.dart`、`enemy_weapons.dart`、`boss_catalog.dart`、`enemy_motion.dart`、`bullet_field.dart`、`kPowerUpWeights`、`DropLedger` 逻辑。
- 不改 Boss 弹幕以消除「缺口正对玩家」（§3.2 解释为何不动）。
- 不新增 `BulletKind`、不新增 `PowerUpKind`；`supplyHints()` 长度仍为 7。
- 不回退 v0.5–v0.7 的任何解锁波（凝神 / 擦弹 3、共鸣 5、矛击 6）。
- 不做「只抬数值」：本文改动的数值要么是**消除不对称**（凝神进慢出快），要么是**让两条路径的回报分叉**，每个都要在 §3 / §5 里说明它修的是哪条决策。

---

## 3. 四个手感风险：根因与对策

### 3.1 风险 1：凝神阈值误触（慢闪突然收束火力）

**根因（真实常量）**

| 常量 | 现值 | 问题 |
| --- | --- | --- |
| `kFocusEnterSpeed` / `kFocusEnterDelay` | 42 / 0.12 s | 进入本身合理：手指停住就是想稳。 |
| `kFocusExitSpeed` | **80** | 滞回带 42–80 太宽，慢拖（尤其跟 Boss）也留在凝神。玩家以为自己在「动」。 |
| `kFocusRiseRate` / `kFocusFallRate` | 6 / 9 | 同一个 `focus` 同时驱动**判定半径**（救命）和**火力收束**（改形状）。判定变小是纯收益，应该快；火力改形状是有代价的，应该慢且可预告。 |
| 收束入口 | `appendPlayerShots`、`_updateWingmen` 直接读 `player.focus` | 与上一行同源，无法分别调。 |

**对策（四条，全部为不对称调整，不是抬数值）**

1. **拆开「判定」与「火力形状」**：`Player` 新增一个字段 `squeeze`（0–1）。`focus` 继续驱动 `hitRadius`、蓄矛、擦弹带、判定点；**`squeeze` 只驱动弹道收束与僚机内收**。
   - 上升：`kSqueezeRiseRate = 2.5`（0.4 s 满），键盘 `Shift` 按住时用 `kSqueezeRiseHeld = 8`（主动意图立即生效）。
   - 下降：`kSqueezeFallRate = 12`（约 0.08 s 满回扩散）。
   - 目标：`focused ? 1 : 0`。
   - 效果：0.3 s 的短停只会收束到约 0.45，0.5 s 才满；一动起来立刻展开。「慢闪」几乎不会改变火力形状，「真的站定」仍然得到完整收束。
2. **缩窄滞回带**：`kFocusExitSpeed 80 → 60`。慢拖超过 60 即回到运动。进入阈值 42 不动。
3. **预告**：在 `squeeze` 过渡期（0.05–0.95）于机头两侧画两根 6 世界像素的短竖线，位置 `x = ±16 * (1 - 0.4 * squeeze)`，透明度 `0.5 * sin(π * squeeze)`——**只在变形的瞬间闪**，告诉玩家「你的火力形状正在变」。走既有 `_segments` 批（§4.6 预算）。
4. **刷新教学文案**（§9）：凝神的描述改成「判定变小；停稳约 0.4 秒后火力才收束」。

**不做**：不把进入阈值调高（会让「想稳」更难）；不引入「确认手势」。

**验收**：`stance_rules_test`：短停（0.3 s）后 `squeeze < 0.6`；60 世界像素/秒匀速慢拖不再保持 `focused`；`Shift` 按住 0.15 s 内 `squeeze ≥ 0.9`。

### 3.2 风险 2：Boss 站桩凝神 / 蓄矛过强

**先量化（手算，D = 玩家到 Boss 的纵向距离）**

世界高度取 1:2 屏的 800 左右，玩家出生高度 `h - 84 ≈ 716`，Boss 悬停 `kBossHoverY = 92`，故常见 D ≈ 450–620。Boss 半径 38，加弹半径 3，命中带宽约 ±41。取 6 级弹道（`_kLevel6Shots`）：

| 状态（D = 620，Boss 正对） | 命中弹 | 每齐射伤害 |
| --- | --- | --- |
| 运动（`focus = 0`） | 新星 2 + 两侧长矛各 1（`offsetX ±9`）；针弹内侧 `14 + tan(0.13)*620 ≈ 95` **脱靶** | **4** |
| v0.7 凝神（`sx = 0.5, sa = 0.6`） | 同上 + 内侧针弹 `7 + tan(0.052)*620 ≈ 39` **命中**（左右各 1） | **6（+50%）** |
| 偏移 60 的 Boss | 运动 1；凝神 2 | 凝神 ×2 |

D = 450、540 时同样是 +50%（手算）。也就是：**站定对单目标是 +50%，而且慢拖跟随也享有**。再叠加：
- 判定面积 -51%；
- Boss 的若干弹幕**把缺口放在玩家脚下**：利维坦弹幕墙 `gap = round((target.dx - 22) / 44.5)`（`enemy_weapons.dart`），幽影方舟环形弹 `_angleGap(...) > 0.42` 的缺口正对玩家——站着不动正好待在缺口里；
- 站着免费蓄矛。

→ 站桩**更安全且更强**，运动的回报（擦弹分 / 共鸣条）在几秒的 Boss 战里几乎兑现不了：6 级火力 `playerFireInterval = 0.15 - 0.008*5 = 0.11 s`（约 9 齐射/秒），运动对正的 Boss 约 36 DPS，第 4 波 Boss 血量 `180 * 1.19 ≈ 214`，**约 6 秒打完，才 3 轮弹幕**；擦弹满一条共鸣要 25 次，一场 Boss 战里基本攒不满。

**对策（不动 Boss 弹幕、不动波次，只动玩家一侧）**

1. **收束只管「精度」，不再管「额外伤害」**：`kFocusSqueezeX 0.5 → 0.4`，`kFocusSqueezeAngle 0.6 → 0.4`。手算：收束后内侧针弹 `14*0.6 + tan(0.13*0.6)*620 ≈ 57 > 41`，对正 Boss 时凝神与运动**同为 4**（D = 450 时 `43.6`，同样脱靶；落在刀口上，所以验收用一组 D 取均值，而不是单点）。凝神仍然在**偏移**时更准（偏移 60：运动 1，凝神仍 ≥ 1），对小目标队形仍有收益——只是不再白送 Boss 额外 DPS。
2. **慢拖跟随不再算凝神**：§3.1 的 `kFocusExitSpeed 80 → 60` 同时修这条（Boss 平均巡航 54、峰值 85，跟随时会周期性离开凝神）。
3. **回报分叉由「冒险一侧」承担**：站桩得到的是**安全与普通矛击**；贴着弹幕飞得到的是**更多擦弹 → 共鸣 → 更重的矛**（§6）。站在缺口里不会擦弹，也就攒不出共鸣——这正是该有的代价，不需要改 Boss 弹幕。
4. **蓄矛的收益边界**：矛击不能穿透 Boss（沿用 `bullet.pierce > 0 && !enemy.isBoss`），单发 14–26 点，对 Boss 本来就只是调味；§6 的乘数才让「值得冒险去放」成立。

**为什么不改 Boss 弹幕**：`enemy_weapons.dart` / `boss_catalog.dart` 在本通是保护文件；缺口放哪属于**挑战曲线**，间接改变难度，违反「不改波次 / 敌种」。玩家一侧的回报分叉已经足以让站桩不再支配。

**验收**：`player_weapon_test` 新增「对正 Boss 的每齐射伤害」守护：对 D ∈ {450, 540, 620}、偏移 ∈ {0, ±30}，用真实 `buildPlayerShots` + 命中带宽 41 计算，**凝神 / 运动的平均比值 ≤ 1.25**；6 级与三条过载路线、两阶都要过。

### 3.3 风险 3：双击共鸣误触

**根因**

- `DoubleTapDetector.onUp` 只存 `_last`（时间），**不比较两次轻点的位置**。
- 共鸣无保护：`useResonance()` 在条满后无条件清零，即使 170 半径内没有一颗敌弹（一次空放浪费 100 点 ≈ 25 次运动擦弹）。
- 第一次轻点无任何反馈，玩家不知道自己「已经点了一下」。

**对策（三层，层层兜底，不加按键）**

1. **空间约束**：新增 `kDoubleTapMaxGap = 56`（dp，两次轻点落点距离）；检测器记录上一次轻点的 `upPos`，第二次 `downPos` 与之距离 ≥ 56 视为新的第一击。
2. **空放保护**：`kResonanceMinConvert = 4`。`useResonance()` 先数半径内敌弹，**少于 4 颗：不扣条、不无敌、不充矛、不复位卫星**，只飘一条 `无弹可吞`（≤ 1 次 / 0.8 s，复用 `ScorePopup`）。这同时是风险回报的一部分——共鸣是「危险里才兑现」的东西。
3. **第一击回应**：检测器由返回 `bool` 改为返回 `TapResult { none, first, double }`；条满时 `first` 触发控制器 `armResonance()`，战机上的就绪环闪一下（0.32 s，与 `kDoubleTapWindow` 对齐）。误触的人会学到「点一下已经被看见」，有意的人得到确认。

**不做**：不加专用共鸣按钮（右下角已有炸弹按钮，单手拇指区拥挤；§7）；不加冷却（共鸣本来就要靠擦弹赚）。

**验收**：`stance_rules_test` 双击组：落点间距 ≥ 56 不触发；`first` 在条未满时不触发 `armResonance`；`useResonance()` 在 3 颗弹时返回无变化（`resonance` 保持 100、`invuln` 不变、`charge` 不变），4 颗弹时正常。

### 3.4 风险 4：弹幕下蓄矛太难（共鸣可充满——保留，但要读得懂）

**诊断**：矛击的两条来路本来就是两种玩法，只是玩家不知道——

| 来路 | 适合 | 代价 |
| --- | --- | --- |
| **静蓄**（凝神 1.5 s） | 波间空隙、杂兵清场后的空档（`kBetweenWaveGap = 2.6 s` 本来就够蓄满） | 弹幕里蓄不成 |
| **共鸣充满**（`useResonance` 置 `charge = 1`） | 弹幕正密的时候 | 要先靠擦弹攒满 100 点，且空放无效（§3.3） |

**保留共鸣充满**，对策是把它**说清楚**并让两条路回报分叉（§6），而不是把静蓄调成弹幕里也能蓄。仅做两个不对称调整：

1. `kChargeDecayPerSec 1.2 → 0.6`：与蓄能速率 `1 / 1.5 ≈ 0.667` 基本对称。一次 0.3 s 冲刺只扣 0.18，不再把半蓄清零；但**不追求弹幕里能蓄**（弹幕里净蓄能仍 ≈ 0，由共鸣负责）。
2. **读得懂**（§4）：蓄能环 + 满蓄瞄准线 + 专属音 + 释放飘字。玩家要知道「我现在有矛、它会打哪、是我自己蓄的还是共鸣给的」。

**验收**：`stance_rules_test`：静蓄 1.5 s 仍满；冲刺 0.3 s 后 `charge` 保留 ≥ 0.8 × 原值（原值 0.6）；半蓄在运动 1.0 s 后下降 ≈ 0.6。

---

## 4. 可读性 / juice / 教学通

> 原则：**战机本体就是 HUD**。三个状态——擦弹窗、共鸣就绪、矛击蓄满——都在机身周围用既有的圆 / 弧 / 线表达；密集弹幕里玩家本来就盯着机身。

### 4.1 战机周围的信号（一圈带、一道环、一条线）

| 信号 | 现状 | v0.8 |
| --- | --- | --- |
| **擦弹带**（半径 `Player.radius + kGrazeBand = 25`） | 仅 `focus > 0.5` 画，alpha 0.18 | 第 3 波起**常显**（`kGrazeFromWave`），基础 alpha 0.10；擦弹结算时脉冲 `grazePulse`（控制器计时器，结算 → 1，按 4/秒衰减），alpha `+0.25 * grazePulse`；凝神再 `+0.18 * focus`。**仍是同一次 `drawCircle`**。 |
| **共鸣就绪** | 仅 HUD 小条 | 条满且 `wave ≥ kResonanceFromWave` 时，同一圈带改为琥珀色 `appAmber`（与 HUD 条就绪色一致）并呼吸（`0.25 + 0.15 * sin(elapsed * 6)`）；`armResonance()` 的 0.32 s 内提亮到 0.6。 |
| **矛击蓄能** | 环 `r = 19`（`charge` 扫角），满蓄脉冲 + 两侧亮点 | 不变；**加**：满蓄且在凝神时画**瞄准线**（§4.2）。 |
| **火力收束过渡** | 无 | 两根短竖线（§3.1），只在 `squeeze ∈ (0.05, 0.95)` 出现。 |

### 4.2 矛击瞄准线（做中学：会打哪）

- `player_weapon.dart` 新增 `ChargeSpec chargeSpecFor(Player p)`（把 `appendChargeLance` 里现有的 `kChargeSpecs[...] ?? kChargeSpecDefault` 取值抽出来，**单一出处**）。
- `charge ≥ 1` 且 `focus > 0.5` 时，对 `spec.angles` 的每个角画一条从机头向上的线，长度 140 世界像素，宽 1（`× (1 + 0.25 * (chargePower - 1))`），颜色取路线色，alpha `0.35 * pulse`。散射三条、贯穿 / 聚能 / 默认一条。
- 走 `_segments`，**同色同宽共用一个批桶**；不额外 `drawLine`。

### 4.3 声音与触感（只改代码合成，不增文件）

- `GameSound` 新增 `lance`、`resonance` 两项；`SoundService.presets` 各补一条 `SynthNote` 配方：
  - `lance`：1100 → 2600 Hz 上扫，0.18 s，亮音色，音量略大于 `shoot`（0.55 → 0.8），**一眼能与连射区分**；
  - `resonance`：90 Hz 低频鼓起 + 440 → 880 Hz 上行，0.32 s。
- `battle_field_component.dart:_soundOf` 改为 `lance → GameSound.lance`、`resonance → GameSound.resonance`。触感：`lance` 轻、`resonance` 中（`SoundService` 现有 `HapticFeedback` 映射表补两行）。
- `sound_service_test` 已按 `GameSound.values` 遍历，新增项会被自动覆盖；同时断言**两个新音与 `shoot`、`powerUp` 的合成字节不同**。

### 4.4 一次性飘字：讲「为什么」

- 共鸣：`共鸣 吞噬 ×n  +score`（保持）；若至少有一颗卫星被修复（`overheat > 0` 或 `energy < kGuardMaxEnergy`），**追加**一行 `卫星复位`（y 再 -14，青色）。
- 矛击释放：`chargePower > 1.05` 时飘 `矛击 ×2.4`（§6），否则不飘。
- 空放：`无弹可吞`（§3.3）。
- 解锁提示（`systemHintForWave`）改写（§9）：把「为什么」写进去。

### 4.5 节奏呼吸（靠反馈，不改波次表）

- **波间静蓄窗口**：`kBetweenWaveGap = 2.6 s` 本来就能蓄满矛（1.5 s）；v0.8 靠蓄能环 + 瞄准线 + 第 6 波提示让玩家**看见**「空档就是蓄矛的时间」。不改任何间隔常量。
- **共鸣后的 1 s 无敌**（`kResonanceInvuln`）：已有 `flash 0.2`、`shake 10`、吞噬环；再加专属音（§4.3）与重矛提示，作为一次「强拍」。
- **受伤后的缓冲**：`kHitInvuln = 2 s`、清 100 半径弹——不动。

### 4.6 渲染预算（v0.7 实测基线：十六弹种 + 150 敌弹 + 三僚机 + 满蓄凝神 = 43 次批提交、6 圆、2 弧）

| 新增 | 预算 |
| --- | --- |
| 擦弹带常显 | 0（与原来同一 `drawCircle`，只是条件放宽） |
| 收束过渡短竖线 | 并入 `_segments`，同色同宽 → +0~1 批 |
| 瞄准线 | 并入 `_segments`，同色同宽 → +0~1 批 |
| 重矛放大 | 矛击弹的辉光 / 弹体宽度按 `power` **量化为 3 档**（≤1.5、≤2.5、>2.5），最多 +2 个批桶 |

合计 `battle_render_test` 的批提交上限由 45 放宽为 **≤ 49**，圆 / 弧数不增加。不新增每帧分配；`grazePulse` / `resonanceArm` 是控制器两个 `double`。

### 4.7 卫星过热与过载路线的可读性

- 卫星已有能量弧、`energy < 4` 变色、过热变灰（`battle_field_component.dart` 约 255–275 行）——**不动**，但共鸣后「卫星复位」的飘字（§4.4）把因果说清。
- 过载路线：机身与蓄能环已用路线色。本通补一条文案：**路线决定共鸣之后的那一矛长什么样**（§5.2），写进 `routeHints()`。

---

## 5. 系统协同与风险回报收紧

### 5.1 既有计分钩子：同一个决策，三个产出一起响应

现状（`stance_rules.dart:GrazeLedger.credit`、`battle_controller.dart:_collideEnemyShots`）：运动 / 凝神只在共鸣供能上区分，分数 `kGrazeScore = 10` 与续命 `kGrazeComboExtend = 0.25` 是硬编码在控制器里的常量。改为**一个奖励表**，出处单一：

```dart
// battle_tuning.dart
class GrazeReward {
  const GrazeReward({required this.resonance, required this.score, required this.comboExtend});
  final double resonance, comboExtend;
  final int score;
}
const kGrazeRewardMoving  = GrazeReward(resonance: 4, score: 10, comboExtend: 0.25);
const kGrazeRewardFocused = GrazeReward(resonance: 2, score: 6,  comboExtend: 0.15);
GrazeReward grazeRewardFor(double focus) => focus < 0.5 ? kGrazeRewardMoving : kGrazeRewardFocused;
```

- `GrazeLedger.credit` 返回 `GrazeReward?`（`null` = 未结算：未解锁 / 无敌期 / 令牌桶空），控制器据此 `score += _scaled(reward.score)`、`comboTimer += reward.comboExtend`；删除 `kGrazeGainMoving` / `kGrazeGainFocused` / `kGrazeScore` / `kGrazeComboExtend` 的散落引用（常量由表替代，`rules_text` 同步，§9）。
- 含义：**运动擦弹 = 10 分、+4 共鸣、+0.25 s 连击**；**凝神擦弹 = 6 分、+2 共鸣、+0.15 s 连击**。贴近弹幕的人三项全面领先——冒险被明码标价。
- `challengeModifier.scoreScale` 仍通过 `_scaled()` 作用；`daily_challenge.dart` 零改动。
- 其他计分钩子**不变**：击破分、连击倍率、`kResonanceBulletScore = 20`（前 60 发）、`kBombCapScore` 等。

### 5.2 协同矩阵（六样东西如何互相说话）

| 来源 → 去向 | 已有？ | v0.8 如何被**看见 / 被说清** |
| --- | --- | --- |
| 擦弹 → 共鸣条 | 已有（4 / 2） | 擦弹带常显 + 脉冲（§4.1）；条满 → 战机上的琥珀环。 |
| 擦弹 → 连击窗口 | 已有 | 随奖励表分档（§5.1）。 |
| 共鸣 → 吞噬转分 | 已有 | 不变。 |
| 共鸣 → 卫星复位 | 已有，**静默** | 飘字 `卫星复位`（§4.4）。 |
| 共鸣 → 矛击满蓄 | 已有 | 瞄准线 + 专属音（§4.2、§4.3）。 |
| **共鸣吞噬数 → 矛击重量** | **新（唯一想法）** | §6。 |
| 凝神 → 矛击静蓄 | 已有 | 蓄能环 + 衰减放缓（§3.4）。 |
| 凝神 → 火力收束 | 已有 | 过渡期预告（§3.1）、对 Boss 不再白送 DPS（§3.2）。 |
| 路线（散 / 贯 / 聚）→ 矛击形态 | 已有 | 共鸣后的那一矛：**散射 = 清场、贯穿 = 割路、聚能 = 斩 Boss**，写进 `routeHints()`。 |
| 卫星 → 擦弹 | 已有，**负协同**（卫星偷走正前方的弹，不涨共鸣） | 文案明说「卫星稳，但吃掉的弹不涨共鸣」（§9）。这是**有意的取舍**：稳健流 vs 分数流。 |

### 5.3 风险回报账（修完之后的站位）

| 选择 | 风险 | 回报 |
| --- | --- | --- |
| 站定凝神 | 低（判定 -51%） | 安全、静蓄矛（普通 ×1）、对偏移目标更准；擦弹分 / 共鸣减半 |
| 慢拖跟随 | 中 | 超过 60 即回运动，不再享受凝神；对 Boss DPS = 站定（§3.2） |
| 贴弹幕运动 | 高 | 每次擦弹 10 分 / +4 共鸣 / +0.25 s 连击；条满后冲进弹幕双击 → 吞噬 + 满蓄 + **重矛（§6）** |

---

## 6. 本通被记住的一件事（唯一 1 个）：吞噬越多，那一矛越重

### 6.1 为什么必须新增（诊断证明调参 / 协同填不了）

洞是：**风险回报分叉在「放矛」这个动作上没有路径**。
- 调参能做的：把站桩的优势磨平（§3.2 已做）。但磨平只能让两条路「一样」，**不能让冒险那条路「更赚」**。
- 协同能做的：共鸣已经 `charge = 1`，擦弹已经供能共鸣。但两条来路（静蓄 / 共鸣）放出的矛**完全一样**，所以玩家没有理由冒险去蓄——静蓄免费，共鸣昂贵，却得到同一发矛。
- 计分钩子能做的：§5.1 已把运动擦弹拉到 10 分，但在 Boss 战里这点分不能改变战局（§3.2 的 6 秒）。

所以需要**一条把「吞了多少弹」（风险的量）连接到「矛有多重」（回报的量）的线**——一个乘数，不是一个系统。没有新实体、新按键、新资源条、新命名。

### 6.2 规则

- `Player` 新增 `chargePower`（默认 1，范围 `[1, kLancePowerMax]`）。
- `useResonance()` 吞噬 `converted` 颗弹后（`wave ≥ kChargeFromWave` 时）：
  `chargePower = 1 + min(converted, kLancePowerCapBullets) * kLancePowerPerBullet`。
- `appendChargeLance(...)`：伤害 `spec.damage * chargePower`，弹半径 `spec.radius * (1 + kLanceRadiusGrowth * (chargePower - 1))`（碰撞半径随之增大，辉光按 3 档放大，§4.6）。释放后 `chargePower = 1`。
- **挨打熄灭**：`_hitPlayer()` 中真正掉命的分支（护盾挡住的不算）把 `chargePower = 1`——余烬在手里，被打就灭；**不影响 `charge` 本身**（v0.7 的「受伤不毁进度」保留）。
- 静蓄满蓄的矛 `chargePower = 1`；在已满蓄时再共鸣，同样升到对应倍率（**先在静处蓄好，再冲进弹幕放共鸣** = 一个技巧动作）。

| 常量 | 值 | 说明 |
| --- | --- | --- |
| `kLancePowerPerBullet` | 0.05 | 每吞一颗 +5% |
| `kLancePowerCapBullets` | 40 | 吞 40 颗封顶 |
| `kLancePowerMax` | 3.0 | = `1 + 40 * 0.05`，守护测试断言一致 |
| `kLanceRadiusGrowth` | 0.2 | 满倍率半径 ×1.4 |

**手算**（`kChargeSpecs`）：吞 30 颗 → ×2.5。默认矛 14 → 35；聚能 26 → 65（第 8 波 Boss 血量 `180 * 1.55 * 1.15 ≈ 321`，约 20%）；散射三束各 9 → 22.5；贯穿 14 → 35 且仍可切割敌弹。上限 ×3 时聚能 78（约 24%）。这是**一次性爆发**，不是新 DPS 来源：每个共鸣周期最多一发（需要 25 次运动擦弹 + 一次冲入弹幕）。

### 6.3 为什么它不是「厨房水槽」

- 不新增玩家要记的名词：飘字是 `矛击 ×2.4`，不命名为任何「某某矛」。
- 不新增输入 / 资源条 / 补给 / 敌种 / 存储键；`Bullet` 不新增字段（`damage`、`radius` 已存在）。
- 它只是把共鸣「吞噬数」这个**已有的数字**接到矛击「伤害」这个**已有的数字**上。

### 6.4 它如何兑现六个透镜

- **有趣的决策**：何时放共鸣——等弹幕最密再放，倍率最高，但更危险；等条满就放，安全但矛轻。
- **风险回报**：冒险（贴弹幕攒条 + 在密集处放共鸣）→ 更重的矛；站桩 → 普通矛。
- **协同**：擦弹 → 共鸣 → 吞噬数 → 矛重 → 路线形态（散 / 贯 / 聚）→ 卫星复位，一条链。
- **自教学**：释放时飘字 `矛击 ×2.4`，瞄准线随倍率变粗，弹体也变粗。
- **精通**：可复述的瞬间：「这把我吞了 38 颗，聚能矛砍掉半条 Boss 血」。
- **不破坏难度**：只在第 6 波起（矛击解锁）生效；第 5 波共鸣不涉及。

---

## 7. 考虑过但拒绝的方向

| 方向 | 拒绝理由 |
| --- | --- |
| **极性 / 吸收反弹**（Ikaruga） | 要把所有敌弹分属性并重写 Boss 弹幕，是硬塞的新系统；共鸣的「吞噬转分」已够用。 |
| **新敌种**（护盾机 / 俯冲自爆 / 母舰） | 改变挑战曲线；本通不动 `EnemyKind`、`wave_director`。 |
| **新武器 / 第四条过载路线** | 平行加系统，违背「深化已有」的承诺。 |
| **1UP / 分数加命 / 勋章链** | 动 `DropLedger` 与生命经济，且与受伤保护规则冲突。 |
| **子弹时间 / 全局慢动作** | 改变弹幕可读的基础节奏，Boss 战会变形；也会让「凝神」的价值被稀释。 |
| **击停（hit-stop）** | 想过在共鸣瞬间停 60 ms，但与固定步长测试和 `early_wave_snapshot_test` 的逐帧校验冲突，收益只是手感增色，已有闪屏 / 震屏 / 新音效替代。 |
| **专用共鸣按钮** | 右下角炸弹按钮已占拇指区；§3.3 的三层兜底足够。 |
| **共鸣冷却** | 共鸣本来要靠擦弹赚，加冷却是惩罚新手。 |
| **「凝神疲劳」类机制**（站久了发热 / 降火力） | 为治站桩再造一个子系统；§3.2 的玩家侧分叉已解决。 |
| **擦弹直接转 Boss 伤害** | 与 §6 的乘数重复，而且第二条收益通道会失控。 |
| **把静蓄调到弹幕里也能蓄满** | 会抹掉「静蓄 vs 共鸣充满」的分工，也让矛击变成常驻攻击。 |
| **自动释放 / 手动确认矛击** | 前者拿走「什么时候放」的决策，后者要新增输入。保持「起手移动即放」。 |
| **改 Boss 弹幕去掉脚下缺口** | 间接改难度，且是保护文件；用玩家侧回报分叉替代。 |
| **全局提高矛击伤害** | 「只抬数值」；风险回报要靠分叉而不是整体加。 |
| **常驻凝神 HUD 控件** | 战机本体已能表达（§4.1），角落 HUD 在弹幕里读不到。 |
| **结算页新增统计** | 需要新界面与可能的存储键，另议（v0.8.1 候选）。 |

---

## 8. 与过载 / 卫星 / 炸弹 / 护盾 / 每日挑战的交互

| 系统 | 交互（v0.8） |
| --- | --- |
| **过载 / 路线** | 矛击形态沿用 `kChargeSpecs` 按 `player.overdrive > 0 ? player.route : null` 取值；`chargePower` 是**乘数**，对每条路线都成立：散射 = 三束清场、贯穿 = 割路（`cuts` 不变）、聚能 = 单点斩击。受伤降过载的规则（`applyHitPenalty`）不变；`chargePower` 因掉命归 1（§6.2）。核心拾取不影响 `chargePower`。 |
| **护卫卫星** | 共鸣复位保持；复位被**说出来**（§4.4）。卫星「偷」正前方的弹仍然成立（不涨共鸣，也不进吞噬数，因为已 `dead`）；文案明说。空放保护（§3.3）也意味着不能靠空放来修卫星。 |
| **炸弹** | 炸弹清空敌弹时**不产生擦弹**也**不触发吞噬**；不重置 `chargePower`（炸弹是保命，不是惩罚）。炸弹 + 共鸣仍可连用，但炸弹清弹后共鸣会因弹数不足被拦（保护）。 |
| **护盾** | 护盾挡住的一击**不熄灭** `chargePower`、不扣共鸣（沿用 v0.7 `_hitPlayer`）；护盾破碎期间 `invuln > 0`，不擦弹（沿用）。 |
| **每日挑战** | `daily_challenge.dart` **零 diff**。`barrage`（弹速 +16%）→ 弹更密，吞噬数更高，重矛更容易兑现，同时空放保护不影响；`scoreScale` 通过 `_scaled()` 作用于新奖励表；`ace`（2 命）→ 挨打熄灭更痛；种子仅驱动 `WaveDirector`，所有新反馈**不消耗 `_rng`**（沿用 v0.7 的 `_fx` 计数器方式），同一击破脚本的掉落序列不变。 |
| **第 1–2 波** | `squeeze`、`chargePower`、`grazePulse`、`resonanceArm` 恒为 0 / 1 / 0 / 0，擦弹带不画（`wave < kGrazeFromWave`），所有几何因子 = 1；`early_wave_snapshot_test` 的逐帧校验值（`752886552`）必须**不变**。 |
| **引入波次** | 凝神 / 擦弹第 3 波、共鸣第 5 波、矛击第 6 波均不变；重矛只在第 6 波起有意义。第 5 波首次共鸣提示强调「弹多时再放」（§9）。 |

---

## 9. HUD / rules_text / README

### 9.1 HUD（`battle_hud.dart` / `hud_stats.dart`）

- **不新增控件**。`resonanceMeterFor(permille, wave)` 的 `label` 保持（`共鸣就绪 · 双击`）；`_ResonanceBar` 就绪态的 `双击` 小字保留。
- 战机上的琥珀环（§4.1）与 HUD 条**同色同节奏**（呼吸周期 `833333 µs` ≈ `2π / 7.54` 的近似，不要求完全一致）。
- 320 dp 宽布局回归：`battle_hud_test` 现有「满状态含就绪共鸣条无溢出」用例不改。

### 9.2 `rules_text.dart`（单一出处，数字全部来自 `battle_tuning`）

`stanceHints()` 改写（模板，常量插值）：

1. `凝神：第 $kFocusFromWave 波起，手指停稳自动进入；判定点缩小至 $kFocusHitRadius，停稳约 ${kSqueezeSeconds} 秒后弹道与僚机才向机身收束。`
2. `擦弹：敌弹从判定外 $kGrazeBand 像素内掠过且未命中。运动中擦弹 ${kGrazeRewardMoving.score} 分、共鸣 +${kGrazeRewardMoving.resonance}；凝神中减半。`
3. `共鸣：第 $kResonanceFromWave 波起，条满后双击屏幕。身边至少 $kResonanceMinConvert 颗弹才会释放；吞噬转分，$kResonanceInvuln 秒无敌，修复卫星。`
4. `矛击：第 $kChargeFromWave 波起，凝神静止 $kChargeSeconds 秒蓄满，起手移动射出；共鸣也会瞬间充满。共鸣吞噬的弹越多，那一矛越重（最高 ×$kLancePowerMax），被击中则熄灭。`
5. `卫星会吃掉正前方的弹：更稳，但不涨共鸣。`

`systemHintForWave` 改写（含「为什么」）：
- 第 3 波：`凝神：停稳判定变小；贴近弹幕有擦弹加分`
- 第 5 波：`共鸣条满后双击：弹多时再放，吞得越多越划算`
- 第 6 波：`静处蓄矛，起手移动射出；冲进弹幕放共鸣，矛更重`

`routeHints()` 补一行：`共鸣之后的那一矛：散射清场、贯穿割路、聚能斩击。`

`controlHints()` 的共鸣一行改为：`共鸣条蓄满、身边有弹时，双击屏幕释放共鸣。`

`how_to_play.dart` 仍然只引用 `rules_text`，**本通不在页面里新写任何数字字面量**；`rules_test` 增加一条：把所有说明行里出现的数字与调参表对照。

### 9.3 README 与版本

- `pubspec.yaml`：`version: 0.8.0`；`lib/utils/constants.dart`：`AppConstants.version = '0.8.0'`。
- `README.md`：下载链接 `v0.8.0`（第 7 行）、tag 示例（第 115–117 行 `v0.8.0` 与 `v0.8.0: 设计师打磨：看得懂的凝神、擦弹、共鸣与矛击`）、版本表增行 `| v0.8.0 | 内容版本：设计师打磨（凝神进慢出快、空放保护、重矛、可读性） |`。
- 不改 CI、签名、密钥。

---

## 10. 文件级实现清单与顺序

### 10.1 文件清单

| 文件 | 变更 |
| --- | --- |
| `lib/game/battle/battle_tuning.dart` | 新增 `kSqueezeRiseRate 2.5 / kSqueezeRiseHeld 8 / kSqueezeFallRate 12`、`kSqueezeSeconds = 0.4`（文案用，测试守护 `== 1 / kSqueezeRiseRate`）、`kDoubleTapMaxGap 56`、`kResonanceMinConvert 4`、`kLancePowerPerBullet 0.05 / kLancePowerCapBullets 40 / kLancePowerMax 3.0 / kLanceRadiusGrowth 0.2`、`GrazeReward` 与两档表、`grazeRewardFor`；改 `kFocusExitSpeed 80→60`、`kFocusSqueezeX 0.5→0.4`、`kFocusSqueezeAngle 0.6→0.4`、`kChargeDecayPerSec 1.2→0.6`；移除 `kGrazeGainMoving/Focused/kGrazeScore/kGrazeComboExtend`。 |
| `lib/game/battle/battle_types.dart` | `Player` 新增 `squeeze`、`chargePower`（默认 0 / 1）。 |
| `lib/game/battle/stance_rules.dart` | `updateStance` 更新 `squeeze`（上升用 `held ? kSqueezeRiseHeld : kSqueezeRiseRate`）；`GrazeLedger.credit` 返回 `GrazeReward?`。 |
| `lib/game/battle/double_tap.dart` | 返回 `TapResult { none, first, double }`；记录上一次 `upPos`，加 `kDoubleTapMaxGap` 判断。 |
| `lib/game/battle/player_weapon.dart` | 收束读 `player.squeeze`；抽出 `chargeSpecFor(Player)`；`appendChargeLance` 乘 `chargePower` 并增长半径，释放后清 1（清理发生在调用方，避免纯函数改状态）。 |
| `lib/game/battle/battle_controller.dart` | `_updateWingmen` 读 `squeeze`；`_collideEnemyShots` 用奖励表并写 `grazePulse`；`useResonance()` 先数弹→空放保护→写 `chargePower`→追加 `卫星复位` 飘字；新增 `armResonance()`、`resonanceArm`/`grazePulse` 计时器（`clearRun`、`start` 重置）；`_hitPlayer()` 掉命分支清 `chargePower`；矛击释放时飘 `矛击 ×n`；`_emit` 事件保持。 |
| `lib/game/battle/rules_text.dart` | §9.2。 |
| `lib/flame/battle_field_component.dart` | 擦弹带常显 / 脉冲 / 就绪琥珀；过渡短竖线；矛击瞄准线；重矛档位；`_soundOf` 新映射。 |
| `lib/flame/battle_visuals.dart` | 重矛三档样式（宽度 / 辉光半径量化）。 |
| `lib/services/sound_service.dart` | `GameSound.lance/resonance`、presets、触感映射。 |
| `lib/pages/game_page.dart` | `_onPointerUp` 处理 `TapResult`：`first` → `controller.armResonance()`，`double` → `useResonance()`。 |
| `lib/pages/widgets/hud_stats.dart`、`battle_hud.dart` | 仅文案；无结构改动。 |
| `pubspec.yaml`、`lib/utils/constants.dart`、`README.md` | §9.3。 |
| **不得改动** | `daily_challenge.dart`、`wave_director.dart`、`enemy_weapons.dart`、`boss_catalog.dart`、`enemy_motion.dart`、`bullet_field.dart`、`pickup_rules.dart` 的 `DropLedger` 与 `kPowerUpWeights`。 |

### 10.2 建议顺序（每步 `flutter analyze && flutter test` 通过后再进下一步）

1. **调参表与类型**（`battle_tuning.dart`、`battle_types.dart`），先更新受影响的 v0.7 测试常量引用，保证编译通过；`early_wave_snapshot_test` 校验值不变。
2. **凝神进慢出快**（`stance_rules.dart` + `player_weapon.dart` + 控制器僚机）+ 对应测试。
3. **Boss DPS 守护测试**（先写失败的测试，再靠 §3.2 的常量让它通过；若测试不过，只调 `kFocusSqueezeX/Angle` 区间 `[0.3, 0.5]`）。
4. **奖励表**（`GrazeReward` + 控制器改造）+ 测试。
5. **双击三层兜底**（`double_tap.dart`、`game_page.dart`、`useResonance` 空放保护、`armResonance`）+ 测试。
6. **矛击对称衰减 + 重矛**（`chargePower`）+ 测试。
7. **可读性**（擦弹带常显、就绪环、瞄准线、过渡竖线、飘字）+ `battle_render_test` 预算更新。
8. **声音**（两个新合成音）+ 测试。
9. **文案与版本**（`rules_text`、README、`pubspec`、`constants`）。

---

## 11. 测试与验收

### 11.1 需要更新的既有测试

- `stance_rules_test`：凝神退出阈值（60）、收束常量（0.4 / 0.4）、`squeeze` 取代 `focus` 作为几何输入（`level $level focus preserves damage and squeezes geometry` 与路线组用 `squeeze` 构造）、`kChargeDecayPerSec` 相关、`GrazeLedger.credit` 的新返回值、双击组改用 `TapResult`。
- `battle_controller_test` / `gameplay_controller_test`：擦弹计分改读奖励表；共鸣测试的弹幕需 ≥ 4 颗。
- `rules_text_test`：新文案、数字全来自常量。
- `battle_render_test`：批提交上限 45 → 49。
- `sound_service_test`：覆盖 `lance`、`resonance`。
- `early_wave_snapshot_test`：**不改校验值**，若变化即为回归。

### 11.2 新增测试

**凝神**
- `短停 0.3 s 后 squeeze < 0.6`；`0.5 s 后 ≥ 0.95`。
- `Shift 按住 0.15 s 内 squeeze ≥ 0.9`。
- `squeeze` 下降约 0.08 s 回 0。
- 60 世界像素/秒匀速慢拖不保持 `focused`；42 以下仍进入。
- `hitRadius` 与 `charge` 仍由 `focus` 驱动，不受 `squeeze` 影响。

**Boss 站桩守护**
- 对 D ∈ {450, 540, 620}、偏移 ∈ {0, ±30}，6 级与三条路线两阶共 7 组弹道，凝神 / 运动平均对正伤害比 ≤ 1.25；v0.7 值（0.5 / 0.6）应当在该测试里**失败**（作为守护有效性的反例，用 `skip` 注释记录，不进 CI）。
- 偏移 60 时凝神 ≥ 运动。

**双击与共鸣**
- 落点间距 ≥ 56 不触发；`first` 仅在条满时触发 `armResonance`；`first` 之后超过 0.32 s 再点 → 再次 `first`。
- `useResonance()`：3 颗弹 → 条 / 无敌 / 充矛 / 卫星均不变，飘 `无弹可吞`，0.8 s 内再次空放不重复飘字；4 颗弹 → 正常；第 5 波（未解锁矛击）`chargePower` 保持 1。
- 卫星复位飘字仅在确实有卫星需要修复时出现。

**重矛**
- `chargePower = 1 + min(converted, 40) * 0.05`：converted = 0（被拦）、4、20、40、80 的值；`kLancePowerMax == 1 + kLancePowerCapBullets * kLancePowerPerBullet`。
- `appendChargeLance`：伤害 = `spec.damage * power`，半径 = `spec.radius * (1 + 0.2 * (power - 1))`；三条路线与默认。
- 释放后 `chargePower == 1`；真正掉命时归 1，`charge` 保留；护盾挡一击时 `chargePower` 保留。
- 已满蓄时再共鸣，倍率照样提升；静蓄满蓄的矛 `chargePower == 1`。

**奖励表**
- 运动 / 凝神擦弹的分数、共鸣、连击窗口按表；`scoreScale` 作用于分数；令牌桶、`invuln`、未解锁不结算。
- 同一击破脚本（固定种子）下，开启 / 关闭新反馈，掉落序列一致（沿用 v0.7 的 `_fx` 方式）。

**渲染**
- 十六弹种 + 150 敌弹 + 三僚机 + 满蓄凝神 + 重矛三档 + 擦弹带常显：批提交 ≤ 49、圆 ≤ 6、弧 ≤ 2。
- 320 dp 满状态 HUD 无溢出。

**回归**
- 第 1–2 波：`squeeze == 0`、`chargePower == 1`、擦弹带不绘制；`early_wave_snapshot_test` 校验值不变。
- `git diff main -- lib/game/challenge/daily_challenge.dart lib/game/battle/wave_director.dart lib/game/battle/enemy_weapons.dart lib/game/battle/boss_catalog.dart lib/game/battle/enemy_motion.dart lib/game/battle/bullet_field.dart` 为空（路径以仓库实际位置为准）。
- `supplyHints()` 长度 == `PowerUpKind.values.length` == 7。

### 11.3 验收标准

自动：
1. `flutter analyze` 无问题；`flutter test` 全绿，预计 ≥ 440 项（基线 409）。
2. 上述守护测试全部通过；受保护文件无 diff。
3. 版本号三处（pubspec、constants、README）一致为 `0.8.0`。

人工（保留为设备验收，**自动测试无法替代**）：
1. 凝神：停手约 0.3 s 的「慢闪」不再明显改变火力形状；真正站定 0.5 s 后火力收束，期间有短竖线预告。
2. Boss：站桩不再比跟打快；贴着弹幕飞、攒条、冲进去双击，能放出 ≥ ×2 的矛并明显削血。
3. 双击：重新握机的两次落指不再误触；平静时双击只飘 `无弹可吞`、不扣条。
4. 矛击：蓄满时能看到瞄准线；释放有专属音；重矛的飘字与弹体变粗对得上。
5. 读得懂：关掉 HUD 角落小条，仅看战机周围也能判断「擦弹窗在哪、共鸣就绪没、矛蓄满没」。
6. 320 dp 手机与 120 Hz 设备的帧时间与 v0.7 对照，性能回退 ≤ 10%（沿用 v0.6 / v0.7 的保留项，设计稿不宣称已完成）。

---

## 12. 风险

| 风险 | 缓解 |
| --- | --- |
| **收束调弱后凝神显得「没用」**（对 Boss 正对不再有额外 DPS） | 凝神的价值仍在**判定 -51%、偏移目标更准、静蓄矛、擦弹带更宽（18.5）**；若人工测试觉得空，只允许在 `kFocusSqueezeX/Angle ∈ [0.3, 0.5]` 内回调，且必须通过 §11.2 的 Boss 守护测试。 |
| **刀口敏感**：D = 450 时内侧针弹 `43.6` 只比 41 高 2.6 | 守护测试用多个 D 取均值；调参时看比值而不是单点。 |
| **`squeeze` 与 `focus` 双状态引入新的不同步**（例如读错字段） | 只有两处读 `squeeze`（`appendPlayerShots`、`_updateWingmen`）；测试分别断言几何跟 `squeeze`、判定跟 `focus`。 |
| **重矛被囤积**（共鸣后长时间不动、等 Boss 再放） | 受 `kLancePowerMax` 限制，且每个共鸣周期只有一发；挨打即灭。若实测仍囤积，下一版再考虑时间衰减（本通不加）。 |
| **空放保护让共鸣在弹少时失去「保命」用法** | 有意：共鸣是危险里兑现的东西，保命用炸弹 / 护盾。 |
| **第 5 波首次共鸣被拦**（玩家在空旷处双击） | 飘字 `无弹可吞` + 第 5 波提示「弹多时再放」；条不扣，学得起。 |
| **擦弹带常显增加视觉噪音** | 基础 alpha 仅 0.10、半径 25，与机身同尺度；同一次 `drawCircle`。 |
| **新音效过响 / 过密** | `lance` 与 `resonance` 都是低频次事件（矛击需蓄能、共鸣需满条）；沿用 `_soundOf` 的同步去重位掩码。 |
| **渲染预算被突破** | 瞄准线、竖线、重矛都并入既有批桶，档位量化；预算测试上限显式放宽到 49 并卡死。 |
| **手算数字与实测不符** | 本文所有「手算」均需被 §11.2 的测试复核；不符时以测试为准，调参区间已在上文给出。 |

---

## 实现偏差 / 验证与审查结果

### 实现偏差

- §11.2 的「偏移 60 时凝神 ≥ 运动」无法普遍覆盖聚能路线：以指定的 D 三点累计，聚能两阶均为运动 1.5、收束 0（聚能弹原本向中轴汇聚，收束后在远处失去偏移目标）。保留指定 `0.4 / 0.4` 和全部原弹道；七组路线的核心 DPS 比值 ≤ 1.25 守护全部通过，偏移守护覆盖默认、散射、贯穿；聚能不套用该次要断言。未为满足断言修改武器或敌人。
- §3.4 / §11.2 的「0.6 蓄能冲刺 0.3 秒后 ≥ 原值的 0.8」与指定衰减 0.6/s 算术冲突：真实结果 `0.6 - 0.3 * 0.6 = 0.42`，为原值 70%。按明确指定的速率实现并测试 0.42。
- 擦弹文案按奖励表明确写「凝神 6 分、+2 共鸣」，未沿用 §9.2 模板的笼统「减半」（分数并非 5）。
- 重矛主辉光半径与弹体宽度按三档放大；尾部三粒辉光保持原半径 7，共用原批桶，使三档同屏加瞄准线、过渡线仍不超过 49 批（若尾光也逐档放大会达到 51）。未增加 Bullet 字段或逐帧构造样式列表。
- 新增验收集中于 `test/designer_pass_test.dart`，渲染预算实际位于 `test/battle_render_batch_test.dart`，故在该文件更新。保留 v0.7 参数的故意失败反例并标记 skip，不纳入 CI 执行。
- 按 §10 的功能顺序推进；中间有跨步骤的旧用例夹具修正，未做到每一步均全套绿色后才进入下一步。最终完整检查全绿。

### 自动验证与审查

- `flutter analyze`：No issues found。
- `flutter test --no-pub --reporter expanded`：455 项通过（409 → 455），另有 1 项按设计跳过的旧参数反例。
- 第 1–2 波快照仍为 `752886552`，快照测试文件零 diff；新增 squeeze / chargePower 初始值断言。
- 相对 main：daily_challenge、wave_director、enemy_weapons、boss_catalog、enemy_motion、bullet_field、pickup_rules 全部零 diff；掉落权重和 DropLedger 未改；无新补给、敌种或武器上限。
- 最重同屏渲染预算通过：≤49 批、6 圆、≤2 弧；320 dp 满状态 HUD 原测试通过。
- 自审核对 focus/squeeze 读写分工、空放原子性、受伤与护盾分支、倍率消费、随机序列回归、波次解锁和版本一致性。未调用独立审查代理，未声称完成独立代码审查。
- §11.3 全部手感、音量、真机 320 dp / 120 Hz 帧时间与 ≤10% 性能回退项目仍保留为设备验收；本次环境未做真机测量。

### 独立代码审查（Claude）

审查通过，无必须修复的问题。对照设计：
1. `focus` / `squeeze` 读写分工正确；退出阈值 60；Boss 收束 0.4/0.4。
2. 双击空间约束、`TapResult`、`armResonance` 守卫、空放保护（≥4 弹）均符合。
3. `GrazeReward` 两档、`chargePower` 公式与掉命熄灭、护盾不熄灭符合。
4. 擦弹带常显、瞄准线、新合成音、卫星复位飘字已接线。
5. 保护文件零改；无新系统/新持久化键；第 1–2 波快照不变。

协调方本地复验：`flutter analyze` 零问题，`flutter test` 455 通过（+1 skip）。
