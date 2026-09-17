#!/usr/bin/env swift
//
// 生成 MuM 的应用图标（AppIcon.iconset → iconutil → AppIcon.icns）。
//
// 用代码画而不是塞一张位图：图标需要 16pt 到 1024pt 共 10 个尺寸，从矢量描述
// 逐个尺寸渲染出来，小尺寸下笔画才不会糊成一团。
//
// 设计：深色圆角方块 + 居中的几何 M + 底部一道绿色横线。
//
// M 不用字体字形，而是用几段粗线画出来 —— 关键差别在**接头**：
// 字体里的 M 是圆角设计（SF Rounded），顶角是圆的；这里用斜接（miter）接头，
// 顶角是刀锋一样的尖点，端点也是平切。整体更硬、更有棱角。
// 底部横线用绿色（#2ECC4A），作为整个图标唯一的高饱和色。

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

    // M 字形 —— 几何绘制，斜接尖角。
    // 笔画宽度必须明显小于字面宽度的 1/4，否则四段笔画会互相吃掉，
    // 中间那个 V 填实，整个字就糊成一个三角块了。
    let stroke = size * 0.090
    let mWidth = size * 0.435
    let mHeight = size * 0.445
    let centerX = body.midX
    let bottom = body.minY + size * 0.335
    let top = bottom + mHeight
    let left = centerX - mWidth / 2
    let right = centerX + mWidth / 2
    // V 的谷底：抬高一点才有"谷"，太深会顶到横线
    let valley = bottom + mHeight * 0.42

    let mPath = NSBezierPath()
    mPath.move(to: NSPoint(x: left, y: bottom))
    mPath.line(to: NSPoint(x: left, y: top))
    mPath.line(to: NSPoint(x: centerX, y: valley))
    mPath.line(to: NSPoint(x: right, y: top))
    mPath.line(to: NSPoint(x: right, y: bottom))
    mPath.lineWidth = stroke
    mPath.lineJoinStyle = .miter
    mPath.lineCapStyle = .butt
    // 默认斜接限制是 10，顶角那个锐角会被削平成斜角；放宽到 20 保住尖点
    mPath.miterLimit = 20

    NSColor.white.setStroke()
    mPath.stroke()

    // 底部强调线
    let barWidth = size * 0.34
    let barHeight = max(size * 0.028, 1)
    let bar = NSRect(
        x: body.midX - barWidth / 2,
        y: body.minY + size * 0.155,
        width: barWidth,
        height: barHeight
    )
    NSColor(srgbRed: 0.180, green: 0.800, blue: 0.290, alpha: 1).setFill()   // #2ECC4A
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
