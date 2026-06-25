/**
 * [INPUT]: 依赖 SwiftUI/AppKit(NSView 捕获点击、NSMenu 原生菜单)
 * [OUTPUT]: 对外提供 NativeSelect<Value> 视图(shadcn NativeSelect 风格定宽下拉)
 * [POS]: 通用下拉控件,被 MenuBarView 的设备/语言选择消费。闭合态=纯 SwiftUI(渲染可控)、展开态=原生 NSMenu(可靠);故弃用渲染不可控的 SwiftUI Menu
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI
import AppKit

// ============================================================================
// MARK: - NativeSelect  shadcn 风格定宽下拉
// ----------------------------------------------------------------------------
// 闭合态:描边盒 + rounded-md + 文字左对齐(占位走 muted)+ 右侧单下箭头,恒定宽度。
// 展开态:点击 → 透明覆盖层弹出原生 NSMenu(带勾选),选中回填 binding。
// ============================================================================
struct NativeSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]
    var muted: Bool = false
    var width: CGFloat = 184

    private var selectedIndex: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var selectedLabel: String {
        options.indices.contains(selectedIndex) ? options[selectedIndex].label : ""
    }

    var body: some View {
        labelBox
            .overlay(
                NativeMenuOverlay(
                    labels: options.map { $0.label },
                    selectedIndex: selectedIndex,
                    onPick: { index in
                        if options.indices.contains(index) { selection = options[index].value }
                    }
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var labelBox: some View {
        HStack(spacing: 8) {
            Text(selectedLabel)
                .font(.system(size: 12))
                .foregroundStyle(muted ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(0.6)
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 1, x: 0, y: 0.5)
    }
}

// ============================================================================
// MARK: - NativeMenuOverlay  透明点击层 → 弹原生 NSMenu
// ----------------------------------------------------------------------------
// 标签/索引驱动(非泛型),避免 @objc 不能落在泛型类上的限制。
// ============================================================================
private struct NativeMenuOverlay: NSViewRepresentable {
    let labels: [String]
    let selectedIndex: Int
    let onPick: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPick = onPick
        let labels = self.labels
        let selected = self.selectedIndex
        view.makeMenu = {
            let menu = NSMenu()
            for (index, title) in labels.enumerated() {
                let item = NSMenuItem(title: title, action: #selector(Coordinator.pick(_:)), keyEquivalent: "")
                item.target = coordinator
                item.tag = index
                item.state = (index == selected) ? .on : .off
                menu.addItem(item)
            }
            return menu
        }
    }

    final class Coordinator: NSObject {
        var onPick: ((Int) -> Void)?
        @objc func pick(_ sender: NSMenuItem) { onPick?(sender.tag) }
    }
}

// 透明 NSView:仅捕获点击并在控件正下方弹出菜单
private final class ClickView: NSView {
    var makeMenu: (() -> NSMenu)?

    override var isFlipped: Bool { true }   // y 向下:bounds.height 处即控件底边
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        menu.minimumWidth = bounds.width
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }
}
