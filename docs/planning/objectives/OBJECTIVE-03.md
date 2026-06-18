# OBJECTIVE-03 — Model Lifecycle States + Repair/Redownload

_Phase 1. Depends on OBJ-02. Closes PRD §12 (F3, F5, F8) and RISK R10._

## Mission
Introduce the full PRD model-state set behind a small **model registry**, and expose Repair/Redownload plus model storage status in Settings so a missing/corrupt model is recoverable.

## Scope
- A `ModelRegistry` (or equivalent) describing each model: id, provider, display name, plain-language speed/accuracy hints, approximate size, on-disk location, and a `ModelStatus` of `notDownloaded / downloading / downloaded / verifying / ready / missingOrCorrupt / failed`.
- Derive status from OBJ-02's file check + downloader state + a cheap verify step.
- Settings: per-model status row + "Download / Repair / Redownload" affordances and a storage-status summary (sizes where available; static size table acceptable if frameworks don't expose sizes).
- Unit tests for status derivation and state transitions.

## Out of Scope
- Launch/Settings auto-refresh + verify-before-process (OBJ-04).
- Model Lab columns (OBJ-11).
- Cache cleanup / storage management beyond status display (future).

## Worker Instructions
1. Build the registry as a thin descriptor layer over the existing `FinalTranscriptionModelChoice` / `WhisperModelChoice` — do not duplicate or replace them; map to them.
2. Implement `status(for:)` combining file presence (OBJ-02), active download state, and a verify hook (verify may be a no-op placeholder returning `.ready` when files complete, filled in OBJ-04).
3. Wire Settings to show status and offer Repair (delete partial/corrupt files → redownload) and Redownload. Repair must **never** touch recordings/transcripts — only model cache.
4. Keep copy calm and plain-language (per PRD §16, AGENTS §0).

## Auditor Checklist
- [ ] Registry maps to existing choice types (no parallel source of truth for selection).
- [ ] Repair/Redownload only deletes model-cache files, never user data — verify the delete path.
- [ ] All seven states representable and reachable.
- [ ] No dependency bump; strict concurrency intact; builds green.

## QA Checklist
- [ ] Status renders correctly for downloaded/not-downloaded models.
- [ ] Failure injection: corrupt/remove a model's files → status shows missing/corrupt → Repair restores.
- [ ] Repair on a model leaves recordings/transcripts untouched (verify Library intact).
- [ ] Regression: selecting/downloading models still works.

## Acceptance Criteria
- Seven-state model status visible in Settings.
- Repair/Redownload present and functional (cache-only).
- Size/status shown where available.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + registry/status tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Device persistence/corruption realism is re-validated in OBJ-20.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if states + Repair/Redownload land with data safety proven.
- **ASK USER** if model sizes aren't programmatically available (approve a static size table).
- **FIX FIRST** if Repair could touch user recordings.

## Rollback Considerations
Registry is additive; Settings rows revertible. No `Recording` schema change. Revert removes states/Repair UI without affecting downloads already on disk.
