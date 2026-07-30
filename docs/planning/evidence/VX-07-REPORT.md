# VX-07 Consolidated Evidence

Date: 2026-07-29

Risk tier: High

Gate: `PROCEED`

## Result

Added a dormant actor-based `AudioPreparationService` and focused tests. The service creates versioned mono 16 kHz Float32 CAF derivatives, source/output/time-map metadata, SHA-256 and byte-count evidence, conservative quality measurements, deterministic reuse, and interruption-safe ownership records.

Production/test files:

- `Transcriber/AudioPreparationService.swift`
- `TranscriberTests/AudioPreparationServiceTests.swift`

No current recording, import, transcription, diarization, playback, export, schema, UI, project, entitlement, model, dependency, or sibling-workspace path calls or adopts the service.

## Safety behavior

- Source audio is read-only and canonical source/generated-path collisions are rejected before reuse or cleanup.
- Generated-root symlink escapes and unowned deterministic occupants fail closed.
- Sidecar publication is authoritative and occurs after a synchronized derivative and durable ownership evidence.
- Prepublication crash markers are bound to the exact source digest, recipe, regeneration key, identity, and filenames.
- Published markers require paired digest/byte-count evidence that exactly matches the derivative.
- Coherent sidecars can authorize safe regeneration of a corrupt owned derivative; forged, stale, half-populated, missing, or contradictory ownership evidence cannot authorize deletion.
- Cleanup and invalidation require the source URL and recheck collision protection for every generated removal.

## Conversion and quality evidence

- Programmatic mono/stereo and 16/22.05/32/44.1/48 kHz inputs cover conversion to actual mono 16 kHz noninterleaved Float32.
- Source format ID, sample rate, channel count/layout tag, frame count, duration, byte count, and digest are retained as metadata.
- Output frame count, measured duration, time mapping, digest, byte count, algorithm versions, recipe, transforms, and regeneration key are recorded.
- Peak amplitude, RMS amplitude/dBFS, clipping count/ratio, silence ratio/regions, and conservative speech regions use explicit versioned thresholds and units.

## Audit history

Initial audit found a source/generated-path collision that could delete original audio and missing High-risk evidence.

Subsequent audits found increasingly narrow ownership-authority defects: orphan cleanup without durable proof, marker fields not bound to the actual source/key, and published marker evidence not matched to the actual derivative. Each finding was corrected with fail-closed validation and regression tests.

Final Auditor result: **`ALIGNED`**.

## Validation

- Mac build: **PASS**.
- Independent focused QA: **17/17 PASS**.
- Final full governed `TranscriberTests`: **225/225 PASS**.
- Final full xcresult: `Test-Transcriber-2026.07.29_13-33-14--0400.xcresult`.
- `git diff --check`: PASS.
- `SWIFT_STRICT_CONCURRENCY = complete`, project settings, and dependency pins unchanged.
- No private/repository audio or application data was used.

## Limitations

Tests use programmatically generated PCM, temporary directories, and injected interruption points. They do not claim literal power-loss behavior or calibrated quality thresholds on representative real recordings. Production adoption and threshold calibration remain later benchmark decisions.

## Rollback

Remove the dormant service and focused tests. Delete only test-generated temporary derivatives. No existing original audio, `Recording`, transcript, correction, job, artifact, or application-flow data needs migration or rollback.
