# Halo 设置看板设计文档

本文档定义 Halo 设置面板（`HaloApp/SettingsWindow.swift` 承载）的信息结构、配置项与默认策略。设计目标是让用户在不理解内部概念的情况下，能快速完成"如何召唤 Halo、Halo 如何呈现、在哪些应用里被抑制"的基础设置。

> **v1.1 实施状态 (2026-05)：** §2.1 / §2.2 / §2.3 / §2.4（含 panelScale） / §2.6 / §2.7 / §3.1 / §3.2 / §3.3 / §4 / §5 已落地。设置窗口已改为 sidebar nav + 720×620（不再是 §1 写的 TabView / 560×540），以 `mockups/halo-settings.html` 为视觉契约。§2.5 反馈与动效仍为 roadmap；§3 多 profile 仍为 roadmap。

## 1. 总体结构

设置面板以 macOS 原生 `TabView` 形式打开，固定四个 Tab：

| Tab | 主题 | 何时使用 |
|---|---|---|
| 通用 | 召唤、外观、行为 | 第一次打开默认进入；日常调整都在这里 |
| Apps | 槽位绑定与应用配色 | 想把常用 App 固定到方向上，或修改 identity color |
| 白名单 | 在指定应用内抑制 Halo | 排除会和触发键冲突的应用（IDE、游戏、远程桌面、设计软件） |
| 关于 | 版本、链接、许可证 | 升级时核对版本，提交反馈 |

窗口尺寸固定 `560 × 540`，不允许全屏与缩放，便于在多显示器场景下随光标所在屏幕居中弹出。

## 2. 通用 Tab

按"召唤 → 触发 → 外观 → 启动 → 语言"自上而下排布，使用 grouped `Form` 分组。

### 2.1 召唤位置与排序

| 配置项 | 控件 | 默认 | 说明 |
|---|---|---|---|
| 槽位数量 | Segmented(`4 / 6 / 8 / 10 / 12`) | `8` | 决定 Halo 一次性展示的方向数，与触屏精度、屏幕大小相关 |
| 召唤位置 | Segmented(`光标 / 屏幕中心`) | `光标` | 影响召唤后视线/手感的连续性，桌面浏览者建议保留默认 |
| 频次模型 | Segmented(`MFU / Balanced / MRU`) | `Balanced` | 控制空槽如何被自动填充：高频优先、混合、近期优先 |

设计说明：
- 槽位数量改变会立即触发 `AppDelegate.applyPreferences()` 重排绑定，因此提供 `4–12` 即可，过多反而破坏角度可辨识度。
- "频次模型"是 Halo 与传统 Dock/Launchpad 的核心差异之一，应作为通用项暴露给用户，而不是埋到高级里。

### 2.2 触发键

| 配置项 | 控件 | 默认 | 说明 |
|---|---|---|---|
| 召唤快捷键 | Chord capture | `⌘⌥ Space` | 按下召唤、松开提交所在槽位 |
| 重置到默认 | Button | — | 回到 `⌘⌥ Space` |
| 双击触发键 | Popup | `⌘ Command` | 第二条触发路径所用的键，见下表五选一 |
| 双击间隔 | Slider `0.15 – 0.50s` | `0.30s` | 两次点按之间必须落入的窗口；超出视为单击，不召唤 |

#### 双击触发键候选

| 选项 | 显示标签 | 事件源 | 适用 |
|---|---|---|---|
| `.leftOption` | `⌥ Option (Left)` | `flagsChanged` + `keyCode == 58` | 重度使用 `⌘` 类编辑快捷键的人，把左 ⌥ 让给 Halo |
| `.rightOption` | `⌥ Option (Right)` | `flagsChanged` + `keyCode == 61` | 中文输入习惯用左手、右手 ⌥ 几乎空闲的人 |
| `.command` | `⌘ Command` | `flagsChanged` + `keyCode == 54/55` | 默认；与现有 `CommandLongPressMonitor` 行为一致 |
| `.control` | `⌃ Control` | `flagsChanged` + `keyCode == 59/62` | 接受 emacs 风格 `⌃` 习惯，且不常用 Mission Control 自定义快捷键的人 |
| `.middleMouse` | `Mouse 3 (Middle)` | `otherMouseDown` + `buttonNumber == 2` | 配有可编程鼠标的桌面用户；可绕开所有键盘修饰冲突 |

