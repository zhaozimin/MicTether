# MicTether/
> L2 | 父级: ../CLAUDE.md

## 成员清单

MicTetherApp.swift: @main 入口。`AppDelegate` 装配状态栏图标(NSStatusItem,船锚矢量模板图标 StatusBarIcon)、无边框浮窗(NSWindow + NSHostingController 承载 SwiftUI)、主菜单(文本编辑快捷键)、首启 onboarding；持有 viewModel/launchAtLoginManager/onboardingManager/localizationManager；Combine 订阅语言变化→重建原生菜单/状态栏/重排浮窗。`OnboardingManager` 用 UserDefaults 记忆是否看过引导。

MenuBarView.swift: SwiftUI 设置面板(宽 348)。摘要区用 App 图标(NSApplicationIcon);logo 下方一排半宽双广告卡(`adCard` 参数化构造器统一卡片外壳,紧凑单行=图标+短标签+跳转箭头——左主页 globe→zhaozimin.com + 右 GitHub octocat→zhaozimin/MicTether 仓库,整卡可点 NSWorkspace 打开外链);4 个设备选择 + 1 个语言选择全部用 NativeSelect 组件(恒 controlWidth=184,等宽右对齐);自动切换/开机自启用自绘 ShadcnSwitch(开绿关灰轨道);引导卡片 + 设备在线状态点 + 退出按钮。文案全部取自注入的 localization,失焦自动隐藏。

GitHubMark.swift: GitHub 官方 Octocat 矢量剪影 `GitHubMark: Shape`(SF Symbols 无此 logo),内含迷你 SVG 路径解析器(M/L/H/V/C/S/A/Z 绝对+相对、椭圆弧→cubic 贝塞尔),等比居中缩放;被 MenuBarView logo 下方 GitHub 广告卡 fill 消费。

NativeSelect.swift: shadcn NativeSelect 风格定宽下拉组件 `NativeSelect<Value>`。闭合态纯 SwiftUI 自绘(描边盒+rounded-md+单下箭头+占位 muted,渲染可控)、展开态点击弹原生 NSMenu(透明 NSView 覆盖层捕获点击,带勾选);弃用渲染不可控的 SwiftUI Menu。

ShadcnSwitch.swift: shadcn Switch 风格自绘开关 `ShadcnSwitch`。开→绿轨道、关→灰轨道,白滑块 offset+弹簧动画滑动,轨道底色即状态反馈;替代 .tint 在 macOS 上不可靠的原生 Toggle。

LocalizationManager.swift: i18n 单一真相源(@MainActor 单例 ObservableObject)。`@Published preference`(LanguagePreference)持久化到 UserDefaults→解析为具体 language→渲染为 strings,数据单向流动;切换即触发全 UI 重渲染。

StatusBarIcon.swift: 状态栏船锚图标的代码矢量绘制器。`enum StatusBarIcon.anchor(pointSize:)` 用 NSBezierPath 在 24x24 归一化坐标描边(锚眼+锚杆+横杆+底部锚臂弧+实心锚爪),isTemplate=true 自动适配明暗菜单栏;纯几何、无 emoji、无 bundle 资源。

AutoSwitchViewModel.swift: 大脑(@MainActor, ObservableObject)。锁定状态机——监听设备变化→0.9s 去抖窗口→evaluateRoutingPolicy→偏离首选则强制切回。三级回退(preferred/learned)；pendingProgrammatic UID 防自激；蓝牙双端点原子同步锁定(linkedBluetoothCoSwitch)+2.5s HFP 协商保护期(治 AirPods 抖动)。所有偏好持久化到 UserDefaults。

AudioDeviceManager.swift: CoreAudio HAL 薄封装(单例 shared)。枚举设备并读取元数据(name/uid/传输类型/采样率/通道数/路由组/canBeDefaultSystemOutput)；监听三类系统事件(设备插拔/默认输入变/默认输出变)；setDefault{Input,Output}Device(含幂等校验)。全部用现代非废弃 API(kAudioObjectPropertyElementMain)。

AppStrings.swift: 纯文案字典 + 语言枚举。`enum AppLanguage`(english/simplifiedChinese 两枚举,`systemResolved` 按 `Locale.preferredLanguages` 前缀解析) + `enum LanguagePreference`(system/english/simplifiedChinese,可持久化 rawValue,把"跟随系统"特殊态在 `resolvedLanguage` 一次性解析掉) + `struct AppStrings`(switch 返回硬编码中英文案,非 .strings)。语言决策已上移至 LocalizationManager,本文件无可变状态。

LaunchAtLoginManager.swift: 开机自启，基于 `SMAppService.mainApp`(沙盒安全)；非 /Applications 目录时给友好错误(文案语言走 LocalizationManager)。

ReleaseConsistencyChecker.swift: 启动自检，比对运行包 bundleId 是否等于 com.zimin.MicTether，不一致仅 print 告警。

Info.plist / MicTether.entitlements / PrivacyInfo.xcprivacy: 应用元数据 / 空 entitlements(沙盒开启,不录音故无需录音权限) / 隐私清单(仅声明 UserDefaults 用途)。

Resources/AppIcon.icns: 应用图标。

法则: 成员完整·一行一文件·父级链接·技术词前置。隐私铁律——只调用 CoreAudio 切默认设备，永不采集/录制音频。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
