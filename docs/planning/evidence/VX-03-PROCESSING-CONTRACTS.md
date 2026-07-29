# VX-03 Versioned Processing Contracts

Design version: `vx03-contracts-v1`

Status: Proposed for Human approval; not implemented

## 1. Design invariants

Every future contract and implementation must preserve these rules:

1. Original audio is immutable source data, never a cache.
2. A useful stage result is durably written before dependent work starts.
3. Artifacts are immutable. A changed result receives a new artifact ID and version.
4. Human corrections and verified transcripts are never overwritten by model work.
5. A late or canceled attempt cannot publish over a newer attempt or correction.
6. Unknown, ambiguous, overlapping, inaudible, and unresolved outcomes are valid data.
7. Anonymous speaker clusters remain separate from display names and person identity.
8. Raw provider output and normalized output are distinct artifacts.
9. Every meaning-changing model, runtime, preprocessing, schema, pipeline, calibration, and correction version is recorded.
10. Large/versioned evidence stays outside opaque SwiftData blobs.
11. Private paths, transcript text, names, embeddings, and audio are excluded from ordinary logs and diagnostic exports.
12. Existing `Recording` blobs remain readable compatibility projections until a separately approved retirement objective.

## 2. Common primitives

### 2.1 Identifiers

All persisted IDs use lowercase canonical UUID strings unless a later objective proves another format necessary.

| ID | Meaning | Stability |
|---|---|---|
| `recordingID` | Stable processing identity for one Library recording | Never reused; survives title/audio-filename changes |
| `sourceAudioID` | Identity of the immutable original audio source | Never reused; derivatives reference it |
| `artifactID` | One immutable artifact envelope/payload | New for every payload change |
| `pipelineRunID` | One requested end-to-end or partial pipeline run | Stable across its stage attempts |
| `attemptID` | One executable attempt at one stage | New on retry |
| `transcriptVersionID` | One immutable transcript version | New for each draft/reconciliation/correction result |
| `unitID` | Stable logical timed unit inside a lineage | Preserved for unchanged units; split/merge creates new IDs with ancestry |
| `clusterID` | Anonymous speaker cluster within a diarization lineage | Never a person/profile ID |
| `profileID` | User-owned known-speaker profile | Defined fully in VX-17 |
| `correctionID` | One append-only Human correction event | Never reused |
| `jobID` | One persisted processing job | New for each requested job |

Current `Recording` has no explicit UUID field. A future Critical implementation may add optional `processingRecordID` and `sourceAudioID` fields with nil-safe legacy defaults. On first adoption, both random IDs are minted together and durably saved to the legacy `Recording` before any artifact is created. This identity-only save does not change authority from `legacyOnly`. A retry must re-read and reuse either saved ID; it may never mint a replacement for a non-nil value. Neither ID may be inferred from title, filename, transcript text, path, content digest, or SwiftData’s internal identity.

### 2.2 Time

- Canonical unit: signed 64-bit integer microseconds from the beginning of the immutable original audio.
- Valid stored ranges are non-negative half-open intervals `[startUs, endUs)`.
- `endUs` must be greater than or equal to `startUs`; zero-length markers require an explicit marker kind.
- A payload declares `timebase = original_audio_start_us`.
- Converters from current milliseconds use checked multiplication by 1,000.
- Provider-relative, chunk-relative, sample-index, or prepared-audio times remain in raw output and are converted with recorded transform/offset evidence.
- Timing precision is declared as `word`, `token`, `segment`, `region`, or `unknown`; normalization must not claim word precision when the provider supplies only regions.
- Overlapping intervals are preserved.

### 2.3 Confidence and uncertainty

A score is meaningless without its source and scale. Each confidence field therefore includes:

- optional numeric value;
- named scale/range;
- producer/model version;
- calibration version or `uncalibrated`;
- reason codes and quality inputs.

Semantic outcome fields use enumerations such as:

- `accepted`
- `uncertain`
- `unresolved`
- `inaudible`
- `overlap`
- `not_applicable`