交互逻辑：
- **主触发**：按住自定义 chord 召唤 Halo，移动鼠标/方向键到目标扇区，松开任一修饰键提交。
- **辅助触发**：单独双击上面选中的键。第一次点按建立 sentinel，必须在"双击间隔"内完成第二次点按；按住第二次期间可继续导航，松开即提交。
- 左/右 Option 通过设备相关 keyCode（`58 / 61`）区分，不依赖 `NSEvent.ModifierFlags.option`（后者无法区分左右）。
- 中键路径不依赖任何 modifier，因此和键盘组合键完全正交；但与浏览器/终端的"中键粘贴 / 新标签"语义冲突，UI 上需提示用户先在白名单里排除这些 App。
- chord capture 行 chip 在采集态使用 Liquid Glass tint（系统强调色），明确"现在请按下组合键"。

设计建议：
- chord 至少需要一个修饰键，否则 capture 视图直接 `NSSound.beep()` 拒绝。
- 默认 `⌘⌥ Space` chord + `⌘` 双击的组合保留现状，已升级用户无感知。新增的左右 Option / Control / Mouse 3 选项默认收起在 Popup 后面，避免新用户被淹没。
- 不建议主 chord 默认是 `⌥ Any`（与 IDE 冲突太严重，见 §4 白名单设计动机）。
- 选择 `.middleMouse` 时，"双击间隔"语义仍然成立——两次中键按下之间必须落入窗口；这是和键盘路径行为对齐的关键。

实现钩子：
- `AppPreferences` 增 `doubleTapTrigger: DoubleTapTrigger` 枚举与 `doubleTapGap`（沿用 `cmdDoubleTapGap` 存储键以保持迁移兼容）。
- 把 `CommandLongPressMonitor` 重命名/泛化为 `DoubleTapMonitor`，按枚举值切换内部状态机：键盘路径监听 `flagsChanged`，鼠标路径监听 `otherMouseDown`。
- 选项切换需要重建事件 tap（中键路径需要 `.otherMouseDown` mask，键盘路径不需要）。

### 2.3 导航与切换

Halo 召唤后，除了"移动鼠标到目标方向"这条主路径外，还提供两条辅助选择路径：

| 配置项 | 控件 | 默认 | 说明 |
|---|---|---|---|
| 滚轮切换槽位 | Toggle | 开 | 鼠标滚轮 / 触控板双指上下，按滚动方向在当前 Halo 内依次切换槽位 |
| 数字键提交 | Toggle | 开 | 直接按 `1 2 3 … 9 0 - =` 选中并提交对应槽位，等价于松开触发键 |
| 召唤时高亮 frontmost | Toggle | 开 | 召唤瞬间把"选中"落在当前 frontmost App 所在的槽；该 App 未被 pin 时回落到 12 点方向 |

交互逻辑：

- **滚轮切换**：以"选中槽"为锚点，向下滚（`deltaY < 0`）顺时针前进一格，向上滚（`deltaY > 0`）逆时针。需要做事件去抖（建议 `> 4` 行才视为一次"切换"），避免触控板惯性滚出多格。滚动期间不消费事件转发给系统，因为 Halo 是 overlay 焦点窗，无下游接收方。
- **数字键映射**：`1 2 3 4 5 6 7 8 9 0 - =` 对应槽 1–12。槽位数量小于 12 时多余键无效；按下任一映射键即立即提交，与"松开触发键提交"语义一致。
  - 数字键提交不要求继续按住触发键，但触发键仍在按下态时按数字键，也走同一路径，方便单手操作。
  - `0 / - / =` 在国际键盘上位置一致，无需根据 layout 适配。
- **从当前应用开始滚动**：召唤时如果 frontmost 的 bundle ID 在 `pinnedBundleIDs` 中，把它对应的 slot index 设为初始选中；否则用 slot 0（北向）。这让"先 Halo，再滚一格切回上一个 App"成为可能。

实现钩子：
- `AppPreferences` 增 `scrollToSwitch: Bool` / `numberKeyCommit: Bool` / `highlightFrontmostOnSummon: Bool`。
- `HaloState` 暴露 `advanceSelection(by: Int)` 与 `commit(slotIndex: Int)`，由 `HaloWindow` 的 scrollWheel / keyDown 事件转发调用。
- 召唤路径里把"初始选中索引"从硬编码 0 改为基于 frontmost 计算。

