/**
 * [INPUT]: 依赖 SwiftUI(Shape/Path)
 * [OUTPUT]: 对外提供 GitHubMark 形状(GitHub 官方 Octocat mark 矢量剪影,可 fill 任意色/尺寸)
 * [POS]: 通用矢量图标,被 MenuBarView 的 GitHub 广告卡消费;内含迷你 SVG 路径解析器(cubic + 椭圆弧→贝塞尔)
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

// ============================================================================
// MARK: - GitHubMark  GitHub 官方 Octocat 剪影
// ----------------------------------------------------------------------------
// 用 GitHub octicons 官方 16x16 SVG 路径绘制(SF Symbols 无此 logo)。
// 自带最小 SVG 路径解析:M/L/H/V/C/S/A/Z(绝对+相对),含弧标志位单字符解析与
// 椭圆弧→cubic 贝塞尔转换。等比居中缩放到给定 rect。
// ============================================================================
struct GitHubMark: Shape {
    static let svg = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

    func path(in rect: CGRect) -> Path {
        let p = Self.build()
        let s = min(rect.width, rect.height) / 16.0
        let tx = rect.midX - 8 * s
        let ty = rect.midY - 8 * s
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty))
    }

    // MARK: 迷你 SVG 路径解析
    static func build() -> Path {
        var path = Path()
        let sc = Array(svg.unicodeScalars)
        var i = 0
        func skip() { while i < sc.count, sc[i] == " " || sc[i] == "," || sc[i] == "\n" || sc[i] == "\t" { i += 1 } }
        func isCmd(_ c: UnicodeScalar) -> Bool { "MmLlHhVvCcSsZzAa".unicodeScalars.contains(c) }
        func num() -> CGFloat {
            skip(); let start = i; var dot = false; var dig = false
            if i < sc.count, sc[i] == "+" || sc[i] == "-" { i += 1 }
            while i < sc.count {
                let c = sc[i]
                if c >= "0" && c <= "9" { dig = true; i += 1 }
                else if c == "." { if dot { break }; dot = true; i += 1 }
                else if c == "e" || c == "E" { i += 1; if i < sc.count, sc[i] == "+" || sc[i] == "-" { i += 1 } }
                else { break }
            }
            guard dig else { i = start; return 0 }
            return CGFloat(Double(String(String.UnicodeScalarView(sc[start..<i]))) ?? 0)
        }
        func flag() -> Bool { skip(); if i < sc.count { if sc[i] == "0" { i += 1; return false }; if sc[i] == "1" { i += 1; return true } }; return num() != 0 }

        var cur = CGPoint.zero, start = CGPoint.zero, prevC: CGPoint? = nil
        var last: UnicodeScalar = " "
        while i < sc.count {
            skip(); if i >= sc.count { break }
            var cmd: UnicodeScalar
            if isCmd(sc[i]) { cmd = sc[i]; i += 1 } else { cmd = last == "M" ? "L" : (last == "m" ? "l" : last) }
            last = cmd
            switch cmd {
            case "M": cur = CGPoint(x: num(), y: num()); start = cur; path.move(to: cur); prevC = nil
            case "m": cur = CGPoint(x: cur.x + num(), y: cur.y + num()); start = cur; path.move(to: cur); prevC = nil
            case "L": cur = CGPoint(x: num(), y: num()); path.addLine(to: cur); prevC = nil
            case "l": cur = CGPoint(x: cur.x + num(), y: cur.y + num()); path.addLine(to: cur); prevC = nil
            case "H": cur = CGPoint(x: num(), y: cur.y); path.addLine(to: cur); prevC = nil
            case "h": cur = CGPoint(x: cur.x + num(), y: cur.y); path.addLine(to: cur); prevC = nil
            case "V": cur = CGPoint(x: cur.x, y: num()); path.addLine(to: cur); prevC = nil
            case "v": cur = CGPoint(x: cur.x, y: cur.y + num()); path.addLine(to: cur); prevC = nil
            case "C": let a = CGPoint(x: num(), y: num()); let b = CGPoint(x: num(), y: num()); let e = CGPoint(x: num(), y: num()); path.addCurve(to: e, control1: a, control2: b); prevC = b; cur = e
            case "c": let a = CGPoint(x: cur.x + num(), y: cur.y + num()); let b = CGPoint(x: cur.x + num(), y: cur.y + num()); let e = CGPoint(x: cur.x + num(), y: cur.y + num()); path.addCurve(to: e, control1: a, control2: b); prevC = b; cur = e
            case "S": let a = prevC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur; let b = CGPoint(x: num(), y: num()); let e = CGPoint(x: num(), y: num()); path.addCurve(to: e, control1: a, control2: b); prevC = b; cur = e
            case "s": let a = prevC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur; let b = CGPoint(x: cur.x + num(), y: cur.y + num()); let e = CGPoint(x: cur.x + num(), y: cur.y + num()); path.addCurve(to: e, control1: a, control2: b); prevC = b; cur = e
            case "A", "a":
                let rx = num(); let ry = num(); let rot = num(); let laf = flag(); let sf = flag()
                let e = cmd == "A" ? CGPoint(x: num(), y: num()) : CGPoint(x: cur.x + num(), y: cur.y + num())
                arc(&path, cur, e, rx, ry, rot, laf, sf); cur = e; prevC = nil
            case "Z", "z": path.closeSubpath(); cur = start; prevC = nil
            default: i += 1
            }
        }
        return path
    }

    // MARK: 椭圆弧 → cubic 贝塞尔(SVG 端点参数化)
    static func arc(_ path: inout Path, _ p0: CGPoint, _ p1: CGPoint, _ rxi: CGFloat, _ ryi: CGFloat, _ rotDeg: CGFloat, _ large: Bool, _ sweep: Bool) {
        var rx = abs(rxi), ry = abs(ryi)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotDeg * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry); if lam > 1 { let s = sqrt(lam); rx *= s; ry *= s }
        let sign: CGFloat = (large != sweep) ? 1 : -1
        var n = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1; n = max(0, n)
        let d = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let co = sign * sqrt(n / d), cxp = co * (rx * y1 / ry), cyp = co * (-ry * x1 / rx)
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy, ln = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, dot / ln))); if ux * vy - uy * vx < 0 { a = -a }; return a
        }
        let t1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dt = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi }; if sweep && dt < 0 { dt += 2 * .pi }
        let segs = max(1, Int(ceil(abs(dt) / (.pi / 2)))), del = dt / CGFloat(segs)
        let tt = (4.0 / 3.0) * tan(del / 4); var th = t1
        for _ in 0..<segs {
            let c1 = cos(th), s1 = sin(th), c2 = cos(th + del), s2 = sin(th + del)
            func P(_ ct: CGFloat, _ st: CGFloat) -> CGPoint { CGPoint(x: cp * (rx * ct) - sp * (ry * st) + cx, y: sp * (rx * ct) + cp * (ry * st) + cy) }
            func D(_ ct: CGFloat, _ st: CGFloat) -> CGVector { CGVector(dx: cp * (-rx * st) - sp * (ry * ct), dy: sp * (-rx * st) + cp * (ry * ct)) }
            let pa = P(c1, s1), pb = P(c2, s2), da = D(c1, s1), db = D(c2, s2)
            path.addCurve(to: pb, control1: CGPoint(x: pa.x + tt * da.dx, y: pa.y + tt * da.dy), control2: CGPoint(x: pb.x - tt * db.dx, y: pb.y - tt * db.dy))
            th += del
        }
    }
}
