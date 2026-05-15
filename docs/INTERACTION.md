# Halo — 交互规格

> 状态: 与 v1.1 实现对齐 (2026-05-14). 配套 [PRODUCT.md](PRODUCT.md) / [SETTING.md](SETTING.md).
> 主语言: 中文.
>
> **v1.1 实施备注**:
> - §1 触发组合键已扩展为 5 选 1 双击触发器 (⌥-L / ⌥-R / ⌘ / ⌃ / Mouse 3), 默认仍是 `⌘⌥ Space` + ⌘ 双击.
> - §2 几何参数 (Halo 直径 / 图标尺寸 / 图标距中心) 已通过 Settings 暴露为用户可调; 默认值已更新.
> - §11 设置面板已重做为 sidebar 布局 (4 section), 新增 Whitelist / Panel size / Navigation 三个子区.
> - §4.2 hover 窗口标签 (AX-powered) 仍为 deferred (未实现).

## 1. 召唤（Summon）

| 触发 | 行为 |
| --- | --- |
| `⌘⌥Space`（主快捷键，默认） | **按下即召唤**（无阈值）。Halo 在鼠标位置或屏幕中心淡入（约 120ms） |
| 双击 `⌘`（单键第二入口） | 第一次 ⌘ 短按 ≤ 200ms 释放，第二次 ⌘ 按下需落在窗口内（默认 300ms，可在 Settings 中 0.15–0.50s 调整）；按下第二次 ⌘ 即召唤，松开提交 |
| 菜单栏图标点击 → "Summon Halo" | Halo 在鼠标所在显示器中心显示，常驻直到点击瓣 / ESC / 外部点击 |

召唤位置策略：

- **At cursor（默认）**：Halo 中心吸附到鼠标当前位置，撞屏幕边缘时自动反向偏移保证完整可见
- **Screen center**：Settings 中可切换为屏幕几何中心
- 多显示器：Halo 始终出现在鼠标当前所在的显示器
- 召唤时保存上一个 frontmost app；cancel 时恢复，commit 时不恢复

> 历史：v0 设计有 200ms 长按阈值 + `<200ms` 短按 Quick Swap，以及 ⌘ 单键长按 1.5s 的第二入口。两者都已替换：主热键改为"按下即触发"，把短按让渡给系统 `⌘Tab`；第二入口改为双击 ⌘——原长按容易在 ⌘+c / ⌘+v 这类 chord 里误触。

## 2. 视觉布局

槽位数 **N 可配置 4–12，默认 8**。槽 0 永远在 12 点位置，其余顺时针递增。下图按 N=8 绘制；其他 N 仅角度变化，拓扑等价。

```
          slot 0 (上 / 12 点)
              ╲     ╱
       N-1 ── ⊙ ── 1
              ╱     ╲
              slot N/2 (下 / 6 点)
```

| N | 单瓣角度 | 数字键直选 | 适用场景 |
| --- | --- | --- | --- |
| 4 | 90° | 1–4 | 极简，只盯 4 个核心 app |
| 6 | 60° | 1–6 | 写作 / 设计 |
| **8（默认）** | **45°** | **1–8** | Hue 游戏原味；多数人最佳 |
| 10 | 36° | 1–9 / 0 | 重度多 app |
| 12 | 30° | 1–9 / 0；11、12 仅方向键 / Tab | 已接近肌肉记忆上限 |

几何参数（v1.1: 大部分已支持用户调节, 这里给出默认值）：

- Halo 外盘直径: **380 pt** 默认, 用户可调 280–440 pt (Settings → 通用 → 外观)
- 中心 dead-zone 直径: **112 pt**, 显示当前 frontmost app 图标 / hover 时预览目标 app 图标 (不可调)
- 面板外框 (含呼吸 + 阴影 + label 溢出): `直径 + 200 pt`
- 面板缩放 panelScale: **1.00x** 默认, 用户可调 0.80–1.50x (整体渲染期统一缩放, hit-test 同步除以该值)
- 每瓣: `360°/N` 扇形, 瓣间 1° 角度缝隙 (沿径向切出)
- 瓣内: app icon **48 pt** 默认 (可调 36–64 pt), 居中; icon 右上角状态点
  - 绿 = app 已运行
  - 无 = app 未启动（提交时会启动）
  - 红 = 上一次切换失败
- 玻璃材质：`NSVisualEffectView`（AppKit 原生）配 `.hudWindow` 材质、`.behindWindow` 混合
- 边框：上亮下暗的线性渐变细描边 + 12 点方向一段 specular 高光弧
- 悬停瓣：身份色低透明填充 + 身份色描边 + icon 1.08× 放大 + 身份色外溢 halo

