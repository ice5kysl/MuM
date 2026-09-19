# 构建与运行

> 从 README 拆出（它 595 行太长了）。内容一字未改。


```bash
./scripts/run.sh              # 构建 release 并启动
./scripts/build-app.sh debug  # 只构建，产出 dist/MuM.app
```

只需要 Xcode 命令行工具（Swift 6.0+），不需要打开 Xcode，也没有 `.xcodeproj`
需要维护 —— 整个应用就是 `swift build` 加一个 Info.plist。

### 装到「应用程序」并设为默认编辑器

```bash
./scripts/build-app.sh release
cp -R dist/MuM.app /Applications/        # 建议放这里，见下
```

**为什么要移进 `/Applications`**：macOS 按**路径**记住"这类文件用哪个应用打开"。
留在 `dist/` 里也能设为默认，但仓库一旦被移动或清理，绑定就指向一个不存在的路径了。

`Info.plist` 里声明了三组文档类型，全部用 `LSHandlerRank = Alternate`：

| 类型 | UTI | 角色 |
| :--- | :--- | :--- |
| Markdown / 纯文本 | `net.daringfireball.markdown`、`public.plain-text`、`public.text` | Editor |
| 源代码 | `public.source-code`、`public.json`、`public.yaml` … | Editor |
| 文件夹 | `public.folder` | Viewer |

**为什么不用 `Owner`**：`Owner` 的意思是"这类文件归我"，会去抢系统默认；`Alternate`
只表示"我能打开"。于是 MuM 出现在「打开方式」里，但不主动劫持你已有的选择 ——
这类声明应该是"可选"，不是"夺权"。

同时写了 `LSItemContentTypes`（现代 UTI）和 `CFBundleTypeExtensions`（旧式扩展名）：
只写 UTI 时，某些动态生成的 UTI 不会出现在「打开方式」里，扩展名是兜底。

**设成默认有两种方式**：

1. **MuM 菜单：文件 → 设为默认 Markdown 编辑器**。走
   `NSWorkspace.setDefaultApplication(at:toOpen:)`（macOS 12+）——
   这是唯一公开的、应用能自己调用的方式。已经是默认时该项会打勾并置灰。
2. **访达手动指定**：选中任意 `.md` → 显示简介 → 「打开方式」选 MuM → 点「全部更改」。

只在第 1 种里设了 Markdown 一种。把 `.txt` 和源代码也一并抢过来是越界的 ——
那些类型用户多半已经有别的主力工具，而声明（出现在「打开方式」里）已经够用了。

### 命令行入口：`mum`

```bash
ln -sf /Applications/MuM.app/Contents/Resources/mum /usr/local/bin/mum

mum .            # 把当前目录作为项目打开
mum README.md    # 打开单个文件
```

脚本本体住在 bundle 里（`Contents/Resources/mum`），跟应用同版本发布。
它走 LaunchServices（`open -a`）：应用没在跑就拉起，在跑就把打开事件递给
现有实例 —— 不会出现第二个进程、第二个 Dock 图标。

**为什么在 `Resources` 而不是 `MacOS`**：macOS 默认文件系统大小写不敏感，
`Contents/MacOS/mum` 和主二进制 `Contents/MacOS/MuM` 是同一个文件 ——
放进去会直接覆盖掉应用本体（踩过，勿试）。

验证当前绑定：

```bash
# 系统认为 .md 现在由谁打开
mdls -name kMDItemContentType README.md          # → net.daringfireball.markdown
```

```swift
// 或者用 Swift 查
import AppKit, UniformTypeIdentifiers
let md = UTType("net.daringfireball.markdown")!
NSWorkspace.shared.urlForApplication(toOpen: md)        // 当前的默认应用
NSWorkspace.shared.urlsForApplications(toOpen: md)      // 全部候选，MuM 应在其列
```

### 自检与离屏快照

预览区的正确性体现在 `NSAttributedString` 的属性上，肉眼看截图只能看个大概。
`--selftest` 不启动窗口，直接对渲染结果做 24 项断言：

```bash
.build/release/MuM --selftest                              # 跑断言
.build/release/MuM --selftest Examples/demo/README.md      # 打印结构报告
```

`--snapshot` 把整个窗口离屏渲染成 PNG，不需要屏幕点亮，也不弹窗 ——
锁屏、SSH、CI 里都能检查界面：

```bash
dist/MuM.app/Contents/MacOS/MuM --snapshot /tmp/mum.png
```

注意要用 app bundle 里的二进制：直接跑 `.build/release/MuM` 时没有 bundle id，
读不到已保存的项目列表。

### 关于 `.mumenv`

构建脚本会 `source .mumenv`，它只做一件事：**把 clang / SwiftPM 的模块缓存重定向到 `.build/`**。

必需的理由很硬：clang 默认把模块缓存写到 `$TMPDIR` 下的
`/var/folders/.../C/clang/ModuleCache`，而受限沙箱不让写那里，构建会直接失败：

```
error: unable to open output file '.../ModuleCache/.../SwiftShims-....pcm'
       'Operation not permitted'
```

它**不重定向 `HOME`**，这是踩过三次坑之后才定下来的。早先有一行
`export HOME="$PWD/.build/home"`，看起来无害，实际会让所有读 `~/.gitconfig`、
`~/.config/gh`、`~/Library/Preferences` 的命令找不到配置：

| 症状 | 真实原因 |
| :--- | :--- |
| `git commit` 报 "Author identity unknown" | git 去 `.build/home` 找 `.gitconfig` |
| `gh` 报 "please run gh auth login" | gh 去 `.build/home` 找配置 |
| 离屏快照读不到已保存的项目列表 | `UserDefaults` 指向了另一个 HOME |

**三个症状和"HOME 被改"看起来都毫无关系** —— 这正是它值得单独记一笔的原因。

另外支持一个可选的 GitHub 代理（用 `GIT_CONFIG_COUNT` 注入，不改用户的 `~/.gitconfig`），
地址写在 `.mumenv.local`（已 gitignore），不硬编码进版本库。


---
