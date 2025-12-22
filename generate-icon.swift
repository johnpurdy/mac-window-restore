#!/usr/bin/env swift

import AppKit

// Generate app icon from SF Symbol
func generateIcon() {
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    let iconsetPath = "/Users/johnpurdy/Github/mac-window-restore/AppIcon.iconset"

    // Create iconset directory
    try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for size in sizes {
        // Create image at 1x
        if let image = renderIcon(size: size) {
            let filename = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
            saveImage(image, to: "\(iconsetPath)/\(filename)")
        }

        // Create image at 2x (except for 1024 which is already 512@2x)
        if size <= 512, let image = renderIcon(size: size * 2) {
            let filename = "icon_\(size)x\(size)@2x.png"
            saveImage(image, to: "\(iconsetPath)/\(filename)")
        }
    }

    print("Icon images generated in \(iconsetPath)")
    print("Run: iconutil -c icns AppIcon.iconset -o WindowRestore.app/Contents/Resources/AppIcon.icns")
}

func renderIcon(size: Int) -> NSImage? {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Background - rounded rectangle with gradient
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.2
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background (blue)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -90)

    // Draw window icon in white
    let iconSize = CGFloat(size) * 0.6
    let iconX = (CGFloat(size) - iconSize) / 2
    let iconY = (CGFloat(size) - iconSize) / 2

    NSColor.white.setStroke()
    NSColor.white.setFill()

    // Main window
    let windowRect = NSRect(x: iconX, y: iconY + iconSize * 0.1, width: iconSize * 0.7, height: iconSize * 0.6)
    let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: iconSize * 0.05, yRadius: iconSize * 0.05)
    windowPath.lineWidth = CGFloat(size) * 0.03
    windowPath.stroke()

    // Title bar
    let titleBar = NSRect(x: iconX, y: iconY + iconSize * 0.55, width: iconSize * 0.7, height: iconSize * 0.15)
    NSBezierPath(roundedRect: titleBar, xRadius: iconSize * 0.05, yRadius: iconSize * 0.05).fill()

    // Second window (offset)
    let window2Rect = NSRect(x: iconX + iconSize * 0.3, y: iconY + iconSize * 0.25, width: iconSize * 0.7, height: iconSize * 0.6)
    let window2Path = NSBezierPath(roundedRect: window2Rect, xRadius: iconSize * 0.05, yRadius: iconSize * 0.05)
    window2Path.lineWidth = CGFloat(size) * 0.03
    window2Path.stroke()

    // Second title bar
    let titleBar2 = NSRect(x: iconX + iconSize * 0.3, y: iconY + iconSize * 0.7, width: iconSize * 0.7, height: iconSize * 0.15)
    NSBezierPath(roundedRect: titleBar2, xRadius: iconSize * 0.05, yRadius: iconSize * 0.05).fill()

    image.unlockFocus()
    return image
}

func saveImage(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
}

generateIcon()
