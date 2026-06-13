# LimitHUD · Pet Animation Matrix

The card mascot performs different actions, expressions, and "bubble-break"
effects depending on **character + quota state**. This file is the source of
truth; implementation lives in `Sources/LimitHUD/PixelPet.swift` (sprite /
expressions) and the `Choreo` type in `Sources/LimitHUD/HUDView.swift`
(interaction choreography).

State is derived from the tightest window: `healthy ≥50%` · `caution <50%` ·
`danger <20%` · `dead 0%` · `party` for 90s after a refill · `sleep` when there's
no data.

---

## 1. Action matrix (character × state)

Each (character, state) has its own set of actions (`repertoire(style, state)`),
rotated per cycle with rests mixed in.

| | 🟢 healthy | 🟡 caution | 🔴 danger | 🎉 party | 😴 sleep | 💀 dead |
|---|---|---|---|---|---|---|
| **🐶 dog inu** | bump · tail-wag · zoomies · roll-over · sniff · finisher | bump · sniff · peek · wag (subdued) | **frantic warning bumps** · peek · finisher + constant tremble | huge zoomies · roll-over · wag · frequent finisher | curls up dozing · z | flopped flat |
| **🐱 cat neko** | bump · turn-away · knock-the-bubble · stretch · loaf · finisher | turn-away · peek · stretch · knock (subdued) | **puffs up, arches, recoils** · turn-away · finisher | rare pounce · gleeful knocking · finisher | curls into a loaf · deep z | flopped flat |
| **👻 ghost boo** | bump · drift · ethereal swirl · vanish-Boo · finisher | drift · peek · vanish | **erratic frantic flicker** · vanish · finisher | spin · repeated vanish-Boo · finisher | slow fade in/out · drift | fades away |
| **🍡 mochi** | bump · jelly-jiggle · spring-hop · stretch-plop · finisher | jiggle · peek · plop (subdued) | **violent panic wobble** · finisher | big bounces · stretch · jiggle · frequent finisher | slow squish-breaths | melts into a puddle |

### Motion feel (global, layered on the actions)
| State | Pace (period) | Intensity k | Extra |
|---|---|---|---|
| healthy | 72 frames (~3.6s) | 1.0 | — |
| caution | 88 frames (~4.4s) | 0.8 (damped) | more rests, hesitant |
| danger | 52 frames (~2.6s) | 1.2 | **constant high-freq tremble**, actions aim at the bubble |
| party | 54 frames (~2.7s) | 1.35 | biggest hops/spins, finisher fires most often |
| sleep | 120 frames (~6s) | — | only doze + breathing; never touches the bubble |
| dead | — | — | fully still |

> Animation is continuous frame-driven at ~20fps; the sprite itself also has
> breathing/squash-and-stretch, blinks, eye darts, and a scripted expression
> timeline (see PixelPet).

---

## 2. Everyday bubble reaction (per character)

The ordinary `.contact` tap reacts differently per character:

| Character | Attack | Bubble reaction |
|---|---|---|
| 🐶 dog | headbutt | dents on the contact side + bouncy overshoot |
| 🐱 cat | paw tap | swings like a pendulum |
| 👻 ghost | phases through (translucent) | ripples + opacity shimmer |
| 🍡 mochi | soft squish | both squash, then rebound |

The bubble is **always quietly breathing** (out of phase with the pet) and
reacts to non-contact moves too (pet wags → bubble grooves along; hops → bubble
bounces a beat later; peeks → bubble leans in, curious). On a bump, **the text
jolts** too.

---

## 3. Finisher: bubble-break effects (8 total → 2 per character)

When a character's finisher fires, it alternates between that character's two
signature effects. The attack is in-character too (dog headbutt, cat paw-off-the-
table, ghost phase-through, mochi soft press).

