# PLAN.md — Transcriber 2.0 Beta Engineering Plan

_Read alongside [PRD.md](PRD.md), [AGENTS.md](AGENTS.md), and the active [OBJECTIVE.md](OBJECTIVE.md). Supporting analysis lives in [docs/planning/](docs/planning/). This plan is owned by the Manager and revised only with Human Reviewer approval._

## How to read this plan

- The product target is [PRD.md](PRD.md). The current code is reviewed in [docs/planning/ARCHITECTURE_REVIEW.md](docs/planning/ARCHITECTURE_REVIEW.md); the delta is in [docs/planning/GAP_ANALYSIS.md](docs/planning/GAP_ANALYSIS.md).
- Work is delivered as **20 sequential objectives** (`docs/planning/objectives/OBJECTIVE-01.md` … `-20.md`), each ≈ one implementation session, each independently completable, building, and green.
- **Active path:** the only app under development is `src/native/Transcriber2/`. Never modify `src/python/` (independent), and treat `src/legacy-ios/` and `XCode App Build/` as read-only reference.
- **Sequencing is dependency-driven.** Foundations (status model, model registry, microphone abstraction, diagnostics model) precede the UI that consumes them. Critical-risk work precedes new surface area.

## Guiding constraints (non-negotiable)

1. Never lose audio or transcripts. Persist-then-proceed; surface save failures.
2. Keep `SWIFT_STRICT_CONCURRENCY = complete`; both iOS-simulator and macOS builds stay green.
3. Favor refactors over rewrites; many small reversible changes over big ones.
4. Real-device behaviors (background recording, model persistence across reboot, 30-min reliability, performance, battery, offline) are **Human-Reviewer-owned gates**, validated on iPhone 17 Pro.
5. Don't bump WhisperKit/FluidAudio inside a feature objective.

## Standard milestone template

Every objective documents: **Purpose · Technical goals · Affected systems · Dependencies · Implementation tasks · Validation steps · Definition of Done · Implementation risk · Rollback considerations**, plus the multi-agent **Worker/Auditor/QA/Gate** sections (see [AGENTS.md](AGENTS.md) and [docs/planning/MULTI_AGENT_WORKFLOW.md](docs/planning/MULTI_AGENT_WORKFLOW.md)).

## Baseline validation (run for every objective)

```sh
# From repo root. Adjust scheme/destination names only if the project changes.
xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild test -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TranscriberTests
```

On-device acceptance (Human Reviewer, iPhone 17 Pro) covers: real mic capture, background/lock recording, model download/persistence across reboot, 30-min reliability, performance, battery, offline.

---

## Phase 0 — Governance & baseline (foundation)

**Purpose:** Make change safe before making change. Establish the planning system, a known-green build/test baseline, repo-hygiene conventions, and a SwiftData migration policy.

- **OBJ-01 — Governance, green baseline & data-safety guardrails.** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-01--governance-green-baseline--data-safety-guardrails--2026-06-18).** Confirm both builds + tests green; document the active-path rule; write the SwiftData schema/migration policy; add round-trip/corruption tests for `Recording` blob accessors; inventory the stale `XCode App Build/` tree and propose (don't execute) archiving.

**DoD:** baseline commands pass; migration policy in [DECISIONS.md](DECISIONS.md); guardrail tests added; no behavior change.
**Risk:** Low. **Rollback:** revert added tests/docs.

## Phase 1 — Data safety & model persistence (Critical risks R2, R3, R10)

**Purpose:** Make model readiness honest and downloads recoverable — the highest-risk PRD §12 gap.

- **OBJ-02 — File-based model readiness.** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-02--file-based-model-readiness--2026-06-18).** Unified Whisper + Parakeet readiness on actual on-device files; replaced the in-memory Whisper flag as source of truth.
- **OBJ-03 — Model lifecycle states + Repair/Redownload.** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-03--model-lifecycle-states--repairredownload--2026-06-18).** Introduced the full lifecycle state set backed by a model registry; exposed cache-only Repair/Redownload plus storage status in Settings.
- **OBJ-04 — Default preload + status refresh + verify-before-process.** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-04--default-preload-status-refresh--verify-before-process--2026-06-18).** Added non-blocking default preload scheduling, launch/Settings model-status refresh, and verify-before-process with safe fallback plus user-facing notice. Human-owned real-device preload/persistence/offline/corruption checks are deferred to OBJ-04/OBJ-20 gates.

**Affected systems:** model management, Settings, `TranscriptionSession` pre-flight. **Dependencies:** OBJ-01; model registry introduced in OBJ-03.
**Risk:** Medium (touches download/load paths). **Rollback:** registry/readiness are additive; revert restores prior behavior.

## Phase 2 — Recording reliability & microphone (Critical/High R4, R5, R11)

**Purpose:** Close the entire PRD §8 microphone gap and harden long/background recording.

