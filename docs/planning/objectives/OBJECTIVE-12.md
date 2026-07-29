# OBJECTIVE-12 — Segment-Level Speaker Reassignment
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 4. Depends on OBJ-01 (migration policy). Closes PRD §10/§11 (D6) — a **beta-required** feature. RISK R15._

## Mission
Let the user reassign an individual transcript segment to a different speaker, persist it durably, and reflect it in exports — completing the beta editing requirement alongside the existing rename.

## Scope
- UI to select a transcript segment and assign it to an existing speaker (or a renamed speaker), in the Library detail transcript.
- Persist the reassignment so it survives relaunch (apply to `Recording.segments` / speaker map per the OBJ-01 migration policy).
- Exports (TXT/SRT/JSON) reflect reassignments.
- Unit tests for the reassignment + persistence + export reflection.

## Out of Scope
- Merge/split speaker identities (production roadmap).
- Free-text transcript editing (explicitly out of beta).
- Consistent state surfacing (OBJ-13).

## Worker Instructions
1. Add a per-card affordance (e.g. long-press/menu) to change a segment's speaker among known speakers.
2. Persist by updating the stored `segments` (the speaker field already exists on `TranscriptSegment`) and saving via the existing `persistChanges` path; if any schema change is needed, follow OBJ-01 migration policy + DECISIONS entry.
3. Ensure `TranscriptExporter`/`displayName` and rename interplay still resolve correctly after reassignment.
4. Keep it reversible in-session where reasonable (re-pick another speaker).

## Auditor Checklist
- [ ] Reassignment persists across relaunch; uses existing persist path (save-failure surfaced).
- [ ] No transcript text mutated — only the speaker attribution.
- [ ] Exports reflect reassignment; rename + reassignment compose correctly.
- [ ] Schema change (if any) migration-safe + documented.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Reassign a segment → UI updates → relaunch → still reassigned.
- [ ] Export TXT/SRT/JSON shows the new speaker (and custom name if set).
- [ ] Save-failure path surfaces the storage alert (failure injection).
- [ ] Regression: rename, share, playback unaffected.

## Acceptance Criteria
- Segment reassignment works, persists, and shows in exports.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + reassignment/export tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if reassignment persists + exports reflect it.
- **ASK USER** if a `Recording` schema change is required (approve migration).
- **FIX FIRST** if reassignment can corrupt or fail to persist silently.

## Rollback Considerations
UI + persistence change to an existing field. Revert removes the affordance; previously reassigned data remains valid (speaker field already part of the model). Any migration must be additive per OBJ-01.

## Completion Report — 2026-06-20

### Worker Summary
- Added a Library-detail-only per-segment ellipsis menu on transcript cards to reassign a saved segment to an existing speaker.
- Persisted reassignment by updating only `TranscriptSegment.speaker` inside `Recording.segments`, then saving the existing SwiftData `ModelContext`.
- Kept transcript text, timing, raw transcription, audio, speaker names, and SwiftData schema unchanged.
- Reused existing display-name/export behavior so speaker rename and reassignment compose: assigning a segment to a renamed speaker exports and displays the renamed speaker name.
- Updated TXT, SRT, and JSON export coverage to prove reassigned speakers appear in existing exports.

### Auditor Alignment
- ALIGNED: touched paths stayed inside `src/native/Transcriber2/` plus planning/QA docs.
- No transcript text editing, speaker merge/split workflow, SwiftData schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, or OBJ-13+ implementation was added.
- The change is reversible as a normal code/doc revert; reassigned data remains valid because `speaker` was already part of each stored transcript segment.

### QA Evidence
- Focused reassignment/export tests: PASS.
- Baseline macOS build: PASS.
- Baseline iOS simulator build: PASS.
- Full `TranscriberTests`: PASS, 107 passed / 107 total.
- `git diff --check`: PASS.
- QA evidence appended in [QA.md](../../../QA.md#obj-12--segment-level-speaker-reassignment--2026-06-20).

### Gate Decision
- Manager recommendation: PROCEED.
- Human/product decision needed: none.
