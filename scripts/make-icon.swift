#!/usr/bin/env swift
//
// 生成 MuM 的应用图标（AppIcon.iconset → iconutil → AppIcon.icns）。
//
// 用代码画而不是塞一张位图：图标需要 16pt 到 1024pt 共 10 个尺寸，从矢量描述
// 逐个尺寸渲染出来，小尺寸下笔画才不会糊成一团。
//
// 设计：深色圆角方块 + 居中的粗体 M + 底部一道强调色横线（暗示 Markdown 的下划线语法）。

import AppKit

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

// MARK: - 绘制

func drawIcon(in rect: NSRect) {
    let size = rect.width

    // 圆角方块底
    let inset = size * 0.055
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.2237 // 贴近 macOS 的 squircle 比例
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.196, green: 0.204, blue: 0.243, alpha: 1),
        NSColor(srgbRed: 0.078, green: 0.082, blue: 0.106, alpha: 1),
    ])
    gradient?.draw(in: shape, angle: -90)

    // 顶部一道极弱的高光，让方块不至于死板
    NSGraphicsContext.saveGraphicsState()
    shape.setClip()
    let highlight = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.09),
        NSColor(white: 1, alpha: 0.0),
    ])
    highlight?.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // M 字形
    let fontSize = size * 0.50
    let base = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    let font = NSFont(descriptor: descriptor, size: fontSize) ?? base

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let glyph = "M" as NSString
    let glyphSize = glyph.size(withAttributes: attributes)

    let glyphOrigin = NSPoint(
        x: body.midX - glyphSize.width / 2,
        y: body.midY - glyphSize.height / 2 + size * 0.045
    )
    glyph.draw(at: glyphOrigin, withAttributes: attributes)

    // 底部强调线
    let barWidth = size * 0.34
    let barHeight = max(size * 0.028, 1)
    let bar = NSRect(
        x: body.midX - barWidth / 2,
        y: body.minY + size * 0.155,
        width: barWidth,
        height: barHeight
    )
    NSColor(srgbRed: 0.298, green: 0.604, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
}

func renderPNG(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// MARK: - 输出 iconset

let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (文件名, 像素尺寸)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    guard let data = renderPNG(pixels: pixels) else {
        FileHandle.standardError.write("渲染 \(name) 失败\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(name))
}

print("已生成 \(iconset.path)")
