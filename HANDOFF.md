# Halo · Handoff

> 状态：v1.2 HUD 重写已 commit，但未合并到 main，**未经用户视觉验收**。
> 项目根：`/Users/elon/code-space/GitHub/Halo`
> 当前工作 worktree：`.claude/worktrees/halo-v1.1-polish`（分支 `worktree-halo-v1.1-polish`）

## Goal

用户已在实际运行的 Halo 上看出多处 UI 问题（方形阴影、图标灰块化、圆盘简陋），要求**照抄** `~/code-space/GitHub/tabsapp/` 的轮盘切换实现。v1.2 的重写已 commit。下一步：让用户打开新装的 `/Applications/Halo.app` 验收视觉，并把分支合回 `main`。

## Current Progress

### 当前状态

- `/Applications/Halo.app` 已替换为 v1.2.0（bundle 12）
- `dist/Halo-v1.2.0.zip` 打好包（938K）
- 单元测试 26/26 全绿（`swift test`）
- worktree 分支 `worktree-halo-v1.1-polish` **领先 main 2 个 commit**：
  - `b3d6457` v1.1: 圆形阴影 + 彩色图标 + 渐变圆盘 + ⌘ 1.5s 长按快捷键
  - `351565d` v1.2: 照抄 tabsapp 的 HUD 重写

### v1.2 的关键改动（照抄 tabsapp 的部分）

| 来自 tabsapp | 对应 Halo 文件 |
|---|---|
| `SectorShape` 扇形切片 + `RadialSwitcherGeometry` | `Sources/HaloUI/RadialGeometry.swift`（新建）|
| `VisualEffectBackground`（NSVisualEffectView 包装）| `Sources/HaloUI/VisualEffectBackground.swift`（新建）|
| 分层：halo glow → glass → sectors → centerHub → label | `Sources/HaloUI/RadialView.swift`（重写）|
| 60 fps cursor timer + `NSApp.activate` + `previousFrontApp` 恢复 | `Sources/HaloUI/HaloWindow.swift`（重写）|
| 方向键 ←↑→↓ 循环高亮 | `Sources/HaloApp/AppDelegate.swift`（`cycleHighlight(by:)`）|
| `RadialPanelFrame` 边界夹取 | `Sources/HaloUI/RadialGeometry.swift` 中的 enum |

**尺寸变更**：HUD 外径 280 → 320，中心 72 → 112，图标 28 → 48，总面板 304 → 440。

**Halo 特色保留**：空槽 "+" 呼吸标记 / `HaloSlot.RunState` 运行状态指示点 / OKLCH `IdentityColor` 用作 accent / ⌘ 1.5s 长按第二快捷键 / 空槽提交时弹 Pin picker。

### 设计参考来源

用户明确说「不会写就抄」，抄的是 `~/code-space/GitHub/tabsapp/Sources/TabsApp/UI/`：
- `RadialSwitcherView.swift`
- `RadialSwitcherWindowController.swift`
- `VisualEffectBackground.swift`
- `Services/AppIconColorExtractor.swift`

`~/code-space/GitHub/tabsapp/Sources/TabsApp/Models/RadialSwitcherState.swift` 中的 `RadialSwitcherGeometry` 是几何逻辑的直接蓝本。

## What Worked

- **tabsapp 的 cursor timer 方案**：`DragGesture(minimumDistance: 0)` 单独不可靠（非 key window 下 SwiftUI hover 事件不稳），60 fps 轮询 `NSEvent.mouseLocation` 是主力机制
- **`NSApp.activate(ignoringOtherApps: true)` + `previousFrontApp` 恢复**：既让本地 `NSEvent` 监听能收到键盘，又不丢失取消后的焦点归宿
- **`panel.level = .popUpMenu`** + `.ignoresCycle, .transient`：浮在全屏 app 上方、不进 Cmd-Tab 循环
- **扇形 + 独立 centerHub 覆盖打洞**：比 donut arc reversed 的 `PetalShape` 几何更简洁，边缝不会重叠
- **NSVisualEffectView 直接包装**：SwiftUI 的 `.ultraThinMaterial` 在非激活面板上会塌成灰色，换成 AppKit 原生 view 后玻璃效果真实

## What Didn't Work

- **v1.1 的「加 `.compositingGroup()` + `.ultraThinMaterial` 修阴影」只是治标**：整体几何结构（donut petal）本身就有设计问题，最后还是全推倒重来。下次遇到「阴影不对 / 图标错」这类报告先判断是不是更底层的结构问题
- **原 v0.1 的 `.onContinuousHover`** 只在 key window 下工作，对非激活 panel 无效。已替换为 timer + DragGesture 双保险
- **原 `.renderingMode(.template)`** 导致所有图标变成白色矩形。根本不应该加 template mode — 用户想要彩色图标
- **原 `PetalShape`（donut arc 反向闭合）** 在槽间隙处做 stroke 容易出现肉眼可见的重叠线 — 切换到扇形 + hub 覆盖后没了

