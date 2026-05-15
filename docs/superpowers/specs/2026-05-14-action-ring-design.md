# Action Arc v2 — Design Spec

> 状态: v2 redesign, 2026-05-14. Replaces the v1 whole-wheel swap.
> Source: `docs/BRAINSTORM.md §二段手势 Action Ring` + 视觉迭代收敛到 mockup `mockups/halo-action-arc.html`.

## 1. 目标

按住主 hotkey 把 Halo 召出来 → 指向一个 app slot → 触发"二段手势"（⇧ / 右键 / 触控板双指轻点）→ 在那一瓣**外侧**弹出一段小弧，挂 4 个动作按钮。第一层轮盘原位不变。

非目标:
- 不做 shell / 任意命令
- 不做命令面板 / 模糊搜索
- 不读窗口标题
- 不联网

## 2. 模型对比 (v1 → v2)

| | v1 (废) | v2 |
| --- | --- | --- |
| 视觉 | 整个轮盘换成动作环 | 第一层 8 瓣不动, 单瓣外侧弹小弧 |
| 触发 | ⇧ 一种 | ⇧ / 右键按住 / 触控板双指轻点 三选一 |
| 数量 | 1..N 个动作 (用户随便加) | **固定 4 个** chip |
| 内容 | 全用户自定义 | 3 个内置(关闭/全屏/隐藏) + 1 个用户自定义 |
| 配置 | 每 app 一整 list | 每 app 一个自定义 |

## 3. 触发器 (3 种, 等价)

| 触发 | NSEvent 类型 | 备注 |
| --- | --- | --- |
| 单按 ⇧ | `.flagsChanged`, `.shift` off→on 边沿 | 一次 toggle 出/收; ⇧ 释放无作用 |
| 单按右键 | `.rightMouseDown` | 一次 toggle 出/收; 右键释放无作用 |
| 触控板双指轻点 | 同 `.rightMouseDown` (System Settings → Trackpad → 「辅助点按 = 用两指轻点」) | 等价右键 |

Tap-toggle 语义 (实现已收敛到这版, 实际比早期 spec 的"按住即可见"更顺手):
- 没 arc 时: 触发器按下 → 弹弧, 锚定到 `currentHoverSlot` (空位 / deadzone 时 fallback 到 `summonOriginBundleID`)
- 有 arc 且 cursor 在同一 slot: 触发器按下 → 收弧
- 有 arc 且 cursor 在不同 app slot: 触发器按下 → **直接重新弹弧到新 slot** (一次按下完成换锚)
- 有 arc 且 cursor 在空槽 / deadzone: 触发器按下 → 收弧

退出 (不 commit):
- 触发器再按一次 (按上面规则的"同 slot"或"空槽"路径)
- ESC

退出并 commit (主 hotkey 释放):
- chip 在 hover → 跑 chip
- chip 没 hover, cursor 在 slot 上 → dismiss arc + 走 layer-1 切那个 slot 的 app
- 都没 → cancel

## 4. 状态机

```
hidden
 │ summon
 ▼
idle   ◄────────────────────────────────┐
 │ cursor on app slot                   │ trigger off (commit-less)
 ▼                                      │
slot.hovering(i)                        │
 │ trigger down (⇧/right/2-finger)      │
 ▼                                      │
arc.shown(slotIdx=i, chipHover=nil) ◄──┐│
 │ cursor over chip k                  ││
 ▼                                      │
arc.chipHover(slotIdx=i, chip=k)       │
 │ release hotkey  /  click chip       │
 ▼                                      │
arc.committing(slotIdx=i, chip=k)      │
 │ execute action ──────────────────────┘ (back to hidden via dismiss)
```

ESC → 任何 arc 状态都回 hidden + cancel.

## 5. 4 个 chip (位置稳定)

| idx | 内置 / 自定义 | 名 | API | 颜色 (chip 自身, 不沿用 slot 身份色) |
| --- | --- | --- | --- | --- |
| 0 | builtin | 关闭 | `NSRunningApplication.terminate()` | `#FF453A` red |
| 1 | builtin | 全屏 (toggle) | `AXUIElementSetAttributeValue(window, AXFullScreen, !current)` | `#F7B500` yellow |
| 2 | builtin | 隐藏 | `NSRunningApplication.hide()` | `#3B82F6` blue |
| 3 | user custom | (用户取名) | `HaloAction` (folder/URL/Shortcut) | `#1DB954` green |

设计要点:
- **chip 颜色固定**, 不染身份色 — 关闭永远红 / 全屏永远黄 / 隐藏永远蓝, 形成跨 app 的双通道肌肉记忆 (位置 + 颜色).
- **位置固定**: idx 0/1/2/3 永远是 close/fullscreen/hide/custom. 不允许重排.
- chip 3 未配置 → 渲染 "+" 占位, commit 走 Settings 入口.

## 6. 全屏 chip (AX-gated, toggle)

