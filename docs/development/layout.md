# 目录结构

> 从 README 拆出（它 595 行太长了）。内容一字未改。


```
MuM/
├── README.md              入口（你在这里）
├── CHANGELOG.md           每个版本改了什么、为什么原来不对
├── LICENSE  VERSION       MIT；版本号唯一来源
├── Package.swift          构建定义（没有 .xcodeproj）
│
├── docs/                  所有文档
│   ├── vision.md              定位与判断标准 ← 先读这个
│   ├── roadmap.md             版本计划与验收标准
│   ├── metrics.md             指标体系（北极星：TTFR）
│   ├── collaboration.md       三方协作规则
│   ├── versions/              版本定义，每版一个文件
│   ├── performance-baseline.md
│   └── qa-log.md
│
├── Sources/MuM/           源码
│   ├── App/                   生命周期、菜单
│   ├── Core/                  文件树、工作区、设置、计时
│   ├── Markdown/              解析与渲染（含阅读主题色板）
│   ├── UI/                    窗口、三个面板、设置界面
│   └── Debug/                 自检、离屏快照、性能基线
│
├── Tests/MuMTests/        单元测试（`swift test`）
├── scripts/               构建、图标、样本生成
├── Examples/demo/         示例项目（用 MuM 打开它）
└── Resources/Info.plist   打包资源
```

### 文件放哪：一条规则

> **根目录只放"进门必看的"。其余按用途进各自的目录。**

| 类型 | 去哪 | 例子 |
| :--- | :--- | :--- |
| 门面与约定 | 根目录 | `README.md`、`CHANGELOG.md`、`LICENSE`、`VERSION` |
| 项目文档 | `docs/` | 定位、路线图、指标、协作规范 |
| 版本定义 | `docs/versions/` | `v0.4.md` |
| 可执行工具 | `scripts/` | 构建、图标生成、样本生成 |
| 源码 | `Sources/MuM/<层>/` | 按 App / Core / Markdown / UI / Debug 分层 |
| 测试 | `Tests/MuMTests/` | |
| 示例内容 | `Examples/demo/` | 被 MuM 打开的样本项目 |

**三条约束：**

1. **根目录的 `*.md` 不超过 2 个**（README + CHANGELOG）。多出来的说明该进 `docs/`。
2. **不留可重建的文件** —— 大样本、生成物用脚本产出（见 `scripts/make-bench-fixture.py`）。
3. **不留临时产物** —— `/tmp` 里的测完就删；进程用完就关（见 `docs/collaboration.md`）。

**新增文档时先问：** 它是"进门必看"吗？不是就进 `docs/`。文档变多时按**读者**分目录，
不按文件类型分。