### 2.4 外观与轮盘布局

| 配置项 | 控件 | 默认 | 范围 | 说明 |
|---|---|---|---|---|
| 面板大小 | Slider `x` | `1.00x` | `0.80 – 1.50`，step `0.05` | 一个统一的缩放系数，乘到下面三项之上 |
| Halo 直径 | Slider `pt` | `380` | `280–440` | 整个圆环外径（缩放前的基准值） |
| 图标尺寸 | Slider `pt` | `48` | `36–64` | 单个 App 图标大小（缩放前的基准值） |
| 图标到圆心距离 | Slider `pt` | 自动 | `iconRadiusBounds` 计算 | 图标在径向上的位置（缩放前的基准值） |
| 重置布局 | Button | — | — | 一键回到默认四联值（含 `1.00x`） |

设计说明：
- "面板大小"是一个**渲染期统一缩放**，等价于在 Halo 视图根节点套一个 `scaleEffect(panelScale)`，不会改变三项基准 slider 的存储值。这样高 DPI 显示器、低视力用户能一键放大，而不破坏精细微调过的直径/图标尺寸比例。
- 布局变更不会立刻在设置面板内预览，需要"召唤一次 Halo"才能看到。在 Section footer 用 callout 提醒：`Summon Halo to see size changes take effect.`
- "图标到圆心距离"的上下限随 Halo 直径与图标尺寸动态变化（避免图标互相重叠或滑出环外），由 `AppPreferences.iconRadiusBounds` 计算，UI 端不允许越界。
- `panelScale` 取 `0.80 – 1.50`：再小会让 hit-test 扇区角度精度不足，再大会在 13" 屏幕上溢出可见范围。

### 2.5 反馈与动效（保留扩展位）

参考 OrbitRing 类产品，未来可在通用 Tab 内补齐以下开关，目前 Halo 尚未实现，文档先占位：

| 待引入项 | 类型 | 建议默认 | 说明 |
|---|---|---|---|
| 启用音效 | Switch | 关 | 提交/取消时的反馈音，需先评估对菜单栏工具的打扰 |
| 启用旋转动画 | Switch | 关 | 召唤/切换时圆环转入；与"响应优先"的产品价值有冲突，默认关 |
| 鼠标移出环外取消选中 | Switch | 开 | 防止鼠标越界仍然提交 |
| 隐藏当前 Halo 名称 | Switch | 关 | 控制圆心是否显示选中 App 名称 |
| 显示快捷键提示 | Switch | 开 | 在图标旁展示 `1–9` 索引 |
| 降低光晕散射 | Switch | 关 | 视觉敏感用户使用 |

> **实施状态**：本组当前未在 v1.0 实现。引入时再开一个 Effects Section，不与"布局"混排。

### 2.6 启动与诊断

| 配置项 | 控件 | 默认 | 说明 |
|---|---|---|---|
| 开机自启 | Toggle | 关 | 通过 `LaunchAgentManager.apply(enabled:)` 写入 LaunchAgent plist |
| 重播欢迎引导 | Button | — | 重新展示 `WelcomeWindow` |
| 重置 onboarding 蒙层 | Button | — | 让首次召唤的浮层提示再次出现 |
| 导出诊断日志 | Button | — | 抽取最近一小时 Halo 子系统的 unified log，写入 `~/Downloads/Halo-diagnostic-<ts>.log` 并在 Finder 中选中 |

设计说明：
- 隐藏 Dock 图标在 Halo 中是**默认开启**的（应用以 `.accessory` 政策运行），无需暴露开关。打开设置时临时升级为 `.regular` 使窗口可见，关闭后回到 `.accessory`。
- 因此参考文档中"隐藏 Dock 图标"的警告不适用 Halo，但需要在 Welcome 文案里说明菜单栏图标是唯一入口。

### 2.7 语言

| 配置项 | 控件 | 默认 | 说明 |
|---|---|---|---|
| 显示语言 | Popup(`系统 / English / 简体中文`) | `系统` | 写入 `AppleLanguages` 偏好，需重启生效 |