- **入口**: `kAXFullScreenAttribute` (macOS 私有但稳定常量, Magnet/Rectangle/Raycast 在用).
- **读**: `AXUIElementCopyAttributeValue(focusedWindow, AXFullScreen)` → `Bool`.
- **写**: 取反 → `AXUIElementSetAttributeValue(...)`.
- **toggle 图标**: 当前 fullscreen → 渲 `arrow.down.right.and.arrow.up.left` (退出); 否则 `arrow.up.left.and.arrow.down.right` (进入).

权限渐进流程:
1. `AXIsProcessTrusted()` → false: chip 灰显 (色彩降饱和 + 右上角黄点), label 仍渲染 "全屏".
2. 用户首次点灰 chip → 弹一次性 sheet 「Halo 需要 Accessibility 权限来读写目标窗口的全屏属性。Halo 不读输入、不模拟键盘。」
   - 按 [打开系统设置] → `AXIsProcessTrustedWithOptions(prompt:true)` 弹系统对话框, 跳转 Privacy & Security → Accessibility.
   - 按 [稍后] → 关 sheet, 不再 nag 直到下次点.
3. 用户授权后 → chip 立即恢复亮态; commit 直接生效.
4. **核心切换路径 (layer 1) 仍不依赖 AX** — 这条规约不破.

## 7. 几何

```
SLOT_RADIUS  = 114pt              (iconRadius default, 跟 layer 1 一致)
ARC_RADIUS   = 240pt              (slot 中心 → chip 中心)
ARC_SPAN     = 48°                (4 chip 总跨度)
CHIP_GAP     = ARC_SPAN / 3 = 16°
CHIP_SIZE    = 42pt 圆形 glass chip
LABEL_OFFSET = chip 下方 6pt, 标签常驻 (不藏 hover)
```

边界处理:
- 弧本身超出屏幕 → 整段弧绕到 slot 内侧 (径向反射). 检测: `(slotX ± ARC_RADIUS, slotY ± ARC_RADIUS)` 是否超 screen visibleFrame.
- 与相邻 slot 重叠: 不会, ARC_RADIUS(240) > slot 之间距离 (~87pt for N=8).

## 8. Commit 与 Cancel

| 触发 | 行为 |
| --- | --- |
| 释放主 hotkey, 当前 chip 已 hover | 执行该 chip 动作 |
| 释放主 hotkey, 弧上无 hover | cancel (Halo 退出, 不 commit) |
| 左键点 chip | 同主 hotkey 释放 (执行) |
| 数字键 1–4 | 直接执行对应 chip |
| 触发器松开 (⇧ / 右键) | 退出 arc, 回 slot 层; 不 commit, slot 继续 hover |
| ESC | 整个 Halo cancel |

错误反馈: 执行失败 (例如 AX 写失败 / Shortcut 不存在) → shake-and-dismiss, 与 layer 1 app 启动失败同款.

## 9. 数据模型

```swift
public enum BuiltInActionKind: String, Codable, Sendable {
    case quit
    case fullscreenToggle
    case hide
}

public enum ArcChip: Equatable, Sendable {
    case builtin(BuiltInActionKind)
    case custom(HaloAction)       // 现有 HaloAction 继续用
    case emptyCustom              // chip 3 未配置占位
}

public struct ActiveArc: Equatable, Sendable {
    public let slotIndex: Int
    public let bundleID: String
    public let appName: String
    public let chips: [ArcChip]   // 固定 4 个: [.builtin(.quit), .builtin(.fullscreenToggle), .builtin(.hide), .custom 或 .emptyCustom]
    public let appIsFullscreen: Bool  // 进入弧时一次性读取, 渲染时决定 toggle 图标
    public let axGranted: Bool        // 进入时读, 决定全屏 chip 是否灰显
}
```

存储:
- 自定义 chip 复用现有 `AppPreferences.actions(forBundleID:)` 数组存储, **arc 渲染只取 `.first`**.
- 现有 Settings → Actions 改成"每 app 一个自定义" — 不允许多个, 改 / 删 / 加 都只动 `.first`.

## 10. 视觉

复用 `RadialView` 的玻璃材质. Arc 自己一个子 view:
- 4 个 `Capsule()` / `Circle()` glass chip, `glassEffect(.regular, in: Circle())` (macOS 26) / `NSVisualEffectView` fallback
- chip 内部: SF Symbol 居中 (19pt), 颜色 = chip accent
- chip 下方: 常驻 label (10pt, semibold), 黑底白字 readability
- hover 单 chip: 1.15× scale + chip accent 描边 1.5pt + 18pt 高斯外发光 (chip accent × 0.6)
- 弧本身: SVG 不画 — chip 之间的"弧"感由空间布局自然形成. 可选加一条**身份色细虚线**从 slot 拉到弧中点 (tether), strong tie 视觉.

进出动画:
- 进: chip 从 slot 中心 `translate + scale(0.4)` → 目标位置 + `scale(1.0)`, 错位 30ms 一个 (sequential pop), 总时长 ~240ms
- 出: 反向, 收回 slot 中心, 总时长 ~160ms (出比进略快)
- ReduceMotion: 全部退化为单纯 opacity crossfade 80ms

## 11. AX 权限网关

