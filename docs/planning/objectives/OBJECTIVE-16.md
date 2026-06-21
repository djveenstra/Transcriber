# OBJECTIVE-16 — Export Hardening

_Phase 6. Depends on OBJ-12 (reassignment in exports). Closes PRD §11 export (E3, E4) robustness. RISK R19._

## Mission
Make exports type-safe and provably correct: JSON via `Codable`, speaker names verified across all formats, SRT timing validated, and large/odd-format import sanity checked.

## Scope
- Replace `JSONSerialization`/`[String: Any]` in `TranscriptExporter` JSON with a `Codable` `ExportedSegment` (start, end, speaker, text).
- Unit tests: TXT/SRT/JSON output shape; speaker custom names appear in all three; SRT timecode formatting (incl. hours, ms); reassigned speakers reflected.
- Import sanity: confirm supported extensions filter + a large-file import doesn't crash (sim).

## Out of Scope
- New export formats.
- Sharing UI changes.

## Worker Instructions
1. Introduce `ExportedSegment: Codable`; encode with `JSONEncoder` (pretty). Keep output stable/compatible (seconds as decimals, speaker display name).
2. Add exporter tests covering all formats + names + SRT edge cases (e.g. >1h timestamps).
3. Verify `displayName` resolution composes with rename + OBJ-12 reassignment.

## Auditor Checklist
- [ ] JSON now `Codable`; no `[String: Any]` cast remains.
- [ ] Output remains compatible (no breaking field/shape changes) unless documented.
- [ ] Speaker names + reassignment reflected in all formats.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Export TXT/SRT/JSON; open each; verify structure + speaker names.
- [ ] Rename a speaker → re-export → name appears (PRD §17 Export).
- [ ] SRT timing correct for short + long (>1h) transcripts.
- [ ] Large/odd-format import doesn't crash.
- [ ] Regression: share sheet flow unaffected.

## Acceptance Criteria
- Type-safe JSON; verified TXT/SRT/JSON with speaker names; SRT timing tested.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + exporter tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if exports are type-safe + correctness tests green.
- **ASK USER** only if a JSON shape change would break an external consumer.

## Rollback Considerations
Internal refactor + tests. Revert restores `JSONSerialization`. No data/schema change.

## Completion Report — 2026-06-21

**Worker summary:** Added `TranscriptExporter.ExportedSegment: Codable` and changed JSON export to encode `[ExportedSegment]` with `JSONEncoder` and pretty printing. The JSON shape remains compatible: a top-level array of segment objects with `start`, `end`, `speaker`, and `text`; start/end remain seconds as decimal numbers; `speaker` remains the display name; `text` remains transcript text.

**Speaker/export behavior:** TXT, SRT, and JSON all continue to resolve speaker names through `TranscriptExporter.displayName(_:names:)`. Because OBJ-12 reassignment updates the segment speaker id, reassigned segments export as the new speaker; if that speaker has a custom rename, the renamed display name exports in all three formats.

**Import sanity:** Strengthened `SharedAudioInbox` filter tests for all supported audio extensions, odd unsupported names, and a 12 MB placeholder `.m4a` that is classified without reading/parsing contents. This covers import eligibility sanity without adding heavy fixtures or broad codec claims.

**Auditor report:** ALIGNED. `TranscriptExporter` JSON no longer uses `JSONSerialization` or `[String: Any]` for segment construction; the only remaining `[String: Any]` in the active app is unrelated AVAudioRecorder settings in `CapturedAudioChunk`. Export output remains compatible at the field/shape level; speaker names, renamed speakers, reassigned speakers, and renamed-plus-reassigned speakers are covered in TXT/SRT/JSON tests. SRT numbering and timestamp syntax include milliseconds and >1h formatting. No new export formats, share UI redesign, transcript text editing, speaker merge/split workflow, schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, or OBJ-17+ work was introduced.

**QA evidence:** Recorded in [QA.md](../../../QA.md#obj-16--export-hardening--2026-06-21). macOS build PASS; iOS simulator build PASS; focused `TranscriptExportTests` + `SharedAudioInboxTests` PASS; full `TranscriberTests` PASS (126/126); `git diff --check` PASS.

**Gate recommendation:** PROCEED. No Human/product decision is required because JSON compatibility was preserved.
