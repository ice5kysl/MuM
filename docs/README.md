# 文档索引

**从这里进。** 15 份文档按"给谁看"分组，不按文件类型分组。

## 核心（扁平放，因为任何时候都该先看）

| 文件 | 回答 |
| :--- | :--- |
| [vision.md](vision.md) | **为什么是这个定位** · 判断标准 · 明确不做 |
| [roadmap.md](roadmap.md) | 0.5 → 1.0 的版本计划 |
| [metrics.md](metrics.md) | 指标体系（北极星 TTFR） |
| [status.md](status.md) | **现在到哪一步了** ← 想知道进展看这个 |
| [collaboration.md](collaboration.md) | 三方协作规则 · 文件所有权 · 收尾规范 |

## versions/ — 每个版本的定义

[0.4](versions/v0.4.md) · [0.4.1](versions/v0.4.1.md) · [0.5](versions/v0.5.md)

**规矩**：定义写清"做了什么 / 明确不做 / 验收标准 / 风险"，确认后才实现。

## qa/ — 测试与审计（cc 维护）

| 文件 | 内容 |
| :--- | :--- |
| [log.md](qa/log.md) | 验收记录流水 |
| [metrics.md](qa/metrics.md) | QA 角色的指标体系 |
| [audit-2026-09-18.md](qa/audit-2026-09-18.md) | 全量代码审计（41 文件 / 高危 4） |
| [unclicked-checklist.md](qa/unclicked-checklist.md) | 未真实点击项清单 |
| [click-runbook.md](qa/click-runbook.md) | 点击验证执行手册 |

## perf/ · retro/

- [perf/baseline.md](perf/baseline.md) —— 性能基线与测量方法
- [retro/2026-09-18.md](retro/2026-09-18.md) —— 阶段性复盘

---

## 新增文档时放哪

| 类型 | 去哪 |
| :--- | :--- |
| 定位 / 路线图 / 指标 / 状态 / 协作 | `docs/` 根（**只有这五类**） |
| 版本定义 | `docs/versions/` |
| 测试与审计 | `docs/qa/` |
| 性能 | `docs/perf/` |
| 复盘 | `docs/retro/` |

**根目录的 `*.md` 不超过 2 个**（`README` + `CHANGELOG`）—— 多出来的说明该进 `docs/`。
