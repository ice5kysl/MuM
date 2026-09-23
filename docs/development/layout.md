# 仓库结构

```
MuM/
├── README.md              入口（你在这里）
├── README_EN.md           同一份说明的英文版
├── CHANGELOG.md           每个版本改了什么、为什么原来不对
├── LICENSE  VERSION       MIT；版本号唯一来源
├── Package.swift          构建定义（SwiftPM，没有 .xcodeproj）
│
├── docs/                  文档（用户文档；内部协作 / 审计 / 复盘不在公开范围）
│   ├── README.md              文档索引
│   ├── vision.md              定位与判断标准 ← 先读这个
│   ├── roadmap.md             版本序列（已完成的有 ✅ 标记）
│   ├── known-limits.md        已知边界（不装懂）
│   ├── design/                技术选型 · 界面与交互
│   ├── development/           构建与发布 · 本文件
│   ├── perf/                  实测数字 · 怎么量的
│   └── images/                文档配图
│
├── Sources/MuM/           源码（57 个文件，约 1.5 万行）
│   ├── App/                   生命周期、菜单
│   ├── Core/                  文件树、工作区、设置、计时、解码
│   ├── Markdown/              解析与渲染（含阅读主题色板）
│   ├── UI/                    窗口、三个面板、设置界面、关于窗口
│   └── Debug/                 自检、离屏快照、headless CLI、性能基线、UITest
│
├── Tests/MuMTests/        单元测试（`swift test`，106 个）
├── scripts/               构建 · 图标 · 验收 · TTFR 测量 · 样本生成
├── site/                  落地页（mum.jiker.ai，GitHub Pages）
├── Examples/demo/         示例项目（用 MuM 打开它）
└── Resources/Info.plist   打包资源
```

## 文件放哪：一条规则

> **根目录只放"进门必看的"。其余按用途进各自的目录。**

| 类型 | 去哪 |
| :--- | :--- |
| 门面与约定 | 根目录（`README` · `CHANGELOG` · `LICENSE` · `VERSION`） |
| 定位 / 路线图 / 已知边界 | `docs/` 根 |
| 版本定义 | 版本序列写进 `docs/roadmap.md`（不预先编未来的功能清单） |
| 设计 / 工程 / 性能 | `docs/design/` `development/` `perf/` |
| 可执行工具 | `scripts/` |
| 源码 | `Sources/MuM/<层>/` |
| 测试 | `Tests/MuMTests/` |
| 站点 | `site/` |

**三条可检验的约束：**

1. **根目录的 `*.md` 不超过 3 个**（`README.md` + `README_EN.md` + `CHANGELOG.md`）
2. **两个 README 各不超过 200 行**
3. **不留可重建的文件**（大样本用 `scripts/make-bench-fixture.py` 生成）
