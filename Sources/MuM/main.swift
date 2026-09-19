import AppKit
LaunchTimer.origin = Date()          // t0：进程启动
LaunchTimer.mark("进程启动")


// MuM 走 AppKit 优先的路线（和 Ghostty 的 macOS 层同构）：由 NSApplication
// 显式接管生命周期，而不是用 SwiftUI App 协议。这样窗口、菜单、快捷键、
// 响应链全部可控，也避免了 SPM 可执行目标里 @main + App 协议的各种坑。

// 无界面自检通道：跑 `MuM --selftest` 只验证渲染器，不弹窗口。
// 放在启动 NSApplication 之前，这样它也能在 CI 或 SSH 会话里跑。
if CommandLine.arguments.contains("--selftest") {
    exit(RendererSelfTest.run(arguments: CommandLine.arguments))
}

// 大文档性能基线：`MuM --bench <文件.md>`；滚动流畅度：`MuM --bench scroll <文件.md>`
if CommandLine.arguments.contains("--bench") {
    if let index = CommandLine.arguments.firstIndex(of: "--bench"),
       index + 1 < CommandLine.arguments.count,
       CommandLine.arguments[index + 1] == "scroll" {
        exit(ScrollBench.run(arguments: CommandLine.arguments))
    }
    exit(RenderBench.run(arguments: CommandLine.arguments))
}

// 全局搜索性能基线：`MuM --bench-search <语料目录> <查询词>`
if CommandLine.arguments.contains("--bench-search") {
    exit(SearchBench.run(arguments: CommandLine.arguments))
}

// 应用内自驱动 UI 测试：`MuM --uitest <场景|all> [文档.md]`。
// 外部模拟点击要 Accessibility 权限且不可靠，所以让应用自己触发自己的动作再断言状态。
if CommandLine.arguments.contains("--uitest") {
    exit(UITestRunner.run(arguments: CommandLine.arguments))
}

// headless 子命令（给 agent 用）：`MuM render|outline|search|check …`
// prohibited 策略：无窗口、无 Dock 图标、无 UI 激活。返回 nil 表示不是子命令，继续正常启动。
if let code = Headless.run(arguments: CommandLine.arguments) {
    exit(code)
}

// 离屏快照：`MuM --snapshot out.png`，不需要屏幕点亮
if CommandLine.arguments.contains("--snapshot")
    || CommandLine.arguments.contains("--snapshot-settings") {
    exit(SnapshotRenderer.run(arguments: CommandLine.arguments))
}

let mumApplication = NSApplication.shared
let mumDelegate = AppDelegate()

mumApplication.delegate = mumDelegate
mumApplication.setActivationPolicy(.regular)
mumApplication.run()
