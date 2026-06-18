# Planning & Governance System — Transcriber 2.0 Beta

This folder is the engineering planning and governance system for the native app (`src/native/Transcriber2/`). It was produced from a full review of [PRD.md](../../PRD.md) and the current codebase. **No implementation code was changed to create it.**

## Read order for a new agent
1. [../../PRD.md](../../PRD.md) — the product target.
2. [../../PLAN.md](../../PLAN.md) — phases & sequencing.
3. [../../OBJECTIVE.md](../../OBJECTIVE.md) — the active objective.
4. [../../AGENTS.md](../../AGENTS.md) — the rules + roles.

## Documents
| Document | Purpose |
|---|---|
| [EXECUTIVE_REVIEW.md](EXECUTIVE_REVIEW.md) | What the app is, users, systems, top risks, strategy |
| [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) | Current architecture, strengths & weaknesses |
| [GAP_ANALYSIS.md](GAP_ANALYSIS.md) | PRD-vs-code, every feature rated + hidden work |
| [RISK_REGISTER.md](RISK_REGISTER.md) | Ranked risks (R1–R22) + mitigations + owning objectives |
| [MULTI_AGENT_WORKFLOW.md](MULTI_AGENT_WORKFLOW.md) | Manager→Worker→Auditor→QA→Human operating loop |
| [QA_STRATEGY.md](QA_STRATEGY.md) | Test types, cadence, acceptance mapping |
| [SELF_CRITIQUE.md](SELF_CRITIQUE.md) | Honest critique of this plan + revisions |
| [objectives/](objectives/) | 20 sequential, one-session objectives (OBJ-01…20) |

## Governance docs at repo root
- [PLAN.md](../../PLAN.md), [OBJECTIVE.md](../../OBJECTIVE.md), [AGENTS.md](../../AGENTS.md), [QA.md](../../QA.md), [DECISIONS.md](../../DECISIONS.md)

## Key invariants (see AGENTS.md for the full list)
- Never lose audio or transcripts; persist-then-proceed; surface save failures.
- Active path is `src/native/Transcriber2/` only; never touch the Python app.
- Keep `SWIFT_STRICT_CONCURRENCY = complete`; both builds green every objective.
- Refactor over rewrite; many small reversible changes; ask before deleting files/assets.
- Real-device behaviors are Human-Reviewer-owned gates.
