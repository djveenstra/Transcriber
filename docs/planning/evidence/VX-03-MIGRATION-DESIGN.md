# VX-03 Storage and Migration Design

Design version: `vx03-migration-v1`

Status: Proposed for Human approval; not implemented

## 1. Placement decision

### 1.1 Original audio

Keep original audio in the existing application-owned recordings directory. It remains linked by the current `Recording.audioFileName` compatibility field.

Rules:

- never rename, recompress, normalize, or replace original audio during artifact migration;
- never treat original audio as cache;
- do not require a full audio checksum before opening an existing Library row;
- future optional integrity digests are local metadata and cannot block legacy readability.

### 1.2 SwiftData

SwiftData remains the small, queryable Library/control-plane store:

- existing `Recording` metadata and legacy blobs;
- future optional `processingRecordID` and `sourceAudioID`;
- future optional selected/current transcript-version reference and artifact-manifest generation;
- lightweight persisted job summaries needed for Library/Dashboard state;
- later profile metadata only under VX-17.

SwiftData must not absorb raw provider outputs, prepared audio, embeddings, large diagnostics, candidate transcripts, or artifact payloads.

Any added `Recording` field must be optional or have a legacy-safe default. The exact schema change belongs to a Critical implementation objective with old-store fixtures and rollback proof.

### 1.3 Artifact store

Future path, relative to the existing application root:

```text
ProcessingArtifacts/
  store-v1/
    recordings/
      <recording-id>/
        manifests/
          manifest-<generation>.json
          current
          current.previous
        artifacts/
          <artifact-id>/
            envelope.json
            payload.<extension>
        jobs/
          <job-id>.json
        quarantine/
```

Rules:

- all stored references are relative to the versioned store root;
- recording and artifact IDs are opaque and validated before path construction;
- no user-supplied string becomes a path component;
- each artifact directory is immutable after publication;
- manifests are immutable generations; `current` is the sole authoritative commit pointer and `current.previous` is its validated fallback;
- a recording directory cannot reference another recording’s private artifact except through a future explicitly shared/profile store.

### 1.4 Regenerable cache

Regenerable cache may hold:

- decoded audio buffers;
- duplicate prepared derivatives whose recipe/input still exists;
- indexes and previews;
- temporary alignment structures;
- downloaded/compiled model caches managed by their existing provider lifecycle.

Cache is never the only location for a transcript, correction, identity decision, approved enrollment sample, artifact manifest, or original audio.

## 2. Authoritative-state rules

During migration there are two readable representations:

1. legacy `Recording` fields;
2. the published artifact manifest and referenced immutable artifacts.

Authority transitions per recording, not globally:

- `legacyOnly`: current fields are authoritative; no valid committed `current` pointer. Saved identity fields alone do not change this state.
- `artifactPrimaryDualWrite`: manifest is primary for new pipeline work; compatibility fields are still written.
- `artifactPrimaryProjectionStale`: manifest is primary, but a SwiftData compatibility projection failed and must be repaired; the UI may use the valid manifest while clearly reporting persistence repair.

There is no “migration complete” flag based only on an in-memory state or the presence of a directory.

## 3. Additive rollout sequence

### Stage A — Characterize and fixture

Before production writes:

- freeze representative synthetic/approved legacy stores;
- test empty/corrupt transcript, raw transcription, and speaker-name blobs;
- test missing audio and unusual filenames;
- characterize current Library/status/export/retry behavior;
- prove the old build still reads its existing fields.

### Stage B — Introduce dormant store support

- Add versioned path and decoder types behind tests.
- Add optional `processingRecordID`, `sourceAudioID`, and manifest/projection references with legacy-safe defaults only in the approved Critical objective.
- Do not create artifacts merely by launching or listing the Library.
- Existing rows remain `legacyOnly`.

### Stage C — Lazy per-recording adoption

Adopt a recording only when a scoped operation needs artifacts:

