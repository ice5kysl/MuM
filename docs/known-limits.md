# 已知边界

> 从 README 拆出（它 595 行太长了）。内容一字未改。


- 数学公式（KaTeX）与 Mermaid 尚未支持 —— 这两样是原生渲染路线上代价最高的部分
- 三种模式之间没有过渡动画（朴素 NSSplitView 的取舍）
- 未做 `.gitignore` 感知，文件树用的是固定噪音目录黑名单
- 单窗口单文件，没有标签页；这是刻意的取舍，但多标签对某些工作流确实更方便
- **访达「服务」里那一项的文案跟随系统语言，不跟随 app 内的语言开关**（「系统」/中文/English）。
  系统在注册服务时读 `Info.plist`，而且**只查 `<lang>.lproj/ServicesMenu.strings`** ——
  既不是 `Localizable.strings` 也不是 `InfoPlist.strings`（0.8.2 放错了文件，0.8.3 才修对），
  拿不到运行期的语言覆盖 —— 这是 Services 机制的边界，不是漏做
- **「零上报」从 0.8.4 起不再严格成立**：MuM 每天发一次匿名使用计数（只带日期与版本号，
  无标识、不可追踪、跨不了天），用来回答"到底有没有人在用"。可在「设置 → 隐私」关掉，
  关掉即永不发送。对外口径写在 README 的 Privacy 一节

`Examples/demo/` 是一个用于验证渲染的示例项目，`docs/rendering.md` 覆盖了
所有受支持的 Markdown 元素。
