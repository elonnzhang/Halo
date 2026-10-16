# ALL 面板：Apple Watch 风格动效

日期：2026-10-13。范围：ALL 的蜂窝入场、焦点投影、平移、缩放与命中测试。

## 设计目标

蜂窝像一块连续的曲面：用户移动时图标跟手穿过焦点，大小自然变化；松手后短促减速。保留 macOS 原生应用图标、键盘搜索和固定的 profile 标签栏。

## 参考与取舍

- [Lucas Menge — WatchSpringboard-Prototype](https://github.com/lmmenge/WatchSpringboard-Prototype)：阅读 `LMSpringboardView.m` 中的 `LM_transformView:` 与滚动代理。借鉴稳定的图标网格、随视口连续变化的缩放/位移，以及原生滚动惯性。Halo 使用自己的 Swift 几何，保留方形应用图标。
- [Janum Trivedi — Wave](https://github.com/jtrivedi/Wave)：借鉴 retargeting 时保留当前位置和速度。Halo 在连续滚轮输入之间延续临界阻尼弹簧的速度，不引入依赖。
- [Apple — Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)：直接操控保持一对一反馈，新的操作可以中断进行中的动画。

## 动效规格

| 场景 | 行为 | 参数 |
| --- | --- | --- |
| 切入 ALL | 中心向外轻微展开与淡入，每次重新进入都播放 | 位置/大小 0.92 → 1；spring response 0.38、damping 0.86；径向延迟最多 65ms |
| 焦点变化 | 中心大、边缘小；跨过焦点半径时变化速度连续 | smoothstep；原有按应用数量配置的 scale/radius；向中心收拢最高 12% |
| 鼠标拖动背景 | 跟手，松手后沿预测方向短促滑行；再次拖动立即接管当前位置 | 指数衰减 8/s；预测行程最长 260pt；剩余距离 < 0.25pt 时停止 |
| 触控板双指平移 | 直接消费系统滚动与 momentum，不叠加第二段惯性 | 与鼠标共用边界 |
| 鼠标滚轮缩放 | 每次滚动更新目标，延续当前速度；反向滚动也连续 | 临界阻尼，角频率 24/s；范围 0.5×–2.5× |
| 触控板捏合 | 使用同一套位置、大小与鱼眼投影连续更新；松手不换算法 | 范围 0.5×–2.5× |
| 图标经过 profile 标签栏 | 按最终投影位置及图标尺寸淡出，经过后恢复 | 不交换槽位；透明图标不参与命中 |
| 搜索/排序变化 | 短促、克制的重新排列 | spring response 0.28、damping 0.88 |
| Reduce Motion | 入场仅 50ms 淡入，禁用空间展开、鼠标惯性及滚轮弹簧 | 保留必要的直接操控反馈 |

正常浏览隐藏图标名称，悬停或搜索时显示；底部名称提示保持固定。图标运动期间暂停鼠标自动选择，静止光标不覆盖键盘选择。

## 实现边界

- `HoneycombViewportGeometry.swift`：固定槽位快照、平滑焦点投影、边界、指数惯性和弹簧解析公式。纯数学，无 UI 状态。
- `HoneycombGridView.swift`：每个 hosting view 一个布局缓存；仅应用数量、搜索布局、视口或标签栏变化时重建。pan/zoom 不改变缓存键。每帧只计算投影、可见范围及相同投影的命中矩形。
- `GridViewportMotion.swift` / `GridState.swift`：每个 grid 独立的短期运动任务。运动中更新的是实际呈现值，取消、退出或重新载入时停止。无全局运动状态；空闲时没有动画计时任务。
- `HaloGridWindow.swift`：仅光标移动才更新鼠标选中，避免 60Hz 光标轮询覆盖键盘搜索选中。
- 新的布局与投影使用 `PerfSignpost` 的 `watchLayout` / `watchViewportProject`；不改玻璃材质、不新增 AX、网络或第三方依赖；使用 macOS 12 已有 API。

## 验证与风险

数学与状态测试覆盖：跨标签栏移动不跳槽、焦点中心/边缘斜率连续、捏合结束投影一致、命中矩形与缩放一致、惯性边界、不同帧率的时间一致性、滚轮反向 retarget 的值/速度连续、Reduce Motion、重新接管及退出取消。

`HALO_PERF_LOG=1` 的同一 224-app / 240-frame CPU 工作量比较：移动 keep-out + 投影 41.65ms；缓存槽位 + 投影 3.70ms。这是测试中的几何成本，不能当作整页 GPU 帧率或实际屏幕流畅度。

本机验证：全套 228 tests / 0 failures，包含 `HoneycombGeometryTests` 36/0、`HoneycombViewportGeometryTests` 10/0、`RadialGeometryHitTestTests` 5/0、`GridViewportMotionTests` 7/0；`make app` 的 arm64 / x86_64 Release 构建和 ad-hoc 签名验证通过。另用临时原生 preview 容器加载改动前/后的真实 `HoneycombGridView`，捕获相同窗口尺寸的画面对比，操作背景拖动与 Replay。该容器不替代正式启动器的热键、窗口与启动流程验证。

自动化剩余限制：正式菜单栏应用在当前 Computer Use 中多次返回 `timeoutReached`；preview 的滚动/文字输入又遇到窗口定位和 ScreenCaptureKit `-3811` 错误，未完成这些 UI 检查。捏合、触控板 momentum 与 Wheel → ALL → Action Arc 的黄金路径仍需实机检查。

需要实机观察大量图标、快速反向缩放、跨标签栏平移与快速 ALL/Wheel 往返。macOS 12–25 与 macOS 26 的实际视觉分支需在对应系统验证；本机是 macOS 27。构建成功与纯数学测试不能替代这些 UI 验证。
