import AppKit
import Foundation

// Demo-data helper for filming Pasteboard. All data is fake.
//
//   demo_tool notes  <output.json>   write demo notes (uses the app's own Note model)
//   demo_tool assets <folder>        write demo images + a demo file to copy by hand
//   demo_tool clips                  copy demo items to the clipboard, one at a time

// MARK: - Drawing helpers

func png(_ w: Int, _ h: Int, _ draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rounded(_ r: CGRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}

/// A fake analytics dashboard
func dashboardImage() -> Data {
    png(1600, 1000) { r in
        NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1),
                            NSColor(srgbRed: 0.10, green: 0.12, blue: 0.24, alpha: 1)])!.draw(in: r, angle: -60)
        rounded(CGRect(x: 60, y: 880, width: 1480, height: 70), 18, NSColor.white.withAlphaComponent(0.06))
        for i in 0..<3 {
            let x = CGFloat(60 + i * 500)
            rounded(CGRect(x: x, y: 640, width: 480, height: 200), 24, NSColor.white.withAlphaComponent(0.07))
            rounded(CGRect(x: x + 30, y: 760, width: 120, height: 18), 9, NSColor.white.withAlphaComponent(0.35))
            rounded(CGRect(x: x + 30, y: 690, width: 220, height: 44), 14,
                    [NSColor.systemBlue, NSColor.systemPurple, NSColor.systemTeal][i].withAlphaComponent(0.9))
        }
        rounded(CGRect(x: 60, y: 60, width: 1480, height: 540), 28, NSColor.white.withAlphaComponent(0.06))
        let heights: [CGFloat] = [180, 260, 210, 340, 300, 420, 380, 470, 400, 500]
        for (i, h) in heights.enumerated() {
            let x = CGFloat(120 + i * 140)
            let g = NSGradient(colors: [NSColor.systemBlue, NSColor.systemPurple])!
            let path = NSBezierPath(roundedRect: CGRect(x: x, y: 100, width: 80, height: h), xRadius: 16, yRadius: 16)
            g.draw(in: path, angle: 90)
        }
    }
}

/// An abstract gradient "poster"
func posterImage() -> Data {
    png(1400, 900) { r in
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.40, alpha: 1),
                            NSColor(srgbRed: 0.55, green: 0.30, blue: 0.95, alpha: 1),
                            NSColor(srgbRed: 0.20, green: 0.55, blue: 1.00, alpha: 1)])!.draw(in: r, angle: -35)
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: CGRect(x: 880, y: 380, width: 640, height: 640)).fill()
        NSBezierPath(ovalIn: CGRect(x: -140, y: -160, width: 520, height: 520)).fill()
        rounded(CGRect(x: 170, y: 250, width: 640, height: 400), 40, NSColor.white.withAlphaComponent(0.92))
        rounded(CGRect(x: 230, y: 520, width: 360, height: 40), 14, NSColor(white: 0.25, alpha: 1))
        rounded(CGRect(x: 230, y: 450, width: 480, height: 22), 11, NSColor(white: 0.7, alpha: 1))
        rounded(CGRect(x: 230, y: 400, width: 420, height: 22), 11, NSColor(white: 0.8, alpha: 1))
        rounded(CGRect(x: 230, y: 310, width: 170, height: 56), 28, NSColor.systemBlue)
    }
}

// MARK: - Demo content

let demoFileDir = "/tmp/PasteboardDemo"
let demoFilePath = demoFileDir + "/Q4-Report.pdf"

func writeDemoFile(to path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                             withIntermediateDirectories: true)
    try? "Q4 report (demo file)".write(toFile: path, atomically: true, encoding: .utf8)
}

let swiftSnippet = """
import Foundation

func greeting(for name: String) -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    return hour < 12 ? "Good morning, \\(name)" : "Hello, \\(name)"
}
"""

