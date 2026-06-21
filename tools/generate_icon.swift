import AppKit
import CoreGraphics
import Foundation

// SmartEdge app icon generator (Concept 1 — "content card surfacing from
// the notch"). Draws with CoreGraphics at every macOS AppIcon size and
// writes PNGs + Contents.json into the AppIcon.appiconset. No SVG→PNG
// dependency; fully reproducible via `swift tools/generate_icon.swift`.

let outDir = "SmartEdge/Resources/Assets.xcassets/AppIcon.appiconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

func roundedRect(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) {
    let path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
}

func drawIcon(size S: CGFloat, into ctx: CGContext) {
    // Big Sur grid: rounded body inset ~9.77%, transparent margin for shadow.
    let inset = S * 0.0977
    let bx = inset, by = inset, bw = S - 2 * inset
    let corner = bw * 0.2237

    // Background squircle with vertical charcoal gradient.
    ctx.saveGState()
    roundedRect(ctx, bx, by, bw, bw, corner)
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [color(42,42,46), color(20,20,22)] as CFArray,
                          locations: [0, 1])!
    // CG origin is bottom-left → start at top (by+bw) going down to by.
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: bx, y: by + bw),
                           end: CGPoint(x: bx, y: by),
                           options: [])
    ctx.restoreGState()

    // Notch pill at the top edge of the body.
    let pillW = bw * 0.443, pillH = bw * 0.096
    let pillX = bx + bw * 0.279
    let pillY = by + bw - pillH      // flush with body top
    ctx.setFillColor(color(7,7,8))
    roundedRect(ctx, pillX, pillY, pillW, pillH, pillH/2)
    ctx.fillPath()

    // White content card.
    let cardW = bw * 0.5, cardH = bw * 0.386
    let cardX = bx + bw * 0.25
    let cardTopFromTop = bw * 0.35
    let cardY = by + bw - cardTopFromTop - cardH
    ctx.setFillColor(color(255,255,255))
    roundedRect(ctx, cardX, cardY, cardW, cardH, bw * 0.078)
    ctx.fillPath()

    // Coral artwork circle.
    let r = bw * 0.0786
    let ccx = bx + bw * 0.379
    let ccy = by + bw - bw * 0.543
    ctx.setFillColor(color(255,90,95))
    ctx.fillEllipse(in: CGRect(x: ccx - r, y: ccy - r, width: 2*r, height: 2*r))

    // Two text lines.
    let lineH = bw * 0.039
    let lineX = bx + bw * 0.493
    ctx.setFillColor(color(199,199,204))
    let l1y = by + bw - bw * 0.493 - lineH
    roundedRect(ctx, lineX, l1y, bw * 0.2, lineH, lineH/2)
    ctx.fillPath()
    ctx.setFillColor(color(218,218,222))
    let l2y = by + bw - bw * 0.571 - lineH
    roundedRect(ctx, lineX, l2y, bw * 0.136, lineH, lineH/2)
    ctx.fillPath()
}

func renderPNG(size: Int) -> Data {
    let S = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    drawIcon(size: S, into: ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let data = renderPNG(size: s)
    let path = "\(outDir)/icon_\(s).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}

// Contents.json — macOS AppIcon with shared files across @1x/@2x where the
// pixel dimension matches.
let contents = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_64.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_512.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_1024.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(outDir)/Contents.json")
