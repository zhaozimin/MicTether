/**
 * [INPUT]: 依赖 SwiftUI/AppKit(NSImage 取 App 图标)、NativeSelect 下拉组件、ShadcnSwitch 开关组件；依赖 AutoSwitchViewModel/LaunchAtLoginManager/OnboardingManager/LocalizationManager 四个可观察对象
 * [OUTPUT]: 对外提供 MenuBarView 设置面板(panelWidth)
 * [POS]: components 唯一视图层，被 AppDelegate 经 NSHostingController 承载；文案全部取自注入的 localization
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI
import AppKit

struct MenuBarView: View {

    static let panelWidth: CGFloat = 348
    // 所有下拉控件统一宽度,杜绝菜单 Picker 按内容自适应导致的参差
    private static let controlWidth: CGFloat = 184

    @ObservedObject var viewModel: AutoSwitchViewModel
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var onboardingManager: OnboardingManager
    @ObservedObject var localization: LocalizationManager

    private var strings: AppStrings { localization.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if onboardingManager.isPresented {
                onboardingSection
            } else {
                summarySection
            }

            deviceSection(
                title: strings.microphoneSectionTitle,
                symbol: "mic.fill",
                selection: $viewModel.targetInputUID,
                primaryOptions: primaryOptions(viewModel.inputs, targetUID: viewModel.targetInputUID, includes: viewModel.includesInputDevice),
                fallbackSelection: $viewModel.preferredFallbackInputUID,
                fallbackOptions: fallbackOptions(viewModel.inputs, preferredUID: viewModel.preferredFallbackInputUID, targetUID: viewModel.targetInputUID, includes: viewModel.includesInputDevice),
                selectedName: selectedDeviceName(uid: viewModel.inputStatusUID, in: viewModel.inputs),
                isOnline: viewModel.includesInputDevice(uid: viewModel.inputStatusUID)
            )

            if viewModel.isLinkedBluetoothLockActive {
                linkedBluetoothLockHintRow
            }

            deviceSection(
                title: strings.speakerSectionTitle,
                symbol: "speaker.wave.2.fill",
                selection: $viewModel.targetOutputUID,
                primaryOptions: primaryOptions(viewModel.outputs, targetUID: viewModel.targetOutputUID, includes: viewModel.includesOutputDevice),
                fallbackSelection: $viewModel.preferredFallbackOutputUID,
                fallbackOptions: fallbackOptions(viewModel.outputs, preferredUID: viewModel.preferredFallbackOutputUID, targetUID: viewModel.targetOutputUID, includes: viewModel.includesOutputDevice),
                selectedName: selectedDeviceName(uid: viewModel.outputStatusUID, in: viewModel.outputs),
                isOnline: viewModel.includesOutputDevice(uid: viewModel.outputStatusUID)
            )

            settingsSection
            quitSection
        }
        .padding(12)
        .frame(width: Self.panelWidth, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(8)
    }

    private var linkedBluetoothLockHintRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.green)
            Text(strings.linkedBluetoothLockHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var summarySection: some View {
        nativeSection {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(strings.appName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.isEnabled ? strings.autoSwitchOn : strings.autoSwitchOff)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var onboardingSection: some View {
        nativeSection {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.onboardingTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(strings.onboardingSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    onboardingStepRow(index: "1", title: strings.onboardingStepOneTitle, detail: strings.onboardingStepOneDetail)
                    onboardingStepRow(index: "2", title: strings.onboardingStepTwoTitle, detail: strings.onboardingStepTwoDetail)
                    onboardingStepRow(index: "3", title: strings.onboardingStepThreeTitle, detail: strings.onboardingStepThreeDetail)
                    onboardingStepRow(index: "4", title: strings.onboardingStepFourTitle, detail: strings.onboardingStepFourDetail)
                }

                HStack(spacing: 10) {
                    Button(strings.onboardingPrimaryAction) {
                        onboardingManager.complete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(strings.onboardingSecondaryAction) {
                        onboardingManager.complete()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func deviceSection(
        title: String,
        symbol: String,
        selection: Binding<String?>,
        primaryOptions primaryItems: [(label: String, value: String?)],
        fallbackSelection: Binding<String?>,
        fallbackOptions fallbackItems: [(label: String, value: String?)],
        selectedName: String,
        isOnline: Bool
    ) -> some View {
        nativeSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(strings.targetSectionBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Divider()

                settingRow(title: strings.primaryDeviceLabel) {
                    NativeSelect(
                        selection: selection,
                        options: primaryItems,
                        muted: selection.wrappedValue == nil,
                        width: Self.controlWidth
                    )
                }

                settingRow(title: strings.fallbackDeviceLabel) {
                    NativeSelect(
                        selection: fallbackSelection,
                        options: fallbackItems,
                        muted: fallbackSelection.wrappedValue == nil,
                        width: Self.controlWidth
                    )
                }

                Divider()

                HStack(spacing: 8) {
                    Circle()
                        .fill(isOnline ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text("\(strings.activeSelectionLabel): \(selectedName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var settingsSection: some View {
        nativeSection {
            VStack(alignment: .leading, spacing: 10) {
                Text(strings.settingsSectionTitle)
                    .font(.system(size: 13, weight: .semibold))

                Divider()

                toggleRow(
                    title: viewModel.isEnabled ? strings.autoSwitchOn : strings.autoSwitchOff,
                    symbol: "bolt.fill",
                    isOn: $viewModel.isEnabled
                )

                toggleRow(
                    title: strings.launchAtLogin,
                    symbol: "sunrise.fill",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )

                if let errorMessage = launchAtLoginManager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingRow(title: strings.languageLabel) {
                    NativeSelect(
                        selection: $localization.preference,
                        options: LanguagePreference.allCases.map { (label: $0.label(using: strings), value: $0) },
                        width: Self.controlWidth
                    )
                }

                Divider()

                Button(strings.onboardingReopenButton) {
                    onboardingManager.reopen()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
    }

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                Text(strings.quitButton)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func nativeSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            content()
                .frame(width: Self.controlWidth, alignment: .trailing)
        }
    }

    // MARK: - 设备下拉选项构造(严格对齐原 Picker 逻辑)

    /// 首选设备项:不指定 + (离线占位) + 全部设备
    private func primaryOptions(_ devices: [AudioDevice], targetUID: String?, includes: (String?) -> Bool) -> [(label: String, value: String?)] {
        var items: [(label: String, value: String?)] = [(label: strings.notSpecified, value: nil)]
        if let uid = targetUID, !includes(uid) {
            items.append((label: strings.selectedDeviceOffline, value: uid))
        }
        items.append(contentsOf: devices.map { (label: $0.name, value: Optional($0.uid)) })
        return items
    }

    /// 备选设备项:自动记住 + (离线占位) + 过滤掉=首选的设备(但保留=当前备选)
    private func fallbackOptions(_ devices: [AudioDevice], preferredUID: String?, targetUID: String?, includes: (String?) -> Bool) -> [(label: String, value: String?)] {
        var items: [(label: String, value: String?)] = [(label: strings.automaticFallback, value: nil)]
        if let uid = preferredUID, !includes(uid) {
            items.append((label: strings.selectedDeviceOffline, value: uid))
        }
        let filtered = devices.filter { $0.uid != targetUID || $0.uid == preferredUID }
        items.append(contentsOf: filtered.map { (label: $0.name, value: Optional($0.uid)) })
        return items
    }

    private func toggleRow(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 12))

            Spacer(minLength: 0)

            // 自绘开关:开→绿轨道、关→灰轨道,滑块底色即状态反馈
            ShadcnSwitch(isOn: isOn)
        }
    }

    private func onboardingStepRow(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectedDeviceName(uid: String?, in devices: [AudioDevice]) -> String {
        guard let uid else { return strings.unavailable }
        return devices.first(where: { $0.uid == uid })?.name ?? strings.selectedDeviceOffline
    }
}
