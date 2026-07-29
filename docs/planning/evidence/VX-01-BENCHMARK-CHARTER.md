# VX-01 Private Benchmark Charter

Charter version: `transcriber-private-benchmark-v1`

Approved handling boundary: 2026-07-29

Status: Design approved for future implementation; no dataset or private audio was created or used in VX-01

## 1. Purpose

The benchmark exists to compare the working production pipeline with proposed changes using representative, Human-corrected evidence. It must help reject unnecessary complexity as readily as it supports an improvement.

It does not authorize a model, threshold, dependency, private recording, or production default.

## 2. Privacy and approval policy

1. Audio remains outside Git in a private, user-controlled location.
2. A tracked manifest may contain opaque case IDs and non-identifying condition labels, but never absolute private paths, transcript text, person names, embeddings, or audio.
3. A private local overlay maps opaque case IDs to source locations. The overlay and ground truth are ignored by Git.
4. Daniel must approve each recording or an explicitly bounded collection before it is referenced.
5. Approval records the permitted uses: ground-truth creation, local model comparison, derived clips, enrollment/identity testing, report excerpts, and retention. Unchecked uses are forbidden.
6. Repository audio is not automatically a fixture. `Kelly Creek Dr.m4a` and `test_clip.m4a` remain unapproved and unused.
7. Source audio is read-only. Preparation creates versioned derivatives in private benchmark storage and never replaces the source.
8. Reports use case IDs and aggregate metrics. They omit private paths, transcript content, voice clips, names, and identity scores tied to real names by default.
9. A case can be withdrawn. Withdrawal removes benchmark references and derived benchmark artifacts without deleting the original source.
10. Network processing is forbidden unless a later objective and Human privacy decision explicitly authorize it.

## 3. Versioned manifest contract

The future VX-08 implementation may choose JSON or another deterministic encoding, but it must represent these fields:

```yaml
schema_version: 1
dataset_id: opaque-stable-id
dataset_version: 1
created_at: timestamp
ground_truth_policy_version: 1
cases:
  - case_id: opaque-stable-id
    private_source_ref: key-into-untracked-local-overlay
    source_checksum_ref: value-kept-in-private-overlay
    approval_id: local-approval-record
    approval_scope:
      transcription: true
      diarization: false
      identity: false
      derived_clips: false
    split: calibration | development | held_out
    language_tags: [en]
    condition_tags: [quiet, near_field]
    codec_container: declared-metadata
    channel_count: declared-metadata
    duration_bucket: short | medium | long
    speaker_count_bucket: one | two | three_to_four | unknown
    enrolled_identity_state: not_applicable | enrolled | unenrolled | mixed
    ground_truth_ref: key-into-private-ground-truth-store
    notes_code: optional-non-identifying-code
```

Requirements:

- Stable opaque IDs do not derive from filenames, names, transcript text, or full paths.
- Dataset and ground-truth versions are immutable. A correction creates a new version with provenance.
- The calibration/development/held-out split is assigned before comparing production candidates.
- Exclusions and failed cases remain in the report with a structured reason; they are not silently removed.
- Manifest validation fails closed on unknown schema versions, duplicate IDs, missing approval, or missing private overlay entries.

## 4. Ground-truth rules

### 4.1 Transcript truth

- Preserve what was audibly spoken; do not rewrite for grammar or style.
- Use a documented normalization profile for case, punctuation, numbers, contractions, filled pauses, non-speech events, and partial words.
- Mark inaudible or genuinely uncertain spans explicitly instead of guessing.
- Keep proper names and domain terms in an annotated term list so their errors can be counted separately.
- Record annotator, timestamp, source version, normalization version, and each correction.
- A second review is required for disputed or low-audibility spans used in release decisions.

### 4.2 Timing truth

- Prefer word-level timing where reliable.
- Allow region-level timing when word boundaries cannot be placed honestly.
- Preserve overlap rather than forcing simultaneous speech into one sequence.
- Record timing tolerance used by each metric.

