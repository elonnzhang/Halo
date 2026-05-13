# Halo, 视觉规格

> 状态：v0 视觉稿（与 [PRODUCT.md](PRODUCT.md) / [INTERACTION.md](INTERACTION.md) 配套）
> 主语言：中文。配套可点击 mockup：[`mockups/halo.html`](../mockups/halo.html)

## 1. 视觉主张

**Liquid glass radial HUD.** 一块凸面玻璃浮盘，12 点方向一道 specular 高光弧，12 点稍偏左上模拟光源，中心 deadzone 是向内凹陷的 lens。默认态几乎全透明——瓣间 1° 角度缝隙本身就是视觉分割，不靠描边。身份色只在两个时刻介入：hover 瞬间瓣内亮起身份色玻璃 + 身份色外溢 halo，以及 commit 瞬间的 vignette ripple。

与 macOS Tahoe（System 26）的 Control Center / Spotlight 同一视觉语言：
- 顶部 rim 的亮边高光（specular）
- 玻璃"沾色"——hover 时整盘带极轻的身份色染色（~5%）
- 底部自然变暗，暗示玻璃厚度而非画一层黑底
- 中心呈凹陷 lens 状，上缘内阴影

参照同类（按属性借鉴而非整体抄袭）：

| 参照 | 借来的属性 | 不借的属性 |
| --- | --- | --- |
| macOS Tahoe 26 Control Center | 顶部 specular 弧 + 内容感知染色 | 堆叠的白色 tile 布局 |
| visionOS 浮板 | 凹凸玻璃 + rim light + 底部衰减 | 高饱和立体图形 |
| Raycast HUD | 细线分割、无重描边、深灰 + 玻璃 | 列表式信息密度 |
| Hue 游戏色环 | 8 槽方位 + 色相记忆 | 高饱和默认态 |

## 2. N 槽几何（默认 8）

槽位数 **N 可配置 4–12**。槽 0 永远对准 12 点；其余顺时针递增。下图按 N=8 绘制；其他 N 同心拓扑等价，只是每瓣角度变化。

```
          0 (北 / 12 点)
       ┌────────────┐
   7   │            │   1
       │            │
       │   ⊙ deadzone   ← 中心 dead-zone, ⌀72pt
       │   (72pt)   │     显示当前 frontmost app
       │            │
       │            │
   5   │            │   3
       └────────────┘
          4 (南 / 6 点)
```

### 角度与键位（随 N 变化）

| 维度 | N=4 | N=6 | N=8 | N=10 | N=12 |
| --- | --- | --- | --- | --- | --- |
| 单瓣角度 | 90° | 60° | 45° | 36° | 30° |
| 单瓣可视面积 | 巨大 | 大 | 适中 | 紧凑 | 极紧凑 |
| 数字键直选 | 1–4 | 1–6 | 1–8 | 1–9 / 0 | 1–9 / 0 |
| 11、12 槽位访问 | n/a | n/a | n/a | n/a | 方向键 / Tab |

### 固定参数（不随 N 变化）

| 维度 | 值 | 备注 |
| --- | --- | --- |
| HUD 外盘直径 | **320 pt** | 不随 N 变化，瓣自适应 |
| 内圈直径 (deadzone) | **112 pt** | 中心图标 `⌀ 112 × 0.62 ≈ 69 pt` 居中 |
| 面板外框 | `HUD + 120 pt = 440 pt` | 含 halo 溢出 + 阴影 + 弧外 label |
| 瓣间缝隙 | 1° 角度切缝 | 沿径向切出，非 stroke |
| 外盘描边 | 0.6–0.8 pt 渐变 | 上亮下暗 + 顶部 specular 高光弧 |
| 角度起点 | -90° | 槽 0 始终对准 12 点 |
| 单瓣角度公式 | `360°/N` | 自动计算 |
| Icon 尺寸 | 48 × 48 | 瓣内居中显示 |
| Label 字体 | SF Pro Medium 12pt | 浮在瓣外沿弧外 28pt |

