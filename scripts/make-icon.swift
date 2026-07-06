import AppKit
import ImageIO

// Renders the Clap app icon — a clapperboard on an indigo squircle — as a
// 1024x1024 PNG. Driven by `make icon`, which downscales it into an .icns.
//
// Usage: make-icon <output.png>

let canvas: CGFloat = 1024

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <output.png>\n".utf8))
    exit(1)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: - Background squircle (824pt content box per macOS icon grid)

let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [rgb(0x6E6CF5), rgb(0x4438C9)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 512, y: 924),
                       end: CGPoint(x: 512, y: 100),
                       options: [])
// Soft top-edge highlight for a bit of depth.
let highlight = CGGradient(
    colorsSpace: space,
    colors: [rgb(0xFFFFFF, 0.14), rgb(0xFFFFFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(highlight,
                       start: CGPoint(x: 512, y: 924),
                       end: CGPoint(x: 512, y: 800),
                       options: [])
ctx.restoreGState()

// MARK: - Clapperboard

let dark = rgb(0x23232B)
let light = rgb(0xF4F4F7)

/// Fills a rounded bar with diagonal light stripes, in the current transform.
func stripedBar(width: CGFloat, height: CGFloat, radius: CGFloat) {
    let bar = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                     cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setFillColor(dark)
    ctx.addPath(bar)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(bar)
    ctx.clip()
    ctx.setFillColor(light)
    let stripe: CGFloat = 62
    let slant: CGFloat = height * 0.6
    var x: CGFloat = -height
    while x < width {
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x + stripe, y: 0))
        ctx.addLine(to: CGPoint(x: x + stripe + slant, y: height))
        ctx.addLine(to: CGPoint(x: x + slant, y: height))
        ctx.closePath()
        ctx.fillPath()
        x += stripe * 2
    }
    ctx.restoreGState()
}

// Drop shadow under the whole board group.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: rgb(0x000000, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

// Board body.
let board = CGRect(x: 282, y: 278, width: 460, height: 264)
ctx.setFillColor(dark)
ctx.addPath(CGPath(roundedRect: board, cornerWidth: 32, cornerHeight: 32, transform: nil))
ctx.fillPath()

// "Clipboard history" lines on the board.
ctx.setFillColor(rgb(0xFFFFFF, 0.30))
for (y, width) in [(458, 330), (404, 290), (350, 350)] as [(CGFloat, CGFloat)] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 322, y: y, width: width, height: 24),
                       cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
}

// Static striped bar sitting on the board.
ctx.saveGState()
ctx.translateBy(x: 282, y: 550)
stripedBar(width: 460, height: 72, radius: 18)
ctx.restoreGState()

// Raised clap stick, hinged at the left.
ctx.saveGState()
ctx.translateBy(x: 284, y: 630)
ctx.rotate(by: 16 * .pi / 180)
stripedBar(width: 458, height: 72, radius: 18)
ctx.restoreGState()

ctx.endTransparencyLayer()
ctx.restoreGState()

// MARK: - Write PNG

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("error: could not create image\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("error: could not write \(outputURL.path)\n".utf8))
    exit(1)
}