Absence, low confidence, unknown, and failure are distinct.

## 3. Artifact envelope

Every artifact has a small common envelope:

```yaml
envelope_schema_version: 1
artifact_id: uuid
artifact_kind: prepared_audio | transcription | diarization | identity | reconciliation | transcript_version | correction_log | diagnostics | provenance
payload_schema_version: 1
recording_id: uuid
source_audio_id: uuid
pipeline_run_id: uuid
attempt_id: uuid
created_at: timestamp
completed_at: timestamp-or-null
producer:
  component_id: stable-string
  component_version: version
  runtime_id: stable-string
  runtime_version: version
  model_id: stable-string-or-null
  model_version: version-or-null
  dependency_revisions: map
parents: [artifact-id]
inputs: [typed-artifact-reference]
payload:
  encoding: json | binary | media
  relative_path: opaque-relative-path
  byte_count: integer
  digest_algorithm: sha256
  digest: hex
privacy_class: ordinary_private | transcript_private | audio_private | identity_sensitive
```

Rules:

- The envelope never contains an absolute path.
- Timestamps use UTC with an explicit format/version.
- `completed_at` is set only for a finalized immutable artifact.
- Partial work may be stored as a non-authoritative attempt artifact, but it cannot be published as completed.
- Unknown envelope or payload schema versions are preserved and skipped safely, not decoded as an older shape.
- Parent and input references are typed and validated to prevent accidental cross-recording links.
- Raw and normalized results use separate artifact IDs linked by `parents`.
- `sourceAudioID` is the durable random identity saved on `Recording` during adoption. It identifies the original-audio relationship even when the file is temporarily missing; the filename remains the legacy location reference.

## 4. Prepared audio contract

`PreparedAudioV1` records:

- derivative artifact ID and source audio ID;
- source container/codec/channel layout metadata without changing the original;
- output relative file reference;
- sample rate, channel count/layout, sample format, frame count, duration, and time mapping to original audio;
- ordered transform steps with component/version/configuration;
- source region when the derivative is a clip;
- quality measurements with algorithm/version and units;
- clipping, silence, and speech-activity regions when measured;
- digest, byte count, and regeneration key;
- `regenerable = true` unless Human edits make it unique;
- failure/exclusion reasons when a requested derivative cannot be produced.

A denoised, separated, normalized, clipped, or mono 16 kHz file is a new derivative. It never replaces the original or another derivative.

## 5. Timed transcription contract

`TimedTranscriptionV1` contains:

- prepared-audio input reference;
- engine/provider/model/runtime/configuration and decoding parameters;
- language request and detected-language evidence;
- raw provider artifact reference;
- ordered timed units;
- full-result status: `complete`, `partial`, `failed`, or `canceled`;
- warnings, exclusions, and provider limitations.

Each `TimedTextUnitV1` contains:

- `unitID`;
- original-audio `startUs` and `endUs`;
- timing precision;
- exact factual text selected by the engine;
- optional provider token/word IDs;
- optional confidence descriptor;
- optional alternative hypotheses with the same evidence rules;
- language tag;
- uncertainty and non-speech reason codes;
- source raw-result references;
- ancestry for split/merge/normalization.

Normalization may standardize encoding and timing representation. It may not silently correct, paraphrase, punctuate beyond a separately versioned formatting step, or invent provider confidence.

## 6. Diarization contract

`DiarizationResultV1` contains:

- prepared-audio input and raw provider output references;
- engine/model/runtime/configuration;
- declared overlap and confidence capabilities;
- anonymous clusters;
- ordered speech regions;
- expected/estimated speaker count evidence;
- complete/partial/failed/canceled status and limitations.

Each `SpeakerRegionV1` contains:

- region ID;
- original-audio time range;
- anonymous `clusterID` or `unresolved`;
- optional overlap-group ID and simultaneous cluster IDs;
- optional confidence/quality descriptor;
- speech/non-speech/uncertain label;
- source evidence references.