### 槽位编号

顺时针，永远从 12 点起：

- N=8：0=北 1=东北 2=东 3=东南 4=南 5=西南 6=西 7=西北
- N=4：0=北 1=东 2=南 3=西
- N=12：每 30° 一个，0=12 点位置，1 = 12 点顺时针 30°，依此类推

## 3. 状态枚举

每个状态都有"视觉"与"行为"两栏。视觉描述 HUD 当下渲染；行为描述驱动该状态进入的事件。

### 3.1 Idle（召唤完成，无 hover）

```
   ╭──────────────────╮
   │ ⌀320pt liquid    │
   │  glass disc       │
   │  ┌─ 顶部 specular 弧
   │  ⌒     ─ (12 点方向)
   │                   │
   │    ⊙ 凹陷 lens    │
   │     ⌀112pt       │
   │                   │
   │  N 瓣几乎透明    │
   │  1° 角度缝隙    │
   ╰──────────────────╯
```

玻璃层（由外到内，从下至上堆叠）：

1. **Base blur**：`NSVisualEffectView` + `.hudWindow` + `.behindWindow`，桌面内容透过来
2. **Depth radial**：`RadialGradient` 从 UnitPoint(0.42, 0.34) 起——中心 white@9%、中段 white@2%、外缘 black@22%，模拟凸面受光
3. **Content-aware tint**：hover 时整盘叠一层身份色 @5%（blendMode `.plusLighter`），hover 消失时 220ms ease-out 淡出
4. **Bottom weight**：`LinearGradient` 从 center 到 bottom，透明 → black@26%，让底半部"坠下去"
5. **Rim stroke**：`strokeBorder` 线性渐变 top-to-bottom，white@34% → 10% → 2%，宽 0.8pt
6. **Specular arc**：12 点方向 -135° … -45° 的 `SpecularArc`，中间 white@78%、两端透明，`blur(0.35)`，宽 1.1pt

瓣（SectorShape）Idle 态：
- 填色：white@1.5%（几乎不可见）
- 描边：white@3%，0.5pt（只在瓣 active 时变身份色 1.4pt）
- 瓣间分隔：靠 `slotGapDegrees: 1.0` 的角度切缝，不靠描边

中心 lens（⌀112pt）：
1. 填色：black@48%
2. 上缘 inner shadow：`Circle.stroke(LinearGradient top → clear, width 3)` + `blur(2.6)`
3. Lens rim：`strokeBorder` 渐变 white@24% → 6%，0.8pt
4. Lens 顶部 specular：`SpecularArc(-120°, -60°)`，white@48%，0.7pt
5. 中心图标：deadzone × 0.62 ≈ 69pt，居中

### 3.2 Hovering（光标进入瓣）

- 瓣背景：身份色 ×10% alpha
- 瓣描边：1.4pt 身份色
- 内侧光晕：身份色 ×55% stroke 宽 6pt + `blur(4)`，用 sector 形状做 mask，形成玻璃内部被点亮的感觉
- Icon：1.08× 放大
- 整盘：content-aware tint 身份色 @5% 淡入
- 外圈 halo：`RadialGradient(identity@32% → 0)`，`blur(18)`，延伸出 HUD 边缘

### 3.3 Preview（hover ≥ 120ms，已确认意图）

```
   ╭──────────────────╮
   │  瓣 N：              │
   │    bg = identity×14%  │
   │    stroke = identity 2pt │
   │    inner glow 6pt     │
   │  中心 icon:           │
   │    跨越淡入到 app N    │
   │  HUD 外圈：           │
   │    身份色 halo 10pt 高斯 │
   ╰──────────────────╯
```

- 瓣背景：身份色 ×14% alpha
- 瓣内侧光晕：6 pt 高斯，身份色 ×20%
- HUD 整体玻璃底色：注入身份色 ×5%
- 外圈光晕：10pt 高斯模糊，身份色 ×20% 透明度沿径向外溢
- 中心 dead-zone：原 frontmost 图标 fade-out + 目标 app 图标 fade-in（cross-fade 200ms，scale 0.95 → 1.0）

