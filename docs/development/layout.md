# 仓库结构

```
MuM/
├── README.md              入口（你在这里）
├── CHANGELOG.md           每个版本改了什么、为什么原来不对
├── LICENSE  VERSION       MIT；版本号唯一来源
├── Package.swift          构建定义（SwiftPM，没有 .xcodeproj）
│
├── docs/                  所有文档
│   ├── vision.md              定位与判断标准 ← 先读这个
│   ├── roadmap.md             版本序列（已完成的有 ✅ 标记）
│   ├── metrics.md             指标体系（北极星 TTFR）
│   ├── status.md              现在到哪一步了 ← 想知道进展只看这个
│   ├── collaboration.md       三方协作规则 · 文件所有权 · 收尾规范
│   ├── known-limits.md        已知边界（不装懂）
│   ├── design/                技术选型 · 界面与交互
│   ├── development/           构建与发布 · 本文件
│   ├── perf/                  实测数字 · 怎么量的
│   ├── qa/                    测试与审计（cc 维护）+ 真人试用观察表
│   ├── retro/                 阶段性复盘
│   └── versions/              版本定义（做什么 / 明确不做 / 验收标准 / 风险）
│
├── Sources/MuM/           源码（54 个文件，约 1.4 万行）
│   ├── App/                   生命周期、菜单
│   ├── Core/                  文件树、工作区、设置、计时、解码
│   ├── Markdown/              解析与渲染（含阅读主题色板）
│   ├── UI/                    窗口、三个面板、设置界面、关于窗口
│   └── Debug/                 自检、离屏快照、headless CLI、性能基线、UITest
│
├── Tests/MuMTests/        单元测试（`swift test`，76 个）
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
| 定位 / 路线图 / 指标 / 状态 / 协作 | `docs/` 根（**只有这五类**） |
| 版本定义 | `docs/versions/` |
| 设计 / 工程 / 性能 / 测试 / 复盘 | `docs/design/` `development/` `perf/` `qa/` `retro/` |
| 可执行工具 | `scripts/` |
| 源码 | `Sources/MuM/<层>/` |
| 测试 | `Tests/MuMTests/` |
| 站点 | `site/` |

**三条可检验的约束：**

1. **根目录的 `*.md` 不超过 2 个**（README + CHANGELOG）
2. **README 不超过 200 行**
3. **不留可重建的文件**（大样本用 `scripts/make-bench-fixture.py` 生成）
