# Action Ring — Design Spec

> 状态: draft, 2026-05-14. Source: `docs/BRAINSTORM.md §二段手势 Action Ring`.
> 配套: 实现完成后写入 `docs/INTERACTION.md §X` / `docs/PRODUCT.md §11`.

## 1. 目标

把 Halo 从"按住、指向、松开 = 切 app"扩展成"按住、指向、按 ⇧、再指向、松开 = 跑动作"。
第一层（slot ring）保留 v1.1 的体验，**不变更任何热路径**。
第二层（Action Ring）只在用户主动按下 ⇧ 时浮现，给当前指向的 app 提供 4–12 个本地动作。

非目标:

- 不做 shell / AppleScript 任意命令（v1）
- 不替代 Raycast / Alfred 的命令面板
- 不读窗口标题、不依赖 Accessibility
- 不联网、不同步、不引入账号

## 2. 触发与状态机

```
Layer 1 (slot ring)                Layer 2 (action ring)
┌────────────────────┐             ┌────────────────────┐
│ hover slot i with  │  press ⇧    │ render actions for │
│ a non-empty app    │ ─────────► │ slot i's bundleID  │
│                    │  release ⇧  │                    │
│                    │ ◄───────── │                    │
└─────────┬──────────┘             └─────────┬──────────┘
          │ release hotkey                   │ release hotkey
          ▼                                  ▼
    switch to app                      execute action
```

详细规则:

- **进入条件**: layer == .slots 且 currentHoverSlot 指向一个 `.app != nil` 的 slot 且 ⇧ flag 被按下。监听 `NSEvent.flagsChanged`，每次 ⇧ flag 变化都重新评估 — 用户在 idle 状态按 ⇧、然后再 hover 一个 slot 也应进入 layer 2 (持续监听 hover 变化时的 ⇧ flag 状态)。
- **退出条件**: ⇧ 被松开 → 回到 layer 1，仍保持原 slot 高亮。
- **空 slot**: layer 1 的空 slot 按 ⇧ 不进入 layer 2（"+"slot 没有 app context）。
- **app 没有任何绑定动作**: 进入 layer 2 后 8 个 sector 全为"+ Configure"占位；commit 任一占位 → 打开 Settings → Actions 并定位到该 bundleID。
- **没有 hover**: layer 1 idle 状态按 ⇧ 不切换。⇧ 不是无条件 layer 切换键。
- **layer 切换不调用 SoundEffectPlayer.slide**（避免按 ⇧ 时多余声音；按 ⇧ 后第一次方向变化才发声）。

为什么选 ⇧:

- ⇧ 不参与 Halo 任何当前路径（默认 chord `⌘⌥Space`、双击 ⌘ / ⌥ / ⌃ / Mouse 3 都不用 ⇧）。
- ⇧ 是 macOS 体系里的"次级修饰键"——和 Finder "Show in Enclosing Folder"、tab 切换等等保持一致直觉。
- 按住 ⇧ 进入 / 松开 ⇧ 退出，是 Halo 原生 "按住即可见、松开即提交" 语言的自然延伸。
- 备选「dwell 600ms」语义太重（拖慢 commit），「scroll 进入」与现有 slot cycle 冲突。

## 3. 数据模型

```swift
public enum HaloActionKind: String, Codable, Sendable {
    case openFolder       // payload: file path
    case openURL          // payload: https://... or any scheme
    case runShortcut      // payload: Shortcut name (uses shortcuts://run-shortcut)
}

public struct HaloAction: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var label: String      // user-supplied, displayed under icon
    public var kind: HaloActionKind
    public var payload: String    // path / URL / shortcut name
    public var sfSymbol: String?  // optional override; default per kind
}
```

存储:

- `AppPreferences.actions(for: bundleID) -> [HaloAction]` / `set(actions: [HaloAction], for: bundleID)`
- UserDefaults key: `halo.prefs.actionBindings.v1` → `[String: [HaloAction]]` JSON
- 删除最后一个 action → 该 bundleID 的 key 被清除
- 存储无上限，渲染时只取前 `slotCount` 个（§7）；存储不随 `slotCount` 改变重排

Default SF symbol:

- openFolder → `folder.fill`
- openURL → `link`
- runShortcut → `wand.and.stars`

## 4. 视觉

复用 `RadialView` 的几何 + 玻璃材质，**通过四处差异告诉用户"这是第二层"**:

