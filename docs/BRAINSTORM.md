# Halo 脑暴池

这份文档记录围绕 Halo 的未来想法。它不是 roadmap，也不是承诺清单；只保留那些能强化 Halo 核心气质的方向：**无权限、极快、视觉强、像游戏道具一样的 macOS 启动器**。

## 方向原则

- **先守住核心交互**：按住、指向、松开必须始终是最快路径。
- **默认本地优先**：不引入遥测、账号、云端同步或网络依赖。
- **权限渐进开启**：核心切换继续无辅助功能权限；需要额外权限的能力必须独立开关、清楚解释收益。
- **肌肉记忆优先**：空间位置、颜色身份和固定槽位要服务长期记忆，而不是频繁变化。
- **视觉为效率服务**：动画、玻璃、粒子和主题只增强反馈，不拖慢操作。

## 高优先级候选

### 场景环 Profiles

不同工作场景使用不同 Halo 环，例如 Coding、Design、Meeting、Writing。每个 Profile 可以拥有独立的 pins、槽位数量、颜色覆写、排序模型和白名单策略。

- 可手动切换，也可基于前台应用轻量推荐。
- 适合高级用户建立多套肌肉记忆。
- 可以从设置页先做最小版本：Profile 列表 + 复制当前配置。

### 二段手势 Action Ring

Halo 第一层继续负责 app 切换；停留、滚轮或按修饰键进入第二层动作环。第二层可以绑定常用动作，例如打开项目、触发快捷指令、新建窗口或打开目录。

- 不破坏当前最快切换路径。
- 让 Halo 从启动器进化成“操作系统道具”。
- 第一版可以只支持用户手动配置的 shell-free 本地动作：打开文件夹、打开 URL、运行 Shortcut。

### 可分享主题与配置卡片

一键导出自己的 Halo 配置卡片，隐藏隐私信息，只展示槽位、图标、颜色、主题和视觉风格。后续可支持 `.halo-theme` 或 `.halo-profile` 导入导出。

- 适合开源项目传播。
- 可以自然带动主题系统和 GitHub Pages 展示页。
- 导出时默认去除 bundle ID 以外的敏感本地状态。

## 产品玩法

### Spatial Memory Mode

强调固定槽位和空间记忆。用户可选择稳定模式，让特定应用始终固定在同一方向，减少排序变动带来的认知成本。

- 适合高频用户。
- 可配合 onboarding 讲清楚“方向就是快捷键”。
- 可以弱化标签，突出方向、图标和颜色。

### App Constellation 可视化

在设置页展示过去 7 天的应用使用星图。应用按使用频率、最近程度、身份色或类别漂浮排列，用来解释 Halo 为什么这样排序。

- 只使用本地已有 usage log。
- 兼具诊断、解释和展示价值。
- 可作为 About 或 General 页里的可展开视图。

### Focus-aware Whitelist

把白名单升级成“专注保护”。在游戏、远程桌面、全屏演示、设计工具内，Halo 可自动静默并在菜单栏给出轻提示。

- 保持 Carbon 热键注册，不把组合键泄漏给其它应用。
- 增加“为什么这次没有出现 Halo”的可解释性。
- 可结合推荐应用和当前白名单做状态页。

### First-run Interactive Tutorial

把首次引导做成 30 秒小关卡：用户按住热键、指向目标、松开，连续完成几次真实操作后进入正式使用。

- 比静态说明更符合 Halo 的游戏感。
- 可以降低“按住再松开”这种交互的理解成本。
- 可复用现有 welcome / onboarding 状态。

## 视觉与品牌

### Halo Trails

鼠标指向槽位时出现短促液态拖尾、光晕或色彩折射。视觉反馈要轻、快、可关闭。

- 强化“色环”和“指向”的感受。
- macOS 26 可使用更强 Liquid Glass 表达；旧系统保持简洁 fallback。

### Launch Burst

成功切换 app 时，从选中槽位释放一次短促光晕；失败时用抖动、色相闪烁或轻微弹回表达。

- 成功和失败反馈更明确。
- 可以复用当前 Switcher 真实启动结果。

### Theme Forge

允许用户用 OKLCH 生成整套 Halo 主题，例如 Vaporwave、Solarized、Terminal Green、Glass Candy。

