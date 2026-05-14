# Halo — 产品设计

> 状态: v1.1 已发布 (2026-05-14). 文档基线 = 实现; 与 [INTERACTION.md](INTERACTION.md) / [VISUAL.md](VISUAL.md) / [SETTING.md](SETTING.md) 配套.
> 主语言: 中文.
>
> **v1.1 实施备注**:
> - §7 取色策略已删除 Hue-8 调色板降级 (现在每个 app 完全用自己 icon 提取的颜色, 极端低饱和的 icon 也显示淡色而不是借色), 详见 [VISUAL.md §4.2](VISUAL.md).
> - §11 路线图标的 v0.1 / v0.2 / v0.3 已全部落地. 当前发版基线 v1.1: 新增 Whitelist tab、5 选 1 双击触发、panelScale 缩放、scroll-cycle、digit-key 提交、frontmost 滚轮锚定、async Switcher outcome、AX 权限探测; 仍 deferred: 多 profile 切换、动效与音效组、AX-powered 窗口标题预览.
> - 触发器扩展: 单击 chord (默认 `⌘⌥ Space`) + 双击辅助键 (5 选 1: ⌥-L / ⌥-R / ⌘ / ⌃ / Mouse 3 Middle, 默认 ⌘).

## 1. 概览

Halo 是一个 macOS 径向应用启动器（radial launcher），灵感来自解谜游戏 *Hue* 的色环切换机制。按住快捷键召唤一个圆形 Halo，方向定向 Top-N 高频应用（**N 可配置 4–12，默认 8**），松开即切过去。

**形态：独立 macOS App。** 开箱即用，不需要辅助功能权限（AX）就能完成核心切换。AX 是可选增强，只在用户希望看到目标 app 的最近窗口标题时才需要授权。

## 2. 为什么要做

`⌘Tab` 是线性列表，按住才能看见，松开就走人 — 一旦记错位置就要重新唤起；Dock 要鼠标横扫；Raycast 类要键入。这三类都没有为"我有 6–8 个 app 真的天天用"这个普遍场景提供一个**纯肌肉记忆**的入口。

Halo 把 Hue 游戏里"色 = 上下文"的把戏借过来：**每个高频 app 占圆环里一个固定方位 + 一个稳定身份色**，位置 + 颜色 = 一次性识别，无需眼睛扫描列表，方向键 / 鼠标方向都能击中。

## 3. 灵感：Hue 的核心机制

游戏 *Hue*（Curve Digital, 2016）的核心是 8 色色环：玩家旋转色盘把世界染色，与当前色相同的障碍融入背景消失。Halo 借三件事：

1. **径向 ≠ 线性**：8 个方向比一维序列承载更多肌肉记忆。
2. **选中即整体染色**：被选 app 的身份色短暂接管视觉环境，给出强反馈。
3. **可逆**：来回切只是换色，没有破坏操作。

## 4. 目标用户与场景

| 是 | 不是 |
| --- | --- |
| 每天反复在 5–10 个固定 app 之间切换的工程师 / 设计师 / 写作者 | 偶尔用、一周一次的长尾 app 用户（这是 Spotlight / Raycast 的事） |
| 已有 Dock / `⌘Tab` 肌肉记忆但觉得不够快的人 | 完全不在意切换效率、靠 Mission Control 的人 |
| 想用方位 + 颜色双通道形成肌肉记忆的人 | 重度多 Space / Stage Manager 用户（Halo 不竞争，是补位） |

典型路径：写代码（Cursor）→ 看文档（Safari）→ 回消息（Slack / Telegram）→ 看图（Figma）→ 回代码 ↻

## 5. 架构

