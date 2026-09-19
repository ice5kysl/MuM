# 文档索引

**从这里进。** 按「给谁看 / 回答什么」分组，不按文件类型分。

## 先看这两份

| 文件 | 回答 |
| :--- | :--- |
| [vision.md](vision.md) | **为什么是这个定位** · 判断标准 · 明确不做 |
| [status.md](status.md) | **现在到哪一步了** ← 想知道进展只看这个 |

## 产品

| 文件 | 内容 |
| :--- | :--- |
| [roadmap.md](roadmap.md) | 版本序列与总原则 |
| [metrics.md](metrics.md) | 指标体系（北极星 TTFR） |
| [versions/](versions/) | 每个版本的定义：做什么 / 明确不做 / 验收标准 / 风险 |
| [known-limits.md](known-limits.md) | 已知边界（不装懂） |

## 设计

| 文件 | 内容 |
| :--- | :--- |
| [design/technical-choices.md](design/technical-choices.md) | 为什么不用 Web 引擎、为什么 SwiftPM… |
| [design/interface.md](design/interface.md) | 界面与交互 |

## 工程

| 文件 | 内容 |
| :--- | :--- |
| [development/build.md](development/build.md) | 构建、测试、发布（含签名公证） |
| [development/layout.md](development/layout.md) | 仓库结构 |

## 性能

| 文件 | 内容 |
| :--- | :--- |
| [perf/baseline.md](perf/baseline.md) | 实测数字 |
| [perf/methodology.md](perf/methodology.md) | **怎么量的**、口径是什么 |

## 测试与审计（cc 维护）

| 文件 | 内容 |
| :--- | :--- |
| [qa/log.md](qa/log.md) | 验收记录流水 |
| [qa/role-metrics.md](qa/role-metrics.md) | QA 角色的指标体系（**注意：不是产品指标**，产品指标在 [metrics.md](metrics.md)） |
| [qa/audit-2026-09-18.md](qa/audit-2026-09-18.md) | 全量代码审计（41 文件 / 高危 4） |
| [qa/unclicked-checklist.md](qa/unclicked-checklist.md) | 未真实点击项清单 |
| [qa/click-runbook.md](qa/click-runbook.md) | 点击验证执行手册 |

## 协作与复盘

| 文件 | 内容 |
| :--- | :--- |
| [collaboration.md](collaboration.md) | 三方协作规则 · 文件所有权 · 收尾规范 |
| [retro/](retro/) | 阶段性复盘 |

---

## 新增文档时放哪

| 类型 | 去哪 |
| :--- | :--- |
| 定位 / 路线图 / 指标 / 状态 / 协作 | `docs/` 根（**只有这五类**） |
| 版本定义 | `docs/versions/` |
| 设计（技术选型、界面） | `docs/design/` |
| 工程（构建、仓库结构） | `docs/development/` |
| 性能 | `docs/perf/` |
| 测试与审计 | `docs/qa/` |
| 复盘 | `docs/retro/` |

**根目录的 `*.md` 不超过 2 个**（`README` + `CHANGELOG`）—— 多出来的说明该进 `docs/`。
**README 不超过 200 行** —— 超了就说明有内容该拆到 `docs/`。
