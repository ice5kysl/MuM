// 生成站点 favicon：与 app 图标同一套几何（小 M + 细长绿光标）。
// 为什么单独写：favicon 是**扁平**的 —— 不带 app 图标那层渐变和阴影，
// 在 16px 的浏览器标签页上，渐变只会变成一团脏色。
import AppKit

let size: CGFloat = 512
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 底色：圆角方块（浏览器标签页里 favicon 通常直接是方的，圆角留给浏览器）
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
             xRadius: size * 0.2237, yRadius: size * 0.2237).fill()

let centerX = size / 2
let stroke = size * 0.075          // favicon 比 app 图标粗一档 —— 16px 下才看得见
let mWidth = size * 0.29
let mHeight = size * 0.33
let bottom = size * 0.44
let top = bottom + mHeight
let left = centerX - mWidth / 2
let right = centerX + mWidth / 2
let valley = bottom + mHeight * 0.42

let m = NSBezierPath()
m.move(to: NSPoint(x: left, y: bottom))
m.line(to: NSPoint(x: left, y: top))
m.line(to: NSPoint(x: centerX, y: valley))
m.line(to: NSPoint(x: right, y: top))
m.line(to: NSPoint(x: right, y: bottom))
m.lineWidth = stroke
m.lineJoinStyle = .round
m.lineCapStyle = .butt
NSColor.white.setStroke()
m.stroke()

let barWidth = size * 0.60
let barHeight = size * 0.075       // 比 app 图标粗一倍：标签页里那条线必须看得见
NSColor(srgbRed: 0.180, green: 0.800, blue: 0.290, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: centerX - barWidth / 2, y: size * 0.305,
                                 width: barWidth, height: barHeight),
             xRadius: barHeight * 0.45, yRadius: barHeight * 0.45).fill()
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "favicon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("已生成 \(out)（\(Int(size))x\(Int(size))）")
