import AppKit

/// 滚动流畅度基线（v0.5.1，定义见 `docs/versions/v0.5.1.md`）。
///
/// 用法：`MuM --bench scroll <文件.md>`
/// 样本：`scripts/make-bench-fixture.py 1 /tmp/scroll-1mb.md`（1MB / 5MB 各一份），
/// 再加一份真实项目里的真实文档 —— 生成样本结构均匀，真实文档才走得到极端路径。
///
/// 双口径，互补：
///   离屏绘制 —— 每步 `cacheDisplay` 强制立即绘制，测排版+绘制的 CPU 成本。
///               不含合成 / GPU / 显示链路调度，**只能当回归与趋势口径**，
///               不能当"用户实际帧率"写进对外文档。
///   真上屏   —— 真实在屏窗口 + `CADisplayLink` 记实际帧间隔。进程内自测，
///               零权限（不需要 Accessibility）。窗口被遮挡 / 无屏幕时明确报不可用。
///
/// 测量卫生：首滚（首次排版新区域）与热滚分开记；向下 / 向上分开记；
/// 打开后的第一屏不计入滚动数据（那是打开路径，TTFR 已管）。
enum ScrollBench {

    /// 判定线（v0.5.1）：P95 单步重绘 ≤ 16.7ms（等效 60fps），最差单步 ≤ 33ms
    static let p95BudgetMS = 16.7
    static let worstBudgetMS = 33.0

    static func run(arguments: [String]) -> Int32 {
        guard let flagIndex = arguments.firstIndex(of: "--bench"),
              flagIndex + 2 < arguments.count,
              arguments[flagIndex + 1] == "scroll" else {
            FileHandle.standardError.write("用法：MuM --bench scroll <文件.md>\n".data(using: .utf8)!)
            return 2
        }
        let path = arguments[flagIndex + 2]
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write("读不到文件：\(path)\n".data(using: .utf8)!)
            return 1
        }

        // 与阅读路径同一个 renderer，全量渲染 = 渐进填充完成后的状态
        let renderer = MarkdownRenderer(
            theme: MarkdownTheme(),
            baseURL: URL(fileURLWithPath: path).deletingLastPathComponent()
        )
        let attributed = renderer.render(text)

        // AppKit 视图体系需要 NSApplication 存在，但不需要 run()（同 SnapshotRenderer）
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let preview = PreviewViewController()
        let window = NSWindow(contentViewController: preview)
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.title = "MuM --bench scroll"
        // accessory + orderFrontRegardless：窗口上屏但不抢焦点、不进 Dock
        window.orderFrontRegardless()

        preview.show(attributed: attributed, restoreFraction: nil)
        // 让首屏布局跑完 —— 首屏排版属于打开路径，不计入滚动数据
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        preview.view.layoutSubtreeIfNeeded()

        let textView = preview.previewTextView
        let scrollView = preview.debugScrollView
        let clip = scrollView.contentView
        let viewportH = clip.bounds.height
        guard viewportH > 100,
              let rep = textView.bitmapImageRepForCachingDisplay(in: textView.visibleRect) else {
            FileHandle.standardError.write("视图未能完成初始布局\n".data(using: .utf8)!)
            return 1
        }

        let mb = Double(text.utf8.count) / 1_048_576
        let label = (path as NSString).lastPathComponent
        print("文件  \(label)")
        print("大小  \(String(format: "%.2f", mb)) MB / \(text.count) 字符 / \(text.split(separator: "\n").count) 行")
        // debug / release 的绘制成本差好几倍，数字必须带构建配置才有意义
        #if DEBUG
        print("构建  ⚠️ debug（判定数字请用 release 构建：swift build -c release）")
        #else
        print("构建  release")
        #endif
        print("视口  \(Int(clip.bounds.width))×\(Int(viewportH)) pt @\(Int(window.backingScaleFactor))x，步进 = 一屏（整页重绘，最坏的真实滚动）")
        if let fps = NSScreen.main?.maximumFramesPerSecond {
            print("屏幕  标称 \(fps) fps")
        }
        print("")

        // ── 口径一：离屏绘制（cacheDisplay）─────────────────────────────
        // 首滚向下：每个新区域的首次排版发生在这里 —— 用户第一次通读付的钱
        let coldDown = measurePass(textView: textView, scrollView: scrollView, rep: rep, direction: 1)
        // 回到顶部，热滚向下：整篇已排版，纯绘制
        scrollToAbsolute(textView: textView, scrollView: scrollView, y: 0)
        let warmDown = measurePass(textView: textView, scrollView: scrollView, rep: rep, direction: 1)
        // 热滚向上：向上通常更贵（排版缓存自上往下建）
        let warmUp = measurePass(textView: textView, scrollView: scrollView, rep: rep, direction: -1)

        print("离屏绘制（cacheDisplay 强制立即绘制 = 排版+绘制成本；回归/趋势口径，≠ 用户实际帧率）")
        report("首滚向下", coldDown)
        report("热滚向下", warmDown)
        report("热滚向上", warmUp)

