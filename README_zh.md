# Halo

一款 macOS 上的环形启动器，灵感源自解谜游戏《Hue》的色环机制。一个手势在常用应用间切换：按下热键，指向方向，松开。

单一、自包含的 macOS 应用。**核心切换流程不需要辅助功能（Accessibility）权限**。

[English README](README.md)

## 状态

**v1.0** — 首个公开版本。macOS 26 完整启用 Liquid Glass Halo，macOS 14 / 15 回退至 NSVisualEffectView。支持双击 ⌘ 作为第二触发方式。基于色度加权色相直方图的身份色提取。详见 [CHANGELOG.md](CHANGELOG.md)。

## 安装

需要 **macOS 12（Monterey）及以上**。以 **通用二进制**（Apple Silicon + Intel）发布。Liquid Glass 表面材质在 macOS 26（Tahoe）上点亮；macOS 12 / 13 / 14 / 15 自动回退到 `NSVisualEffectView`，视觉配方保持一致。

```sh
make install      # release 编译 + ad-hoc 签名 + 拷贝到 /Applications
open /Applications/Halo.app
```

或构建可分发的 zip：

```sh
make dist         # 产出 dist/Halo-v1.0.0.zip
```

## 使用

1. **按 `⌘ ⌥ Space`**（或单独双击 `⌘`）在光标处召唤 Halo。
2. **移动光标**——或按方向键 / 数字键——高亮目标槽位。
3. **松开热键**——或点击 / 按 `Return`——完成切换。`ESC` 取消。
4. **菜单栏图标**用于无键盘召唤和打开「设置」。

最常用的 **N** 个槽位（可配置 4 / 6 / 8 / 10 / 12）由过去 7 天内激活次数最多的应用填充。频率模型（仅 MFU / 平衡 / 仅 MRU）在「设置」中可调。在「Pins / 颜色」标签下可将特定应用钉到指定槽位，或覆写其身份色。

## 设置（菜单栏 → 设置…）

- **行为** — 槽位数量、频率模型、召唤位置、开机自启、重置引导。
- **热键** — 实时重绑定主热键（Liquid Glass 键帽），或调整双击 ⌘ 时间窗（0.15–0.50 秒）。
- **Pins** — 把特定应用锁定到特定槽位。应用选择器使用原生 `.searchable` 工具栏字段。Pins 在槽位数量变化后仍保留。
- **颜色** — 按 pin 应用单独覆写身份色。
- **关于** — 版本信息。

## 开发

```sh
make build        # debug 构建
make test         # 27 个单元测试（engine、store、switcher、OKLCH 数学、prefs、冲突解析器）
make app          # 产出 dist/Halo.app（release，ad-hoc 签名）
make clean        # 清除 .build 和 dist
```

## 项目结构

```
Sources/HaloCore        无 UI 内核：engine、usage store、switcher、OKLCH、prefs
Sources/HaloUI          SwiftUI 视图 + Carbon 热键 + 透明 NSPanel
Sources/HaloApp         AppDelegate、设置窗口、Pin 选择器、LaunchAgent
Tests/HaloCoreTests     27 个单元测试
Resources/              Info.plist、Halo.icns、Halo.iconset
scripts/                build-app.sh、render-icon.swift
docs/                   产品 / 交互 / 视觉规格（中文）
mockups/halo.html       单文件可点击 UI 原型
```

## 文档

- [产品设计](docs/PRODUCT.md)
- [交互规格](docs/INTERACTION.md)
- [视觉规格](docs/VISUAL.md)
- [CHANGELOG.md](CHANGELOG.md)

## 权限

Halo **不需要辅助功能权限**。激活追踪使用 `NSWorkspace` 通知；切换使用 `NSWorkspace.activate` / `openApplication`；热键使用 Carbon `RegisterEventHotKey` 与 `NSEvent.modifierFlags` 轮询。无 event tap，不读取辅助功能树。

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
| `halo.prefs.pinnedSlots.v1` | Data (JSON) | `[String?]` — 每个槽位钉住的 bundle ID，按槽位索引 |
| `halo.prefs.overflowPins.v1` | Data (JSON) | `[String]` — 当前槽位数容纳不下的 pin |
| `halo.prefs.identityOverride.v1` | Data (JSON) | `{ bundleID → OKLCH }` — 按应用单独覆写身份色 |
| `halo.usage.v1` | Data (JSON) | **滚动 7 天的激活日志。** 对于每个切换过的应用：bundle ID、显示名、激活时间戳数组。读取时丢弃 7 天以前的记录。 |
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
