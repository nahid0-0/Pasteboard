import AppKit

// Draws the still graphics for the product video (1920x1080 PNGs, transparent where needed).
//
//   assets bg       <out.png>
//   assets card     <out_bg.png> <out_mask.png> <w> <h> <cy>    background + card shadow, and the card's rounded mask
//   assets caption  <out.png> <text>                             caption at the top of the frame
//   assets keys     <out.png> <key> [<key> ...]                  key caps at the bottom of the frame
//   assets title    <out.png> <icon.png>
//   assets end      <out.png> <icon.png>

let W = 1920, H = 1080
let accent = NSColor(srgbRed: 0.18, green: 0.48, blue: 1.0, alpha: 1)

func render(_ w: Int, _ h: Int, to path: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Top-left based rect → AppKit (bottom-left) rect
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(H) - y - h, width: w, height: h)
}

func drawBackground() {
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    NSGradient(colors: [NSColor(srgbRed: 0.035, green: 0.043, blue: 0.075, alpha: 1),
                        NSColor(srgbRed: 0.075, green: 0.090, blue: 0.150, alpha: 1)])!.draw(in: full, angle: -70)
    // soft accent glow behind the card
    let glow = NSGradient(colors: [accent.withAlphaComponent(0.22), accent.withAlphaComponent(0.0)])!
    glow.draw(fromCenter: NSPoint(x: 960, y: 470), radius: 0, toCenter: NSPoint(x: 960, y: 470), radius: 900, options: [])
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color, .kern: kern])
}

func drawCentered(_ a: NSAttributedString, topY: CGFloat) {
    let sz = a.size()
    a.draw(at: NSPoint(x: (CGFloat(W) - sz.width) / 2, y: CGFloat(H) - topY - sz.height))
}

let args = CommandLine.arguments
switch args[1] {
case "bg":
    render(W, H, to: args[2]) { drawBackground() }

case "card":
    let cw = CGFloat(Double(args[4])!), ch = CGFloat(Double(args[5])!), cy = CGFloat(Double(args[6])!)
    let rect = r((CGFloat(W) - cw) / 2, cy - ch / 2, cw, ch)
    let radius: CGFloat = 22
    render(W, H, to: args[2]) {
        drawBackground()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 60
        shadow.shadowOffset = NSSize(width: 0, height: -24)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        // hairline border
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: radius + 1, yRadius: radius + 1)
        border.lineWidth = 2
        border.stroke()
    }
    // mask is the card's own size: white rounded rect on black
    render(Int(cw), Int(ch), to: args[3]) {
        NSColor.black.setFill(); CGRect(x: 0, y: 0, width: cw, height: ch).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: cw, height: ch), xRadius: radius, yRadius: radius).fill()
    }

case "caption":
    // sits in the 120 px bar above the footage
    render(W, H, to: args[2]) {
        let a = text(args[3], size: 44, weight: .medium, color: .white, kern: -0.3)
        drawCentered(a, topY: (120 - a.size().height) / 2)
    }

case "keys":
    let keys = Array(args[3...])
    let cap: CGFloat = 92, gap: CGFloat = 14, pad: CGFloat = 18
    let widths = keys.map { k -> CGFloat in k.count > 1 ? max(cap, text(k, size: 34, weight: .medium, color: .white).size().width + 48) : cap }
    let total = widths.reduce(0, +) + gap * CGFloat(keys.count - 1) + pad * 2
    let pill = r((CGFloat(W) - total) / 2, CGFloat(H) - 64 - cap - pad * 2, total, cap + pad * 2)
    render(W, H, to: args[2]) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 26, yRadius: 26).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let pb = NSBezierPath(roundedRect: pill, xRadius: 26, yRadius: 26); pb.lineWidth = 1.5; pb.stroke()

        var x = pill.minX + pad
        for (k, w) in zip(keys, widths) {
            let keyRect = CGRect(x: x, y: pill.minY + pad, width: w, height: cap)
            // key body with a darker "skirt" at the bottom for depth
            NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
            NSBezierPath(roundedRect: keyRect, xRadius: 16, yRadius: 16).fill()
            let top = CGRect(x: keyRect.minX, y: keyRect.minY + 6, width: w, height: cap - 6)
            NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.29, blue: 0.35, alpha: 1),
                                NSColor(srgbRed: 0.20, green: 0.215, blue: 0.26, alpha: 1)])!
                .draw(in: NSBezierPath(roundedRect: top, xRadius: 16, yRadius: 16), angle: -90)
            NSColor.white.withAlphaComponent(0.14).setStroke()
            let kb = NSBezierPath(roundedRect: top.insetBy(dx: 0.75, dy: 0.75), xRadius: 15, yRadius: 15); kb.lineWidth = 1.5; kb.stroke()
            let label = text(k, size: k.count > 1 ? 34 : 44, weight: .medium, color: .white)
            let ls = label.size()
            label.draw(at: NSPoint(x: top.midX - ls.width / 2, y: top.midY - ls.height / 2))
            x += w + gap
        }
    }

case "title", "end":
    let icon = NSImage(contentsOfFile: args[3])!
    render(W, H, to: args[2]) {
        drawBackground()
        if args[1] == "title" {
            icon.draw(in: r(960 - 90, 250, 180, 180))
            drawCentered(text("Your clipboard forgets.", size: 84, weight: .bold, color: .white, kern: -1.5), topY: 490)
            drawCentered(text("Pasteboard doesn’t.", size: 84, weight: .bold, color: accent, kern: -1.5), topY: 600)
        } else {
            icon.draw(in: r(960 - 110, 220, 220, 220))
            drawCentered(text("Pasteboard", size: 96, weight: .bold, color: .white, kern: -1.5), topY: 470)
            drawCentered(text("Clipboard history for macOS · Free & open source", size: 38, weight: .regular,
                              color: NSColor.white.withAlphaComponent(0.7)), topY: 600)
            drawCentered(text("github.com/nahid0-0/Pasteboard", size: 40, weight: .semibold, color: accent), topY: 672)
        }
    }

default:
    fatalError("unknown command \(args[1])")
}