1. acquire a per-recording migration lock;
2. re-read current legacy fields and both optional identity fields;
3. if either identity is nil, mint only the missing random `processingRecordID`/`sourceAudioID` and durably save both identities to `Recording` before creating any artifact;
4. re-read the row and require exact reuse of the saved identities; this identity-only save leaves authority at `legacyOnly`;
5. create immutable “legacy import” artifacts from current blobs without altering them;
6. import the exact legacy transcript segments, speaker reassignments, and speaker display-name mapping as the selected version with `verification_provenance = legacy_unknown` and `selection_protection = legacy_preserved`;
7. validate encode/decode, references, digests, time conversion, and semantic/display equality;
8. commit manifest generation 1 through the authoritative pointer protocol;
9. save optional SwiftData manifest/projection state;
10. leave all legacy blobs and audio unchanged.

If the identity save fails, no artifact is created. If a later step fails, delete or quarantine only unpublished temporary files and remain `legacyOnly`; the already saved opaque identities are harmless and must be reused on retry. A crash after identity save is therefore recoverable without deriving identity from user data. A missing source file still reuses its saved `sourceAudioID` and remains honestly missing.

### Stage D — Dual-write

For each new useful result:

1. write and validate the immutable artifact;
2. compare-and-publish a new manifest generation;
3. update the current `Recording` compatibility fields from the selected transcript/version and stage state;
4. save SwiftData;
5. if SwiftData save fails, keep the valid manifest, mark the projection repairable, and do not run dependent work that requires the projection to be current unless its artifact inputs are independently proven.

The projection update cannot replace a newer Human correction: it uses expected transcript version and manifest generation.

### Stage E — Retirement is separate

Removing or ceasing dual-write of legacy blobs is not part of VX-03 or VX-05. It requires:

- evidence that all supported old records migrate;
- at least one released rollback-compatible version;
- corrupt/interrupted/newer-version tests;
- export and Human acceptance;
- an exact Human-approved retirement objective.

## 4. Atomic write and publish protocol

### 4.1 Artifact write

1. Validate IDs and choose a same-filesystem temporary directory under the recording root.
2. Write payload and envelope with restrictive permissions.
3. Close and request durable synchronization appropriate to the implementation.
4. Reopen and validate size, digest, schema, required fields, recording ID, and references.
5. Atomically rename the completed temporary artifact directory to its final immutable ID path.
6. If the final path already exists, require byte/digest identity or fail closed.

### 4.2 Manifest publish

1. Read and validate the authoritative `current` pointer and its referenced manifest generation. For first adoption, the expected state is no pointer and `legacyOnly`.
2. Check expected generation, attempt ownership, and correction/version preconditions.
3. Write the full next immutable manifest to a same-directory temporary file.
4. Close/synchronize and validate it.
5. Atomically rename to `manifest-<generation>.json`. At this point it is valid but uncommitted.
6. When a prior `current` exists, atomically write/replace `current.previous` with an exact validated copy of that prior pointer.
7. Write, close/synchronize, and validate a new pointer containing the new generation, manifest digest, and prior generation/digest.
8. Atomically replace `current` with the new pointer. This replacement is the commit point.
9. Reopen through `current`, validate the pointer and referenced manifest, and verify the published generation.

An artifact that completes but loses the compare-and-publish race remains unreferenced. It cannot become current later without a new explicit reconciliation.

If manifest rename succeeds but `current` replacement fails, the new manifest is uncommitted and remains an orphan. Readers continue through the old `current`. Recovery never scans for or promotes the numerically newest manifest.

### 4.3 Cross-store failure

Filesystem and SwiftData cannot be assumed to share one transaction.

Safe ordering:

1. persist immutable artifact;
2. publish manifest;
3. update SwiftData compatibility projection/pointer.

If step 3 fails, the artifact result is still recoverable from the manifest and the previous SwiftData data remains intact. Relaunch reconciliation repairs the projection or reports it honestly. The reverse ordering is forbidden because SwiftData could point to an artifact that was never durably written.

## 5. Corruption and unknown-version handling

On read:

1. validate `current` pointer syntax, digest, generation, and containment;
2. validate only the manifest referenced by `current`;
3. validate envelope/payload schema, recording ID, byte count, digest, and reference graph;
4. reject traversal, cycles, cross-recording references, missing required parents, and mismatched source audio;
5. if `current` is missing, corrupt, or references an invalid manifest, validate `current.previous` and its exact referenced manifest;
6. if neither pointer is valid, remain/fall back to `legacyOnly` or the last valid compatibility projection and require repair.

Safe outcomes:

