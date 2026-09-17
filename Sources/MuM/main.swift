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

// 大文档性能基线：`MuM --bench <文件.md>`
if CommandLine.arguments.contains("--bench") {
    exit(RenderBench.run(arguments: CommandLine.arguments))
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