        // ── 口径二：真上屏（CADisplayLink 帧间隔）────────────────────────
        // 热路径整篇连滚：每帧前进一屏，记录实际帧间隔。回调被拖慢/跳帧
        // 会直接体现为帧间隔变大 —— 这才是用户看到的流畅度。
        scrollToAbsolute(textView: textView, scrollView: scrollView, y: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let scroller = DisplayLinkScroller(textView: textView, scrollView: scrollView)
        // macOS 没有 CADisplayLink(target:selector:) 构造器，由窗口创建并跟随其屏幕；
        // 但返回的 link 不会自动挂上 runloop（实测 macOS 26 不挂就永远不触发），
        // 必须手动 add —— 和 iOS 的 CADisplayLink 一样
        let link = window.displayLink(target: scroller, selector: #selector(DisplayLinkScroller.tick(_:)))
        link.add(to: .main, forMode: .common)
        let deadline = Date().addingTimeInterval(180)
        let firstFrameDeadline = Date().addingTimeInterval(3)
        while !scroller.done, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if scroller.timestamps.isEmpty, Date() > firstFrameDeadline { break }
        }
        link.invalidate()

        print("")
        if scroller.intervalsMS.count >= 10 {
            print("真上屏（CADisplayLink 实际帧间隔 = 用户看到的流畅度；零权限进程内自测）")
            report("热滚向下", scroller.intervalsMS, unitIsFrameInterval: true)
        } else {
            print("真上屏（CADisplayLink）：不可用 —— 窗口未上屏或被遮挡（收到 \(scroller.timestamps.count) 帧回调）")
        }

        print("")
        let strictest = coldDown
        let p95 = percentile(strictest, 95)
        let worst = strictest.max() ?? 0
        if p95 <= p95BudgetMS, worst <= worstBudgetMS {
            print(String(format: "判定（v0.5.1）：首滚 P95 %.1f ms ≤ %.1f，最差 %.1f ms ≤ %.0f → 达标", p95, p95BudgetMS, worst, worstBudgetMS))
        } else {
            print(String(format: "判定（v0.5.1）：首滚 P95 %.1f ms（线 %.1f），最差 %.1f ms（线 %.0f）→ 超标", p95, p95BudgetMS, worst, worstBudgetMS))
        }
        return 0
    }

    // MARK: - 步进滚动 + 逐步计时

    /// 以一屏为步长把文档走一遍，每步滚动后用 cacheDisplay 强制立即绘制并计时。
    /// 到头（滚动位置不再移动）即停。
    private static func measurePass(
        textView: NSTextView,
        scrollView: NSScrollView,
        rep: NSBitmapImageRep,
        direction: CGFloat
    ) -> [Double] {
        let clip = scrollView.contentView
        let viewportH = clip.bounds.height
        var samples: [Double] = []
        var lastY = clip.bounds.origin.y
        for _ in 0..<10_000 {
            let targetY = max(lastY + direction * viewportH, 0)
            // scrollToVisible 会先强制排版目标区域（NSTextView 的既有行为），
            // 因此首滚的每一步都含"排版新区块"的成本 —— 正是要测的东西
            textView.scrollToVisible(NSRect(x: 0, y: targetY, width: 1, height: viewportH))
            scrollView.reflectScrolledClipView(clip)
            let y = clip.bounds.origin.y
            let visible = textView.visibleRect
            let t0 = Date()
            textView.cacheDisplay(in: visible, to: rep)
            samples.append(Date().timeIntervalSince(t0) * 1000)
            if abs(y - lastY) < 0.5 { break }
            lastY = y
        }
        return samples
    }

    private static func scrollToAbsolute(textView: NSTextView, scrollView: NSScrollView, y: CGFloat) {
        let clip = scrollView.contentView
        textView.scrollToVisible(NSRect(x: 0, y: y, width: 1, height: clip.bounds.height))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - 统计与输出

    /// 最近秩百分位
    private static func percentile(_ samples: [Double], _ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rank = max(1, Int((p / 100 * Double(sorted.count)).rounded(.up)))
        return sorted[min(rank, sorted.count) - 1]
    }

    private static func report(_ label: String, _ samples: [Double], unitIsFrameInterval: Bool = false) {
        guard !samples.isEmpty else { return }
        let p50 = percentile(samples, 50)
        let p95 = percentile(samples, 95)
        let worst = samples.max() ?? 0
        let suffix = unitIsFrameInterval ? "帧" : "步"
        let fps = unitIsFrameInterval ? String(format: "（P95 等效 %.0f fps）", 1000 / max(p95, 0.01)) : ""
        print(String(format: "  %@  P50 %6.1f ms   P95 %6.1f ms   最差 %6.1f ms   （%d %@）%@",
                     label, p50, p95, worst, samples.count, suffix, fps))
    }
}

/// CADisplayLink 每帧回调：记一帧时间戳，再把滚动位置推进一屏。
/// 帧间隔的统计在 ScrollBench 里做（这里只负责采集）。
private final class DisplayLinkScroller: NSObject {

    let textView: NSTextView
    let scrollView: NSScrollView
    var timestamps: [CFTimeInterval] = []
    var done = false

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
    }

    var intervalsMS: [Double] {
        zip(timestamps, timestamps.dropFirst()).map { ($1 - $0) * 1000 }
    }

    @objc func tick(_ link: CADisplayLink) {
        timestamps.append(CACurrentMediaTime())
        let clip = scrollView.contentView
        let viewportH = clip.bounds.height
        let before = clip.bounds.origin.y
        textView.scrollToVisible(NSRect(x: 0, y: before + viewportH, width: 1, height: viewportH))
        scrollView.reflectScrolledClipView(clip)
        if abs(clip.bounds.origin.y - before) < 0.5 {
            done = true
        }
    }
}
