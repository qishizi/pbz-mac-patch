// Draws the app icon (original artwork, no game assets): dark red squircle, ink ring, blade slash, "零".
import AppKit
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let box = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()
shape.addClip()
NSGradient(colors: [NSColor(red: 0.42, green: 0.03, blue: 0.05, alpha: 1), NSColor(red: 0.07, green: 0.06, blue: 0.08, alpha: 1)])!.draw(in: box, angle: -70)
// ink ring
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 285, startAngle: 115, endAngle: 440)
ring.lineWidth = 46; ring.lineCapStyle = .round
NSColor(red: 0.86, green: 0.1, blue: 0.1, alpha: 0.95).setStroke(); ring.stroke()
// blade slash
let slash = NSBezierPath()
slash.move(to: NSPoint(x: 150, y: 250)); slash.line(to: NSPoint(x: 890, y: 760)); slash.line(to: NSPoint(x: 865, y: 790)); slash.close()
NSColor(white: 0.8, alpha: 0.55).setFill(); slash.fill()
// character
let font = NSFont(name: "STSongti-SC-Black", size: 440) ?? NSFont(name: "PingFangSC-Semibold", size: 440) ?? NSFont.boldSystemFont(ofSize: 430)
let str = NSAttributedString(string: "零", attributes: [.font: font, .foregroundColor: NSColor.white])
let sz = str.size()
str.draw(at: NSPoint(x: 512 - sz.width / 2, y: 512 - sz.height / 2 + 8))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