- Corrupt committed manifest or pointer: fall back only through valid `current.previous` and surface repair diagnostics.
- Valid manifest with no authoritative pointer: treat it as an uncommitted orphan; never promote it by scan.
- Corrupt non-current artifact: isolate it; preserve other artifacts.
- Corrupt current artifact with valid legacy projection: fall back to legacy fields and mark artifact repair/reprocessing.
- Corrupt legacy blob with valid artifact: use the artifact and offer projection repair.
- Both representations invalid: preserve original audio and row, show honest recovery/retranscription state.
- Unknown newer schema: preserve bytes, do not downgrade/rewrite, use an older compatible manifest or legacy projection if available.
- Missing original audio: never invent it; transcript/history may remain readable with an explicit missing-audio state.

Quarantine moves only corrupt derived/unpublished artifacts inside the same recording store. It never moves original audio, verified transcripts, correction history, profiles, or enrollment material.

## 6. Transcript selection and history

Each recording manifest records:

- all transcript-version artifact IDs;
- `selectedDisplayVersionID`;
- optional `latestVerifiedVersionID`;
- selection protection and verification provenance;
- parent/supersession graph;
- review-needed regions;
- compatibility-projection source version.

Rules:

- An automatically selectable draft may become selected when no verified, `human_locked`, or `legacy_preserved` selected version exists and it provides the best useful result.
- Once a verified version exists, automation cannot replace `selectedDisplayVersionID`.
- Automation also cannot replace a selected `human_locked` or `legacy_preserved` version.
- A Human may select another historical or new version.
- Editing creates a new child version and append-only correction events.
- Verification creates or marks a new immutable verified version; it does not mutate its parent.
- Reprocessing old audio creates a new draft branch.
- Export records selected transcript version and can explicitly export a historical version.
- Display names and identity mappings are versioned separately so a person-label change does not rewrite anonymous cluster evidence.

Legacy imports:

- If legacy data does not record explicit Human verification, import its transcript as `draft` with origin `legacy_projection`, `verification_provenance = legacy_unknown`, and `selection_protection = legacy_preserved`.
- Import transcript segments, embedded anonymous speaker assignments, and `speakerNamesData` display mappings together so existing Human reassignment/naming remains visually and semantically intact.
- The imported legacy version remains selected and automation-locked until a Human explicitly selects a replacement or creates/confirms a corrected descendant.
- Do not silently downgrade current UX labels during migration; the compatibility UI remains unchanged until a later scoped transcript-version UI objective.

## 7. Persisted jobs and relaunch boundary

VX-03 defines only the storage interface needed by VX-06:

- job ID, requested operation, recording ID, input manifest generation, stage, attempt ID, state, timestamps, and published output refs;
- states: `queued`, `running`, `cancelRequested`, `interrupted`, `partial`, `succeeded`, `failed`;
- `succeeded` requires a valid published output artifact;
- relaunch changes stale `running` to `interrupted`, never `succeeded`;
- a job cannot publish when its input generation or correction precondition is stale.

VX-06 owns scheduler behavior and UI.

## 8. Cleanup and retention classes

### Never automatic cleanup

- original audio;
- selected or verified transcript versions;
- Human corrections and decision provenance;
- profile records, embeddings, and approved enrollment samples;
- manifests required to interpret retained artifacts;
- the only valid compatibility representation.

### Retain by default, user/policy review required

- raw/normalized production model outputs;
- non-selected transcript versions;
- diarization, identity, reconciliation, and diagnostic evidence used by a retained transcript;
- approved benchmark references.

No age/size retention threshold is approved in Phase 0.

### Automatically reclaimable only after reference proof

- unpublished temp files from a failed write;
- orphan artifacts that lost publication and exceed a future conservative grace period;
- regenerable prepared derivatives with intact source and recipe;
- disposable previews/indexes;
- provider-managed model caches through existing explicit model lifecycle.

Cleanup uses a reference-graph mark phase from every valid manifest plus a conservative grace period. It fails closed on corrupt/unknown manifests and produces a redacted report. Low disk may stop new processing; it does not justify deleting protected classes.

### User-initiated recording deletion

A future objective must define and test the sequence for deleting original audio, SwiftData row, and artifact subtree. VX-03 does not change current deletion behavior. Partial deletion failure must preserve enough metadata to retry and must not claim success.

