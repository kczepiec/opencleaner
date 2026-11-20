import SwiftUI

/// Własny zestaw ikon paska bocznego: wszystkie na siatce 24 x 24, kreska 1,7 z zaokrągleniami i lekkie dwutonowe wypełnienie.
/// Jeden styl, jedna grubość i jeden rozmiar optyczny, zamiast mieszania symboli systemowych o różnej wadze.
struct RailIcon: View {
    let area: Area
    var color: Color
    var size: CGFloat = 24

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

    /// (kontur, wypełnienie) w układzie 24 x 24.
    private func paths() -> (stroke: Path, fill: Path) {
        var s = Path(), f = Path()
        switch area {
        case .dashboard:
            let c = CGPoint(x: 12, y: 13), r: CGFloat = 8.6
            for i in 0...36 {
                let a = (135 + 270 * Double(i) / 36) * .pi / 180
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { s.move(to: p) } else { s.addLine(to: p) }
            }
            s.move(to: c); s.addLine(to: CGPoint(x: 16.2, y: 8.6))
            f.addPath(Self.circle(c, r)); s.addPath(Self.circle(c, 1.2))
        case .cleaning:
            s.addPath(SparkleShape().path(in: CGRect(x: 2.5, y: 7.5, width: 13, height: 13)))
            s.addPath(SparkleShape().path(in: CGRect(x: 14.5, y: 2.5, width: 7, height: 7)))
            f.addPath(SparkleShape().path(in: CGRect(x: 2.5, y: 7.5, width: 13, height: 13)))
            s.addPath(Self.circle(CGPoint(x: 19, y: 17.5), 1.1))
        case .apps:
            for (x, y) in [(4.0, 4.0), (13.0, 4.0), (4.0, 13.0), (13.0, 13.0)] {
                let r = CGRect(x: x, y: y, width: 7, height: 7)
                s.addRoundedRect(in: r, cornerSize: CGSize(width: 2.2, height: 2.2))
                if x == 13 && y == 4 { f.addRoundedRect(in: r, cornerSize: CGSize(width: 2.2, height: 2.2)) }
            }
        case .analysis:
            for (x, top) in [(4.0, 12.5), (10.0, 5.0), (16.0, 9.0)] {
                let r = CGRect(x: x, y: top, width: 4, height: 19.5 - top)
                s.addRoundedRect(in: r, cornerSize: CGSize(width: 1.6, height: 1.6)); f.addRoundedRect(in: r, cornerSize: CGSize(width: 1.6, height: 1.6))
            }
        case .photos:
            let frame = CGRect(x: 3, y: 4.5, width: 18, height: 15)
            s.addRoundedRect(in: frame, cornerSize: CGSize(width: 3.2, height: 3.2)); f.addRoundedRect(in: frame, cornerSize: CGSize(width: 3.2, height: 3.2))
            s.move(to: CGPoint(x: 3.5, y: 16)); s.addLine(to: CGPoint(x: 9, y: 11)); s.addLine(to: CGPoint(x: 13, y: 14.5)); s.addLine(to: CGPoint(x: 16, y: 12)); s.addLine(to: CGPoint(x: 20.5, y: 16))
            s.addPath(Self.circle(CGPoint(x: 16.5, y: 8.6), 1.3))
        case .status:
            s.move(to: CGPoint(x: 2.5, y: 12)); s.addLine(to: CGPoint(x: 7, y: 12)); s.addLine(to: CGPoint(x: 9.7, y: 4.8))
            s.addLine(to: CGPoint(x: 14.3, y: 19.2)); s.addLine(to: CGPoint(x: 17, y: 12)); s.addLine(to: CGPoint(x: 21.5, y: 12))
        case .settings:
            for (y, k) in [(6.5, 8.5), (12.0, 15.5), (17.5, 9.5)] {
                s.move(to: CGPoint(x: 3.5, y: y)); s.addLine(to: CGPoint(x: k - 2.6, y: y))
                s.move(to: CGPoint(x: k + 2.6, y: y)); s.addLine(to: CGPoint(x: 20.5, y: y))
                s.addPath(Self.circle(CGPoint(x: k, y: y), 2.3)); f.addPath(Self.circle(CGPoint(x: k, y: y), 2.3))
            }
        }
        return (s, f)
    }

    var body: some View {
        let k = size / 24, p = paths()
        let t = CGAffineTransform(scaleX: k, y: k)
        ZStack {
            p.fill.applying(t).fill(color.opacity(0.16))
            p.stroke.applying(t).stroke(color, style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