### 3.4 Committing（松开 hotkey / 点击 / 数字键）

```
   ╭──────────────────╮
   │  瓣 N 放大 1.0 → 1.1× │
   │  HUD opacity 1 → 0   │
   │  150ms ease-out      │
   ╰──────────────────╯
            ↓
   屏幕中心向外：身份色 vignette ripple
   - 半径 280 → 600 pt
   - 不透明度 0 → 0.12 → 0
   - 180ms ease-out
   - 不阻挡点击（pointer-events: none）
```

- HUD 整体淡出与 ripple 同步起跑
- ripple 是一个全屏覆盖层 `position: fixed; inset: 0`，内绘 `radial-gradient(circle at center, identity 0%, transparent 60%)`，整体 scale + opacity 双轴动画

### 3.5 Cancelling（ESC / dead-zone 释放 / 失焦）

- HUD 淡出 100ms ease-in
- 无 ripple，无颜色残留
- 区别于 commit：用户感受到"什么都没发生"

### 3.6 Empty slot（Top-N 不满）

```
       ╭────────╮
       │  + + + │   虚线轮廓 `1pt dashed rgba(255,255,255,0.18)`
       │   ＋    │   中心 "+" 符号 `rgba(255,255,255,0.32)`
       │  + + +  │   呼吸动画：opacity 0.32 ⇄ 0.48，2.4s ease-in-out infinite
       ╰────────╯
```

提交空瓣 → 弹出 Pin 选择面板（普通 macOS sheet），允许从运行中的 app 列表里钉一个到该槽。

### 3.7 Launching（目标 app 未运行）

- 瓣符号：半透明 `rgba(255,255,255,0.45)`
- 状态点：灰 `rgba(255,255,255,0.30)`
- commit 后：瓣内 6×6 spinner，最多 1.5s，超时 → Failed

### 3.8 Failed（上次切换失败 / app 已卸载）

- 状态点：红 `#FF453A`
- commit 时：HUD 整体 80ms 水平摇晃 × 2（不变形，仅 transform: translateX(±3pt)）
- 频率计数不增加

### 3.9 Tutorial overlay（仅首次召唤）

```
   ╭──────────────────────────╮
   │  ↑                       │
   │ ←   N 瓣 HUD 透出 18%   →│
   │  ↓                       │
   │  移动鼠标 / 按方向键 → 选择 │
   │  松开 → 切换 · ESC → 取消  │
   ╰──────────────────────────╯
```

- 半透明黑覆盖 `rgba(0,0,0,0.55)`，让 HUD 透出 18%
- 中心 4 个方向箭头（柔和动画指示）
- 底部 Geist 中文说明文字
- 8s 后自动消失；点击任意位置立即消失

## 4. 调色与身份色

### 4.1 中性色调色板（Liquid glass）

| Token | Value | 用途 |
| --- | --- | --- |
| `hud-glass-light` | `white @ 9%` | 凸面高光（depth gradient 亮端） |
| `hud-glass-mid` | `white @ 2%` | 中段过渡 |
| `hud-glass-edge` | `black @ 22%` | 凸面暗端（rim 向内的过渡） |
| `hud-weight` | `black @ 26%` | 底部 weight 渐变，玻璃"坠感" |
| `hud-rim-top` | `white @ 34%` | rim stroke 顶端（受光） |
| `hud-rim-mid` | `white @ 10%` | rim stroke 中段 |
| `hud-rim-bot` | `white @ 2%` | rim stroke 底端（阴影） |
| `hud-specular-peak` | `white @ 78%` | 12 点 specular 弧中段亮度 |
| `hub-fill` | `black @ 48%` | 中心 lens 基底 |
| `hub-inner-shadow` | `black @ 55%` | 上缘内阴影 gradient 头端 |
| `hub-rim-top` | `white @ 24%` | lens rim 顶端 |
| `hub-rim-bot` | `white @ 6%` | lens rim 底端 |
| `hub-specular` | `white @ 48%` | lens 顶部 specular |
| `slot-idle-fill` | `white @ 1.5%` | 瓣默认填色（近乎不可见） |
| `slot-idle-stroke` | `white @ 3%` | 瓣默认描边 |
| `label-capsule-fill` | `white @ 6% over hudWindow blur` | 弧外 label 胶囊 |
| `label-capsule-rim` | `white @ 28% → 4%` 线性 | 胶囊 rim stroke |
| `text-primary` | `white @ 96%` | label 主文本 |
| `text-secondary` | `white @ 55%` | 预留 |
| `text-tertiary` | `white @ 30%` | 占位 / 提示 |