| Character | Finisher attack | Signature ① | Signature ② |
|---|---|---|---|
| 🐶 dog (force) | full-force headbutt | **radial shatter** (bursts into 6 shards) | **knocked flying** (whole bubble flung off + 360° spin + shrink, boomerangs back) |
| 🐱 cat (mischief/gravity) | paw it off the ledge | **gravity drop** (shards rain down) | **rolled up** (rolls toward the tail like a blind, then unrolls) |
| 👻 ghost (dematerialize) | phase through it | **pixel dissolve** (scatters into 18 small squares) | **melt** (drips into 5 uneven streams) |
| 🍡 mochi (squishy) | soft body-press | **crushed flat** (squashed to a sliver, springs back) | **spring-stretch** (rubber-band stretch with a low-damped boing) |

> Effect ids: 0 radial shatter · 1 gravity drop · 2 pixel dissolve · 3 crushed
> flat · 4 knocked flying · 5 melt · 6 rolled up · 7 spring-stretch.
> Assignment: dog (0,4) · cat (1,6) · ghost (2,5) · mochi (3,7).

---

## 4. Expression / look (per character × state, see PixelPet)

Body color tracks state (Morandi: sage green / dusty mustard / dusty rose / warm
gray). Each state also cycles several expression poses (healthy: open eyes /
content squint / wink / glance + ✦).

| State | 🐶 dog | 🐱 cat | 👻 ghost | 🍡 mochi |
|---|---|---|---|---|
| healthy | big eyes, tongue out | almond eyes + ω mouth | dot eyes + :o | round smile + blush |
| caution | pleading puppy eyes | side-eye + 💢 | dot eyes + frown | flat + sweat |
| danger | >.< whimper + tremble lines | pinprick shock + ears back | open scream + shaking | worried + double sweat |
| dead | tongue out + soul leaving | XX eyes + halo | soul gone, hollow outline | melted puddle |
| party | panting tongue + ears up | both paws up | sunglasses visor | jumping + party hat |
| sleep | closed eyes | closed eyes | translucent | closed eyes |

---

<details>
<summary><b>中文版</b></summary>

卡片上的吉祥物会**根据角色 + 额度状态**做不同的动作、表情和"撞文字框"特效。
本表是设计真相来源,实现见 `Sources/LimitHUD/PixelPet.swift`(精灵/表情)
与 `Sources/LimitHUD/HUDView.swift` 的 `Choreo`(互动编排)。

状态由最紧额度决定:`healthy ≥50%` · `caution <50%` · `danger <20%` · `dead 0%` ·
`party` 回血后 90 秒 · `sleep` 无数据。

## 1. 动作矩阵(角色 × 状态)

| | 🟢 healthy 开心 | 🟡 caution 警惕 | 🔴 danger 慌 | 🎉 party 嗨 | 😴 sleep | 💀 dead |
|---|---|---|---|---|---|---|
| **🐶 狗 inu** | 撞 · 甩尾 · 撒欢跳 · 打滚 · 凑闻 · 大招 | 撞 · 凑闻 · 张望 · 甩尾(收敛) | **焦急警告撞 ×连发** · 张望 · 大招 + 全程发抖 | 巨型 zoomies · 打滚 · 甩尾 · 频繁大招 | 蜷着打盹 · z | 瘫平不动 |
| **🐱 猫 neko** | 撞 · 扭头 · 拨走气泡 · 伸懒腰 · 趴饼 · 大招 | 扭头 · 张望 · 伸懒腰 · 拨(收敛) | **炸毛弓背 · 嘶后缩** · 扭头 · 大招 | 难得扑跳 · 开心乱拨 · 大招 | 趴成猫饼 · 深度 z | 瘫平不动 |
| **👻 幽灵 boo** | 撞 · 飘浮 · 缥缈旋 · 隐身Boo · 大招 | 飘浮 · 张望 · 隐身 | **剧烈忽明忽暗乱飘** · 隐身 · 大招 | 旋转 · 反复隐身Boo · 大招 | 缓慢淡入淡出 · 飘 | 渐隐 |
| **🍡 团子 mochi** | 撞 · 果冻颤 · 蓄力弹 · 拔高摊 · 大招 | 果冻颤 · 张望 · 拔高摊(收敛) | **剧烈乱颤惊慌挤压** · 大招 | 大幅弹跳 · 拉伸 · 果冻颤 · 频繁大招 | 缓慢一鼓一瘪 | 摊成一滩 |