footer 必须明确："Restart Halo for the language change to take effect."

## 3. Apps Tab

### 3.1 默认绑定卡片

顶部一张 chip 风格的卡片：

- 左侧小圆 + `circle.dashed.inset.filled` 系统符号
- 中部："Default binding" + 摘要文案 `N pinned · M slots`
- 右侧 destructive "Clear all" 按钮（弹确认 Alert）

> 多 profile 支持（"Default / Work / Gaming…"）已在 `SettingsWindow.swift` 留 TODO，未来扩展时把这张卡片升级为 profile 切换器。

### 3.2 绑定轮盘

`BindingWheelView` 居中渲染当前槽位预览：

- 点击空槽 → 弹出 `AppPickerSheet`（搜索/列出 `/Applications` 与 `/System/Applications`）
- 点击已 pin 槽位 → 弹出操作菜单（修改 identity color / 取消 pin）
- 空槽在召唤时由频次模型自动填充

### 3.3 隐藏 Pin

当用户调小 `Slot count` 后，超出新槽位数的 pin 不会被丢弃，而是进入 `overflowPinnedBundleIDs`，在 "Hidden pins" Section 列出。提升槽位数后会自动回流。

## 4. 白名单 Tab（新增）

### 4.1 价值与场景

Halo 的核心触发路径之一是 `⌥` 或包含 `⌥` 的 chord，但 `⌥` 是高频修饰键，在以下场景容易和原生快捷键冲突：

- **IDE / 编辑器**：Xcode、VS Code、JetBrains 全家桶、Sublime、Cursor — `⌥-click`、`⌥-drag` 是多光标/列选择
- **设计工具**：Figma、Sketch、Illustrator、Photoshop — `⌥` 是复制 / 临时取色
- **3D / 游戏**：Blender、Unity、Roblox Studio、各类原生游戏 — `⌥` 是旋转视角或绑定动作
- **远程桌面 / 虚拟化**：Parallels、VMware、Microsoft Remote Desktop、Citrix — 任何召唤都意味着把按键吃掉，远端进程收不到

白名单的语义是：**当前 frontmost 应用属于白名单时，HaloHotkey 与 CommandLongPressMonitor 都直接忽略事件，不召唤 Halo**。

### 4.2 数据模型

新增偏好键 `halo.prefs.whitelist.v1`（`[String]`，存 bundle ID）：

```swift
public var whitelistedBundleIDs: [String]
public func isHaloSuppressed(forFrontmost bundleID: String?) -> Bool
```

抑制判定在 `HaloHotkey` / `CommandLongPressMonitor` 的事件 tap 内联调用，确保事件不被消费、能正常下传给目标 App。

### 4.3 UI 结构

```
┌─ 白名单 ─────────────────────────────────┐
│ ⓘ 在这些 App 中不会召唤 Halo。           │
│   适合排除 IDE、游戏、远程桌面、设计软件。│
├──────────────────────────────────────────┤
│ [icon] Xcode               com.apple.dt… │
│ [icon] VS Code             com.microsoft…│
│ [icon] Figma               com.figma.Des…│
│ ...                                       │
├──────────────────────────────────────────┤
│ [ + 添加…] [ — 移除]   [ 恢复推荐 ]       │
└──────────────────────────────────────────┘
```

控件细节：

| 元素 | 行为 |
|---|---|
| 顶部说明条 | 简短一句话 + 一句示例，不展开成段落 |
| 应用列表 | 复用 `AppsTab` 中 `Hidden pins` 的行样式：icon + 显示名 + bundle ID(monospaced caption)，单选 |
| `+ 添加…` | 弹 `AppPickerSheet`（复用），选中后 append；已存在的 bundle ID 在 picker 中标灰禁选 |
| `— 移除` | 移除当前选中行；多选支持后续迭代 |
| `恢复推荐` | 用 §4.4 的内置列表覆写当前白名单（弹确认 Alert，因为是 destructive） |

空状态：列表为空时用 placeholder `"暂无白名单 — 在 IDE 或游戏里 Halo 会照常召唤"` + 主按钮 `应用推荐白名单`，让新用户一键到位。

### 4.4 推荐白名单（首次启动种子）

首次启动且未导入旧偏好时，预置以下 bundle ID（在系统里存在才生效，避免空 icon 占位）：

