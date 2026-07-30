# VX-05 Consolidated Evidence

Date: 2026-07-29

Risk tier: Critical

Gate: `PROCEED`

## Result

Added a dormant actor-based `ProcessingArtifactStore` implementing the approved `store-v1` envelope, immutable artifact, manifest generation, and authoritative pointer core. Existing app flows do not call it and no `Recording` schema or user data changed.

Production/test files:

- `Transcriber/ProcessingArtifactStore.swift`
- `TranscriberTests/ProcessingArtifactStoreTests.swift`

## Critical safety behavior

- Canonical opaque UUID identifiers and symlink-resolving path containment.
- Payload/envelope staging, synchronization, digest/byte/schema validation, and immutable atomic placement.
- Artifact → immutable manifest → pointer commit ordering with expected-generation comparison.
- Exact `current.previous` linkage, valid fallback, and no promotion of unpointed higher manifests.
- Recovery at both pointer replacement boundaries, including generation-2 and generation-3 interrupted publication.
- Recursive same-recording/source-audio graph validation with missing reference, wrong kind/path, and cycle rejection.
- Cleanup fails closed on corrupt/unknown state, marks every valid manifest graph, retains protected/current/previous/unpointed evidence, and removes only proven old unpublished material.

## Audit history

Initial Auditor result: `DRIFT FOUND` for destructive cleanup risk, non-exact previous linkage, incomplete graph/source validation, symlink containment gaps, and pointer staging validation.

After corrections, re-audit found one residual between-pointer crash boundary. The Worker added exact fault injection and duplicate-pointer journal recovery for generation 2 and 3.

Final Auditor result: **`ALIGNED`**.

## Validation

- Mac build: PASS.
- Focused artifact store tests: **20/20 PASS**.
- Post-fix full `TranscriberTests`: **187/187 PASS**.
- `git diff --check`: PASS.
- Strict concurrency and dependency pins unchanged.
- No schema, current-flow, UI, model, project, entitlement, iOS/Python, private-audio, application-data, or cleanup change.

## Limitations

Tests use invented payloads, temporary directories, and deterministic fault injection. They do not claim literal power-loss behavior on a real application store. The store is dormant, so no existing-data or Human UI gate is created.

## Rollback

Remove the two dormant source/test files. No data conversion is required.
