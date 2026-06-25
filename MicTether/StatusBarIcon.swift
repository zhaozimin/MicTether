/**
 * [INPUT]: 依赖 AppKit 的 NSImage/NSBezierPath
 * [OUTPUT]: 对外提供 StatusBarIcon.anchor(pointSize:) -> NSImage(模板图,系统自动适配明暗菜单栏)
 * [POS]: 状态栏图标的矢量绘制器,被 AppDelegate.updateStatusItemIcon 消费;纯几何,无 emoji、无 bundle 资源
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit

// ============================================================================
// MARK: - StatusBarIcon  船锚状态栏图标(代码矢量绘制)
// ----------------------------------------------------------------------------
// 在 24x24 归一化坐标(y 向上)里描边:锚眼环 + 锚杆 + 横杆(stock) + 底部锚臂半弧
// + 两枚实心锚爪(fluke)。isTemplate=true → 颜色由系统按明暗菜单栏替换。
// ============================================================================
enum StatusBarIcon {

    /// 生成船锚模板图。pointSize 为菜单栏内的逻辑边长(默认 18,留出留白)
    static func anchor(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { _ in
            drawAnchor(scale: pointSize / 24.0, lineWidth: max(1.0, pointSize / 24.0 * 1.7))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawAnchor(scale s: CGFloat, lineWidth lw: CGFloat) {
        NSColor.black.set()   // 模板图只取 alpha 作遮罩,实际着色由系统决定
        func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        func stroke(_ p: NSBezierPath) {
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        }
        func fluke(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint) {
            let t = NSBezierPath(); t.move(to: a); t.line(to: b); t.line(to: c); t.close(); t.fill()
        }

        // 锚眼(环)
        let ring = NSBezierPath(ovalIn: NSRect(x: (12 - 2.0) * s, y: (20.3 - 2.0) * s,
                                               width: 4.0 * s, height: 4.0 * s))
        ring.lineWidth = lw * 0.95
        ring.stroke()

        // 锚杆(竖)
        let shank = NSBezierPath(); shank.move(to: P(12, 18.3)); shank.line(to: P(12, 2.6)); stroke(shank)

        // 横杆 stock(上部横)
        let stock = NSBezierPath(); stock.move(to: P(6.6, 16.2)); stock.line(to: P(17.4, 16.2)); stroke(stock)

        // 底部锚臂半弧(经 270° 扫底)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: P(12, 10), radius: 8 * s, startAngle: 182, endAngle: 358, clockwise: false)
        stroke(arc)

        // 两枚实心锚爪
        fluke(P(4.0, 9.4),  P(1.7, 12.4),  P(6.1, 11.2))
        fluke(P(20.0, 9.4), P(22.3, 12.4), P(17.9, 11.2))
    }
}
