# Halo, 视觉规格

> 状态: 与 v1.1 实现对齐 (2026-05-14). 配套 [PRODUCT.md](PRODUCT.md) / [INTERACTION.md](INTERACTION.md) / [SETTING.md](SETTING.md).
> 主语言: 中文. 可点击 mockup: [`mockups/halo.html`](../mockups/halo.html) (live 轮盘) · [`mockups/halo-settings.html`](../mockups/halo-settings.html) (v1.1 设置面板) · [`mockups/halo-redesign.html`](../mockups/halo-redesign.html) (v1.1 视觉 redesign).
>
> **v1.1 实施备注**:
> - §2 几何参数表已更新: Halo 直径 / 图标尺寸 / 图标到圆心距离 / 面板缩放 panelScale 全部用户可调.
> - §4.2 已删除 Hue-8 fallback (本节文字已更新).
> - §8 资产清单中 "8 色 fallback 调色板" 行已移除, 与 §4.2 一致.
> - `mockups/halo.html` 仍展示 v1.0 8-slot 几何 (320pt / 72pt deadzone), 是历史快照; 当前实现请看 `halo-redesign.html` 与 `halo-settings.html`.

## 1. 视觉主张

**Liquid glass radial Halo.** 一块凸面玻璃浮盘，12 点方向一道 specular 高光弧，12 点稍偏左上模拟光源，中心 deadzone 是向内凹陷的 lens。默认态几乎全透明——瓣间 1° 角度缝隙本身就是视觉分割，不靠描边。身份色只在两个时刻介入：hover 瞬间瓣内亮起身份色玻璃 + 身份色外溢 halo，以及 commit 瞬间的 vignette ripple。

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
       │   ⊙ deadzone   ← 中心 dead-zone, ⌀112pt
       │   (112pt)  │     显示当前 frontmost app
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

### 固定参数（v1.1: 已支持用户调节, 默认值如下）

> v1.0 这一节标的是 hardcoded `Halo 外盘直径 320 pt`。v1.1 后所有几何项都通过 Settings → 通用 → 外观与轮盘布局调节, 并且整体可用 `面板大小` slider 套一层 0.80–1.50× 缩放。下表给出**默认值**与**用户可调范围**。

| 维度 | 默认值 | 可调范围 | 备注 |
| --- | --- | --- | --- |
| Halo 外盘直径 | **380 pt** | 280–440 pt | 用户在 Settings 中可调; 不随 N 变化, 瓣自适应 |
| 内圈直径 (deadzone) | **112 pt** | 固定 | 不可调; 中心图标居中显示当前应用 |
| 图标尺寸 | **48 pt** | 36–64 pt | 用户可调 |
| 图标到圆心距离 | 自动计算 | `[deadzone+iconHalf+4, visibleOuter-iconHalf-4]` | 上下限随直径 / 图标尺寸联动, 越界自动 clamp |
| 面板缩放 panelScale | **1.00x** | 0.80–1.50x | 渲染期统一倍率, 命中测试同步除以该值 |
| 面板外框 | `直径 + 200 pt` | — | 含 halo 溢出 + 阴影 + 弧外 label |
| 瓣间缝隙 | 1° 角度切缝 | 固定 | 沿径向切出, 非 stroke |
| 外盘描边 | 0.6–0.8 pt 渐变 | 固定 | 上亮下暗 + 顶部 specular 高光弧 |
| 角度起点 | -90° | 固定 | 槽 0 始终对准 12 点 |
| 单瓣角度公式 | `360°/N` | 固定 | 自动计算 |
| Icon 尺寸 | 48 × 48 | 瓣内居中显示 |
| Label 字体 | SF Pro Medium 12pt | 浮在瓣外沿弧外 28pt |

### 槽位编号

顺时针，永远从 12 点起：

- N=8：0=北 1=东北 2=东 3=东南 4=南 5=西南 6=西 7=西北
- N=4：0=北 1=东 2=南 3=西
- N=12：每 30° 一个，0=12 点位置，1 = 12 点顺时针 30°，依此类推

## 3. 状态枚举

每个状态都有"视觉"与"行为"两栏。视觉描述 Halo 当下渲染；行为描述驱动该状态进入的事件。

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
- 外圈 halo：`RadialGradient(identity@32% → 0)`，`blur(18)`，延伸出 Halo 边缘

### 3.3 Preview（hover ≥ 120ms，已确认意图）

```
   ╭──────────────────╮
   │  瓣 N：              │
   │    bg = identity×14%  │
   │    stroke = identity 2pt │
   │    inner glow 6pt     │
   │  中心 icon:           │
   │    跨越淡入到 app N    │
   │  Halo 外圈：           │
   │    身份色 halo 10pt 高斯 │
   ╰──────────────────╯
```

