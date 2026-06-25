<div align="center">

# MicTether · 声锚

**把 macOS 的默认麦克风 / 扬声器牢牢钉在你选定的设备上。**
*Lock your preferred macOS input & output devices — new gadgets plug in, your sound stays put.*

macOS 13+ · Swift + SwiftUI + CoreAudio · 菜单栏常驻 · 不录音 · 零网络 · MIT

</div>

---

## 这是什么

每次插入一个新的 USB 声卡、连上 AirPods、接上显示器自带音箱，macOS 都会"自作主张"地把系统默认输入/输出切过去——开会时麦克风莫名其妙变成了摄像头麦，音乐突然从笔记本扬声器里炸出来。

**MicTether 让这件事不再发生。** 你指定一个首选麦克风和一个首选扬声器，它就在后台盯着系统默认设备，一旦被别的设备抢走，立刻、安静地切回来。

它锁定的是**系统默认输入 / 输出 / 系统音效输出**三者，不是逐 App 路由——简单、可靠、符合直觉。

## 核心特性

- 🎤 **输入与输出同时锁定** —— 麦克风和扬声器各自独立钉死在你的首选设备上。
- 🔁 **三级回退** —— 首选设备离线时，回退到你显式指定的备选设备，或自动记住的"上一个手动用过的设备"。
- 🎧 **AirPods / 蓝牙专项处理** —— 识别蓝牙传输与 HFP/A2DP，双端点原子同步切换 + 2.5s 协商保护期，专治蓝牙耳机"切不过去 / 反复抖动"的老毛病。
- 🪶 **去抖动** —— 0.9s 路由稳定窗口吸收插拔瞬间的抖动事件，不误判、不空切。
- 🚀 **开机自启** —— 基于沙盒安全的 `SMAppService`。
- 🌐 **中英文自动切换** —— 跟随系统语言。
- 🔒 **隐私干净** —— 只调用 CoreAudio 切换默认设备，**从不采集 / 录制任何音频**，无网络请求，无遥测。

## 隐私说明

MicTether **不读取、不录制、不上传任何音频**。它做的唯一一件事是调用 CoreAudio 的 `AudioObjectSetPropertyData` 设置"系统默认设备"——和你在"系统设置 → 声音"里手动点选是同一个动作。因此本应用：

- 不需要麦克风权限（`NSMicrophoneUsageDescription`），缺失是正确的；
- `entitlements` 为空但开启 App Sandbox，沙盒下设置默认设备无需录音权限；
- 隐私清单仅声明 `UserDefaults` 用途（保存你的设备偏好）。

## 构建

依赖 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
# 生成 Xcode 工程（.xcodeproj 不入库，由 project.yml 重新生成）
xcodegen generate

# 用 Xcode 打开开发
open MicTether.xcodeproj

# 或一键打包未签名 DMG（仅供本机自用）
./build_dmg.sh
```

> ⚠️ **关于分发签名**：`build_dmg.sh` 产出的是 ad-hoc 签名包，在别人的 Mac 上会被 Gatekeeper 拦截（提示"无法验证开发者"）。要公开分发，需用 Apple Developer ID 证书签名并做 notarization（公证）。开源使用者可自行 `xattr -dr com.apple.quarantine MicTether.app` 解除隔离后运行。

## 架构

菜单栏 App（`LSUIElement`）：AppKit 承载状态栏图标与无边框浮窗，浮窗内容是 SwiftUI。核心是一个"监听 → 去抖 → 评估 → 强制切回 → 防自激"的闭环状态机。

```
MicTether/
├── project.yml                  # XcodeGen 工程定义（唯一可信源，生成 .xcodeproj）
├── build_dmg.sh                 # 一键归档 + 打 DMG（未签名）
└── MicTether/
    ├── MicTetherApp.swift        # @main 入口 · AppDelegate · 状态栏 · 浮窗 · onboarding
    ├── MenuBarView.swift         # SwiftUI 设置面板（设备/语言下拉、开关、引导）
    ├── AutoSwitchViewModel.swift # 大脑：锁定状态机 · 去抖 · 三级回退 · 蓝牙双端点同步
    ├── AudioDeviceManager.swift  # CoreAudio HAL 薄封装：枚举设备 · 监听变化 · 设默认设备
    ├── LocalizationManager.swift # i18n 单一真相源（可切换语言，持久化）
    ├── AppStrings.swift          # 中英文文案字典 + 语言枚举
    ├── LaunchAtLoginManager.swift# 开机自启（SMAppService）
    ├── ReleaseConsistencyChecker.swift # 运行包 bundleId 自检日志
    ├── StatusBarIcon.swift       # 状态栏船锚图标（NSBezierPath 矢量绘制）
    ├── NativeSelect.swift        # 定宽下拉组件（SwiftUI 闭合态 + 原生 NSMenu）
    ├── ShadcnSwitch.swift        # 自绘开关（开绿/关灰轨道）
    ├── Info.plist · *.entitlements · PrivacyInfo.xcprivacy
    └── Resources/AppIcon.icns
```

> 详尽的逐文件职责见各目录 `CLAUDE.md`。

## 已知限制 / Roadmap

这些是代码审计中识别出的健壮性改进点，不影响日常使用，欢迎 PR：

- [ ] **HAL 回调线程上做了同步属性读取** —— Apple 建议监听回调里只做最少工作，应把读取抛回主线程再做（`AudioDeviceManager`）。
- [ ] **单例监听器在进程生命周期内不注销** —— 当前菜单栏常驻无害，但不利于未来多实例 / 重建场景。
- [ ] **启动时 `didSet` 风暴** —— init 阶段连续触发 5~6 次完整策略评估，可合并为一次。
- [ ] **`AppStrings` 残留约 11 个未被引用的死翻译串**，可清理。
- [ ] 蓝牙各档延迟为硬编码经验值（0.6 / 1.2 / 2.0 / 2.5s），可配置化。

## License

[MIT](LICENSE) © zimin