### 4.3 Diarization truth

- Use anonymous reference speaker IDs independent of real names.
- Mark speech regions, overlap, non-speech, uncertain boundaries, and unscorable regions.
- Speaker-count truth comes from annotated audible speakers, not model output.
- Mapping hypothesis clusters to reference speakers is a metric operation and does not rename stored ground truth.

### 4.4 Identity truth

- Identity evaluation requires a separate explicit approval scope.
- Preserve `known`, `unknown`, and `ambiguous` as valid expected outcomes.
- Enrollment and test speech must be separated; the same clip or derived region cannot appear in both.
- Real names are stored only in the private overlay. Reports use profile IDs.
- Similar-voice, insufficient-duration, contaminated, and overlap cases are retained as difficulty labels.

## 5. Metric definitions

No production pass threshold is set in Phase 0.

### Transcription

- `WER = (substitutions + deletions + insertions) / reference words`.
- Report substitutions, deletions, and insertions separately as counts and rates.
- Report proper-name/domain-term exact accuracy against the annotated term list.
- Count hallucination spans: hypothesis words in reference non-speech or unsupported stretches, under a versioned adjudication rule.
- Report uncertainty coverage and the percentage of words/regions requiring Human review.
- Report results per case, condition, split, and aggregate with numerator/denominator counts.

### Diarization and attribution

- Report diarization error components: missed speech, false alarm, and speaker confusion using a declared collar and overlap policy.
- Report speaker-count error, cluster fragmentation, erroneous cluster merges, and overlap handling.
- Report speaker-attributed word accuracy using the same transcript normalization and an explicit time-assignment rule.

### Open-set identity

- Report false known-person identification as the primary safety metric.
- Also report false acceptance, false rejection, correct unknown rejection, ambiguity rate, and coverage.
- Break results down by duration, quality, condition, overlap, enrolled/unenrolled state, and best-versus-second-best margin.
- Never collapse forced nearest-neighbor output into a correct `known` result.

### System and review

- Record wall time by stage and end to end.
- Record peak memory, memory-pressure events, energy/thermal observations, cancellation/failure/recovery, and relaunch recovery on named non-sensitive hardware profiles.
- Record Human correction time and review percentage under a versioned review protocol.
- Compare an ensemble with the best individual component, not only with an older weak baseline.

## 6. Representative categories

The dataset should grow deliberately across:

- quiet near-field speech;
- far-field rooms and reverberation;
- vehicle and field noise;
- television or competing speech;
- speakerphone and compressed audio;
- interruptions and overlapping speech;
- short replies and backchannels;
- one, two, three, and four audible speakers;
- similar voices;
- enrolled, unenrolled, mixed, and insufficient identity evidence;
- names, addresses, technical terms, and uncommon vocabulary;
- clipped, low-level, silent, and partially corrupted inputs;
- short routine cases and long-run recordings.

Categories are selection targets, not an assertion that currently available private recordings cover them.

## 7. Comparison protocol

1. Freeze dataset, ground-truth, normalization, preparation, model/runtime, pipeline, and calibration versions.
2. Run candidates on equivalent prepared audio.
3. Preserve raw outputs and failures.
4. Develop rules on calibration/development cases only.
5. Evaluate the final proposal once on held-out cases before a production gate.
6. Report per-condition results, exclusions, failures, resource costs, and uncertainty—not just one aggregate score.
7. Reject a more complex stage when it does not materially outperform the strongest simpler option under Human-approved priorities.

## 8. Human decisions intentionally deferred

- Supported minimum Mac and memory configuration.
- Exact private recordings or bounded collections.
- Error-priority trade-offs and production thresholds after the current baseline is measured.
- Whether identity-specific dataset use is ever approved.

## 9. VX-01 acceptance

This charter is accepted for Phase 0 under Daniel’s explicit instruction that private audio not be used. Implementing it belongs to VX-08, and selecting thresholds belongs to VX-09. Any future access to private audio still requires the approvals above.