### 运动质感(全局,叠在动作上)
| 状态 | 节奏(周期) | 强度 k | 额外 |
|---|---|---|---|
| healthy | 72 帧(~3.6s) | 1.0 | — |
| caution | 88 帧(~4.4s) | 0.8(收敛) | 多休息、迟疑 |
| danger | 52 帧(~2.6s) | 1.2 | **全程持续高频小抖**,动作冲着气泡来 |
| party | 54 帧(~2.7s) | 1.35 | 弹跳/旋转最大,大招最频繁 |
| sleep | 120 帧(~6s) | — | 只有 doze + 呼吸,不碰气泡 |
| dead | — | — | 完全静止 |

## 2. 普通撞气泡反应(per 角色)

| 角色 | 出手 | 气泡反应 |
|---|---|---|
| 🐶 狗 | 头槌 | 接触侧顶出凹陷 + 弹性过冲 |
| 🐱 猫 | 抬爪轻拍 | 钟摆式整体摆动 |
| 👻 幽灵 | 穿身而过(半透明) | 荡起涟漪 + 透明闪烁 |
| 🍡 团子 | 软体蹭挤 | 双向互挤(都压扁再回弹) |

气泡平时也**自己轻轻呼吸**(错相位),并对非接触动作有同步反应。被撞时**文字也会弹一下**。

## 3. 大招:撞坏文字框特效(8 种 → 每角色专属 2 种)

| 角色 | 大招出手 | 专属特效 ① | 专属特效 ② |
|---|---|---|---|
| 🐶 狗(力量) | 全力头槌 | **放射爆裂** | **撞飞回旋** |
| 🐱 猫(损/重力) | 一爪拍下桌 | **重力坠落** | **卷帘卷走** |
| 👻 幽灵(消散) | 穿身而过 | **像素消散** | **融化滴落** |
| 🍡 团子(软体) | 软重身体压 | **压扁碾碎** | **弹簧拉伸** |

> 8 种特效 id:0 放射爆裂 · 1 重力坠落 · 2 像素消散 · 3 压扁碾碎 ·
> 4 撞飞回旋 · 5 融化滴落 · 6 卷帘卷走 · 7 弹簧拉伸。
> 分配:狗 (0,4) · 猫 (1,6) · 幽灵 (2,5) · 团子 (3,7)。

## 4. 表情/外观(per 角色 × 状态,见 PixelPet)

身体颜色随状态走(莫兰迪:鼠尾草绿 / 灰芥末黄 / 灰玫瑰红 / 暖灰)。

| 状态 | 🐶 狗 | 🐱 猫 | 👻 幽灵 | 🍡 团子 |
|---|---|---|---|---|
| healthy | 大眼吐舌傻笑 | 杏仁细眼 + ω嘴 | 圆点豆豆眼 + :o | 圆脸微笑腮红 |
| caution | 委屈狗狗眼 | 翻白眼侧目 + 💢 | 豆豆眼 + 撇嘴 | 无语 + 冒汗 |
| danger | >.< 呜咽 + 颤抖线 | 缩瞳震惊 + 压耳 | 张嘴尖叫 + 抖动 | 皱眉惊恐 + 双汗 |
| dead | 吐舌 + 灵魂出窍 | XX眼 + 头顶光环 | 魂飞只剩空心轮廓 | 融成一滩 |
| party | 哈气吐舌 + 竖耳 | 双爪举高 | 戴墨镜遮阳板 | 跳起戴派对帽 |
| sleep | 闭眼 | 闭眼 | 半透明 | 闭眼 |

</details>

---

_Implemented in `Choreo` (HUDView.swift) + `PixelPet` (PixelPet.swift). Keep this
file in sync when behavior changes._
