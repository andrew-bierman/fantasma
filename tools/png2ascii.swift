import CoreGraphics
import ImageIO
import Foundation

// png2ascii: converts an image to ASCII art sized for a terminal.
// usage: png2ascii <png-path> <target-columns>
let args = CommandLine.arguments
guard args.count >= 3, let targetW = Int(args[2]), targetW >= 10 else {
    FileHandle.standardError.write("usage: png2ascii <png> <columns>\n".data(using: .utf8)!)
    exit(1)
}
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("failed to load \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

// Terminal chars are ~2x taller than wide, so halve the row count.
let w = targetW
let h = max(1, Int(Double(img.height) * Double(w) / Double(img.width) / 2.1))
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
ctx.interpolationQuality = .high
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
// Dark-terminal ramp: empty space -> blank, brightness -> density.
let ramp = Array(" .:-=+*#%@")

var out = ""
for y in 0..<h {
    var line = ""
    for x in 0..<w {
        let i = ((h - 1 - y) * w + x) * 4  // CG data is bottom-up; flip to top-down
        let r = Double(buf[i]) / 255
        let g = Double(buf[i + 1]) / 255
        let b = Double(buf[i + 2]) / 255
        let a = Double(buf[i + 3]) / 255
        if a < 0.15 { line += " "; continue }
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        let idx = min(Int(lum * Double(ramp.count - 1) + 0.5), ramp.count - 1)
        line += ramp[idx] == " " ? "." : String(ramp[idx])
    }
    out += line + "\n"
}
print(out)