身份色接入点（见 §4.2 / §4.3）：
- 瓣 hover fill：`accent @ 10%`
- 瓣 preview fill：`accent @ 16%`
- 瓣 active 描边：`accent @ 100%` 1.4pt
- 瓣 active 内发光：`accent @ 55%` 6pt stroke + `blur(4)` masked by sector
- 整盘 content tint：`accent @ 5%` `plusLighter`
- 外圈 halo：`accent @ 32% → 0%` radial，`blur(18)`
- commit vignette ripple：`accent`（见 §6）

### 4.2 N 色 fallback 调色板

当 app icon 取色失败、饱和度过低（< 12%）、或与相邻槽身份色冲突无法解算时，落到生成的兜底色。**通用公式（任意 N）：**

```
fallback[i] = oklch(65%, 0.18, (230° + i × 360°/N) mod 360°)
i ∈ [0, N)
```

`base = 230°`（aqua 起点），N 槽自动均分色相环、保持 OKLCH 等距。

**N = 8 特例**：保留 Hue 游戏原 8 色，向游戏致敬：

| Slot | Name | Hex | OKLCH |
| --- | --- | --- | --- |
| 0 | aqua | `#26A5E4` | `oklch(70% 0.13 230)` |
| 1 | navy | `#3B5BDB` | `oklch(52% 0.18 265)` |
| 2 | purple | `#A259FF` | `oklch(60% 0.24 295)` |
| 3 | pink | `#E01E5A` | `oklch(58% 0.24 5)` |
| 4 | orange | `#F97316` | `oklch(70% 0.18 45)` |
| 5 | red | `#FF453A` | `oklch(65% 0.22 22)` |
| 6 | yellow | `#F7B500` | `oklch(80% 0.15 80)` |
| 7 | green | `#1DB954` | `oklch(67% 0.18 145)` |

其他 N（4 / 6 / 10 / 12）按上述 OKLCH 公式动态生成；不再手工列表。

### 4.3 身份色注入规则

- **默认源**：app icon dominant color via CoreImage k-means (k=3，取饱和度最高的簇)
- **饱和度门**：< 12% → 走 fallback 槽位色
- **冲突阈值**：相邻两槽身份色色相差 < `360°/N × 0.6` 即视为冲突
  - N=4 → 阈值 54°
  - N=6 → 阈值 36°
  - N=8 → 阈值 27°
  - N=10 → 阈值 21.6°
  - N=12 → 阈值 18°
- **冲突解算**：高频保留原色，低频沿色相环推 `360°/N × 0.4` 度（仅推 hue，不动 lightness / chroma）
- **用户覆盖**：Settings 中的 colorwell 始终最高优先级

### 4.4 冲突解算示例

```
slot 1 (Figma):       oklch(60% 0.24 295)   purple
slot 2 (Slack):       oklch(58% 0.24 5)     red-pink, hue 5°
                                              ↓
       色相差 = |295 - 5| ≈ 70°, 不冲突 → 保留
```

```
slot 3 (Notion):      oklch(70% 0.18 45)    orange
slot 4 (Reminders):   oklch(70% 0.18 55)    orange-ish, hue 55°
                      色相差 = 10°，冲突
                                              ↓
高频是 slot 3 (Notion) → slot 3 保留 hue 45°
低频是 slot 4 (Reminders) → hue 55° → 70°，得 oklch(70% 0.18 70)
```

