import AppKit

// Reject the simulator's blank launch surface. Only inspect the content area, excluding
// status/navigation bars: a status clock alone must not count as a rendered screen.
guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let bitmap = NSBitmapImageRep(data: data) else { exit(1) }
var dark = 0, light = 0, samples = 0
for y in stride(from: bitmap.pixelsHigh / 5, to: bitmap.pixelsHigh * 9 / 10, by: 4) {
    for x in stride(from: bitmap.pixelsWide / 20, to: bitmap.pixelsWide * 19 / 20, by: 4) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        samples += 1
        if brightness < 0.3 { dark += 1 }
        if brightness > 0.6 { light += 1 }
    }
}
guard samples > 0, Double(dark) / Double(samples) > 0.5, light > 100 else { exit(1) }