- Bundle id：`com.halo.launcher`
- `LSUIElement = true`，无 Dock 图标，只在菜单栏有一个小图标
- 切换实现：`NSWorkspace.shared.runningApplications` 查表 → 命中走 `NSRunningApplication.activate(options:)`；未运行则走 `NSWorkspace.launchApplication(_:)` 启动
- **不需要 Accessibility 权限**就能完成 §8 列出的所有 MVP 能力
- AX 是**可选增强**：用户授权后才能读取目标 app 的最近窗口标题（用于 [INTERACTION §4.2](INTERACTION.md#42-二级反馈hover--300ms) 的弧形 tooltip）
- 频率统计监听 `NSWorkspaceDidActivateApplicationNotification`，本地 `UserDefaults` 持久化，**完全无网络**
- 不写第三方 app 的任何状态；不修改其他 app 的窗口几何；不挂全局 input hook

### 5.1 模块划分

```
HaloApp           ← 独立 App target（main entry、菜单栏图标、Settings 窗口）
HaloCore          ← 核心库（无 UI 依赖，可单测）
  ├ HaloEngine        Top-N 频率选择、Pin 优先级
  ├ UsageStore        UserDefaults 持久化、衰减、统计
  ├ AppIdentityColor  Icon 取色 + 冲突解算
  └ Switcher          NSWorkspace 切换封装
HaloUI            ← SwiftUI 视图
  ├ RadialView        N 瓣几何与渲染（N 来自配置）
  ├ HaloWindow        Halo NSWindow + level / behavior
  └ Hotkey            全局快捷键注册（Carbon HotKey 或等价方案）
```

切换由 `Switcher.switchTo(bundleID:)` 一个入口完成。UI 与频率 / 取色解耦，便于单测。

## 6. Top-N 频率模型

```
score(app) = α · normalize(activations_7d)
           + β · recency_decay(last_used)
           + γ · pin_bonus
α = 0.6, β = 0.3, γ = ∞ if pinned
```

- 监听 `NSWorkspaceDidActivateApplicationNotification` 累计激活次数
- 7 天滚动窗口；7 天外指数衰减
- **槽位数 N 可配置 4–12，默认 8**
- 槽位分配：前 `⌈N × 0.6⌉` 走 **MFU**（最常用），后 `⌊N × 0.4⌋` 走 **MRU**（最近用过但 MFU 没排进的兜底）
  - N=4: 3 MFU + 1 MRU
  - N=6: 4 MFU + 2 MRU
  - N=8: 5 MFU + 3 MRU （默认）
  - N=10: 6 MFU + 4 MRU
  - N=12: 8 MFU + 4 MRU
- 用户可 **Pin** 任意 app 到固定槽位（替代该槽的自动选择）
- 设置只暴露三档：`MFU only` / `Balanced（默认）` / `MRU only`，不暴露 α / β 数值
- 更改 N：Pin 关系跟 app 走，不丢失；未 Pin 的槽位按新 N 重排

## 7. 应用身份色

- 默认从 app icon 自动提取主色（CoreImage + 主导色聚类）
- 冲突解决：相邻方位身份色色相差 < 30° 时，自动把**较高频的那个保留原色**，较低频的**沿色环互推 ±15° 色相**
- 用户可在 Settings 覆盖任意 app 的身份色
- 调色板降级：极端低饱和图标（如纯灰）→ 落到预置 8 色（aqua / navy / purple / pink / orange / red / yellow / green，与 Hue 同源）

## 8. MVP 范围

v0.1 只做以下能力，其余明确推后：

1. 全局 hotkey 长按召唤、松开提交、ESC 取消
2. N 瓣径向 Halo（**N=4–12，Settings 可配，默认 8**），槽位稳定，按身份色高亮
3. Top-N 频率排序 + Pin
4. 鼠标方向 + 键盘方向 + 数字键直选（1–9/0，N>10 时仅前 10 槽可直选）
5. 独立 macOS App + 菜单栏图标 + LaunchAgent 自启
6. 极简 Settings 窗口：hotkey、**槽位数 N**、Pin、配色覆盖、MFU / Balanced / MRU 三档
7. 首次运行教学层（叠加一次性 8 秒说明）

## 9. 明确非目标

- 不做命令面板（Raycast / Alfred 已经做得很好）
- 不做文件 / Web 搜索
- 不做 plugin / extension 生态
- 不做云同步（v1 本机 `UserDefaults`；跨设备 v0.4 再说）
- 不做 Touch Bar / Apple Watch 入口
- 不替代 `⌘Tab`：用户应该可以两者并存

## 10. 命名与品牌

- 项目名 / 产品名：**Halo**（圆环、光晕；与"染色"反馈呼应；好记）
- Bundle id：`com.halo.launcher`
- 中文称呼：**Halo 启动器**
- 视觉基调：玻璃材质、暗色 Halo、身份色高亮、动效短促克制

## 11. 路线图

| 版本 | 内容 |
| --- | --- |
| v0.1 | MVP（见 §8）：召唤、切换、Top-N（4–12，默认 8）、Pin、配色、Settings、教学 |
| v0.2 | 次级弧：hover 一瓣展开该 app 最近窗口列表（需可选 AX 授权） |
| v0.3 | 双环模式：hover 单槽 ≥ 400ms → 外环展开该 app 的最近 5 个窗口；解决"同一 app 多窗口"切换 |
| v0.4 | 跨设备 Pin / 配色同步（iCloud KV-Store） |
| v0.5 | Mac App Store 上架可行性评估（核心路径不依赖 AX，本应可上） |

## 12. 风险与未决

| # | 项 | 备注 |
| --- | --- | --- |
| R1 | hotkey 与系统 / 其他 App 冲突 | Settings 提供冲突检测与改键 |
| R2 | 自动取色对部分应用（深色 icon、纯灰）效果差 | 8 色 fallback + 用户覆盖 |
| R3 | `NSWorkspace.activate` 在某些 sandbox 应用下行为不一致 | v0.1 验证 Safari / Cursor / Slack / Figma / 终端 / Mail / Notes / Finder 八个常见目标 |
| R4 | 频率统计冷启动期数据不足 | 首次运行引导 Pin；7 天前虚线槽 + "+" |
| R5 | 长按 hotkey 与"短按 = Quick Swap"如何不打架 | 200ms 阈值；超过即进入 Halo，未超过则按短按语义切上一个 app |
| R6 | 用户频繁改 N 会扰乱已建立的肌肉记忆 | 默认从 8 起步，建议至少 2 周后再调整；Settings 改 N 时弹一次提示"会重排未 Pin 槽位"；Pin 跟 app 走，不丢失 |
