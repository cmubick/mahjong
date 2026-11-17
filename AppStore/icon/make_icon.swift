import AppKit
import ImageIO

// Draws the Mahjong app icon: a 7 Dot tile on green felt, drawn the same way as
// TileArt.swift draws it in the game.
// usage: swift make_icon.swift <out.png> <light|dark|tinted>
let args = CommandLine.arguments
let out = args[1]
let mode = args.count > 2 ? args[2] : "light"
let side = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let full = CGRect(x: 0, y: 0, width: side, height: side)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r, green: g, blue: b, alpha: a)
}

// The tile's colors, from TileArt.swift. The tinted icon is grey: iOS colors it.
let tinted = mode == "tinted"
let ivory = tinted ? color(1, 1, 1) : color(0.99, 0.97, 0.91)
let edge = tinted ? color(0.55, 0.55, 0.55) : color(0.13, 0.47, 0.40)
let blue = tinted ? color(0.25, 0.25, 0.25) : color(0.11, 0.30, 0.66)
let red = tinted ? color(0.45, 0.45, 0.45) : color(0.78, 0.11, 0.13)

// Background: the table's felt.
if tinted {
    color(0, 0, 0).setFill(); full.fill()
} else {
    let inner = mode == "dark" ? color(0.04, 0.18, 0.12) : color(0.08, 0.40, 0.27)
    let outer = mode == "dark" ? color(0.01, 0.06, 0.04) : color(0.02, 0.20, 0.13)
    let gradient = NSGradient(starting: inner, ending: outer)!
    gradient.draw(fromCenter: CGPoint(x: 512, y: 600), radius: 0,
                  toCenter: CGPoint(x: 512, y: 512), radius: 760, options: [.drawsAfterEndingLocation])
}

// The tile is 60 by 80 units, as in the game, scaled up and tilted a little.
let unit: CGFloat = 9.4
let tileSize = CGSize(width: 60, height: 80)
let depth: CGFloat = 5

ctx.saveGState()
ctx.translateBy(x: 512, y: 500)
ctx.rotate(by: -8 * .pi / 180)
// From here on: tile units, origin at the tile's top-left, y pointing down.
ctx.translateBy(x: -tileSize.width * unit / 2, y: tileSize.height * unit / 2)
ctx.scaleBy(x: unit, y: -unit)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

let face = CGRect(x: 0, y: 0, width: tileSize.width, height: tileSize.height - depth)
if !tinted {
    ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: color(0, 0, 0, 0.45).cgColor)
}
edge.setFill()
NSBezierPath(roundedRect: CGRect(x: 0, y: depth, width: tileSize.width, height: tileSize.height - depth),
             xRadius: 8, yRadius: 8).fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ivory.setFill()
let top = NSBezierPath(roundedRect: face.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
top.fill()
color(0, 0, 0, 0.18).setStroke()
top.lineWidth = 0.6
top.stroke()

// The corner number.
let numberFont = NSFont.systemFont(ofSize: 12, weight: .heavy)
let number = NSAttributedString(string: "7", attributes: [.font: numberFont, .foregroundColor: blue])
let numberSize = number.size()
number.draw(at: CGPoint(x: 9 - numberSize.width / 2, y: 9 - numberSize.height / 2))

// Seven dots: three on a slant in blue, four below in red.
let art = CGRect(x: 6, y: 13, width: tileSize.width - 12, height: tileSize.height - depth - 18)
let spots: [(CGFloat, CGFloat)] = [(0.2, 0.1), (0.5, 0.22), (0.8, 0.34), (0.28, 0.62), (0.72, 0.62), (0.28, 0.88), (0.72, 0.88)]
func circle(_ center: CGPoint, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
}
for (index, spot) in spots.enumerated() {
    let center = CGPoint(x: art.minX + art.width * spot.0, y: art.minY + art.height * spot.1)
    let outer = index >= 3 ? red : blue
    circle(center, 7, outer)
    circle(center, 7 * 0.66, ivory)
    circle(center, 7 * 0.4, outer)
}
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

// Flatten onto an opaque bitmap: App Store icons may not have an alpha channel.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let opaque = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
opaque.fill(full)
opaque.draw(rep.cgImage!, in: full)
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
CGImageDestinationFinalize(destination)
