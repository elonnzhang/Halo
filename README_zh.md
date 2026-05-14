# Halo

一款 macOS 上的环形启动器，灵感源自解谜游戏《Hue》的色环机制。一个手势在常用应用间切换：按下热键，指向方向，松开。

单一、自包含的 macOS 应用。**核心切换流程不需要辅助功能（Accessibility）权限**。

[English README](README.md)

## 状态

**v1.1**（2026-05-14）—— 设置面板重建为原生 `NavigationSplitView` + `Form(.grouped)`；五选一双击触发器（⌥ 左 / ⌥ 右 / ⌘ / ⌃ / 鼠标中键）；新增「白名单」标签可在指定应用内静默 Halo；面板缩放（0.80–1.50×）；滚轮切换槽位；macOS 26 完整 Liquid Glass。`Switcher` 异步等待真实启动结果——损坏的 bundle 现在会触发抖动提示而非静默消失。详见 [CHANGELOG.md](CHANGELOG.md)。

## 安装

需要 **macOS 12（Monterey）及以上**。以 **通用二进制**（Apple Silicon + Intel）发布。Liquid Glass 表面材质在 macOS 26（Tahoe）上点亮；macOS 12 / 13 / 14 / 15 自动回退到 `NSVisualEffectView`，视觉配方保持一致。

```sh
make install      # release 编译 + ad-hoc 签名 + 拷贝到 /Applications
open /Applications/Halo.app
```

或构建可分发的 zip：

```sh
make dist         # 产出 dist/Halo-v1.1.0.zip(版本号取自 Info.plist 的 CFBundleShortVersionString)
```

## 使用

1. **按 `⌘ ⌥ Space`**（或单独双击 `⌘`）在光标处召唤 Halo。
2. **移动光标**——或按方向键 / 数字键——高亮目标槽位。
3. **松开热键**——或点击 / 按 `Return`——完成切换。`ESC` 取消。
4. **菜单栏图标**用于无键盘召唤和打开「设置」。

最常用的 **N** 个槽位（可配置 4 / 6 / 8 / 10 / 12）由过去 7 天内激活次数最多的应用填充。频率模型（仅 MFU / 平衡 / 仅 MRU）在「设置」中可调。在「Pins / 颜色」标签下可将特定应用钉到指定槽位，或覆写其身份色。

## 设置（菜单栏 → 设置…）

四个标签,原生侧栏布局（macOS 13+ 用 `NavigationSplitView`,macOS 12 用自建 HStack 回退）。默认 880 × 720,最小 760 × 600,可缩放。

- **通用**
  - *召唤位置与排序* —— 槽位数量(4 / 6 / 8 / 10 / 12)、光标 vs 屏幕中心、频率模型(最常用 / 平衡 / 最近用)。
  - *触发键* —— 实时重绑定主热键(macOS 26 上 Liquid Glass 键帽);五选一双击辅助键(⌥ 左 / ⌥ 右 / ⌘ / ⌃ / 鼠标中键);双击间隔(0.15–0.50 秒)。
  - *导航与切换* —— 滚轮切换槽位、数字键提交(1–9, 0, −, =)、召唤时高亮当前应用。
  - *外观与轮盘布局* —— **面板大小** 渲染期统一缩放(0.80–1.50×) + Halo 直径 / 图标尺寸 / 图标距中心三项基准 slider + 重置布局。
  - *启动与诊断* —— 开机自启、重播欢迎引导、重置首次提示、导出诊断日志。
  - *语言* —— 系统 / English / 简体中文(重启生效)。
- **Apps** —— 用绑定轮盘把特定应用钉到特定槽位;每个槽位的弹出菜单内可改身份色或取消 pin。Pins 在槽位数量变化后仍保留(超额部分自动暂存)。
- **白名单** —— 列出 Halo 触发被屏蔽的 bundle ID(IDE、设计工具、远程桌面、游戏)。「应用推荐」按 `WhitelistSuggestions.installedSubset()` 填充,只包含系统中实际安装的应用。Carbon 热键注册始终保留,组合键不会泄漏到其它应用。
- **关于** —— 渐变图标徽章、版本号、GitHub / 许可证链接、运行时元数据、内嵌「导出诊断日志」按钮。

## 开发

