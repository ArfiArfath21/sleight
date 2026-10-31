import AppKit
import MaestroBrand

// Usage: maestro-icon <output-dir>
// Writes Maestro.iconset/ (for iconutil), logo.png and menubar.png.
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let iconset = out.appendingPathComponent("Maestro.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try Brand.iconPNG(pixels: px)!.write(to: iconset.appendingPathComponent(name))
    }
}
try Brand.iconPNG(pixels: 1024)!.write(to: out.appendingPathComponent("logo.png"))
try Brand.png(of: Brand.menuBarImage(), pixels: NSSize(width: 88, height: 72))!
    .write(to: out.appendingPathComponent("menubar.png"))
print("wrote \(out.path)")
