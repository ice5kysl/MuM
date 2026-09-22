#!/usr/bin/env swift
//
// 用 ice 设计的新 logo 生成应用图标与网站图标。
//
//   swift scripts/make-icon-from-logo.swift <logo.png> <out-dir>
//
// 产出（都在 out-dir，即 .build/icon/）：
//   - masked.png            圆角外透明的主图（角上色从四角连通域抠掉）
//   - AppIcon.iconset/      10 个尺寸，build-app.sh 用 iconutil 打成 icns
//
// 为什么从位图出发而不是继续用 make-icon.swift 代码画：
// logo 换成了 ice 手绘版（MuM_logo_d/l.png），图形语言不再适合程序化重绘。
// 源图无 alpha（角上是不透明的白/黑），系统 Dock 与网站都需要透明角，
// 所以从四角做连通域抠图 —— 只抠与角色相近且连通到边缘的区域，
// 不会伤到 M 的实心笔画。

import AppKit

guard CommandLine.arguments.count > 2 else {
    FileHandle.standardError.write("用法: make-icon-from-logo.swift <logo.png> <out-dir>\n".data(using: .utf8)!)
    exit(2)
}
let source = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: source) else {
    FileHandle.standardError.write("读不到图片：\(source)\n".data(using: .utf8)!)
    exit(1)
}

// 源图无 alpha —— 必须先重绘进一个 4 通道的位图，
// 否则后面的 setColor(.clear) 没有 alpha 可写，全变成不透明黑（踩过）
let width = Int(image.size.width)
let height = Int(image.size.height)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    FileHandle.standardError.write("创建位图失败\n".data(using: .utf8)!)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
           from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

/// 每通道容差：角上的底色与圆角描边之间有明显亮度差，16 足够分开又不会漏进图形内部
let tolerance = 16

func pixelMatchesCorner(_ x: Int, _ y: Int, corner: (r: Int, g: Int, b: Int)) -> Bool {
    guard let color = bitmap.colorAt(x: x, y: y) else { return false }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return abs(Int(r * 255) - corner.r) <= tolerance
        && abs(Int(g * 255) - corner.g) <= tolerance
        && abs(Int(b * 255) - corner.b) <= tolerance
}

func cornerColor(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let color = bitmap.colorAt(x: x, y: y) ?? .black
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Int(r * 255), Int(g * 255), Int(b * 255))
}

// 从四角 BFS：把与任一角颜色相近、且与边缘连通的像素标成透明
let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
let cornerColors = corners.map { cornerColor($0.0, $0.1) }

func isBackground(_ x: Int, _ y: Int) -> Bool {
    cornerColors.contains { pixelMatchesCorner(x, y, corner: $0) }
}

var visited = [Bool](repeating: false, count: width * height)
var queue: [(Int, Int)] = []
for (cx, cy) in corners where isBackground(cx, cy) {
    visited[cy * width + cx] = true
    queue.append((cx, cy))
}
var index = 0
while index < queue.count {
    let (x, y) = queue[index]; index += 1
    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
        let flat = ny * width + nx
        guard !visited[flat], isBackground(nx, ny) else { continue }
        visited[flat] = true
        queue.append((nx, ny))
    }
}

// setColor(.clear) 在这类位图上不写 alpha（实测 alpha 恒 1）—— 直写位图数据
guard let pixels = bitmap.bitmapData else {
    FileHandle.standardError.write("取不到位图数据\n".data(using: .utf8)!)
    exit(1)
}
let bytesPerRow = bitmap.bytesPerRow
for (x, y) in queue {
    let offset = y * bytesPerRow + x * 4
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
}

FileManager.default.createFile(atPath: "\(outDir)/.mask-log", contents: "抠掉像素 \(queue.count) / \(width * height)\n".data(using: .utf8)!)

guard let masked = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("编码透明主图失败\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try masked.write(to: URL(fileURLWithPath: "\(outDir)/masked.png"))

// iconset：macOS 要的 10 个尺寸
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

guard let maskedImage = NSImage(data: masked) else { exit(1) }
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    maskedImage.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                     from: NSRect(x: 0, y: 0, width: maskedImage.size.width, height: maskedImage.size.height),
                     operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
print("完成：\(outDir)/AppIcon.iconset（抠掉背景像素 \(queue.count)）")
