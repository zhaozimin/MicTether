/**
 * [INPUT]: 依赖 SwiftUI
 * [OUTPUT]: 对外提供 ShadcnSwitch 视图(自绘开关:开→绿轨道、关→灰轨道,白滑块弹簧滑动)
 * [POS]: 通用开关控件,被 MenuBarView.toggleRow 消费;轨道色 100% 自控,替代 .tint 在 macOS 上不可靠的原生 Toggle
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ============================================================================
// MARK: - ShadcnSwitch  自绘开关(滑过即变轨道底色)
// ----------------------------------------------------------------------------
// 关:灰轨道 + 白滑块靠左;开:绿轨道 + 白滑块靠右。滑块用 offset + 弹簧动画平滑滑动,
// 轨道底色随 isOn 渐变 —— 即"已开启"的明确反馈。
// ============================================================================
struct ShadcnSwitch: View {
    @Binding var isOn: Bool

    var onColor: Color = .green
    var trackWidth: CGFloat = 38
    var trackHeight: CGFloat = 22
    var knobSize: CGFloat = 18
    var inset: CGFloat = 2

    private var travel: CGFloat { trackWidth - knobSize - inset * 2 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? onColor : Color.primary.opacity(0.20))

            Circle()
                .fill(.white)
                .frame(width: knobSize, height: knobSize)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .padding(inset)
                .offset(x: isOn ? travel : 0)
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { isOn.toggle() }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}