更改 N 是 Settings 中的显式动作，不在运行时漂移。Pin 关系跟 app 走，更改 N 时 Pin 不丢失，但未 Pin 的槽位按新 N 重排。

## 3. 导航

### 3.1 鼠标

- 光标离开 dead-zone 后，按光标相对中心的角度决定选中瓣
- 距离中心 > 半径 × 1.4 时仍保持选中（hover 容差，避免抖动失选）
- 不强制点击：召唤期间方向即选中（mimic Hue 手柄方向键）
- 光标重新回到 dead-zone：选中清空，等同未选

### 3.2 键盘

- 方向键 ↑↓←→：按角度找最近的槽
- 方向键组合（↑+→ 等，物理上同时按）：斜向；N=4 时退化为正交
- 数字键直选：
  - N ≤ 9：`1`–`N` 直选（按上方为 1，顺时针）
  - N = 10：`1`–`9` + `0`（=10）
  - N = 11–12：`1`–`9` + `0` 覆盖前 10 槽；第 11、12 槽用方向键 / Tab 触达
- `Tab` / `Shift+Tab`：顺时针 / 逆时针单步移动
- `Return` / `Space`：提交当前选中
- `ESC`：取消

### 3.3 触控板

- 双指滑动：等价于鼠标移动
- 单指轻点瓣：直接提交（不需要先 hover）

## 4. 预览（hover）

### 4.1 一级反馈（hover ≥ 120ms）

- 瓣本体亮起：身份色 inner radial 渐变填充、内侧 6pt 光晕（accent @ 55% + `blur(8)`）。v1.2.x 起不再画 1.4pt accent 描边，让"亮起"读为"lit from within"而不是"框选"
- 中心 dead-zone 图标淡出，**替换为该瓣 app 的图标**（让用户预览即将到达的目的地）
- Halo 玻璃材质底色微弱注入身份色（5% 混合）
- Halo 外圈薄薄一圈光晕沿屏幕径向外溢（10pt 高斯模糊 + 身份色 ×20% 透明度），让选择感"漏出"Halo 边界

### 4.2 二级反馈（hover ≥ 300ms）

仅在用户已授权 Accessibility（可选权限）时启用：

- 弧形 tooltip 沿瓣外沿展开，显示该 app 的最近 3 条窗口标题
- 文本字体：SF Pro 11pt，沿弧线排版
- 一级反馈与二级反馈可同时共存

未授权 AX 时整体降级为只显示 app 名作为单条 tooltip。

### 4.3 离开瓣

光标离开瓣或回到 dead-zone：200ms 内回弹到默认态，Halo 底色身份色淡出。

## 5. 提交与取消

### 5.1 提交

| 触发 | 条件 |
| --- | --- |
| 松开 hotkey（⌘⌥Space 或双击 ⌘ 的第二次按下） | 当前选中瓣 ≠ 中心 dead-zone |
| 鼠标点击某瓣 | 任何召唤路径都可触发（尤其是菜单栏召唤） |
| 按数字键 `1`–`9` / `0` | 直接提交对应槽位（跳过 hover 时间） |
| `Return` / `Space` | 当前选中瓣 ≠ 空 |

提交实现（v1.3）：

1. `state.phase = .committing(i)`，选中瓣放大到 1.06×
2. **先 fire ripple、再 dismiss Halo、最后调用 `Switcher.switchTo`**（顺序关键——如果先切换，目标 App 会抢焦点让 Halo 被系统立刻隐藏，fade-out 来不及播）
3. `Switcher` 走 `NSWorkspace.openApplication(at:configuration:)`，fire-and-forget，不阻塞主线程
4. Halo fade-out 120ms；commit ripple 从 Halo 中心向外扩散 ~320ms
5. 频率统计 +1 通过 `NSWorkspaceDidActivateApplicationNotification` 异步累加

> v1.2 曾因 `NSRunningApplication.activate(options:)` 在 cooperative activation 下静默失败而"松手后不切换"。已切换到 `NSWorkspace.openApplication`。

### 5.2 取消

| 触发 | 条件 |
| --- | --- |
| `ESC` | 任何时刻 |
| 松开 hotkey 且光标在 dead-zone | 选中即空 |
| Halo 外部点击 | 仅菜单栏召唤模式 |
| 失去键盘焦点（如系统弹窗强夺） | 自动取消 |

取消动作：

1. Halo 淡出（100ms，比提交快）
2. 不触发切换、不增加频率计数
3. 无 vignette 反馈，区别于提交

## 6. 状态机