## 9. Privacy and filesystem policy

- Store artifacts under Application Support, not documents chosen by the user.
- Use least-permission local files/directories supported by the sandbox.
- Do not place private content in filenames.
- Diagnostics and manifests use opaque relative references.
- Ordinary diagnostic export excludes audio, transcript text, identity embeddings, profile names, and private paths.
- Identity-sensitive protection and verified deletion are expanded in VX-17/VX-25.
- Network access is not part of artifact migration.

## 10. Required implementation tests

### Format and path

- current-version round trip for every envelope/payload;
- empty/optional fields;
- unknown newer version;
- invalid UUID/path traversal/cross-recording reference;
- duplicate artifact ID with same and different digest;
- graph cycle and missing parent;
- time overflow/negative/reversed ranges.

### Legacy migration

- empty legacy record;
- transcript-only, raw-only, and fully populated rows;
- corrupt transcript/raw/speaker-name blobs independently and together;
- missing audio;
- idempotent repeated adoption;
- crash after durable identity save reuses the same `processingRecordID` and `sourceAudioID`;
- failure to save identities creates no artifact;
- missing source audio preserves/reuses `sourceAudioID`;
- crash/failure after each migration step;
- lazy migration leaves untouched rows unchanged;
- millisecond-to-microsecond equivalence;
- old build reads dual-written fields.

### Atomicity and recovery

- truncated payload/envelope/manifest/pointer;
- manifest rename followed by pointer failure leaves an uncommitted orphan;
- corrupt `current` falls back only to valid `current.previous`;
- scan never promotes a valid unpointed higher manifest;
- interrupted temp write and rename;
- checksum mismatch;
- stale expected generation;
- late canceled attempt;
- correction races with model publication;
- SwiftData save failure after manifest publish;
- artifact write failure before projection;
- pointer-authoritative fallback through `current.previous`, then legacy data.

### Retention/deletion

- reference graph preserves protected artifacts;
- unknown/corrupt manifest blocks destructive cleanup;
- orphan grace period;
- derivative regeneration proof;
- low-disk failure preserves old authoritative state;
- explicit recording deletion partial failures.

### Regression

- existing recordings and transcripts open unchanged;
- original audio path and bytes remain unchanged;
- recording/import persistence ordering;
- diarization failure keeps transcript;
- cancel/retry/stale-attempt behavior;
- playback/export/speaker rename/reassignment;
- strict concurrency and dependency pins.

## 11. Rollback

Rollback target: the previous application version can continue using legacy `Recording` fields and original audio.

Requirements:

- dual-write remains enabled through at least one separately approved compatibility window;
- no migration clears or repurposes legacy fields;
- artifact directories are additive and ignored by old builds;
- a rollback never needs to transform original audio;
- data created only in the artifact system is projected to legacy fields when representable;
- unrepresentable future evidence remains preserved for re-upgrade and is not silently discarded.

Before any release that writes artifacts, QA must install/run the prior supported build against a copied test store after new writes and confirm Library/transcript/audio compatibility.

## 12. Decisions requiring Human approval

Approval requested for these principles:

1. Original audio remains in the current recordings directory; artifacts are additive under `ProcessingArtifacts/store-v1`.
2. SwiftData remains the Library/control-plane store, with only small optional pointers/job summaries added.
3. Future `processingRecordID` and `sourceAudioID` are optional, random, lazily assigned, durably saved before artifacts, and reused after interruption.
4. Artifact-first, manifest-second, SwiftData-projection-third is the cross-store write order.
5. Migration is lazy, per-recording, idempotent, and dual-write; no launch-time bulk migration.
6. Legacy blobs remain readable through a separately approved retirement objective.
7. Verified transcripts, Human corrections, and legacy-preserved display versions are immutable/append-only or selection-locked and cannot be replaced by automation.
8. No automatic age/size cleanup threshold is approved; only proven regenerable/unpublished material is reclaimable.
9. Unknown/corrupt state fails closed and preserves original audio/last valid representations.

Encoding library, compression, exact filesystem synchronization mechanism, digest scope for very large media, encryption/profile protection, retention periods, and UI presentation remain implementation-objective decisions with evidence.