1. **中心 hub**: 始终显示当前 app icon + 顶部细标题条 `{appName} · Actions`（11pt SF Pro Bold，accent 色低饱和度文本）
2. **Sector content**: 不再是 app icon，而是 SF Symbol 居中 + 下方两行最多 22 字符的 label
3. **Sector tint**: 全部用 layer 1 当前 slot 的 identity color（统一感）；hovered sector 加深；非 hovered 用 6% alpha 而非 1.5%
4. **Specular arc**: 从 12 点弧移到 6 点弧（视觉锚反向），暗示"翻面进入"
5. **Outer rim**: 在 `visibleOuterRadius` 上方加一圈 0.4pt 的 accent 色细环 (alpha 0.3)，layer 1 没有 — 形成"layer 2 边界"标识

动效:

- ⇧ 按下 → layer 1 sector fade out 100ms (icon → blank)，layer 2 sector fade in 120ms (blank → symbol + label)
- ⇧ 松开 → 反向，slots 重新可见
- 期间 hub icon 不重新淡入，避免闪烁——它已经在 layer 1 hover 时显示该 app

ReduceMotion: 两层切换降级为 60ms 简单 opacity crossfade。

## 5. 提交 / 取消

| 触发 | layer 1 | layer 2 |
| --- | --- | --- |
| 松开 hotkey | `Switcher.switchTo(bundleID)` | `ActionExecutor.execute(action)` |
| 点击 sector | 同上 | 同上 |
| Return / Space | 同上 | 同上 |
| 数字键 1–9 0 - = | 直选 + commit | 直选 layer 2 sector + commit |
| ESC | cancel | cancel（不回 layer 1，整个 Halo dismiss） |
| 松开 ⇧ | n/a | 不 commit，回 layer 1 |

执行失败 (`ActionExecutor` 返回 `.failed`) → `shakeAndDismiss()`，和 app 启动失败同路径。

`ActionExecutor` 实现:

- openFolder: `NSWorkspace.shared.open(URL(fileURLWithPath: payload))`
- openURL: `URL(string: payload).flatMap { NSWorkspace.shared.open($0) } ?? false`
- runShortcut: `NSWorkspace.shared.open(URL(string: "shortcuts://run-shortcut?name=\(percentEncoded)")!)`

返回 `.executed` / `.failed`. 不阻塞主线程（NSWorkspace.open 本身是异步的）。

## 6. 设置 UI

新增 sidebar section: **Actions** (盾牌之后、About 之前)，渐变色 = 紫橙偏暖.

布局:

```
┌──────────────────────────────────────────────────┐
│ App list (left, 200pt)   │ Action list (right)   │
│ ┌──────────────────────┐ │ ┌────────────────────┐ │
│ │ Finder           [3] │ │ │ ☰ Open Downloads   │ │
│ │ Cursor           [5] │ │ │ ☰ Open ~/Code      │ │
│ │ Safari           [2] │ │ │ ☰ AirDrop          │ │
│ │ + Add app          │ │ │ + Add action       │ │
│ └──────────────────────┘ │ └────────────────────┘ │
└──────────────────────────────────────────────────┘
```

- 左侧 app list: 来自所有有绑定动作的 bundleID，按 frequency 排序；底部 "+ Add app" 复用 `PinPickerWindow` 选 bundle。
- 右侧 action list: drag-handle 可重排；行尾 menu 提供 Edit / Delete；底部 "+ Add action" sheet。
- Add / Edit sheet: kind picker (segmented 3 选 1) + label TextField + payload field（type 改变时 placeholder + 验证规则切换）+ optional SF symbol 名 input。
- 验证: openFolder 必须存在且是 directory；openURL 必须 parseable；runShortcut 不验证（用户可能要绑还没安装的）。
- 一个 bundleID 删完所有动作 → 自动从 app list 移除。

## 7. 边界情况