```
                ┌─────────┐
                │ hidden  │ ◄─────────────────────┐
                └────┬────┘                       │
                     │ summon                     │
                     ▼                            │
                ┌─────────┐                       │
                │summoning│ ── 150ms ──┐          │
                └─────────┘            │          │
                                       ▼          │
                                ┌──────────┐      │
                       ┌────────┤   idle   │      │
                       │        │(center)  │      │
                       │        └────┬─────┘      │
                       │             │ direction  │
                       │             ▼            │
                       │       ┌──────────┐       │
                       │       │ hovering │       │
                       │       │  slot N  │       │
                       │       └────┬─────┘       │
                       │            │ 120ms       │
                       │            ▼             │
                       │      ┌──────────┐        │
                       │      │previewing│        │
                       │      │  slot N  │        │
                       │      └─┬───┬────┘        │
                       │ cancel │   │ commit      │
                       │        │   ▼             │
                       │        │ ┌──────────┐    │
                       │        │ │committing│    │
                       │        │ └────┬─────┘    │
                       │        │      │ 150ms    │
                       │        │      ▼          │
                       │  ┌─────▼──┐ + switch ────┤
                       └──┤cancelling│             │
                          └────┬────┘ 100ms       │
                               └─────────────────► (hidden)
```

任何状态下，`ESC` 都进入 `cancelling`。

## 7. 动画与时长

| 动效 | 时长 | 曲线 |
| --- | --- | --- |
| 召唤淡入 | 120ms | ease-out |
| 瓣 hover 亮起 | 100ms | ease-out（v1.2.x: 140 → 100，更"贴手"） |
| 中心图标交换 | 140ms | ease-out + 0.96 → 1.0 scale（v1.2.x: 200ms ease-in-out / 0.94→1.0 改为更脆的 echo timing） |
| 外圈 halo 光晕 | 100ms | ease-out（与 hover 同步） |
| 提交时瓣放大 | 100ms | ease-out + 1.0 → 1.06 scale |
| 提交时 vignette ripple | ~320ms | 半径扩散 + 透明度 0→峰值→0 |
| Halo 淡出（提交 / 取消） | 120ms | ease-in |
| Failed 抖动 | 40ms × 4 帧 | linear |
| Action Arc chip pop-in | spring（response 0.30 / damping 0.72） | 22ms × index stagger |
| 空槽 dashed 呼吸 | 2.4s ease-in-out（仅 wheel hover 时） | autoreverses |

> 所有时长统一通过 `Animation.Halo.snap / echo / surface / chipPop` 在 `Sources/HaloUI/Animation+Halo.swift` 集中维护；调参一键改，无需在 RadialView / ActionArcView / WelcomeWindow 间扫描。Reduce Motion 开启时全部 ease 时长收窄到 0.05s。

动画性能：panel `collectionBehavior` 去掉了 `.transient`，否则目标 app 前置会让系统立即 orderOut 吞掉 fade。`Switcher` 改为 fire-and-forget，CoreAnimation 不被 `DispatchGroup.wait` 阻塞，fade 真正可见。

## 8. 边界情况

| 情况 | 行为 |
| --- | --- |
| Top-N 不满 N 个 app（首次运行） | 不满槽位渲染为虚线轮廓 + "+"，提交时弹出 Pin 选择面板 |
| 目标 app 未运行 | 渲染半透明 icon + 灰色状态点；提交时 `NSWorkspace.launchApplication(_:)` 启动 + 瓣内 spinner |
| 目标 app 启动失败 / bundle 已删除 | 瓣状态点变红、Halo 整体抖动 2 次（80ms × 2），频率不增加 |
| 同一 app 多个实例 | v1 只切到 frontmost；v0.2 通过次级弧选窗口 |
| 当前 frontmost 就是要切的目标 | 不切换；Halo 直接淡出（no-op 无额外提示） |
| hotkey 在系统级被占用 | Settings 红色警告 + 引导改键 |
| 用户在 Halo 显示期间断开鼠标 | 切换到键盘选中，光标位置冻结在最后位置 |
| Halo 召唤时屏幕分辨率变化 | Halo 立即重新居中到鼠标所在新显示器 |
| 召唤时间已超过 5 秒仍未提交 | 继续等待（不超时）；hotkey 一旦松开即按规则提交或取消 |
| 用户在 Settings 改 N（如 8 → 12） | 立即生效，下一次召唤就是 N 槽布局；Pin 关系保留，未 Pin 的槽按新 N 重排 |
| Pin 的 app 数量超过新 N | 超出部分的 Pin 在 Settings 警告并按 Pin 时间倒序保留前 N 个，剩余 Pin 不丢失但暂不显示 |
| N=12 时第 11、12 槽 | 仅可通过方向键 / Tab / 鼠标到达，数字键不直选 |

