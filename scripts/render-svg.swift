import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Int(arguments[3]) else {
    fail("usage: render-svg.swift <input.svg> <output.png> <size>")
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    fail("cannot read \(arguments[1])")
}

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: arguments[2]))
