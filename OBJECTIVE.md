# OBJECTIVE.md — Active Work Pointer

_This file holds the **single active objective** the Worker is currently implementing. The Manager sets it from the roadmap and advances it only when the current objective is gated `PROCEED`. Full details for every objective live in [docs/planning/objectives/](docs/planning/objectives/)._

## ▶ Active objective: **OBJ-04 — Default Preload, Status Refresh & Verify-Before-Process**

Read the full spec: [docs/planning/objectives/OBJECTIVE-04.md](docs/planning/objectives/OBJECTIVE-04.md).

**One-line mission:** Make model readiness self-correcting and pre-flighted: default-model preload, status refresh on launch/Settings open, and verify-before-process with safe fallback plus notice.

**Before starting, read:** [PRD.md](PRD.md) → [PLAN.md](PLAN.md) → this file → [AGENTS.md](AGENTS.md).

---

## Roadmap (sequential — do not skip dependencies)

| # | Objective | Phase | Status |
|---|---|---|---|
| 01 | [Governance, green baseline & data-safety guardrails](docs/planning/objectives/OBJECTIVE-01.md) | 0 | Done — PROCEED 2026-06-18 |
| 02 | [File-based model readiness](docs/planning/objectives/OBJECTIVE-02.md) | 1 | Done — PROCEED 2026-06-18 |
| 03 | [Model lifecycle states + Repair/Redownload](docs/planning/objectives/OBJECTIVE-03.md) | 1 | Done — PROCEED 2026-06-18 |
| 04 | [Default preload + status refresh + verify-before-process](docs/planning/objectives/OBJECTIVE-04.md) | 1 | ▶ Active |
| 05 | [Microphone abstraction & selection backend](docs/planning/objectives/OBJECTIVE-05.md) | 2 | Pending |
| 06 | [Test Mic + live input meter](docs/planning/objectives/OBJECTIVE-06.md) | 2 | Pending |
| 07 | [Mic fallback + active-mic display + notice](docs/planning/objectives/OBJECTIVE-07.md) | 2 | Pending |
| 08 | [Background/lock & 30-min reliability (device gate)](docs/planning/objectives/OBJECTIVE-08.md) | 2 | Pending |
| 09 | [Library status badges + canonical `RecordingStatus`](docs/planning/objectives/OBJECTIVE-09.md) | 3 | Pending |
| 10 | [Dashboard tab](docs/planning/objectives/OBJECTIVE-10.md) | 3 | Pending |
| 11 | [Model Lab as top-level tab + diagnostics columns](docs/planning/objectives/OBJECTIVE-11.md) | 3 | Pending |
| 12 | [Segment-level speaker reassignment](docs/planning/objectives/OBJECTIVE-12.md) | 4 | Pending |
| 13 | [Consistent speaker-label states + edit parity](docs/planning/objectives/OBJECTIVE-13.md) | 4 | Pending |
| 14 | [Phase-timeline progress UI](docs/planning/objectives/OBJECTIVE-14.md) | 5 | Pending |
| 15 | [Diagnostics on normal screens + data model](docs/planning/objectives/OBJECTIVE-15.md) | 5 | Pending |
| 16 | [Export hardening](docs/planning/objectives/OBJECTIVE-16.md) | 6 | Pending |
| 17 | [Accessibility pass](docs/planning/objectives/OBJECTIVE-17.md) | 6 | Pending |
| 18 | [Mac companion parity](docs/planning/objectives/OBJECTIVE-18.md) | 7 | Pending |
| 19 | [Cancellation & failure-injection hardening](docs/planning/objectives/OBJECTIVE-19.md) | 7 | Pending |
| 20 | [Beta acceptance + decomposition + tech debt](docs/planning/objectives/OBJECTIVE-20.md) | 8 | Pending |

> **Sequencing reminders:** `RecordingStatus` (OBJ-09) lands before the Dashboard (OBJ-10) consumes it; the model registry (OBJ-03) lands before OBJ-04 and before OBJ-11's Model Lab columns; the migration policy (OBJ-01) precedes any `Recording` schema change (OBJ-09 if stored, OBJ-12, OBJ-15). The Manager may reorder within a phase only with Human approval and only when dependencies are satisfied.

## How the Manager advances this file
When the active objective is gated `PROCEED`: mark it done in the table, link its completion report, update [PLAN.md](PLAN.md), then set the next objective as ▶ Active and restate its mission here. Never advance while the current objective is `FIX FIRST` / `ASK USER` / `BLOCKED`. See [docs/planning/MULTI_AGENT_WORKFLOW.md](docs/planning/MULTI_AGENT_WORKFLOW.md).