## 9. 多显示器

- Halo 在鼠标当前所在显示器召唤
- 频率数据全局共享，不分 display
- 提交时的屏幕 vignette 仅在召唤所在 display 上绘制，不污染其他屏

## 10. 无障碍

- Halo 是 `NSAccessibilityRole.group`；每瓣是 `NSAccessibilityRole.button`，label 为 app 名
- VoiceOver：召唤后朗读 "Halo 启动器，当前选中：[app 名]"
- hover 切瓣朗读新 app 名
- 提交时朗读 "切换到 [app 名]"
- **Reduce Motion**：所有过渡降级为 50ms 淡入淡出；去掉弹簧与缩放
- **Increase Contrast**：身份色不变，描边强度 +50%；瓣间缝隙加深
- 完整支持键盘导航，鼠标永远是可选项

## 11. 设置项

> v1.1 重做: 原 5 标签 `TabView` 改为 4 section 的 sidebar (macOS 13+ 原生 `NavigationSplitView`, macOS 12 自建 HStack 回退). 默认窗口 880 × 720, 最小 760 × 600, 可缩放. 完整规格见 [docs/SETTING.md](SETTING.md).

**通用 (General)** — 6 个 group 自上而下:
1. 召唤位置与排序: 槽位数量 (4 / 6 / 8 / 10 / 12, 默认 8) · 召唤位置 (光标 / 屏幕中心, 默认光标) · 频次模型 (MFU / 平衡 / MRU, 默认平衡)
2. 触发键: 主组合键 chord (默认 `⌘⌥ Space`, 可重绑); 双击触发键 (五选一: ⌥ Left / ⌥ Right / ⌘ / ⌃ / Mouse 3 Middle, 默认 ⌘); 双击间隔 (0.15–0.50s, 默认 0.30s)
3. 导航与切换: 滚轮切换槽位 · 数字键提交 (1–9 0 - =) · 召唤时高亮当前 frontmost
4. 外观与轮盘布局: **面板大小** 0.80–1.50× (默认 1.0x) · Halo 直径 280–440pt (默认 380pt) · 图标尺寸 36–64pt (默认 48pt) · 图标到圆心距离 (auto-clamp) · 重置轮盘布局
5. 启动与诊断: 开机自启 (写 LaunchAgent plist) · 重播欢迎引导 · 重置首次提示蒙层 · 导出诊断日志
6. 语言: 跟随系统 / English / 简体中文 (重启生效)

**Apps**
- 绑定轮盘可视化编辑当前 8 个槽位
- 点击空槽 → AppPickerSheet (搜索框 + `/Applications` + `/System/Applications`)
- 点击已 pin 槽 → 弹出修改身份色 / 取消 pin 的 popover
- 超过 N 的 overflow pins 在 "Hidden pins" section 列出, 恢复槽位数后自动回流

**Whitelist** (v1.1 新增)
- 列出当前被屏蔽 Halo 触发的 bundle ID; +/− 工具栏 / Apply recommended 一键填入 `WhitelistSuggestions.installedSubset()`
- 命中时 `HaloHotkey` + `DoubleTapMonitor` 都短路 (Carbon 注册不退回, 不会让组合键泄漏到其它应用)

**About**
- 渐变图标徽章、版本号 + build、GitHub / 许可证链接、运行时元数据、内嵌 "导出诊断日志" 按钮

**Accessibility 权限**: 两条触发路径都**不需要 AX**. 主组合键走 Carbon `RegisterEventHotKey`; 双击辅助键盘路径轮询 `CGEventSource.keyState` (HID 级别, 左右 Option / Control 可区分), 中键路径读 `NSEvent.pressedMouseButtons` bitmask. 均为被动状态查询, 与 `NSEvent.modifierFlags` 同一信任级别.

## 12. 首次运行

1. 安装后首次启动：菜单栏图标弹一次气泡 — "按住 ⌘⌥Space 召唤 Halo"
2. **首次召唤**：Halo 上叠加 8 秒半透明教学覆盖层
   - 中心：箭头指向四方
   - 文本：「移动鼠标 / 按方向键 → 选择 · 松开 → 切换 · ESC → 取消」
3. 教学覆盖层显示一次即不再出现；Settings 可重置
4. Top-N 槽位空时全部显示 "+"，引导用户钉应用，或先用一周让频率统计自己填满
5. AX 权限**不**在首次运行强求；只有当用户首次开启 Settings 里"显示窗口标题"开关时才弹出请求
6. **槽位数 N 默认 8**（Hue 原味）；首次教学覆盖层不强调 N 可配，避免一上来就分散注意力。用户在 Settings 里随时可改