- 瓣背景：身份色 ×14% alpha
- 瓣内侧光晕：6 pt 高斯，身份色 ×20%
- Halo 整体玻璃底色：注入身份色 ×5%
- 外圈光晕：10pt 高斯模糊，身份色 ×20% 透明度沿径向外溢
- 中心 dead-zone：原 frontmost 图标 fade-out + 目标 app 图标 fade-in（cross-fade 200ms，scale 0.95 → 1.0）

### 3.4 Committing（松开 hotkey / 点击 / 数字键）

```
   ╭──────────────────╮
   │  瓣 N 放大 1.0 → 1.1× │
   │  Halo opacity 1 → 0   │
   │  150ms ease-out      │
   ╰──────────────────╯
            ↓
   屏幕中心向外：身份色 vignette ripple
   - 半径 280 → 600 pt
   - 不透明度 0 → 0.12 → 0
   - 180ms ease-out
   - 不阻挡点击（pointer-events: none）
```

- Halo 整体淡出与 ripple 同步起跑
- ripple 是一个全屏覆盖层 `position: fixed; inset: 0`，内绘 `radial-gradient(circle at center, identity 0%, transparent 60%)`，整体 scale + opacity 双轴动画

### 3.5 Cancelling（ESC / dead-zone 释放 / 失焦）

- Halo 淡出 100ms ease-in
- 无 ripple，无颜色残留
- 区别于 commit：用户感受到"什么都没发生"

### 3.6 Empty slot（Top-N 不满）

```
       ╭────────╮
       │  + + + │   虚线轮廓 `1pt dashed rgba(255,255,255,0.18)`
       │   ＋    │   中心 "+" 符号 `rgba(255,255,255,0.32)`
       │  + + +  │   呼吸动画：opacity 0.32 ⇄ 0.48，2.4s ease-in-out
       ╰────────╯
```

> 呼吸动画**只在轮盘被 hover 时启动**（任意 sector 进入 hover 即触发，cursor 离开整个轮盘后 200ms ease-out 平滑回到 idle）。Halo 处于 idle 状态时空槽完全静止，不再每槽跑一个 `repeatForever` 动画。Reduce Motion 开启时永远静止，仅以"较亮"色态作为"wheel 被 hover"的静态提示。

提交空瓣 → 弹出 Pin 选择面板（普通 macOS sheet），允许从运行中的 app 列表里钉一个到该槽。

### 3.7 Launching（目标 app 未运行）

- 瓣符号：半透明 `rgba(255,255,255,0.45)`
- 状态点：灰 `rgba(255,255,255,0.30)`
- commit 后：瓣内 6×6 spinner，最多 1.5s，超时 → Failed

### 3.8 Failed（上次切换失败 / app 已卸载）

- 状态点：红 `#FF453A`
- commit 时：Halo 整体 80ms 水平摇晃 × 2（不变形，仅 transform: translateX(±3pt)）
- 频率计数不增加

### 3.9 Tutorial overlay（仅首次召唤）

```
   ╭──────────────────────────╮
   │  ↑                       │
   │ ←   N 瓣 Halo 透出 18%   →│
   │  ↓                       │
   │  移动鼠标 / 按方向键 → 选择 │
   │  松开 → 切换 · ESC → 取消  │
   ╰──────────────────────────╯
```

- 半透明黑覆盖 `rgba(0,0,0,0.55)`，让 Halo 透出 18%
- 中心 4 个方向箭头（柔和动画指示）
- 底部 Geist 中文说明文字
- 8s 后自动消失；点击任意位置立即消失

## 4. 调色与身份色

### 4.1 中性色调色板（Liquid glass）

| Token | Value | 用途 |
| --- | --- | --- |
| `halo-glass-light` | `white @ 9%` | 凸面高光（depth gradient 亮端） |
| `halo-glass-mid` | `white @ 2%` | 中段过渡 |
| `halo-glass-edge` | `black @ 22%` | 凸面暗端（rim 向内的过渡） |
| `halo-weight` | `black @ 26%` | 底部 weight 渐变，玻璃"坠感" |
| `halo-rim-top` | `white @ 34%` | rim stroke 顶端（受光） |
| `halo-rim-mid` | `white @ 10%` | rim stroke 中段 |
| `halo-rim-bot` | `white @ 2%` | rim stroke 底端（阴影） |
| `halo-specular-peak` | `white @ 88%` | 12 点 specular 弧中段亮度（Unreleased: 78 → 88，让高光在 OLED weight-shadow 上仍读得到） |
| `hub-fill` | `black @ 32%` | 中心 lens 基底（Unreleased: 48 → 32，hub 不再像"黑洞"，凹陷感由 rim + inner shadow 承担） |
| `hub-inner-shadow` | `black @ 40%` | 上缘内阴影 gradient 头端（Unreleased: 55 → 40，配合 hub-fill 弱化） |
| `hub-rim-top` | `white @ 24%` | lens rim 顶端 |
| `hub-rim-bot` | `white @ 6%` | lens rim 底端 |
| `hub-specular` | `white @ 48%` | lens 顶部 specular |
| `slot-idle-fill` | `white @ 1.5%` | 瓣默认填色（近乎不可见） |
| `label-capsule-fill` | `white @ 6% over hudWindow blur` | 弧外 label 胶囊 |
| `label-capsule-rim` | `white @ 28% → 4%` 线性 | 胶囊 rim stroke |
| `text-primary` | `white @ 96%` | label 主文本 |
| `text-secondary` | `white @ 55%` | 预留 |
| `text-tertiary` | `white @ 30%` | 占位 / 提示 |

