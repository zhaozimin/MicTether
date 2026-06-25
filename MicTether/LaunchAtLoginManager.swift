/**
 * [INPUT]: 依赖 ServiceManagement 的 SMAppService.mainApp；依赖 LocalizationManager 解析错误文案语言
 * [OUTPUT]: 对外提供 LaunchAtLoginManager(可观察 isEnabled/errorMessage、setEnabled)
 * [POS]: 开机自启管理器，被 MenuBarView 的开关消费；非 /Applications 时给本地化友好错误
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool
    @Published var errorMessage: String?

    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
        self.errorMessage = nil
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = nil
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        let appPath = Bundle.main.bundleURL.path
        if !appPath.hasPrefix("/Applications/") {
            switch LocalizationManager.shared.language {
            case .english:
                return "Move the app to Applications before enabling launch at login."
            case .simplifiedChinese:
                return "请先把 App 移到“应用程序”目录，再开启开机自启。"
            }
        }

        switch LocalizationManager.shared.language {
        case .english:
            return "Launch at login could not be updated. Check Login Items in System Settings."
        case .simplifiedChinese:
            return "开机自启暂时无法更新，请在系统设置的“登录项”中检查。"
        }
    }
}