```sh
make build        # debug 构建
make test         # 88 个单元测试,分布在 HaloCoreTests + HaloUITests
make app          # 产出 dist/Halo.app(release,ad-hoc 签名)
make clean        # 清除 .build 和 dist
```

## 项目结构

```
Sources/HaloCore        无 UI 内核:engine、usage store、AppRuntime / Switcher、OKLCH、prefs、SlotCycle、WhitelistSuggestions
Sources/HaloUI          SwiftUI 视图 + Carbon 热键 + DoubleTapMonitor + NSPanel + NSWorkspaceRuntime
Sources/HaloApp         AppDelegate、设置窗口(NavigationSplitView)、Whitelist 标签、Pin 选择器、LaunchAgent
Tests/HaloCoreTests     纯逻辑:engine、store、switcher、OKLCH、prefs、SlotCycle、whitelist、AppPreferences 边界
Tests/HaloUITests       视图层:RadialGeometry 命中测试、HaloState 状态转移、DoubleTapMonitor 状态机、scrollAnchor 生命周期
Resources/              Info.plist、*.lproj/Localizable.strings(en + zh-Hans)、Halo.icns、Halo.iconset
scripts/                build-app.sh、render-icon.swift
docs/                   产品 / 交互 / 视觉 / 设置规格(中文,v1.1 状态条内联)
mockups/                可点击 UI 原型 —— halo.html(实时轮盘)、halo-settings.html、halo-redesign.html
```

## 文档

- [产品设计](docs/PRODUCT.md)
- [交互规格](docs/INTERACTION.md)
- [视觉规格](docs/VISUAL.md)
- [CHANGELOG.md](CHANGELOG.md)

## 权限

Halo **完全不需要辅助功能权限**。两条触发路径都用被动状态查询:主组合键走 Carbon `RegisterEventHotKey`;双击辅助键盘路径轮询 `CGEventSource.keyState`(keyCode 级别, 左右 Option / Control 可区分), 中键路径读 `NSEvent.pressedMouseButtons` bitmask。激活追踪走 `NSWorkspace` 通知。无 event tap、不读取辅助功能树、无输入监控。

## 数据与隐私

Halo **完全在本地运行**。无网络请求、无遥测、无分析，没有任何数据发往第三方。「设置 → 通用 → 导出诊断日志…」是唯一会把本地数据暴露出来的入口，且也只是写一个文件到 `~/Downloads/`，由你自己决定是否分享。

### 存了什么、存在哪

以下路径默认指当前用户。

**User defaults — `~/Library/Preferences/com.halo.launcher.plist`**（由 macOS 管理，通过 `UserDefaults` 写入）：

| 键 | 类型 | 含义 |
|---|---|---|
| `halo.prefs.slotCount` | Int | 槽位数量（4 / 6 / 8 / 10 / 12） |
| `halo.prefs.profile` | String | 频率模型（`mfuOnly` / `balanced` / `mruOnly`） |
| `halo.prefs.summonPosition` | String | `mouse` 或 `center` |
| `halo.prefs.hotkey.keyCode` | Int | 主热键 key code |
| `halo.prefs.hotkey.mods` | Int | 主热键修饰键位掩码 |
| `halo.prefs.cmdDoubleTapGap` | Double | 双击 ⌘ 的时间窗，秒 |
| `halo.prefs.cmdHoldDuration` | Double | 旧版长按时长（仅保留以便迁移） |
| `halo.prefs.autostart` | Bool | 是否安装了 LaunchAgent |
| `halo.prefs.languageOverride` | String? | `nil` 跟随系统，或 `"en"` / `"zh-Hans"` |
| `AppleLanguages` | [String] | 镜像自 `languageOverride`（系统识别的键），下次启动 Foundation 据此取词 |
| `halo.prefs.doubleTapTrigger` | String | `leftOption` / `rightOption` / `command` / `control` / `middleMouse` 之一 |
| `halo.prefs.scrollToSwitch` | Bool | 滚轮切换高亮槽位 |
| `halo.prefs.numberKeyCommit` | Bool | 数字键 1–9 0 - = 直接提交对应槽位 |
| `halo.prefs.highlightFrontmostOnSummon` | Bool | 召唤后第一次滚动锚定到前台应用所在槽位 |
| `halo.prefs.layout.hudDiameter` | Double | Halo 外径,280–440 pt(存储键沿用旧名) |
| `halo.prefs.layout.iconSize` | Double | 槽位图标大小,36–64 pt |
| `halo.prefs.layout.iconRadius` | Double | 图标距圆心距离,受 hub + 边缘衰减约束 |
| `halo.prefs.layout.panelScale` | Double | 渲染期统一缩放,0.80–1.50× |
| `halo.prefs.pinnedSlots.v1` | Data (JSON) | `[String?]` — 每个槽位钉住的 bundle ID,按槽位索引 |
| `halo.prefs.overflowPins.v1` | Data (JSON) | `[String]` — 当前槽位数容纳不下的 pin |
| `halo.prefs.identityOverride.v1` | Data (JSON) | `{ bundleID → OKLCH }` — 按应用单独覆写身份色 |
| `halo.prefs.whitelist.v1` | Data (JSON) | `[String]` — Halo 触发被屏蔽的 bundle ID |
| `halo.usage.v1` | Data (JSON) | **滚动 7 天的激活日志。** 每次写入时已就地裁剪(不再无限增长)。 |
| `halo.welcome.shown` | Bool | 首次启动的欢迎覆盖层已看过 |
| `halo.onboarding.shown` | Bool | 首次召唤的 Halo 提示已看过 |

