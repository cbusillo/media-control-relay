#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = repoRoot.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let outputIcon = repoRoot.appendingPathComponent("Resources/AppIcon.icns")
let images = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [red, green, blue, alpha]
    )!
}

func renderIcon(pixels: Int) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: pixels,
              height: pixels,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let dimension = CGFloat(pixels)
    context.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let bodyInset = dimension * 0.095
    let bodyRect = CGRect(
        x: bodyInset,
        y: bodyInset,
        width: dimension - bodyInset * 2,
        height: dimension - bodyInset * 2
    )
    let bodyPath = CGPath(
        roundedRect: bodyRect,
        cornerWidth: dimension * 0.18,
        cornerHeight: dimension * 0.18,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -dimension * 0.025),
        blur: dimension * 0.045,
        color: color(0.02, 0.08, 0.18, 0.42)
    )
    context.addPath(bodyPath)
    context.setFillColor(color(0.10, 0.25, 0.50))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            color(0.31, 0.61, 1.00),
            color(0.12, 0.31, 0.67),
            color(0.06, 0.18, 0.40),
        ] as CFArray,
        locations: [0, 0.58, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: dimension * 0.5, y: bodyRect.maxY),
        end: CGPoint(x: dimension * 0.5, y: bodyRect.minY),
        options: []
    )

    let highlightGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 0.6]
    )!
    context.drawLinearGradient(
        highlightGradient,
        start: CGPoint(x: dimension * 0.5, y: bodyRect.maxY),
        end: CGPoint(x: dimension * 0.5, y: dimension * 0.50),
        options: []
    )
    context.restoreGState()

    context.setFillColor(color(1, 1, 1, 0.97))
    context.beginPath()
    context.move(to: CGPoint(x: dimension * 0.275, y: dimension * 0.425))
    context.addLine(to: CGPoint(x: dimension * 0.375, y: dimension * 0.425))
    context.addLine(to: CGPoint(x: dimension * 0.505, y: dimension * 0.315))
    context.addLine(to: CGPoint(x: dimension * 0.505, y: dimension * 0.685))
    context.addLine(to: CGPoint(x: dimension * 0.375, y: dimension * 0.575))
    context.addLine(to: CGPoint(x: dimension * 0.275, y: dimension * 0.575))
    context.closePath()
    context.fillPath()

    context.setStrokeColor(color(1, 1, 1, 0.97))
    context.setLineWidth(max(1, dimension * 0.042))
    context.setLineCap(.round)
    for radius in [dimension * 0.155, dimension * 0.245] {
        context.beginPath()
        context.addArc(
            center: CGPoint(x: dimension * 0.49, y: dimension * 0.50),
            radius: radius,
            startAngle: -0.62,
            endAngle: 0.62,
            clockwise: false
        )
        context.strokePath()
    }

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for (size, filename) in images {
    let destination = outputDirectory.appendingPathComponent(filename)
    try renderIcon(pixels: size).write(to: destination, options: .atomic)
}

try? FileManager.default.removeItem(at: outputIcon)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "--convert", "icns",
    "--output", outputIcon.path,
    outputDirectory.path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}