```swift
public enum AXPermissionGate {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
    @discardableResult
    public static func requestTrust(prompt: Bool = true) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
```

`requestTrust(prompt:true)` 会让 macOS 自己弹一次性系统对话框. 我们不另外做 sheet — Halo 默认不弹系统 dialog 干扰别人的工作, 但 Action Arc 是用户主动点 chip 才发起, 弹一次是合理的.

## 12. 模块划分

```
HaloCore (新):
  ├ BuiltInAction.swift       BuiltInActionKind, ArcChip, ActiveArc 数据模型
  ├ ArcExecutor.swift         protocol ArcRuntime + ArcExecutor 调度
                              (生产 impl 在 HaloUI/NSWorkspaceArcRuntime.swift)

HaloUI (新 / 改):
  ├ AXPermissionGate.swift    AX 检测 + 请求
  ├ FullScreenToggler.swift   AXFullScreen 读/写 (用 ArcRuntime 包装便测试)
  ├ NSWorkspaceArcRuntime.swift  ArcRuntime live impl (combines NSRunningApplication +
                                  AXUIElement + ActionExecutor for custom)
  ├ ActionArcView.swift       SwiftUI arc view (chips + tether + animations)
  ├ HaloState.swift           +activeArc: ActiveArc? +arcHoverChip: Int?
                              -Layer / -ActionContext / -actionSlots / -enter/exit (v1 残留全删)
  └ RadialView.swift          复用; 在 ZStack 顶部根据 state.activeArc 叠加 ActionArcView
                              -v1 的 actionSectorView/actionRimIndicator/ActionSlotContent 全删

HaloApp (改):
  ├ AppDelegate.swift         +installArcTriggerMonitor (right-mouse + flagsChanged 统一)
                              +tryShowArc / hideArc / commitArc
                              改 commitSelection 分发: activeArc != nil → arc commit
                              -v1 的 tryEnterActionRing / exitActionRingIfActive
  └ ActionsSettingsTab.swift  改成"每 app 一个 custom" 单字段表单
```

## 13. 测试

`HaloCoreTests`:
- `BuiltInActionTests` — ArcChip / ActiveArc Equatable
- `ArcExecutorTests` — 用 FakeArcRuntime 覆盖 quit / fs-toggle / hide / custom 四路成功 + 失败
- `HaloActionStoreTests` (已有, 保留)
- `ActionExecutorTests` (已有, 保留, 用于 custom chip)

`HaloUITests`:
- `HaloStateArcTests` — `showArc` / `hideArc` / `setArcHover` 转换
- `FullScreenTogglerTests` — fake AX runtime, 验证读 + 写 + 失败 codepath

## 14. 边界情况

| 情况 | 行为 |
| --- | --- |
| AX 未授权 + 点全屏 chip | 走 `requestTrust(prompt:true)`; 不执行; Halo 不 dismiss, 用户处理完系统弹窗后 chip 仍可用 |
| 目标 app 没有 focused window | toggle fullscreen 直接返 .failed |
| 目标 app 不响应 hide() (有些游戏类) | NSRunningApplication.hide() 返 false → shake |
| 用户在 Settings 删了 custom action, 然后呼 arc | chip 3 渲染 "+ Add"; commit 跳 Settings |
| 用户拼写错的 SF Symbol | SwiftUI 渲染时显示空 — 加 fallback: `Image(systemName: name)` 失败 (检测不到) → 用 kind 默认 |
| 同一秒触发两个触发器 (⇧ + 右键) | 第一个胜; 第二个忽略. State 是单 `activeArc?` |
| Arc 展开期间 slot 被移除 (refreshSlots 异步) | 检测 slot.app == nil → hideArc 不 commit |
| Halo 召唤期间用户改 N | activeArc 用的是召唤瞬间快照, 不重排 (不在 arc 里时 layer 1 正常重排) |

## 15. 实施顺序

1. **Revert v1**: 从 HaloState/RadialView/AppDelegate 删 Layer / actionSlots / 相关方法. 删 HaloStateLayerTests.
2. 加 AXPermissionGate + FullScreenToggler + ArcRuntime + ArcExecutor + 测试.
3. 改 HaloState: 加 activeArc / arcHoverChip / show/hide/setHover 方法 + 测试.
4. 加 ActionArcView. 改 RadialView 顶层叠加.
5. 改 AppDelegate: arc trigger monitor, commit 分发.
6. 改 ActionsSettingsTab: 单 custom 字段表单.
7. swift test 全绿. swift build -c release. build-app.sh. 启动 .app 手动 verify.

## 16. 仍待决 (等用户)

- 触控板"双指轻点"在 macOS 13 之前不一定走 `.rightMouseDown` — 取决于系统设置. 是否要给用户一个开关 "把触控板双指轻点当作 arc 触发器"? v1 先不做, 默认就吃 secondary click.
- 自定义 chip 显示什么 label? 用户在 Settings 取的名 + SF Symbol. 用户没填 → fallback 到 kind 的默认名 (e.g. "文件夹" / "URL" / "Shortcut").
