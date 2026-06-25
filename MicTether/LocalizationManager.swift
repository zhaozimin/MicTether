/**
 * [INPUT]: 依赖 Foundation 的 UserDefaults，依赖 Combine 的 ObservableObject；依赖 AppStrings/AppLanguage/LanguagePreference
 * [OUTPUT]: 对外提供 LocalizationManager 单例(可观察 preference)、解析后的 language 与 strings
 * [POS]: i18n 的单一真相源，被 MenuBarView/AppDelegate/LaunchAtLoginManager 观察与消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import Combine

// ============================================================================
// MARK: - LocalizationManager  语言单一真相源
// ----------------------------------------------------------------------------
// 数据如河流单向流动：
//     preference (唯一可变源·可含"跟随系统")
//        → language (解析为具体语言)
//           → strings (渲染为文案)
// preference 持久化到 UserDefaults；@Published 让 SwiftUI 在切换时自然重渲染。
// ============================================================================
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let preferenceKey = "LanguagePreference"

    /// 用户语言偏好——唯一可变源。改动即持久化，并触发全 UI 重渲染。
    @Published var preference: LanguagePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.preferenceKey)
        preference = stored.flatMap(LanguagePreference.init(rawValue:)) ?? .system
    }

    /// 解析后的具体语言（偏好为 .system 时跟随系统语言）
    var language: AppLanguage { preference.resolvedLanguage }

    /// 当前语言对应的文案字典
    var strings: AppStrings { AppStrings(language: language) }
}
