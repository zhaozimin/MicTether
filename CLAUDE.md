# MicTether · 声锚 — 把 macOS 默认音频输入/输出钉死在首选设备上的菜单栏工具
Swift + SwiftUI + AppKit + CoreAudio(HAL) + ServiceManagement · macOS 13.0+ · XcodeGen

<directory>
MicTether/ - 应用源码 (1 个 target, 11 个 Swift 文件 + 配置 + 图标资源)
</directory>

<config>
project.yml - XcodeGen 工程定义，唯一可信源；target=MicTether，bundleId=com.zimin.MicTether，沙盒开启，LSUIElement 菜单栏应用
build_dmg.sh - 一键 archive + 打 DMG（ad-hoc 签名，公开分发需自行 Developer ID 签名 + 公证）
.gitignore - 忽略 *.xcodeproj（由 project.yml 生成）、build/、*.dmg、macOS 杂物
README.md - 公开文档：定位/特性/隐私/构建/架构/已知限制
LICENSE - MIT
</config>

法则: 极简·稳定·导航·版本精确。只切设备不录音——隐私边界即架构边界。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
