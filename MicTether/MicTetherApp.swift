/**
 * [INPUT]: 依赖 AppKit/SwiftUI/Combine/ServiceManagement；装配 AutoSwitchViewModel/LaunchAtLoginManager/OnboardingManager/LocalizationManager
 * [OUTPUT]: 对外提供 @main AppDelegate(进程入口)、OnboardingManager(首启引导状态)
 * [POS]: 应用入口与装配层，承载状态栏图标 + 无边框浮窗(NSHostingController 托 MenuBarView) + 原生 Edit 菜单
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class OnboardingManager: ObservableObject {
    private let hasSeenKey = "HasSeenWelcomeGuide"

    @Published var isPresented: Bool

    init(defaults: UserDefaults = .standard) {
        isPresented = !defaults.bool(forKey: hasSeenKey)
    }

    func complete(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasSeenKey)
        isPresented = false
    }

    func reopen() {
        isPresented = true
    }
}

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var strings: AppStrings { localizationManager.strings }

    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    private let viewModel = AutoSwitchViewModel()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let onboardingManager = OnboardingManager()
    private let localizationManager = LocalizationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        ReleaseConsistencyChecker.logIfNeeded()

        setupStatusItem()
        setupPopover()
        setupMainMenu()
        observeLanguageChanges()
    }

    // MARK: - 语言切换：重建原生菜单/状态栏（SwiftUI 面板由自身观察自动重渲染）

    @MainActor
    private func observeLanguageChanges() {
        localizationManager.$preference
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setupMainMenu()
                self.updateStatusItemIcon()
                self.resizePopoverToFitContent()
            }
            .store(in: &cancellables)
    }

    // MARK: - 主菜单设置（为文本编辑快捷键 复制/粘贴/撤销 提供支持）
    
    @MainActor
    private func setupMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: strings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: strings.editMenuTitle)
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: strings.undo, action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: strings.redo, action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: strings.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: strings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: strings.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: strings.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 菜单栏图标设置

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        updateStatusItemIcon()
        button.action = #selector(togglePopover)
        button.target = self

        // 监听启用状态，动态更新图标颜色等
        viewModel.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemIcon()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        // 代码矢量绘制的船锚模板图(非 emoji),系统自动适配明暗菜单栏
        let image = StatusBarIcon.anchor(pointSize: 18)
        image.accessibilityDescription = strings.statusItemAccessibility
        button.image = image
    }

    // MARK: - 弹出视图

    @MainActor
    private func setupPopover() {
        let hostingController = NSHostingController(
            rootView: MenuBarView(
                viewModel: viewModel,
                launchAtLoginManager: launchAtLoginManager,
                onboardingManager: onboardingManager,
                localization: localizationManager
            )
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: MenuBarView.panelWidth, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        
        // 当点击其他地方时自动隐藏
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        self.window = window
        
        // 监听焦点丢失
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(sender: nil)
            }
        }

        resizePopoverToFitContent()

        if onboardingManager.isPresented {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                Task { @MainActor in
                    self?.showPopover()
                }
            }
        }
    }

    @MainActor
    @objc private func togglePopover() {
        guard let window = self.window else { return }
        
        if window.isVisible {
            closePopover(sender: nil)
        } else {
            showPopover()
        }
    }

    @MainActor
    func closePopover(sender: Any?) {
        window?.orderOut(sender)
    }

    @MainActor
    private func resizePopoverToFitContent() {
        guard let window, let contentView = window.contentViewController?.view else { return }

        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()

        let fittingSize = contentView.fittingSize
        let targetSize = NSSize(width: MenuBarView.panelWidth, height: fittingSize.height)

        if window.contentRect(forFrameRect: window.frame).size != targetSize {
            window.setContentSize(targetSize)
        }
    }

    @MainActor
    private func showPopover() {
        guard let window, let button = statusItem?.button else { return }

        resizePopoverToFitContent()

        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let windowSize = window.frame.size
        let x = buttonFrame.midX - windowSize.width / 2
        let y = buttonFrame.minY - windowSize.height - 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
