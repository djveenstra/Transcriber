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
