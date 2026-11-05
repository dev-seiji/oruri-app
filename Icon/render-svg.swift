import AppKit
// Gera os PNGs dos ícones a partir dos SVGs (NSImage lê SVG): oruri-small.svg para 16 e 32 px, oruri.svg do 64 em diante.
// uso: swift Icon/render-svg.swift entrada.svg saida.png largura altura
let a = CommandLine.arguments
guard let img = NSImage(contentsOfFile: a[1]) else { fatalError("não abriu \(a[1])") }
let w = Int(a[3])!, h = Int(a[4])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