Clusters contain anonymous labels and optional aggregate quality only. Display names and profile identities are external mappings.

## 7. Speaker identity contract

`SpeakerIdentityResultV1` contains:

- diarization artifact and cluster ID;
- approved profile-set/calibration/model versions;
- suitable and rejected evidence-region references with reasons;
- per-model evidence;
- aggregate decision;
- Human review status.

The aggregate decision is exactly:

```yaml
outcome: known | unknown | ambiguous
profile_id: uuid-or-null
best_score: calibrated-descriptor-or-null
second_best_score: calibrated-descriptor-or-null
acceptance_threshold_version: version
separation_rule_version: version
reason_codes: [...]
```

Rules:

- `profileID` is present only for `known`.
- A nearest candidate alone cannot produce `known`.
- `unknown` means evidence supports rejection of available profiles.
- `ambiguous` means evidence is insufficient or conflicting.
- Anonymous `clusterID` is preserved regardless of outcome.
- Embeddings and enrollment audio are identity-sensitive artifacts with stronger VX-17/VX-25 protection and deletion rules.
- Identity is transcript labeling only, never authentication.

## 8. Reconciliation contract

`ReconciliationResultV1` contains:

- two or more candidate transcription references;
- alignment algorithm/version/configuration;
- formatting/normalization version;
- ordered decision regions;
- reconciled timed units;
- unresolved/review regions;
- complete/partial/failed/canceled status.

Each `ReconciliationDecisionV1` records:

- original-audio range;
- candidate unit references and exact candidate text;
- decision type: `agreement`, `format_only`, `selected_candidate`, `supported_combination`, `uncertain`, or `human_review`;
- deterministic rule/version;
- accepted unit references or null;
- reason codes and confidence/quality evidence;
- whether targeted reprocessing contributed.

`supported_combination` may join factual pieces already present in aligned evidence. It cannot author unsupported words. A failed reconciliation leaves all candidates intact.

## 9. Transcript version contract

`TranscriptVersionV1` is an immutable user-facing transcript representation:

```yaml
transcript_version_id: uuid
kind: draft | reconciled | verified
review_state: not_reviewed | needs_review | in_review | reviewed
verification_provenance: not_verified | explicit_human | legacy_unknown
selection_protection: automatic | human_locked | legacy_preserved
parent_versions: [transcript-version-id]
source_artifacts: [artifact-id]
created_by: system | human
created_at: timestamp
verified_at: timestamp-or-null
verified_by: human-or-null
supersedes: transcript-version-id-or-null
segments: [...]
```

Semantics:

- **Draft:** useful current model output. It may exist before optional stages finish.
- **Reconciled:** deterministic candidate reconciliation; it is not automatically verified.
- **Verified:** explicitly accepted by a Human. It is immutable.
- **Historical:** not a separate content kind. Every prior immutable version retained after another becomes current is historical.
- **Superseded:** a relationship/status in the manifest, never destructive replacement.
- `needs_review` is orthogonal to draft/reconciled/verified kind.
- A rerun creates a sibling or child draft. It cannot replace the selected verified version.
- A selected `human_locked` or `legacy_preserved` version cannot be replaced by automation even when its kind is `draft`.
- Imported legacy transcript segments and display-name mappings use `verification_provenance = legacy_unknown` and `selection_protection = legacy_preserved`. This avoids inventing verification while protecting any Human text, speaker reassignment, or naming already present.
- Export records which transcript version was selected.

Each user-facing segment keeps anonymous cluster attribution, optional display-name mapping, optional separate identity decision, text/timing, uncertainty, and source decision references.

## 10. Correction contract

Corrections are append-only `CorrectionEventV1` records:

- correction ID and Human timestamp;
- target recording, transcript version, segment/unit/cluster;
- expected base transcript version and manifest generation;
- operation type;
- before-value digest/reference and requested after value;
- reason/note code;
- actor `human`;
- result: `applied`, `conflict`, `rejected`, or `reverted`;
- produced transcript version ID when applied.