- **OBJ-05 — Microphone abstraction & selection backend.** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-05--microphone-abstraction--selection-backend--2026-06-18).** Added platform input discovery, automatic/built-in/Bluetooth/named microphone choices, UserDefaults selection persistence, guarded recorder routing through selected iOS inputs, and fallback-to-default backend behavior. Human-owned real-device microphone enumeration and hardware routing checks are deferred to OBJ-05/OBJ-08/OBJ-20 gates.
- **OBJ-06 — Test Mic + live input meter (Settings).** **DONE 2026-06-18 — Gate: PROCEED; evidence: [QA.md](QA.md#obj-06--test-mic--live-input-meter--2026-06-18).** Added Settings Test Mic control with selected-input label, metering-only capture, live RMS meter, clean stop-on-exit/input-change behavior, and no recording persistence. Human-owned real iPhone mic-level validation is deferred to OBJ-06/OBJ-08/OBJ-20 gates.
- **OBJ-07 — Mic fallback + active-mic display + notice.** Fall back to best input when selection unavailable; show active mic during recording; notify on fallback.
- **OBJ-08 — Background/lock & 30-min reliability hardening (Human-owned gate).** Handle interruptions/route changes; document and run the 5/15/30-min and background/lock device scripts.

**Risk:** Medium–High (audio session). **Rollback:** selection defaults to current behavior (default input) if disabled.

## Phase 3 — Information architecture (PRD §6; R14)

**Purpose:** Bring navigation in line with the PRD and surface the status model. The canonical status model is built **first** (OBJ-09), then the Dashboard consumes it (OBJ-10), then Model Lab is promoted (OBJ-11) on top of the model registry/status foundations.

- **OBJ-09 — Library status badges + canonical `RecordingStatus`.** Replace scattered booleans with one status enum; show duration, status badge, final model used, speaker-label status; add orphan reconciliation. **Foundation for OBJ-10/OBJ-11.**
- **OBJ-10 — Dashboard tab.** Home screen: mic status, model readiness, diarization status, recent-attention list, Record/Import/Model Lab actions, missing-model warnings. **Depends on OBJ-09's `RecordingStatus`.**
- **OBJ-11 — Model Lab as top-level tab + diagnostics columns.** Promote Model Lab to a tab; add model load-time + size/status columns. **Depends on OBJ-03's model registry; runs after OBJ-10 so tab order is settled once.**

**Risk:** Medium (UI + model). **Rollback:** status enum is additive (derive from existing flags first); tabs revertible.

## Phase 4 — Speaker workflow completeness (PRD §10/§11; R15)

- **OBJ-12 — Segment-level speaker reassignment.** Reassign a transcript segment to another speaker; persist via migration-safe storage; update exports.
- **OBJ-13 — Consistent speaker-label states + rename/reassign parity.** Surface approximate/failed/canceled/retryable consistently across Record, Library detail, Shared detail, Dashboard.

**Risk:** Medium. **Rollback:** reassignment additive; states derive from existing flags.

## Phase 5 — Progress & diagnostics (PRD §13; R8, R17)

- **OBJ-14 — Phase-timeline progress UI.** Structured phase model (Saving/Preparing/Transcribing/Saving transcript/Identifying speakers/Saving labels/Exporting) with elapsed time, %/activity, cancel, retry, details.
- **OBJ-15 — Diagnostics on normal screens + diagnostics data model.** Thread load time / processing time / RTF / fallback / speaker status through the session; show calmly on detail screens; reuse in Model Lab.

**Risk:** Medium. **Rollback:** diagnostics additive/read-only.

## Phase 6 — Export & accessibility (PRD §11/§15; R16, R19)

- **OBJ-16 — Export hardening.** JSON via `Codable`; verify speaker names in all formats; SRT timing tests; large/odd-format import checks.
- **OBJ-17 — Accessibility pass.** Dynamic Type, VoiceOver labels/traits (incl. transcript cards + status dots), contrast audit, non-color status/speaker indicators, reachability.

**Risk:** Low–Medium. **Rollback:** mostly additive/cosmetic.

## Phase 7 — Mac parity & hardening (PRD §4/§17; R6, R7, R9)

- **OBJ-18 — Mac companion parity.** Open/import/play/share verified; Model Lab on Mac where feasible; document intentional iPhone-first gaps.
- **OBJ-19 — Cancellation & failure-injection hardening.** Full cancel matrix + forced model/mic/diarization failures; stress interleavings; verify model unload + UI recovery + data safety.

**Risk:** Medium. **Rollback:** test-led; behavior fixes isolated.

## Phase 8 — Acceptance & tech-debt

- **OBJ-20 — Beta acceptance pass + `TranscriptionSession` decomposition + small tech debt.** Run the full PRD §17 acceptance matrix (Human-owned device portions); extract persistence + model-selection coordinators without behavior change; add a language setting (default English); fix flagged speaker-color parsing.

**Risk:** Medium (refactor). **Rollback:** behavior-preserving extraction is revertible objective-by-objective.

---

## Dependency graph (summary)

```
OBJ-01
 ├─ OBJ-02 ─ OBJ-03 ─ OBJ-04            (model persistence)
 ├─ OBJ-05 ─ OBJ-06 ─ OBJ-07 ─ OBJ-08   (microphone + reliability)
 ├─ OBJ-09 (status model) ─ OBJ-10 (Dashboard)
 │                         └ OBJ-11 (Model Lab tab; also needs OBJ-03 registry)
 ├─ OBJ-12 ─ OBJ-13                       (speaker workflow; OBJ-12 needs migration policy from OBJ-01)
 ├─ OBJ-14 ─ OBJ-15                       (progress + diagnostics)
 ├─ OBJ-16, OBJ-17                        (export, accessibility)
 ├─ OBJ-18                                (Mac parity; after IA + diagnostics)
 └─ OBJ-19 ─ OBJ-20                       (hardening + acceptance + tech debt; last)
```

Strict prerequisites: OBJ-09's `RecordingStatus` lands before OBJ-10 (Dashboard); OBJ-03's model registry before OBJ-04 and before OBJ-11's Model Lab columns; OBJ-01's migration policy before any `Recording` schema change (OBJ-09 if stored, OBJ-12, OBJ-15). Otherwise phases may be reordered by the Manager with Human approval if a dependency is satisfied early.

## When this plan changes

The Manager updates PLAN.md when: an objective is completed (mark done, link the completion report), a dependency is discovered, scope is added/removed (Human-approved), or a risk materializes. PLAN.md edits that change scope or sequence require Human Reviewer approval. See [docs/planning/MULTI_AGENT_WORKFLOW.md](docs/planning/MULTI_AGENT_WORKFLOW.md).