**诊断日志 — `~/Library/Logs/Halo/`**：

| 文件 | 内容 |
|---|---|
| `halo.log` | 纯文本活动日志（当前）。ISO-8601 时间戳 + 类别 + 消息 —— 热键注册、Halo 召唤 / 提交 / 取消、切换结果、身份色提取、设置变更、引导事件。**包含你切换过的应用 bundle 标识符。** 不含应用内容、按键、窗口标题、截图。 |
| `halo.log.1` | 滚动后的前一份文件（5 MB 时滚动）。 |

**LaunchAgent — `~/Library/LaunchAgents/com.halo.launcher.plist`**（仅在启用「登录时启动 Halo」时存在）：

标准 launchd plist，指向 `/Applications/Halo.app/Contents/MacOS/Halo`。由 `LaunchAgentManager` 写入；关闭自启时移除。

### 不会记录的内容

- Halo 自身热键监听之外的按键（不是 keylogger）
- 窗口标题或文档名称
- 屏幕内容、截图、辅助功能树数据
- 网络活动（Halo 自身不发起网络）
- 应用停留时长 —— 只记录激活那一瞬
- 任何应用的内容 —— Halo 只看得到你切换到了哪个 bundle ID

### 重置到首次启动状态

用于测试新用户流程或从损坏状态恢复：

```sh
# 停止 Halo
killall Halo

# 清除瞬时状态（引导标志 + 7 天使用日志 + pins + 覆写 + 诊断日志）。
# 槽位数、热键绑定、语言、自启保持不变。
defaults delete com.halo.launcher halo.welcome.shown
defaults delete com.halo.launcher halo.onboarding.shown
defaults delete com.halo.launcher halo.usage.v1
defaults delete com.halo.launcher halo.prefs.pinnedSlots.v1
defaults delete com.halo.launcher halo.prefs.overflowPins.v1
defaults delete com.halo.launcher halo.prefs.identityOverride.v1
rm -f ~/Library/Logs/Halo/halo.log ~/Library/Logs/Halo/halo.log.1

open /Applications/Halo.app
```

### 彻底卸载（清掉 Halo 写过的每一个字节）

```sh
killall Halo
rm -rf /Applications/Halo.app
defaults delete com.halo.launcher
rm -rf ~/Library/Logs/Halo
rm -f  ~/Library/LaunchAgents/com.halo.launcher.plist
```

### 实时查看日志（开发者）

```sh
# 跟踪文本日志
tail -F ~/Library/Logs/Halo/halo.log

# 或通过 unified logging 流（Console.app 过滤）
log stream --predicate 'subsystem == "com.halo.launcher"' --level debug
```

「设置 → 通用 → **导出诊断日志…**」会把 `halo.log` + `halo.log.1` 加上一段头信息（Halo 版本、macOS 版本、硬件型号）打包到 `~/Downloads/Halo-diagnostic-<时间戳>.log`，方便随 bug 报告分享。

## 语言

规格文档的主要工作语言是中文。等实现稳定后再补英文镜像。

## 许可

MIT — 见 [LICENSE](LICENSE)。