Initial operations:

- replace transcript text;
- mark uncertain/inaudible;
- choose/reject candidate;
- reassign anonymous speaker;
- rename display label;
- confirm/reject identity suggestion;
- merge/split cluster (future VX-22);
- revert a prior correction by adding a compensating event.

If the expected base version is no longer current, the correction becomes `conflict`; it is never silently applied to different text. Applying a correction creates a new transcript version. Corrections never trigger training or enrollment automatically.

## 11. Diagnostics contract

`ProcessingDiagnosticsV1` contains:

- job, run, attempt, stage, and artifact references;
- stage status and monotonic timing;
- progress events with declared semantics;
- model load/unload and fallback events;
- cancellation/timeout/failure type and redacted message/code;
- resource observations with tool/method/version;
- recovery action and whether a useful result remained;
- app/OS/hardware profile without serial, UUID, username, full path, transcript, or audio.

Diagnostics are evidence, not authority for stage completion. Only a valid published artifact/manifest proves completion.

## 12. Provenance contract

`ProvenanceV1` may be embedded in envelopes and expanded as an artifact. It records:

- source and prepared-audio IDs;
- all input artifact IDs and digests;
- component/model/runtime/dependency/configuration versions;
- preprocessing, normalization, alignment, pipeline, calibration, and schema versions;
- job/run/attempt identities;
- start/end timestamps and host profile;
- Human decisions/corrections by opaque ID;
- failure, cancellation, retry, fallback, and exclusion history;
- license/package review reference for production candidates.

Provenance is a directed acyclic graph. An artifact cannot reference itself or a descendant.

## 13. Publish and stale-attempt rules

The recording manifest has a monotonically increasing `generation`. Publishing requires:

1. the stage artifact is fully written and validated;
2. the attempt still owns the job/stage;
3. the expected manifest generation matches current;
4. no newer Human correction or verified-version selection conflicts;
5. a new immutable manifest is committed by an authoritative pointer update.

A generation mismatch returns a conflict and leaves the artifact orphaned/unpublished for later cleanup. It never overwrites the current manifest.

The `current` pointer is the only publication authority. A valid higher-numbered manifest without a committed pointer is an orphan, not a published result. Recovery never promotes it merely because it is the newest valid file.

Cancellation:

- stops future dependent work;
- may preserve completed upstream artifacts;
- publishes only results that were complete and owned before cancellation;
- never marks an incomplete stage complete;
- keeps the last useful published transcript/audio state.

## 14. Current-type mapping

| Current type/field | Future contract | Compatibility rule |
|---|---|---|
| `Recording.audioFileName` | source-audio reference | Remains the legacy source path link |
| `Recording.rawTranscriptionData` / `TranscriptionSegment` | `TimedTranscriptionV1` | Converted losslessly from milliseconds where possible; legacy blob retained |
| `Recording.transcriptData` / `TranscriptSegment` | initial `TranscriptVersionV1` | Imported as `draft` with `legacy_unknown` verification provenance and `legacy_preserved` selection protection; blob retained |
| `Recording.speakerNamesData` | display-name correction/mapping | Imported separately from anonymous clusters/identity |
| retry flags | job/stage state plus compatibility projection | Legacy flags remain updated during dual-write |
| `ProcessingDiagnostics` | `ProcessingDiagnosticsV1` | Persist only redacted/versioned evidence |
| in-memory attempt UUIDs | persisted attempt/job IDs | Same stale-publication principle, now durable |
| `DiarizationSegment` | `SpeakerRegionV1` | Preserve anonymous label and timing; do not invent overlap/confidence |
| `TranscriptMerger` output | draft transcript plus reconciliation/attribution provenance | Current behavior remains a compatibility baseline, not multi-engine consensus |

## 15. Contract acceptance boundary

Approval of this document permits future implementation objectives to use these semantics. It does not authorize a schema change, artifact store, migration, model, profile, cleanup, or production behavior change. Those require their own Critical/High objectives and tests.
