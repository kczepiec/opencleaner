import AppKit
import SwiftUI

// Ikona OpenCleaner: logo (C z miotłą i iskrą) na granatowym kafelku z delikatną poświatą. Kompilacja:
//   swiftc -parse-as-library tools/make_icon.swift App/Mascot.swift App/Theme.swift -o /tmp/mk && /tmp/mk out.png
struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 190, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.094, green: 0.125, blue: 0.188), Color(red: 0.035, green: 0.051, blue: 0.082)], startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [Color(red: 0.35, green: 0.57, blue: 0.97).opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 330)
                .clipShape(RoundedRectangle(cornerRadius: 190, style: .continuous))
            RoundedRectangle(cornerRadius: 190, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
            Mascot(size: 560, mood: .content, animated: false)
        }
        .frame(width: 836, height: 836)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render(to path: String) {
    let r = ImageRenderer(content: Icon()); r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
}
@main struct IconTool { @MainActor static func main() { render(to: CommandLine.arguments[1]) } }
