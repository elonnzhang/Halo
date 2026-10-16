# 重写为 MyGo 的成本与预期效果评估

日期：2026-10-15。范围：评估把 Halo 从 Swift/SwiftUI 重写为 [egoist/mygo](https://github.com/egoist/mygo)（v0.5.1，纯 Go、无 cgo 的桌面应用框架）的成本和效果。只做评估，不含任何代码改动。

## 结论与决策状态

不建议整体重写。估算成本 15–26 人周，相当于 Halo 从首次提交到最近一次提交的时长（2026-05-13 至 2026-09-29，约 4.5 个月）；预期效果大多持平或变差，另有一项硬冲突：Go 1.27 要求 macOS 13+，而 Halo 承诺 macOS 12（`AGENTS.md:18`）。

可确定的收益只有两点：`mygo build` 一条命令完成签名、公证、DMG 和 universal；理论上的跨平台。`docs/PRODUCT.md` 没有跨平台目标，且每个平台的系统集成层都要重写。

决策：未决。取决于重写动机（跨平台、摆脱 Xcode、偏好 Go）。若仍要推进，先按「验证范围」做 1–2 周 spike，任一项不通过即终止。

## 前提与证据等级

- 「MyGO」指 egoist/mygo。同名的 mygo-lang/mygo 是转译到 Go 的语言（4 star，无 release，无 GUI 方案），不在评估范围。
- 工时是推断：单人、熟悉 Go、AI 辅助，不含产品设计。
- 证据标签：[实测] 本机测量或亲自读代码；[核对] 读取一手来源（官方文档、发行说明）；[调研] 子任务调研所得，附出处，未二次核对；[推断] 基于上述事实的判断。

## Halo 现状基线

### 规模与耦合

| 类别 | 行数 | 占比 | 主要构成 |
| --- | --- | --- | --- |
| 纯逻辑 | 4,288 | 30.3% | AppPreferences 989、HoneycombGeometry 528、GridState 444、HaloState 263 |
| 系统集成 | 3,150 | 22.3% | AppDelegate 1,295、HaloWindow 413、DoubleTapMonitor 220、热键、NSWorkspace、AX |
| 视图与动画 | 6,705 | 47.4% | RadialView 1,128、HoneycombGridView 951、设置与引导 3,707 |
| 合计 | 14,143 | 100% | 另有测试 3,180 行（228 个用例） |

按文件主要职责归类，AppDelegate 整体计入系统集成 [调研]。HaloCore 层界清晰：4 个涉及 AppKit 的文件都有 `#if canImport(AppKit)` 守卫 [调研]。

测试可移植性 [调研]：2,682 行（84.3%）可近机械译成 `go test`；450 行（HaloState*、GridState、DoubleTapMonitorState）需先抽缝；48 行（AppIconResolverCacheTests）绑定 AppKit。6 个 Core 测试使用 `UserDefaults(suiteName:)`，需要键值存储抽象。

### 性能与资源基线

- 物理内存 26 MB（`vmmap -summary`，峰值 26.7 MB），`ps` RSS 77 MB（含共享系统库）。启动约 2 分钟后空闲时的单次测量 [实测]。
- `dist/Halo.app` 11 MB（二进制 11.1 MB，通用包）；thin-arm64、thin-x86_64 各 2.1 MB [实测]。
- 冷启动 116–211 ms；`refreshSlots` 首次 13–72 ms，之后约 2 ms；`DCE.extract` 约 1 ms/图标；扫描应用约 89 ms（`CHANGELOG.md:92`）[核对]。
- `docs/STORAGE.md:104` 仍把 `adaptiveSpiralLayout` 列为测点，当前代码的测点已是 `watchViewportProject`、`watchLayout`（`HoneycombGridView.swift:268,943`）；移植前需按新测点重测基线 [核对]。

### 关键 API 落点

- 热键：`HaloHotkey.swift:57` 调 `RegisterEventHotKey`；`:110-141` 同时处理按下和松开（`kEventHotKeyPressed`、`kEventHotKeyReleased`），松开触发 `.holdReleased`，是「按住召唤、松开确认」的基础 [实测]。
- 双击修饰键：全仓没有 `CGEvent.tapCreate`，靠轮询实现（`DoubleTapMonitor.swift:74,106,124`）[调研]。
- 事件监听：本地监听在 `AppDelegate.swift:813,1075,1099,1209`，全局点击外部在 `:1274` [调研，`:1274` 已核对]。
- 浮层：`HaloWindow.swift:44,243`、`HaloGridWindow.swift:44`、`OnboardingOverlay.swift:57` 都用 `[.borderless, .nonactivatingPanel]` [核对]。
- 材质：`#available(macOS 26` 门控共 8 处 [核对]。`RadialView.swift:113` 是 `GlassEffectContainer` 门控，`:359` 是 `.glassEffect`，`:1089-1090` 是 `.glassEffect` 加 `.glassEffectID`（标签在槽位间形变）；其余在 `OnboardingOverlay.swift:173`、`ProfileTabBar.swift:89`、`WelcomeWindow.swift:381`、`GeneralSettingsTab.swift:559`。旧系统回退在 `HoneycombGridView.swift:223`、`VisualEffectBackground.swift:8` [调研]。
- 其他系统 API [核对]：`AXPermissionGate.swift:15`（AX）、`LaunchAgentManager.swift:13`（`SMAppService`，macOS 12 走旧 LaunchAgent 分支）、`DominantColorExtractor.swift:49`（`CIContext`）、`NSWorkspaceActionRuntime.swift:63`（`NSAppleScript`）。
- 动画与性能 [调研]：SwiftUI spring；ALL 视口 60–120 fps（`GridViewportMotion.swift:60`）；光标 60 fps Timer 轮询（`HaloGridWindow.swift:129`）；`PerfSignpost.swift:15` 用 `OSSignposter`。

### 数据与打包

- 偏好域为 `com.halo.launcher`（`docs/STORAGE.md:70`）。代码里有 28 个 `halo.prefs.*` 键，另有 `halo.onboarding.shown`、`halo.usage.v1`、`halo.welcome.shown`，共 31 个。`docs/STORAGE.md` 缺其中 6 个（`actionBindings.v1`、`activeProfileID`、`appearanceMode`、`frequencyProfile`、`profilesFrequencyMigrated.v1`、`soundEffectsEnabled`），并列有 `actions.v1`、`profile` 两条在代码里找不到字面量 [实测]。移植需经 CFPreferences 读写才能兼容旧数据 [推断]。
- 日志 `~/Library/Logs/Halo/halo.log`，5 MB 轮转（`docs/STORAGE.md:42`）[调研]。本地化为 `Localizable.strings` 中英各 185 键 [实测]，Go 端需自写加载 [推断]。
- `Resources/Info.plist`：`LSMinimumSystemVersion` 12.0、`LSUIElement` true [核对]；无 `.entitlements`，只有 `--options runtime`（`scripts/build-app.sh:76`）；构建链为 swift build ×2、lipo、codesign、notarize [调研]。

## MyGo 能力对照

下表按 Halo 的需求逐项对照。「未提及」指官方文档没写，不等于不支持，需 spike 验证。

| 需求 | MyGo 文档所述 | 页面 |
| --- | --- | --- |
| 渲染 | 原生 UI 自绘（Metal、D3D11、OpenGL 或 CPU 光栅），不是 AppKit/SwiftUI 控件；web 路线用系统 WKWebView，经 `mygo://localhost/` 协议加载 | architecture [调研] |
| 窗口 | 支持 Frameless、Transparent、Vibrancy、AlwaysOnTop、ShowInactive、窗口级 SetIgnoreMouseEvents、SetVisibleOnAllWorkspaces | windows [调研] |
| 非激活浮层 | `Panel` 是 non-activating NSPanel，浮于全屏 App 和所有 Space 之上，不进 Mission Control | launchers [调研] |
| 跟随鼠标 | 无专用 API，需 `Screen.CursorScreenPoint` 加 `SetPosition` | launchers [调研] |
| 玻璃材质 | glass 插件是 shader 仿真，不是系统 NSGlassEffectView；macOS 12–25 回退未提及 | plugins/glass [调研] |
| 全局快捷键 | 只有 `GlobalShortcut.Register(accel, func())`，底层 Carbon；松开事件、仅修饰键、double-tap、全局事件监听、AX 均未提及 | native [核对] |
| 菜单栏常驻 | Tray（`IconIsTemplate`、`Tray.Bounds`）、`SetActivationPolicy(Accessory)`、`SetOpenAtLogin` 明确支持 | menus、app [调研] |
| 系统 API | purego 加 ObjC runtime，无 cgo；公开面只有 `Shell.InstalledApps/LaunchApp/FileIcon` 和 `win.NativeHandle()`；运行中 App 枚举、激活、前台变化通知、AX、CGEvent 均未提及 | architecture [调研] |
| 指针输入 | 有 Hovered、Pressed、Clicked、DoubleClicked、RightClicked、Dragged、PointerPosition、PassThrough、HandleInput；enter/leave、精确滚动、pinch、pan、多点触控、窗口外光标位置、非激活 Panel 内的 hover 均未提及 | ui/input [核对] |
| 绘制 | Painter、Path、Transform、spring 动画；六边形 helper、非矩形命中未提及 | ui/drawing [调研] |
| 分发 | `mygo build` 做 hardened runtime 签名、公证、DMG、`darwin/universal`；`minimumSystemVersion` 默认 12.0；要求 Go ≥ 1.27 | distribution、configuration [调研] |
| 联网 | updater 是 opt-in 插件；web 路线不需要本地 HTTP server；不用 updater 时是否零联网、有无遥测未验证 | updates [调研] |

### 成熟度与底层

- 仓库 2026-09-26 创建（评估时 19 天）；v0.5.1，共 62 个 release，从 v0.1.22（2026-10-01）到 v0.5.1 只隔 13 天；pre-1.0，无稳定性或破坏性变更承诺；MIT；2.0k star、107 fork，18 个 issue、31 个 PR [调研]。
- pkg.go.dev 显示被引用 0；官方 launcher 示例覆盖 Panel、Transparent、Vibrancy、Shortcut、Tray，但没有第三方实战案例；唯一找到的第三方评述（mondary.design，法语）担心自绘渲染栈的成熟度，只看到搜索摘要 [调研]。
- 官网首页列出二进制约 7 MB、原生 UI 约 44 MB、含 webview 约 62 MB，未说明测量条件和指标含义；文档称 Metal 首帧占 30–45 MB，空闲后归还 [调研]。
- purego 是 v0.11.1，自称 beta，API 可能破坏；回调数量有限（至少 2,000 个）且不释放；`NewCallback` 不支持按值传 struct；objc 子包官方称「易误用」。MyGo 自己的 `AGENTS.md` 要求主线程锁定，super 调用用自写的 sendSuper 而不是 purego 的 `SendSuper` [调研]。
- NSGlassEffectView 是 AppKit 类，理论上可在运行时获取；SwiftUI `glassEffect` 是 Swift 修饰符，Go 无法调用，视图层需重写 [推断]。未检索到 purego 加 CGEventTap 的实例 [调研]。
- web 路线的内存参照（单次实测，作者提示 RSS 求和会重复计共享页）：Tauri（WKWebView）空闲 RSS 174 MiB，Electron 346 MiB；另一份对比为 Wails 约 100、Tauri 约 95、Electron 约 369 MB。MyGo 的 web 路线同样使用 WKWebView，设置窗口若走 web 路线，打开期间会有类似的额外进程内存 [调研][推断]。
- Go 运行时：GC 暂停通常亚毫秒，1.26 起默认启用 Green Tea GC，空闲时每 2 分钟强制一次 GC，后台 scavenger 逐步归还内存。GC 暂停不太可能是热键唤起的瓶颈，风险更可能在 purego 调用开销和主线程调度，均无实测数据 [调研][推断]。

### Go 版本与系统下限

Go 1.27 于 2026 年 8 月发布，发行说明写明「Go 1.27 requires macOS 13 Ventura or later; support for previous versions has been discontinued」[核对]。MyGo 文档要求 Go ≥ 1.27，同时把 `minimumSystemVersion` 默认设为 12.0，二者矛盾：产物能否在 macOS 12 运行没有官方保证，需实机验证。

## 成本估算 [推断]

假设：单人、熟悉 Go、AI 辅助，保持现有行为不变，不含新功能。

| 部分 | 估算 | 主要不确定性 |
| --- | --- | --- |
| 纯逻辑加 84% 的测试 | 2–3 人周 | 31 个 UserDefaults 键要兼容旧数据；Core 测试要先抽出键值存储抽象 |
| 系统集成 | 4–7 人周 | 运行中 App、激活、AX、CGEvent、AppleScript、声音在 MyGo 中都没有，需自写 purego 绑定；松开事件热键要绕开 `GlobalShortcut` |
| 放射与蜂巢视图（约 2,350 行） | 4–8 人周 | 重画渲染、玻璃形变、非矩形命中、触控板手势 |
| 设置与引导 UI（3,707 行） | 3–5 人周 | 走 web 路线较省，但多出 WKWebView 和前端工具链 |
| 打包、CI、文档、回归 | 2–3 人周 | 改 `scripts/notarize.sh`、CI、`Resources/Info.plist` 需要明确授权（`AGENTS.md:56`） |
| 合计 | 15–26 人周 | 后三项占大头，且不确定性最高 |

估算时长与 Halo 已提交部分的开发时长相当（107 次提交，2026-05-13 至 2026-09-29）。重写期间新功能要么冻结，要么在 Swift 与 Go 两边各做一遍。

最难的 5 项（来自代码审计 [调研]）：

1. Liquid Glass 渲染层：`RadialView`（1,128 行）、`HoneycombGridView`（951 行）、`ActionArcView`（277 行）。`glassEffectID` 形变、spring、macOS 12–25 材质回退在 Go 侧都没有对应物。
2. 非激活浮层：`HaloWindow.swift:44,410`、`HaloGridWindow.swift:200`。窗口一旦抢焦点，「上一个前台 App」就失真（`HaloState.swift:42`）。
3. 热键与事件监听：`HaloHotkey.swift:117-149`、`AppDelegate.swift:813-1274`。C 回调和 ObjC block 要接进 Go，51 处 `@MainActor` 还要求主线程调度。
4. 设置与引导 UI 共 3,707 行：原生 Form、source list、拖放（`ProfileBar.swift:157`、`BindingWheelView.swift:187`）。
5. 无障碍与外观联动：VoiceOver、Reduce Motion、Increase Contrast（`docs/INTERACTION.md:243-247`）。自绘 UI 难以桥接。

## 预期效果

| 维度 | Halo 现状 | 重写为 MyGo 后 | 证据 |
| --- | --- | --- | --- |
| 最低系统 | macOS 12 | 官方只支持 13+；MyGo 配置默认写 12.0，与之矛盾 | [核对] |
| 玻璃材质 | 系统 `glassEffect`，macOS 12–25 有回退 | glass 插件为 shader 仿真，12–25 回退未提及 | [调研] |
| 按住召唤、松开确认 | Carbon 按下加松开（`HaloHotkey.swift:110-141`） | `GlobalShortcut` 只有单一回调，需自写 Carbon 松开事件 | [核对] |
| 触控板平移与捏合 | 已实现（ALL 视图） | 输入 API 未提及手势和精确滚动 | [核对] |
| 常驻内存 | 26 MB | 官网 44 / 62 MB（口径未披露）；若同为物理内存，约为现状的 1.7–2.4 倍 | [调研][推断] |
| 体积 | 通用包 11 MB | 官网称二进制约 7 MB，无明显收益 | [调研] |
| 召唤延迟 | 淡入 120 ms；冷启动 116–211 ms | 无数据；Metal 资源空闲后归还，空闲后首次召唤可能变慢 | [推断] |
| 成熟度 | Apple 一方框架 | 创建 19 天，pre-1.0，被引用 0；底层 purego 为 beta | [调研] |
| 无障碍与 Instruments | SwiftUI 自带；`OSSignposter` | 自绘 UI 的 VoiceOver 桥接未提及；signpost 需自写绑定 | [推断] |
| 打包 | Makefile 加 scripts，swift build ×2 后 lipo | `mygo build` 一条命令完成签名、公证、DMG、universal | [调研] |
| 跨平台 | 仅 macOS | 框架支持 Windows、Linux，但 `docs/PRODUCT.md` 无此目标，系统集成层需逐平台重写 | [实测][调研] |

综合：收益集中在打包链和理论上的跨平台，代价集中在 macOS 12 下限、视觉保真、召唤手势和长期维护。

## 与项目约束的冲突

对照 `AGENTS.md`：

- macOS 12 下限（`Package.swift:6`、`AGENTS.md:18`）：冲突，见「Go 版本与系统下限」。
- Liquid Glass 加旧系统回退（`docs/VISUAL.md:12-16`、`AGENTS.md:18`）：高风险，shader 仿真与系统玻璃不同，回退行为未知。
- 核心切换环不依赖 AX，AX 仅限 Action Arc（`AGENTS.md:16`）：可守，相关代码约 61 行，但需自写 AX 绑定。
- 无网络、无遥测（`AGENTS.md:17`）：不启用 updater 即可，仍需验证零联网。
- signpost 与双语本地化（`AGENTS.md:33-34`）：都需自写桥接或加载逻辑。
- 授权项（`AGENTS.md:56`）：`scripts/notarize.sh`、CI、`Resources/Info.plist`、LaunchAgent plist 的改动都需要明确授权。

## 风险与缓解

- 框架不稳定：pre-1.0 且发版极快。缓解：锁定版本并 vendor，把对 MyGo 的依赖收敛到一个薄适配层。
- purego 脆弱：回调不回收、需主线程、子类化易出错。缓解：所有 ObjC 调用集中在一个原生桥接包，并为其写集成测试。
- 功能缺口：松开事件、手势、AX、NSWorkspace 都要自写。缓解：这些正是 spike 的验证项，先验证再决定。
- 数据迁移：偏好和 profile 不能丢。缓解：保持 bundle ID 与偏好域不变，经 CFPreferences 读写。
- 回退路径：重写失败不能影响现有用户。缓解：重写期间 Swift 版保持可发布，在独立分支或 worktree 开发。

## 验证范围（若推进）

先在独立分支或 worktree 做 1–2 周 spike，不改主线。任一项不通过即终止重写：

1. 非激活透明 Panel 在全屏 App 上方召唤。先在 Swift 版测出「热键到首帧」基线（现有数据只有淡入 120 ms 和冷启动），再测 MyGo 版，并单测空闲数分钟后的首次召唤。建议阈值：不劣于基线 20 ms 以上。
2. 按住召唤、松开确认：自写 purego 的 Carbon 松开事件，并验证 double-tap 修饰键。
3. 触控板平移和捏合、非激活 Panel 内的 hover 与非矩形命中。
4. 常驻物理内存（`vmmap -summary`）与现状 26 MB 同口径对比。建议阈值：不超过现状的 1.5 倍。
5. Go 1.27 产物能否在 macOS 12 上启动并完成召唤。

阈值是建议值，由决策人在启动 spike 前确认。

## 未验证事项

- 官网 7 / 44 / 62 MB 的测量条件和指标含义。
- 不用 updater 时是否零联网、有无遥测。
- 玻璃插件在 macOS 12–25 的实际表现。
- MyGo 文档内容经 WebFetch 摘要获得，未通读源码，也没有编译或运行任何 MyGo 示例。
- 标 [调研] 的代码行号已抽查，均与源码一致；LOC 分类、测试拆分（2,682 / 450 / 48 行）、AX 相关代码约 61 行等统计值来自审计，未逐条复核。已复核的统计：228 个用例、51 处 `@MainActor`、185 个中英本地化键、31 个偏好键。
- Halo 内存基线是单次空闲测量，未覆盖召唤后和长时间运行。

## 来源

- MyGo：[官网](https://mygo.egoist.dev/)、[architecture](https://mygo.egoist.dev/docs/architecture)、[windows](https://mygo.egoist.dev/docs/windows)、[launchers](https://mygo.egoist.dev/docs/launchers)、[native](https://mygo.egoist.dev/docs/native)、[ui/input](https://mygo.egoist.dev/docs/ui/input)、[ui/drawing](https://mygo.egoist.dev/docs/ui/drawing)、[plugins/glass](https://mygo.egoist.dev/docs/plugins/glass)、[distribution](https://mygo.egoist.dev/docs/distribution)、[configuration](https://mygo.egoist.dev/docs/configuration)、[updates](https://mygo.egoist.dev/docs/updates)、[仓库](https://github.com/egoist/mygo)、[releases](https://github.com/egoist/mygo/releases)、[pkg.go.dev](https://pkg.go.dev/github.com/egoist/mygo)
- Go：[Go 1.27 发行说明](https://go.dev/doc/go1.27)、[Go 1.26 发行说明](https://go.dev/doc/go1.26)、[Go FAQ](https://go.dev/doc/faq)
- purego：[仓库](https://github.com/ebitengine/purego)、[API 文档](https://pkg.go.dev/github.com/ebitengine/purego)
- 同类对比：[Pake 基准](https://zenn.dev/gixo/articles/pake-electron-measured?locale=en)、[Wails/Tauri/Electron 对比](https://github.com/Elanis/web-to-desktop-framework-comparison)