| 情况 | 行为 |
| --- | --- |
| 进入 layer 2 时 app 没绑动作 | 全部 sector 渲染为"+ Configure"占位; 任一 commit → 打开 Settings.Actions 定位 |
| layer 2 渲染中绑定数 < slotCount | 多余 slot 渲染"+ Add action"占位；commit 任一 → 打开 Settings.Actions |
| layer 2 渲染中绑定数 > slotCount | 截断至 slotCount，Settings 显示警告 "8 of 12 actions visible; reduce or increase slot count" |
| 用户在 Settings 改 slotCount | actions 不重排（用户给 action 的 index 是空间记忆，不该跟 slot 数改变） |
| openFolder payload 指向已删除目录 | `NSWorkspace.open` 返回 false → shake-and-fail |
| runShortcut 名拼写错 | macOS 弹一个"Shortcut not found"，我们的角度看是 succeeded（URL open 成功）— 接受这个，不试图替系统判断 |
| 用户在 layer 2 按 ⇧ 第二次（连按） | 不做事; 已在 layer 2 |
| 用户在 layer 1 commit 之前先按 ⇧（idle 状态） | 不做事; 必须先 hover 一个 app slot |
| 多显示器 | 不影响; layer 2 渲染在同一面板 |
| Reduce Motion | crossfade 缩到 60ms |

## 8. 模块划分

```
HaloCore (无 UI):
  ├ HaloAction.swift          数据模型 + JSON
  ├ ActionStore.swift         AppPreferences 的扩展 (新增 actions(for:) / set / remove)
  └ ActionExecutor.swift      protocol AppRuntime 已存在；这里加一个 ActionRuntime
                              live impl 在 HaloUI/NSWorkspaceRuntime+Actions.swift

HaloUI:
  ├ HaloState.swift           +layer (.slots / .actions(ActionContext))
                              +actionSlots
  ├ RadialView.swift          根据 state.layer 二选一渲染
  ├ ActionSectorContent.swift 新文件; SF symbol + label
  └ NSWorkspaceRuntime+Actions.swift live ActionRuntime

HaloApp:
  ├ AppDelegate.swift         +flagsChanged 监听 ⇧
                              +commitSelection 分发到 ActionExecutor
                              +applyActions 缓存
  └ ActionsSettingsTab.swift  新设置面板
  └ ActionEditorSheet.swift   add/edit action sheet
```

## 9. 测试

`HaloCoreTests`:
- `HaloActionStoreTests` — encode/decode round-trip, add/remove, edge cases (空 list、删除最后一个)
- `ActionExecutorTests` — 用 FakeActionRuntime 验证 openFolder/openURL/runShortcut 走对路径，失败传回

`HaloUITests`:
- `HaloStateLayerTests` — 进入 layer 2 / 退出 layer 2 / 在 layer 2 期间 commit 走 layer 2 dispatch
- `ActionRingHoverTests` — layer 2 期间 hover phase 流转和 layer 1 一致

不做端到端 UI 测试（项目现有约定）；本地 build + 手动验证 golden path 在 `Build, run, verify` 任务。

## 10. 风险

| # | 项 | 备注 |
| --- | --- | --- |
| R1 | ⇧ 与系统 shift-arrow 选区冲突 | Halo 召唤期间面板已成为 key window，不会泄漏 |
| R2 | 用户按 ⇧ 改方向意外（例如 ⇧+digit 走 layer 1 索引） | digit 路径在 layer 2 也是 commit layer 2 sector，行为对称 |
| R3 | 多 hop 焦虑 | layer 2 的边界视觉提示 + hub 的 `{app} · Actions` 永远在 — 用户不会迷路 |
| R4 | 用户存放 shell action 的需求 | 明确 v1 不做；v2 可加，但要弹"准予执行 shell"二级确认 |
| R5 | Shortcut name 含特殊字符 | URL 用 `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`，单测覆盖 |

## 11. 实施顺序

1. HaloCore 数据模型 + tests
2. HaloState layer 字段 + tests
3. AppDelegate flagsChanged 监听（先 print，不绘 UI；验证事件流）
4. RadialView 渲染 layer 2 (复用 sectorView，新 sectorContentVariant)
5. ActionExecutor live + commitSelection 分发
6. Settings UI
7. swift test 全绿；build release；启动 .app 手动验证 golden path

## 12. 非目标 / 暂缓

- ⇧ 之外的 layer 进入方式（dwell、scroll 进入）
- 跨 app 的全局 action（"open ~/Downloads regardless of context"）
- macOS Shortcuts 列表自动补全
- 同步、导入导出（属 brainstorm "可分享主题与配置卡片"，独立 spec）
- 二级动作链（action → 二级 action ring）

## 13. 后续追踪

- v1 落地后在 `docs/INTERACTION.md` 加 §15 Action Ring
- BRAINSTORM 中 "Per-App Actions" 与本 spec 等价，落地后把它从 brainstorm 标记为 shipped
