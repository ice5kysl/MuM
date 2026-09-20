# 文档索引

**用户文档。** 这个仓库是源码仓库 —— 内部协作记录、审计、复盘不在公开范围。

| 文件 | 回答 |
| :--- | :--- |
| [vision.md](vision.md) | **为什么是这个定位** · 判断标准 · 明确不做 |
| [roadmap.md](roadmap.md) | 版本序列 |
| [known-limits.md](known-limits.md) | 已知边界（不装懂） |
| [design/technical-choices.md](design/technical-choices.md) | 为什么不用 Web 引擎、为什么 SwiftPM |
| [design/interface.md](design/interface.md) | 界面与交互 |
| [development/build.md](development/build.md) | 构建、测试、发布（含签名公证） |
| [development/layout.md](development/layout.md) | 仓库结构 |
| [perf/](perf/) | 性能数字与测量方法 |

另见仓库根：[README](../README.md) · [CHANGELOG](../CHANGELOG.md)

---

## 新增文档时放哪

| 类型 | 去哪 |
| :--- | :--- |
| 定位 / 路线图 | `docs/` 根 |
| 设计（技术选型、界面） | `docs/design/` |
| 工程（构建、仓库结构） | `docs/development/` |
| 性能 | `docs/perf/` |

**根目录的 `*.md` 不超过 2 个**（`README` + `CHANGELOG`）。
**README 不超过 200 行。** 这两条由 `scripts/doc-check.sh` 强制。