func demoNotes() -> [Note] {
    let now = Date()
    func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
    return [
        Note(title: "Work Logins",
             content: .form([
                FormItem(value: "sam.rivera@acme-demo.com", label: "Username"),
                FormItem(value: "demo-Pass-2026!", label: "Password"),
                FormItem(value: "10.0.12.34", label: "Server"),
                FormItem(value: "482 913", label: "VPN code"),
             ]),
             createdAt: ago(86400 * 9), modifiedAt: ago(600), isPinned: true),
        Note(title: "Shipping Address",
             content: .form([
                FormItem(value: "Sam Rivera", label: "Name"),
                FormItem(value: "42 Harbour Street, Apt 5B", label: "Street"),
                FormItem(value: "Dublin", label: "City"),
                FormItem(value: "D02 X285", label: "Postcode"),
             ]),
             createdAt: ago(86400 * 12), modifiedAt: ago(3600 * 5)),
        Note(title: "Weekend Trip",
             content: .plainText("Packing list\n\n• Passport\n• Charger + adapter\n• Camera\n• Rain jacket\n• Sunglasses\n\nTrain leaves 08:15 from Platform 3."),
             createdAt: ago(86400 * 4), modifiedAt: ago(86400 * 2)),
        Note(title: "Design Mockup",
             content: .image(posterImage()),
             createdAt: ago(86400 * 6), modifiedAt: ago(86400 * 3)),
    ]
}

// MARK: - Commands

func copyToClipboard(_ label: String, _ write: (NSPasteboard) -> Void) {
    let pb = NSPasteboard.general
    pb.clearContents()
    write(pb)
    print("copied: \(label)")
    Thread.sleep(forTimeInterval: 1.3)   // the app polls every 0.5s
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: demo_tool notes <out.json> | assets <folder> | clips"); exit(1)
}

switch args[1] {
case "notes":
    guard args.count >= 3 else { print("need an output path"); exit(1) }
    let notes = demoNotes()
    let data = try JSONEncoder().encode(notes)
    try data.write(to: URL(fileURLWithPath: args[2]))
    // verify with the same decoder the app uses
    let back = try JSONDecoder().decode([Note].self, from: data)
    print("wrote \(back.count) notes to \(args[2])")

case "assets":
    guard args.count >= 3 else { print("need a folder"); exit(1) }
    try FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
    try dashboardImage().write(to: URL(fileURLWithPath: args[2] + "/demo-dashboard.png"))
    try posterImage().write(to: URL(fileURLWithPath: args[2] + "/demo-poster.png"))
    writeDemoFile(to: args[2] + "/Q4-Report.pdf")
    print("wrote demo-dashboard.png, demo-poster.png, Q4-Report.pdf to \(args[2])")

case "clips":
    writeDemoFile(to: demoFilePath)
    Thread.sleep(forTimeInterval: 1.5)   // let the app's clipboard watcher settle
    // Copy order = bottom to top of the list (the last one copied ends up on top)
    copyToClipboard("order status") { $0.setString("Order #48213 · Shipped · arrives Tue 12 Nov", forType: .string) }
    copyToClipboard("email draft") { $0.setString("Hi Sam, thanks for the quick turnaround! I'll send the final design files over this afternoon.", forType: .string) }
    copyToClipboard("swift code") { $0.setString(swiftSnippet, forType: .string) }
    // Copied as an image *file* so the clip is named "Dashboard.png" with a normal size
    // (copying raw image data names it after the source app and bloats it to a few MB)
    let dashboardPath = demoFileDir + "/Dashboard.png"
    try? dashboardImage().write(to: URL(fileURLWithPath: dashboardPath))
    copyToClipboard("dashboard image") { $0.writeObjects([URL(fileURLWithPath: dashboardPath) as NSURL]) }
    copyToClipboard("report file") { $0.writeObjects([URL(fileURLWithPath: demoFilePath) as NSURL]) }
    copyToClipboard("link") { $0.setString("https://github.com/nahid0-0/Pasteboard", forType: .string) }

default:
    print("unknown command \(args[1])"); exit(1)
}
