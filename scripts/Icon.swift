import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
NSColor(calibratedRed: 0.32, green: 0.65, blue: 1, alpha: 1).setStroke()
for points: [NSPoint] in [
    [.init(x: 310, y: 640), .init(x: 714, y: 640), .init(x: 605, y: 749)],
    [.init(x: 714, y: 640), .init(x: 605, y: 531)],
    [.init(x: 714, y: 380), .init(x: 310, y: 380), .init(x: 419, y: 489)],
    [.init(x: 310, y: 380), .init(x: 419, y: 271)],
] {
    let path = NSBezierPath()
    path.lineWidth = 55
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