- 和现有 identity color 能力天然契合。
- 可以先提供只影响 Halo 面板的主题，不改变 app 身份色。
- 后续支持导入导出主题包。

### Presenter Mode

录屏或演示时启用更大图标、更慢动画、更清晰标签和更高对比度，让 Halo 的 demo 更容易看懂。

- 对 README、官网、发布视频很有帮助。
- 可以作为 General 里的临时开关。

## 效率能力

### Per-App Actions

选中某个 app 后继续按住或按数字键，展开该 app 的常用动作。例如 Finder 展开 Downloads、Desktop、AirDrop；IDE 展开最近项目。

- 第一版可只支持手动配置。
- 避免自动读取窗口标题或文档内容。
- 可作为 Action Ring 的一个特化场景。

### Shortcuts Integration

允许槽位或动作触发 macOS Shortcuts。Halo 负责视觉入口，系统快捷指令负责具体自动化。

- 能力边界清楚。
- 本地优先，符合 macOS 生态。
- 需要在设置里提示可能的系统权限弹窗。

### Window Cycling Lite

核心模式仍只做 app 级切换；如果用户显式开启辅助功能权限，再解锁同 app 窗口切换或窗口选择。

- 权限必须渐进、可选、可解释。
- 无权限模式不能退化。
- 适合作为高级功能，不作为默认路径。

## 社区与传播

### README 交互 Demo

把 `mockups/halo.html` 打磨成可嵌入 GitHub Pages 的互动 demo，让用户不用安装也能体验“按住、指向、松开”的节奏。

- 对传播非常直接。
- 可以复用现有 mockups。
- 适合搭配发布视频和截图。

### Privacy Manifest Page

把 README 的隐私说明做成更直观的页面，突出 no network、no telemetry、no Accessibility required、local only。

- 强化信任标签。
- 适合官网、README badge、release note。
- 与项目差异化定位高度一致。

### Theme Pack JSON

定义轻量主题包格式，允许社区分享主题和视觉预设。

- 可以从纯视觉主题开始，不包含 pins。
- 后续再扩展 profile / action 配置。
- 导入时必须预览并确认。

## 开发者工具

### Diagnostic Viewer

设置里直接查看近期 hotkey、summon、commit、cancel、switch failure 事件，而不是只能导出日志。

- 方便用户自助排查。
- 也方便 issue 反馈。
- 需要默认隐藏敏感 bundle 信息或给出清晰提示。

### Config Doctor

检测损坏 bundle、失效 pins、不可启动 app、过期 overflow pins 和异常设置，一键清理或修复。

- 对长期使用很有价值。
- 能减少“为什么某个槽位不能打开”的困惑。
- 可复用 Switcher 的失败结果和 AppRuntime 能力。

### Replayable Debug Sessions

导出匿名化 Halo 状态，让开发者可复现用户排序、布局和切换问题。

- 默认脱敏 display name、bundle ID 或提供可选脱敏级别。
- 适合复杂 issue。
- 不包含窗口标题、屏幕内容或输入内容。

### Golden Visual Snapshots

为 Halo 环、设置页、Liquid Glass fallback 建立截图基准，减少视觉回归。

- 对 macOS 版本差异尤其有用。
- 可先覆盖核心轮盘和设置首页。
- 不要求每次都跑完整 UI 测试。

## 疯狂概念

### Color Memory Trainer

让用户逐步建立“应用 = 颜色 + 方向”的记忆。熟练后可以弱化文字标签，只保留图标、方向和色彩。

- 和 Hue 灵感强关联。
- 可以作为可选练习模式。

### Workspace Portal

一个槽位代表整个工作空间：打开多个 app、指定网页、项目目录和快捷指令。

- 很强大，但要避免变成复杂自动化平台。
- 适合在 Profiles 和 Action Ring 稳定后再考虑。

## 当前最推荐探索的三个方向

1. **场景环 Profiles**：最实用，能显著提升高级用户粘性。
2. **二段手势 Action Ring**：最能把 Halo 从启动器变成“操作系统道具”。
3. **可分享主题与配置卡片**：最利于传播，适合开源项目出圈。
