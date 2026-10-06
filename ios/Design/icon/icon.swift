// App icon generator: `swift ios/Design/icon/icon.swift out.png` (1024×1024, Display P3, opaque).
// Reference: UK-style pool set — solid yellows, red balls with a cream lower cap, white number spot.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)! }

// Background: deep charcoal with a soft overhead table light.
ctx.drawLinearGradient(gradient([c(0.14, 0.14, 0.17), c(0.04, 0.04, 0.06)], [0, 1]),
                       start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
ctx.drawRadialGradient(gradient([c(1, 1, 1, 0.10), c(1, 1, 1, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 760), endRadius: 620, options: [])

enum Kind { case yellow, red }

func ball(_ kind: Kind, _ number: String, cx: CGFloat, cy: CGFloat, r: CGFloat) {
    let rect = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
    // Contact shadow on the cloth.
    ctx.drawRadialGradient(gradient([c(0, 0, 0, 0.6), c(0, 0, 0, 0)], [0, 1]),
                           startCenter: CGPoint(x: cx + r * 0.1, y: cy - r * 0.9), startRadius: 0,
                           endCenter: CGPoint(x: cx + r * 0.1, y: cy - r * 0.9), endRadius: r * 1.0, options: [])
    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()

    // Base colour.
    switch kind {
    case .yellow:
        ctx.setFillColor(c(0.99, 0.76, 0.12)); ctx.fill(rect)
    case .red:
        ctx.setFillColor(c(0.62, 0.05, 0.09)); ctx.fill(rect)
        // Cream lower cap: a spherical cap seen slightly from above reads as an ellipse edge.
        let capY = cy - r * 0.5
        let cap = CGMutablePath()
        cap.addRect(CGRect(x: cx - r, y: cy - r, width: 2 * r, height: capY - (cy - r)))
        cap.addEllipse(in: CGRect(x: cx - r * 1.02, y: capY - r * 0.22, width: r * 2.04, height: r * 0.44))
        ctx.addPath(cap); ctx.setFillColor(c(0.96, 0.93, 0.84)); ctx.fillPath()
    }

    // Number spot, nudged up-left toward the light like the reference.
    let spotC = CGPoint(x: cx - r * 0.12, y: cy + r * 0.22)
    let spotR = r * 0.36
    ctx.setFillColor(c(0.98, 0.97, 0.93))
    ctx.fillEllipse(in: CGRect(x: spotC.x - spotR, y: spotC.y - spotR, width: 2 * spotR, height: 2 * spotR))
    ctx.setStrokeColor(c(0.08, 0.08, 0.1)); ctx.setLineWidth(r * 0.035)
    let ring = spotR * 0.86
    ctx.strokeEllipse(in: CGRect(x: spotC.x - ring, y: spotC.y - ring, width: 2 * ring, height: 2 * ring))
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, spotR * 1.05, nil)
    let attr = NSAttributedString(string: number, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): c(0.06, 0.06, 0.08),
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: spotC.x - b.midX, y: spotC.y - b.midY)
    CTLineDraw(line, ctx)

    // Shading over everything: lit from upper left, dark toward the lower right rim.
    let light = CGPoint(x: cx - r * 0.4, y: cy + r * 0.45)
    ctx.drawRadialGradient(gradient([c(1, 1, 1, 0.18), c(0, 0, 0, 0), c(0, 0, 0, 0.55)], [0, 0.5, 1]),
                           startCenter: light, startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r * 1.08,
                           options: [.drawsAfterEndLocation])
    // Specular highlight.
    ctx.drawRadialGradient(gradient([c(1, 1, 1, 0.95), c(1, 1, 1, 0)], [0, 1]),
                           startCenter: light, startRadius: 0, endCenter: light, endRadius: r * 0.2, options: [])
    ctx.restoreGState()
}

// Head to head: a red and a yellow.
ball(.red, "1", cx: 375, cy: 455, r: 235)
ball(.yellow, "9", cx: 665, cy: 560, r: 235)

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