| 类型 | Bundle ID |
|---|---|
| Apple IDE | `com.apple.dt.Xcode` |
| VS Code 系 | `com.microsoft.VSCode` `com.todesktop.230313mzl4w4u92` (Cursor) `com.vscodium` |
| JetBrains | `com.jetbrains.intellij` `com.jetbrains.pycharm` `com.jetbrains.WebStorm` `com.jetbrains.goland` `com.jetbrains.rider` `com.jetbrains.AppCode` |
| 设计 | `com.figma.Desktop` `com.bohemiancoding.sketch3` `com.adobe.illustrator` `com.adobe.Photoshop` |
| 3D / 游戏引擎 | `org.blenderfoundation.blender` `com.unity3d.UnityEditor5.x` `com.Roblox.RobloxStudio` |
| 远程桌面 | `com.parallels.desktop.console` `com.vmware.fusion` `com.microsoft.rdc.macos` |

> 实际 bundle ID 以仓库中预置的 `WhitelistSuggestions.swift` 为准；上表用于产品文档，落地时按用户系统已安装的子集生效。

### 4.5 与 Apps Tab 的关系

白名单与 Apps Tab 是**正交**的两个维度：

- **Apps Tab**：定义 Halo 召唤时**展示**哪些 App（pin + 频次填充）
- **白名单 Tab**：定义 Halo 在**哪些 App 内**完全不召唤（不论 pin 状态）

两者偏好独立持久化，不互相覆盖。如果用户在 Cursor 里 pin 了 Xcode，但又把 Xcode 加进白名单，那么"在 Xcode 内不召唤 Halo"成立、"在 Cursor 内召唤 Halo 时仍能看到 Xcode 槽位"也成立。

## 5. 关于 Tab

保持现状：

- 系统符号 `circle.dashed.inset.filled` 作为 logo
- 大标题 `Halo` + monospaced 版本号 `v\(Halo.version)`
- 一句产品定位：`Radial app launcher for macOS — point a direction, switch apps.`
- 链接：GitHub 仓库、MIT 许可证

引入白名单后无需新增字段。如果未来加入"反馈"链接，可以放在 GitHub / License 之间，用 `·` 分隔保持现有视觉节奏。

## 6. 默认配置策略

Halo 倾向于"开箱即用、低惊讶"：

- 触发：`⌘⌥ Space` chord + `⌘` 双击两条路径都开启，避免单一路径冲突时无法召唤。
- 召唤位置：光标处，减少视线跳跃。
- 频次模型：Balanced，新用户能立刻看到熟悉的 App，老用户能看到近期切换的。
- 动效：关，响应优先。
- 自启：关，避免未授权前提下静默驻留菜单栏。
- 白名单：种子推荐空（v1）或最小集（v1.1+），让用户自己决定要不要排除哪些工具。

## 7. 风险与改进建议

主要风险：

1. **触发键冲突**：即使白名单存在，用户仍可能在非白名单 App 中触发 IDE 快捷键。建议在 Welcome 引导中先让用户挑一个 chord 模板（`⌘⌥ Space` / `⌘ Space` 替代方案 / `⌃⌥ Space`）。
2. **白名单首启空集**：v1 默认不预置，避免误判用户习惯；v1.1 可在 onboarding 检测到 IDE 进程存在时弹出"是否一键把这些应用加入白名单"。
3. **多 profile**：当前 Apps 只有 "Default binding"，长期来看"工作 / 娱乐 / 远程"三个 profile + 白名单组合最能满足跨场景需求；SettingsWindow.swift 已留 TODO。
4. **诊断入口的可发现性**：Export diagnostic log 目前埋在通用 Tab 底部，提交 issue 时不易被引导到；未来可考虑在 About Tab 里也并列一个入口。

建议下一步：

- 在 `AppPreferences` 中落 `whitelistedBundleIDs` 与 `isHaloSuppressed(forFrontmost:)`。
- 在 `HaloHotkey` 与 `CommandLongPressMonitor` 的事件入口处插入抑制判断，确保事件不被消费。
- 给 chord capture 与白名单"恢复推荐"两个高影响操作补充 tooltip 或 Alert 说明。
- 把 §2.4 反馈与动效组放进 roadmap，下一次 settings 迭代时打开。