## 5. 字体与节奏

### 5.1 字体栈

| 用途 | 字体 | 备注 |
| --- | --- | --- |
| App 内 UI（HUD / Settings） | SF Pro Text / SF Pro Display | macOS native，与系统 HUD 一致 |
| Mockup 网页 display | Geist 500/700 | 留性格 |
| Mockup 网页 body | Geist 400 | 同家族 |
| 等宽 / 键位 / Token | JetBrains Mono 400/500 | Tokens、`⌘⌥Space` 等 |

### 5.2 字号阶梯（mockup 网页内）

| Token | px | line-height | 用途 |
| --- | --- | --- | --- |
| `--fs-hero` | 56 | 1.05 | 页面顶部主标 |
| `--fs-h1` | 32 | 1.15 | section 标题 |
| `--fs-h2` | 20 | 1.3 | 子节 |
| `--fs-body` | 14 | 1.55 | 正文 |
| `--fs-caption` | 12 | 1.4 | 注释、状态名 |
| `--fs-mono-sm` | 11 | 1.3 | token 值 |

HUD 内部字号：
- 弧外 label（hover 时显示的 app 名）：SF Pro Medium 12pt，`rgba(255,255,255,0.94)`
- 瓣内无文字；状态仅靠图标 + 状态点表达

### 5.3 间距与圆角

| Token | px |
| --- | --- |
| `--r-hud` | 140 (即半径) |
| `--r-slot-outer` | 4 (瓣外角微圆) |
| `--r-deadzone` | 36 (即半径) |
| `--r-card` | 14 (mockup spec card) |
| `--r-pill` | 999 (状态切换胶囊按钮) |
| `--sp-1` | 4 |
| `--sp-2` | 8 |
| `--sp-3` | 12 |
| `--sp-4` | 16 |
| `--sp-5` | 24 |
| `--sp-6` | 32 |
| `--sp-7` | 48 |
| `--sp-8` | 64 |

## 6. 切换反馈：Vignette Ripple

```
t = 0ms
   屏幕中心 (HUD 召唤位置)
   ●  半径 280pt，不透明度 0
   
t = 90ms (峰值)
   ◯  半径 420pt，不透明度 0.12
   
t = 180ms (落地)
   ○  半径 600pt，不透明度 0
   
       移除节点
```

- 实现：`<div class="ripple" style="--c: identity-color">` 全屏覆盖
- CSS：`radial-gradient(circle at center, var(--c) 0%, transparent 60%)`
- 动画：transform: scale + opacity 双关键帧
- pointer-events: none，不阻挡任何 app 输入
- z-index 高于 HUD，低于系统 menu bar

ripple 不在 hover/preview 阶段出现；它专门标记"我刚刚做出了选择"这一瞬间。

## 7. 暗色与浅色

**仅 Dark**。Halo HUD 永远暗色玻璃，无浅色变体。理由：

1. HUD 是 transient overlay，需要与任意 app（白底、黑底、彩色）共存
2. 暗色玻璃在浅色 / 深色背景上都能维持视觉对比
3. macOS 系统 HUD（Spotlight、Volume、Brightness）传统都是深色玻璃

身份色饱和度针对深底已校准；切到浅色 HUD 会需要全新调色，**不在 v1 计划内**。

## 8. 资产清单

| 资产 | 状态 | 备注 |
| --- | --- | --- |
| 8 槽几何 SVG | 在 `mockups/halo.html` 中由 JS 生成 | 后续可固化为 `.svg` 资源 |
| 8 色 fallback 调色板 | 本文档 §4.2 | OKLCH + Hex 双格式 |
| Settings 视觉稿 | TBD | v0.1 实现期补 |
| 菜单栏图标 | TBD | template image（黑白 PDF） |
| App icon 占位符号集（mockup） | 见 `mockups/halo.html` | ✈ 𝐅 # ✓ ◇ ♫ ◎ ▷ |
