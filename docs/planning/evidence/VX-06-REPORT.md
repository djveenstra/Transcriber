# VX-06 Consolidated Evidence

Date: 2026-07-29

Risk tier: Critical

Gate: `PROCEED`

## Result

Added optional durable `processingRecordID` and `sourceAudioID` fields, a versioned per-recording atomic job store, current-session checkpoints, and one-time relaunch recovery projected through existing retry flags.

Production/test files:

- `Transcriber/Models.swift`
- `Transcriber/ProcessingJobStore.swift`
- `Transcriber/RecordingProcessingIdentity.swift`
- `Transcriber/TranscriptionSession.swift`
- `Transcriber/Transcriber2App.swift`
- `TranscriberTests/Fixtures/pre-vx06.store`
- `TranscriberTests/ProcessingJobStoreTests.swift`
- `TranscriberTests/RecordingPersistenceTests.swift`
- `TranscriberTests/TranscriptionSessionTests.swift`

## Safety behavior

- Missing random IDs are saved before a job is created and reread from a fresh SwiftData context by exact persistent model ID.
- Job files live under the approved per-recording store path with application-root-anchored canonical containment.
- Legal monotonic stage/state transitions, terminal immutability, timestamps, and compare-before-update preconditions are enforced.
- Atomic start prevents queued/running orphans; create/checkpoint/final/cancel failures surface through the existing Storage Issue path and retain repair state.
- Relaunch changes stale running/cancel-requested jobs to interrupted, never succeeded.
- Interrupted/partial/failed projections are idempotent, require both recording and source IDs, retry unmatched/save failures, and complete only after durable SwiftData save.
- Current legacy-only processing completes as `partial`, never false `succeeded`; succeeded requires externally validated published artifact evidence.

## Migration evidence

The 69,632-byte synthetic `pre-vx06.store` was generated with a separately compiled pre-VX-06 `Recording` model. The current schema opens it with transcript, raw timing, speaker mapping, audio filename, and other legacy fields intact; both optional IDs decode nil.

No original audio or legacy blob is transformed, cleared, or repurposed.

## Audit history

Initial audit: `DRIFT FOUND` for one-shot recovery projection, job containment/global layout, missing transition rules, silent write failure, missing real legacy fixture, and same-context identity reread.

First re-audit: residual whole-store symlink anchor and fresh-context identity reread findings.

After correction, final Auditor result: **`ALIGNED`**.

## Validation

- Mac build: PASS.
- Independent focused QA: **37/37 PASS** across job, persistence, and session failure suites.
- Final full `TranscriberTests`: **208/208 PASS**.
- `git diff --check`: PASS.
- Strict concurrency, project settings, package pins, existing blobs/audio/transcripts, and dependencies unchanged.

## Limitations

Atomic failures are deterministic injections, not literal power loss. Relaunch is tested with file-backed stores rather than a manual force-quit of a private production Library. No private/real audio was used.

## Rollback

Disable job bridging/recovery and remove the job infrastructure. Old builds ignore optional identifiers and continue using legacy blobs/audio; harmless IDs remain preserved.
