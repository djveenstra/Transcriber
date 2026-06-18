# Self-Critique — of this planning system

_An honest review of the plan in this folder, with revisions already folded into [PLAN.md](../../PLAN.md) and the objectives where noted. The point is to catch where Codex (or a future agent) could be misled, over-build, or sequence things wrongly._

## 1. Over-engineering risks

- **A 4-role workflow for a one-person beta.** Manager/Worker/Auditor/QA/Human is heavyweight for a solo developer. _Mitigation:_ the roles are responsibilities, not necessarily separate sessions. For small objectives the same agent may wear several hats sequentially, but the **gates and reports still get written**. The value is the discipline (validate-before-done, audit-before-QA), not ceremony.
- **A model registry + status enum + diagnostics model could become a framework.** _Mitigation:_ each is introduced minimally inside the objective that first needs it (OBJ-03, OBJ-09, OBJ-15), deriving from existing fields first. Objectives explicitly forbid speculative generality.
- **Twenty objectives may over-formalize work that's partly polish.** _Mitigation:_ accessibility (OBJ-17), Mac parity (OBJ-18), and tech-debt (part of OBJ-20) are deliberately late and small; they can be compressed or dropped by the Human Reviewer without disturbing earlier dependencies.

## 2. Unnecessary complexity

- **The phase-timeline progress UI (OBJ-14)** risks gold-plating. The PRD wants "not a vague spinner," not a flight-control panel. _Revision:_ OBJ-14 scope is capped at named phase + elapsed + %/activity + cancel/retry/details affordance — no animation/timeline-scrubbing.
- **Diagnostics everywhere (OBJ-15)** could clutter calm screens. _Revision:_ normal screens show a compact, collapsible diagnostics row; full detail stays in Model Lab, per PRD §13.

## 3. Missing milestones / gaps in the plan

- **No explicit onboarding/permissions objective.** Mic + (future) notification permissions and first-run model preload are spread across OBJ-04/05/07. _Accepted_ as intentional (PRD wants "no heavy onboarding"), but the Manager should watch that first-run UX doesn't fall through the cracks; flagged in OBJ-04 notes.
- **No SwiftData migration objective of its own.** Migration is a _policy_ in OBJ-01 and applied per change. _Risk:_ if `Recording` changes in OBJ-09 (only if `RecordingStatus` is stored rather than derived) and OBJ-12 both, two migrations stack. _Revision:_ OBJ-09 and OBJ-12 each must state their migration step and reference the OBJ-01 policy; the Manager batches schema changes where possible.
- **Battery/thermal** has no dedicated objective. _Accepted:_ it's a measurement concern folded into device gates (OBJ-08/20). Surfacing it as its own objective would be premature without data.
- **Localization** beyond a language _setting_ (OBJ-20) is out of scope per PRD (English-first). Correct to exclude.

## 4. Incorrect or fragile sequencing

- **Dashboard before the status model — RESOLVED by renumbering.** Originally Dashboard (then OBJ-09) preceded `RecordingStatus` (then OBJ-11), which would have forced rework. Phase 3 is now renumbered so the foundation comes first: **OBJ-09 = Library status badges + canonical `RecordingStatus`**, **OBJ-10 = Dashboard** (consumes OBJ-09), **OBJ-11 = Model Lab tab**. File order now equals dependency order, so no "introduce the enum in the Dashboard objective" workaround is needed.
- **Model Lab tab (OBJ-11) adding load-time/size columns** depends on the model registry (OBJ-03, Phase 1) and is sequenced last in Phase 3 so the final tab order is settled in one place. The dependency is called out in OBJ-11.
- **Microphone fallback (OBJ-07) before background hardening (OBJ-08)** is correct — fallback logic is needed before long/background runs are meaningful.

## 5. Hidden assumptions

- **That the project currently builds green.** Not yet verified by an agent. _Revision:_ OBJ-01's first task is to _establish_ the green baseline; if it isn't green, OBJ-01 becomes "get to green" before anything else, and the Manager escalates.
- **That scheme/destination names are stable** (`Transcriber`, macOS, iOS Simulator). If Xcode project names differ, baseline commands fail. _Revision:_ OBJ-01 verifies and, if needed, corrects the documented commands in PLAN.md.
- **That FluidAudio/WhisperKit revisions stay reachable.** Pinned-by-revision deps can vanish or change. _Mitigation:_ dependency integrity is part of OBJ-01's baseline check; bumps are isolated (AGENTS §2.9).
- **That the Human Reviewer can run device tests on demand.** Device gates assume iPhone 17 Pro access. If unavailable, those objectives end at `ASK USER` and the beta acceptance (OBJ-20) cannot be fully closed — the plan states this rather than pretending otherwise.
- **That "Record" tab vs "Dashboard" is a real gap, not a rename.** The PRD clearly specifies a distinct Dashboard _plus_ recording entry points. Treated as a new screen (OBJ-10), with the existing RecordingView retained as the recording surface reachable from Dashboard. The Manager should confirm with the Human whether Record stays a tab or becomes a Dashboard action.

## 6. Implementation risks specific to agents (where Codex may misunderstand intent)

- **Editing the wrong tree.** Three iOS-ish folders exist. _Mitigation:_ AGENTS §2.3 "active path only"; Auditor checks touched paths; RISK R20.
- **"Fixing" deliberate code.** The 1-second post-unload sleeps, the inference semaphore, and the share-sheet scene-phase workaround are intentional and commented. An agent may "optimize" them away. _Mitigation:_ objectives that touch the pipeline explicitly list these as **do-not-remove without measurement**, echoing the in-code comments.
- **Weakening strict concurrency to compile.** Tempting and forbidden (AGENTS §2.2). The Auditor checks the setting every objective.
- **Claiming device behavior as done.** An agent cannot test background recording. _Mitigation:_ Human-owned gates are explicit in every relevant objective's Gate Decision (`ASK USER`).
- **Silent scope creep during refactors** (esp. OBJ-20 decomposition). _Mitigation:_ behavior-preserving extraction only; tests must pass unchanged; Auditor diff review.
- **Over-trusting recalled memory / stale docs.** Agents must verify a symbol still exists before relying on it; this plan references real files as of 2026-06-18 but code moves.

## 7. Things I would change with more information

- I assumed model **sizes** (for the picker/Settings) can be derived from the registries; if WhisperKit/FluidAudio don't expose sizes cleanly, OBJ-03 may need a static size table (acceptable, but note it).
- I assumed **loadability checks** are cheap enough to run at launch/Settings-open. If a load is expensive, OBJ-02/04 should use a lightweight file-manifest check at launch and defer full load to verify-before-process.
- The split between OBJ-13 (state surfacing) and OBJ-12 (reassignment) is slightly artificial; if they prove small, the Manager may merge them — but only with Human approval, since combining unrelated-enough systems is what the workflow tries to avoid.

## Net assessment

The plan is **conservative and dependency-honest**: it stabilizes Critical risks (data safety, model persistence, recording reliability) before adding PRD surface area, and it refuses to let agents claim device behavior or widen scope. The main residual danger is **ceremony cost** for a solo developer — addressed by letting one agent perform multiple roles while still producing the gate artifacts. If anything, future revisions should _shrink_ objectives further rather than add new systems.