身份色接入点（见 §4.2 / §4.3）：
- 瓣 hover fill：`accent @ 10%`
- 瓣 preview fill：`accent @ 16%`
- 瓣 active 内发光：`accent @ 55%` 6pt stroke + `blur(8)` masked by sector（Unreleased: blur 4 → 8，让"光晕"散开成"lit from within"，不再像贴片）
- 整盘 content tint：`accent @ 5%` `plusLighter`
- 外圈 halo：`accent @ 32% → 0%` radial，`blur(18)`
- commit vignette ripple：`accent`（见 §6）

> Unreleased 起，瓣 idle stroke 与 active 1.4pt 硬 accent stroke 都已移除。idle 状态完全靠 `SectorShape` 的 1° 角度间隙做"分槽"提示；active 状态靠上面的 inner glow + sector hover fill + slot icon 1.08× 缩放共同表达，避免在玻璃盘上生硬地画 8 条径向线。

### 4.2 取色策略（v1.1：移除 Hue-8 与饱和度兜底）

> **每个 app 的身份色 = 它自己 icon 提取出来的颜色。** 不再有固定 Hue-8 调色板，不再有"饱和度过低就借色"的兜底。Spotify 永远是 Spotify 自己的绿，Slack 永远是 Slack 自己的粉；Dia / Notion / Terminal 这类柔和或近灰度的 icon 也展示它们提取出来的淡色，而不是被替换成 palette 里的鲜艳色。

提取算法（`DominantColorExtractor`）：24-bin 色相直方图，按 `chroma × alpha` 加权，排除：
- alpha ≤ 0.5（透明边）
- 像素 chroma ≤ 0.04（近灰度像素）
- 像素 lightness ≤ 0.20 或 ≥ 0.92（纯黑/纯白背景）

返回提取胜出 bin 的加权 RGB 平均值的 OKLCH 表示。

### 4.3 身份色注入规则

- **默认源**：app icon dominant color（见 §4.2）
- **空槽 / 提取彻底失败**：chroma-0 中性灰（`oklch(65% 0 0)`），sector 不带色相
- **冲突阈值**：两槽身份色色相差 < `360°/N × 0.6` 即视为冲突
  - N=4 → 阈值 54°
  - N=6 → 阈值 36°
  - N=8 → 阈值 27°
  - N=10 → 阈值 21.6°
  - N=12 → 阈值 18°
- **冲突解算**：按真实激活频次锁定，高频保留原色，低频沿色相环推 `360°/N × 0.4` 度（仅推 hue，不动 lightness / chroma）。chroma-0 中性槽不参与推送。
- **用户覆盖**：Settings 中的 colorwell 始终最高优先级——任何 app 都可以手动指定身份色或重置回 icon 提取色

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
| App 内 UI（Halo / Settings） | SF Pro Text / SF Pro Display | macOS native，与系统 HUD 一致 |
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

Halo 内部字号：
- 弧外 label（hover 时显示的 app 名）：SF Pro Medium 12pt，`rgba(255,255,255,0.94)`
- 瓣内无文字；状态仅靠图标 + 状态点表达

### 5.3 间距与圆角

| Token | px |
| --- | --- |
| `--r-halo` | 140 (即半径) |
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
   屏幕中心 (Halo 召唤位置)
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
- z-index 高于 Halo，低于系统 menu bar

ripple 不在 hover/preview 阶段出现；它专门标记"我刚刚做出了选择"这一瞬间。

## 7. 暗色与浅色

**仅 Dark**。Halo 永远暗色玻璃，无浅色变体。理由：

1. Halo 是 transient overlay，需要与任意 app（白底、黑底、彩色）共存
2. 暗色玻璃在浅色 / 深色背景上都能维持视觉对比
3. macOS 系统 HUD（Spotlight、Volume、Brightness）传统都是深色玻璃

身份色饱和度针对深底已校准；切到浅色 Halo 会需要全新调色，**不在 v1 计划内**。

## 8. 资产清单

| 资产 | 状态 | 备注 |
| --- | --- | --- |
| 8 槽几何 SVG | 在 `mockups/halo.html` 中由 JS 生成 | 后续可固化为 `.svg` 资源 |
| Settings 视觉稿 | 已落地 | 见 `mockups/halo-settings.html`(v1.1) |
| 菜单栏图标 | TBD | template image(黑白 PDF) |
| App icon 占位符号集(mockup) | 见 `mockups/halo.html` | ✈ 𝐅 # ✓ ◇ ♫ ◎ ▷ |