## Next Steps（按顺序）

1. **用户视觉验收**：用户要重新 `open /Applications/Halo.app`，按 `⌘⌥Space` 或 `⌘` 长按 1.5s 召唤 HUD，检查：
   - 阴影是否完全圆形
   - 图标是否彩色（不是灰块）
   - 扇形分隔是否干净、无重叠
   - 高亮扇形外侧有无 accent 颜色的 halo glow
   - 高亮扇形外面有无曲线 tooltip（app 名字）
   - 中心 hub 是否显示当前前台 app 的大图标
   - 方向键 ←→↑↓ 是否能切换高亮
2. 用户如果有视觉细节要调，进入 `design` skill 的 Screenshot Iteration Mode
3. **合并回 main**：
   ```sh
   cd /Users/elon/code-space/GitHub/Halo
   git checkout main
   git merge worktree-halo-v1.1-polish
   ```
   然后可选地 `ExitWorktree` 清理
4. v1.3 可能要做的事（路线图暂存，不要自己动手）：
   - 窗口标题 arc tooltip（需要 AX 权限，已在 PRODUCT.md 标注为 v1.1+）
   - onboarding 覆盖层重做（现版只有占位）
   - 英文版文档镜像

## Verification Status

- `swift build` — ✓ 无警告
- `swift test` — ✓ 26/26（engine/store/switcher/OKLCH/prefs）
- `make app` / `make install` / `make dist` — ✓ 成功
- **视觉验收** — ✗ **未完成**（用户需自己打开 app 确认）
- 多显示器召唤位置 — ✗ 未在这次重写后重新验证（`RadialPanelFrame.frame(...)` 应已正确处理，但需要用户在多屏环境手动过一遍）
- `⌘` 1.5s 长按快捷键 — ✗ 未在 v1.2 后重新验证（代码未改，理论上仍工作）

## Key Files（v1.2 之后的布局）

```
Sources/HaloCore/         # 无 UI 依赖，可单测
  HaloEngine.swift        #   Top-N 频率选择 + Pin 优先
  UsageStore.swift        #   7 天激活记录
  Switcher.swift          #   NSWorkspace.activate / openApplication
  IdentityColor.swift     #   OKLCH + Hue-8 palette + 冲突解算
  DominantColorExtractor  #   CoreImage k-means (k=3)
  AppPreferences.swift    #   UserDefaults ObservableObject
Sources/HaloUI/           # SwiftUI + AppKit 桥接
  RadialView.swift        #   ★ v1.2 重写：halo glow / glass / sectors / hub / label
  HaloWindow.swift        #   ★ v1.2 重写：popUpMenu + cursor timer + NSApp.activate
  RadialGeometry.swift    #   ★ v1.2 新增：SectorShape + sectorIndex + RadialPanelFrame
  VisualEffectBackground  #   ★ v1.2 新增：NSVisualEffectView 包装
  HaloState.swift         #   state.updateHover(slot:) 统一 hover 转移
  HaloHotkey.swift        #   Carbon RegisterEventHotKey（长按 200ms 切 Quick Swap）
  CommandLongPressMonitor #   ⌘-alone 1.5s 第二快捷键（NSEvent.modifierFlags 轮询）
  RippleView.swift        #   vignette ripple commit 反馈
  AppIconResolver.swift   #   NSWorkspace.icon(forFile:) 缓存
Sources/HaloApp/
  AppDelegate.swift       #   ★ v1.2：cycleHighlight(by:) + cancel 时 restorePreviousFront
  SettingsWindow.swift    #   Behavior / Hotkey / Pins / Colors / About
  PinPickerWindow.swift   #   空槽提交时的 app picker
  LaunchAgentManager      #   SMAppService.mainApp 自启
Tests/HaloCoreTests/      # 26 tests
Resources/Info.plist      # 版本 1.2.0，bundle 12
```

## Open Questions（等用户决定）

- v1.2 的新 HUD 用户看了没？视觉上是否还需要微调？（待验收）
- 合并到 main 的时机：等视觉验收通过后再合，还是立即合再修？
- 是否现在做英文版文档？（当前结论：仍延后）

## Suggested Skills

- `design` — 如果用户反馈新 HUD 有视觉问题，进入 Screenshot Iteration Mode
- `superpowers:test-driven-development` — 为新增的 `RadialGeometry.sectorIndex(for:...)` 补纯几何单元测试（目前未覆盖）
- None — 如果只是合并到 main，直接走普通 git 流程就行
