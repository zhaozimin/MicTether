/**
 * [INPUT]: 依赖 Foundation 的 Locale
 * [OUTPUT]: 对外提供 AppLanguage、LanguagePreference、AppStrings(全部界面文案)
 * [POS]: 纯文案字典 + 语言枚举；语言决策上移至 LocalizationManager，本文件不再持有可变状态
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

// ============================================================================
// MARK: - AppLanguage  具体语言（永远只有两枚举，不掺"跟随系统"）
// ============================================================================
enum AppLanguage {
    case english
    case simplifiedChinese

    /// 跟随系统时的解析结果：zh* → 简中，其余 → 英文
    static var systemResolved: AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .english
        }
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

// ============================================================================
// MARK: - LanguagePreference  用户偏好（系统 + 两语言；可持久化为 rawValue）
// ============================================================================
enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// 把"跟随系统"这一特殊态在此处一次性解析掉，下游只见具体语言
    var resolvedLanguage: AppLanguage {
        switch self {
        case .system:            return .systemResolved
        case .english:           return .english
        case .simplifiedChinese: return .simplifiedChinese
        }
    }

    /// 下拉项显示名：具体语言用母语自称(不随界面语言变)，唯"跟随系统"本地化
    func label(using strings: AppStrings) -> String {
        switch self {
        case .system:            return strings.languageFollowSystem
        case .english:           return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

// ============================================================================
// MARK: - AppStrings  文案字典（按 language 返回硬编码中英文案）
// ============================================================================
struct AppStrings {
    let language: AppLanguage

    var appName: String {
        switch language {
        case .english: return "MicTether"
        case .simplifiedChinese: return "声锚"
        }
    }

    var editMenuTitle: String {
        switch language {
        case .english: return "Edit"
        case .simplifiedChinese: return "编辑"
        }
    }

    var quit: String {
        switch language {
        case .english: return "Quit"
        case .simplifiedChinese: return "退出"
        }
    }

    var undo: String {
        switch language {
        case .english: return "Undo"
        case .simplifiedChinese: return "撤销"
        }
    }

    var redo: String {
        switch language {
        case .english: return "Redo"
        case .simplifiedChinese: return "重做"
        }
    }

    var cut: String {
        switch language {
        case .english: return "Cut"
        case .simplifiedChinese: return "剪切"
        }
    }

    var copy: String {
        switch language {
        case .english: return "Copy"
        case .simplifiedChinese: return "复制"
        }
    }

    var paste: String {
        switch language {
        case .english: return "Paste"
        case .simplifiedChinese: return "粘贴"
        }
    }

    var selectAll: String {
        switch language {
        case .english: return "Select All"
        case .simplifiedChinese: return "全选"
        }
    }

    var statusItemAccessibility: String {
        switch language {
        case .english: return "Audio switching"
        case .simplifiedChinese: return "音频切换"
        }
    }

    var targetInputTitle: String {
        switch language {
        case .english: return "Top priority microphone"
        case .simplifiedChinese: return "麦克风最高优先级"
        }
    }

    var targetOutputTitle: String {
        switch language {
        case .english: return "Top priority speaker"
        case .simplifiedChinese: return "音箱最高优先级"
        }
    }

    var targetSectionBadge: String {
        switch language {
        case .english: return "PRIORITY 1"
        case .simplifiedChinese: return "最高优先级"
        }
    }

    var fallbackInputTitle: String {
        switch language {
        case .english: return "Microphone fallback"
        case .simplifiedChinese: return "麦克风断开后回退"
        }
    }

    var fallbackOutputTitle: String {
        switch language {
        case .english: return "Speaker fallback"
        case .simplifiedChinese: return "音箱断开后回退"
        }
    }

    var automaticFallback: String {
        switch language {
        case .english: return "Remember current device"
        case .simplifiedChinese: return "自动记住当前"
        }
    }

    var notSpecified: String {
        switch language {
        case .english: return "Not set"
        case .simplifiedChinese: return "不指定"
        }
    }

    var selectedDeviceOffline: String {
        switch language {
        case .english: return "Selected device offline"
        case .simplifiedChinese: return "已选设备未连接"
        }
    }

    var autoSwitchOn: String {
        switch language {
        case .english: return "Automatic switching is on"
        case .simplifiedChinese: return "已启用自动切换"
        }
    }

    var autoSwitchOff: String {
        switch language {
        case .english: return "Automatic switching is off"
        case .simplifiedChinese: return "未开启切换"
        }
    }

    var appStoreEdition: String {
        switch language {
        case .english: return "App Store Edition"
        case .simplifiedChinese: return "App Store 购买版"
        }
    }

    var launchAtLogin: String {
        switch language {
        case .english: return "Launch at login"
        case .simplifiedChinese: return "开机自启"
        }
    }

    var quitButton: String {
        switch language {
        case .english: return "Quit"
        case .simplifiedChinese: return "退出"
        }
    }

    var priorityHint: String {
        switch language {
        case .english: return "These devices take over as soon as they are connected."
        case .simplifiedChinese: return "这些设备一旦连接，就会立即接管系统输入或输出。"
        }
    }

    var fallbackHint: String {
        switch language {
        case .english: return "Used when the top-priority device is unavailable."
        case .simplifiedChinese: return "当最高优先级设备不可用时，将回退到这里。"
        }
    }

    var currentChoice: String {
        switch language {
        case .english: return "Current choice"
        case .simplifiedChinese: return "当前选择"
        }
    }

    var fallbackSectionTitle: String {
        switch language {
        case .english: return "Fallback devices"
        case .simplifiedChinese: return "回退设备"
        }
    }

    var statusSectionTitle: String {
        switch language {
        case .english: return "Status"
        case .simplifiedChinese: return "状态"
        }
    }

    var microphoneSectionTitle: String {
        switch language {
        case .english: return "Microphone priority"
        case .simplifiedChinese: return "麦克风优先级"
        }
    }

    var speakerSectionTitle: String {
        switch language {
        case .english: return "Speaker priority"
        case .simplifiedChinese: return "音箱优先级"
        }
    }

    var primaryDeviceLabel: String {
        switch language {
        case .english: return "Primary device"
        case .simplifiedChinese: return "首选设备"
        }
    }

    var fallbackDeviceLabel: String {
        switch language {
        case .english: return "Fallback device"
        case .simplifiedChinese: return "备选设备"
        }
    }

    var activeSelectionLabel: String {
        switch language {
        case .english: return "Selected"
        case .simplifiedChinese: return "当前选择"
        }
    }

    var linkedBluetoothLockHint: String {
        switch language {
        case .english: return "Locked together for clearer two-way calls (HFP)."
        case .simplifiedChinese: return "蓝牙双端点同步锁定中，双向通话音质已优化"
        }
    }

    var settingsSectionTitle: String {
        switch language {
        case .english: return "Preferences"
        case .simplifiedChinese: return "偏好设置"
        }
    }

    var languageLabel: String {
        switch language {
        case .english: return "Language"
        case .simplifiedChinese: return "语言"
        }
    }

    var languageFollowSystem: String {
        switch language {
        case .english: return "Follow system"
        case .simplifiedChinese: return "跟随系统"
        }
    }

    var unavailable: String {
        switch language {
        case .english: return "Unavailable"
        case .simplifiedChinese: return "不可用"
        }
    }

    var onboardingTitle: String {
        switch language {
        case .english: return "Welcome to MicTether"
        case .simplifiedChinese: return "欢迎使用声锚"
        }
    }

    var onboardingSubtitle: String {
        switch language {
        case .english: return "A quick setup helps the app switch audio devices automatically."
        case .simplifiedChinese: return "花几十秒完成设置后，它就能自动帮你切换输入与输出设备。"
        }
    }

    var onboardingStepOneTitle: String {
        switch language {
        case .english: return "Choose primary devices"
        case .simplifiedChinese: return "先选首选设备"
        }
    }

    var onboardingStepOneDetail: String {
        switch language {
        case .english: return "Set the microphone and speaker you want to use whenever they are connected."
        case .simplifiedChinese: return "把你最希望优先使用的麦克风和扬声器设为首选设备。"
        }
    }

    var onboardingStepTwoTitle: String {
        switch language {
        case .english: return "Choose fallback devices"
        case .simplifiedChinese: return "再选备选设备"
        }
    }

    var onboardingStepTwoDetail: String {
        switch language {
        case .english: return "When a primary device disconnects, the app falls back to the device you set here."
        case .simplifiedChinese: return "当首选设备断开时，应用会自动退回到这里设置的备选设备。"
        }
    }

    var onboardingStepThreeTitle: String {
        switch language {
        case .english: return "Keep auto-switching on"
        case .simplifiedChinese: return "保持自动切换开启"
        }
    }

    var onboardingStepThreeDetail: String {
        switch language {
        case .english: return "If automatic switching is on, new connections are handled for you immediately."
        case .simplifiedChinese: return "只要自动切换保持开启，新设备连上时就会立刻按你的规则切换。"
        }
    }

    var onboardingStepFourTitle: String {
        switch language {
        case .english: return "Optional: enable launch at login"
        case .simplifiedChinese: return "可选：开启开机自启"
        }
    }

    var onboardingStepFourDetail: String {
        switch language {
        case .english: return "Move the app to Applications first if you want it to launch automatically after startup."
        case .simplifiedChinese: return "如果你希望开机后自动生效，请先把应用移到“应用程序”文件夹，再开启开机自启。"
        }
    }

    var onboardingPrimaryAction: String {
        switch language {
        case .english: return "Start setup"
        case .simplifiedChinese: return "开始设置"
        }
    }

    var onboardingSecondaryAction: String {
        switch language {
        case .english: return "Later"
        case .simplifiedChinese: return "稍后再说"
        }
    }

    var onboardingReopenButton: String {
        switch language {
        case .english: return "View guide"
        case .simplifiedChinese: return "查看引导"
        }
    }

    var onboardingBadge: String {
        switch language {
        case .english: return "FIRST RUN"
        case .simplifiedChinese: return "首次引导"
        }
    }
}
