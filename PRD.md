# PRD.md — Transcriber for Mac, Accuracy Expansion

Last updated: 2026-07-28

## 1. Product definition

Transcriber is a native Mac application that records or imports audio, preserves the original recording, creates a usable transcript, applies speaker labels, and lets the user review, correct, play, and export the result.

The next product stage is an accuracy-first expansion informed by [VoxBot Expanded PLN.md](VoxBot%20Expanded%20PLN.md). It strengthens the existing application rather than replacing it. The working application in `src/native/Transcriber2/` is the baseline; new processing capabilities must attach to that baseline incrementally and remain removable.

“VoxBot” describes the expanded processing direction: multiple transcription candidates, stronger diarization, optional known-speaker identification, deterministic reconciliation, focused human review, and benchmark-driven decisions. It is not yet an approved application rename. The shipped app remains Transcriber until Daniel explicitly chooses otherwise.

## 2. Current product baseline

The current Mac app already provides valuable, tested infrastructure:

- Native SwiftUI Dashboard, Library, Model Lab, and Settings surfaces.
- Microphone recording and audio-file import.
- Original-audio storage under `Application Support/Transcriber2Beta/Recordings/`.
- SwiftData recording metadata and JSON-backed transcript data.
- Actor-based WhisperKit transcription and FluidAudio diarization engines.
- A `TranscriptionSession` state machine with cancellation, retry, fallback, diagnostics, and persist-then-proceed behavior.
- A draft transcript that remains available if speaker labeling fails.
- Library playback, speaker renaming, segment reassignment, and TXT/SRT/JSON export.
- Model readiness, repair/redownload, launch preparation, and Model Lab comparisons.
- Unit coverage for persistence, cancellation, failure injection, model readiness, recording reliability, transcript merging, exports, and core UI presentation logic.

This baseline is the product’s solid core. New work must preserve it or replace a component only after the replacement has passed equivalent safety and quality gates.

## 3. Product goals

### 3.1 Primary goals

1. Produce materially more accurate transcripts than the current single-final-model pipeline on representative recordings.
2. Improve speaker attribution while treating anonymous or uncertain identity as a valid result.
3. Preserve original audio, confirmed transcript text, corrections, profiles, and decision provenance.
4. Keep processing local on the Mac by default.
5. Make every important automated decision reviewable and reversible.
6. Allow transcription, diarization, voiceprint, reconciliation, and adjudication components to evolve independently.
7. Continue providing a useful transcript when an optional model or downstream stage fails.

### 3.2 Success measures

Exact production thresholds will be set from a representative private benchmark dataset. The product must measure at least:

- Word error rate and insertion/deletion/substitution rates.
- Proper-name and domain-vocabulary accuracy.
- Hallucination frequency.
- Speaker-attributed word accuracy.
- Diarization error, speaker-count errors, cluster fragmentation, and overlap handling.
- False known-speaker identification, false acceptance, false rejection, and unknown-speaker rejection.
- Percentage of a transcript requiring human review.
- Total processing time, peak memory, thermal behavior, failure recovery, and reprocessing reliability.

No ensemble, model, fallback, or AI stage becomes the production default merely because it is sophisticated. It must demonstrate a meaningful benefit over the best simpler alternative.

## 4. Product principles

1. **Strengthen, do not restart.** Reuse reliable recording, import, persistence, playback, review, export, diagnostics, and failure-handling paths.
2. **Original audio is the source of truth.** Derived audio may be regenerated; the source recording is never destructively replaced.
3. **Draft first, verified later.** A useful draft may appear before all accuracy and speaker stages finish.
4. **Unknown is better than wrong.** The app must not force a word, speaker cluster, or person identity merely because one candidate ranks first.
5. **Evidence before architecture.** Benchmarks and feasibility work decide which proposed models and runtimes enter production.
6. **Local by default.** Audio, transcripts, speaker profiles, embeddings, and corrections remain on the Mac unless the user explicitly exports them.
7. **Persist before proceeding.** A completed stage writes a recoverable result before a dependent stage begins.
8. **Partial success remains useful.** Failure in a secondary transcription engine, diarizer, voiceprint model, or adjudicator does not erase successful upstream work.
9. **Version everything that changes meaning.** Processing artifacts record their model, runtime, preprocessing, calibration, and schema versions.
10. **Components remain replaceable.** Engines communicate through normalized result contracts rather than reaching into each other’s internal types.

## 5. Target user and use cases

The primary user is Daniel on an Apple Silicon Mac with enough unified memory for accuracy-focused local processing.

Primary uses:

- Meetings, interviews, and conversations with two to four speakers.
- Building walkthroughs and field recordings.
- Imported Voice Memos and other audio files.
- Recordings containing names, addresses, technical terms, interruptions, and background noise.
- Reprocessing older recordings after better models or calibration become available.

Secondary uses:

- Single-speaker lectures and notes.
- Benchmarking transcription and speaker systems.
- Building a private set of enrolled speakers for transcript labeling.

## 6. Scope boundaries

### 6.1 In scope

- macOS application behavior in `src/native/Transcriber2/`.
- Local recording, importing, processing, review, playback, and export.
- Versioned audio derivatives and processing artifacts.
- Multiple transcription candidates when benchmark evidence supports them.
- Strong local diarization and open-set speaker identification.
- Human correction and controlled reuse of confirmed corrections.
- Optional constrained adjudication of disputed regions.
- Persistent, recoverable background processing appropriate to macOS.

### 6.2 Out of scope for the first production-ready accuracy expansion

- iPhone or iPad implementation; that belongs in `../iOS Transcriber/`.
- Cloud transcription as a required path.
- Security authentication or authorization based on a voiceprint.
- Silent training or enrollment from conversations.
- Free-form AI rewriting, summarization, or invention of dialogue.
- Identification across a large public population.
- Destructive replacement of historical transcripts when models or thresholds change.
- A full rewrite of the SwiftUI application or storage system.

## 7. Product architecture

The target architecture contains separable workstreams:

```text
Original Audio
      |
      v
Prepared Audio + Quality Analysis
      |
      +----------------+----------------+----------------+
      |                |                |                |
      v                v                v                v
Transcriber A     Transcriber B     Diarization     Draft Transcript
      |                |                |
      +---------> Normalized, Versioned Results <-------+
                               |
                               v
                Deterministic Reconciliation
                               |
                               v
                  Optional Voice Identification
                               |
                               v
                 Reviewable Attributed Transcript
                               |
                               v
             Targeted Reprocessing / Adjudication
                               |
                               v
                    Verified Transcript Version
```

The existing `TranscriptionSession` remains the behavior baseline while orchestration responsibilities are extracted gradually behind tested seams. A “cleaner architecture” is not sufficient reason to change behavior or weaken failure recovery.

## 8. Functional requirements

### 8.1 Recording and import

- Recording begins without waiting for an accuracy model to load.
- Imported audio is copied into application-owned storage before processing.
- Original recordings remain readable throughout migrations and retries.
- A recording can be played, exported, or deleted only through an explicit user action.
- A failed import or save must not produce a false success state.

### 8.2 Audio preparation

- Preserve the original channel layout and format.
- Produce versioned working derivatives, normally including mono 16 kHz audio.
- Measure duration, channel layout, clipping, speech activity, silence, level, and other quality signals that prove useful.
- Treat denoising and source separation as alternate derivatives, not automatic replacements.
- Supply equivalent prepared audio to models being compared.
- Record the preprocessing version and inputs for every generated derivative.

### 8.3 Transcription

- Every transcription engine implements a normalized, versioned result contract.
- Normalized results support timed words or the most precise timed units the engine exposes.
- Raw provider output remains available for inspection and future reprocessing.
- A primary result can produce a draft without waiting for all secondary work.
- Failure of a secondary engine does not invalidate a successful draft.
- Whisper Large v3 and Parakeet TDT are candidates from the VoxBot reference plan, not unconditional production requirements. Each requires a Mac feasibility, licensing, packaging, resource, and benchmark gate.

### 8.4 Transcript reconciliation

- Align candidates by time and token/word sequence.
- Accept exact or materially equivalent agreement deterministically.
- Preserve disagreements as structured evidence.
- Avoid whole-transcript generative rewriting.
- Extract and reprocess only disputed regions when possible.
- Mark unresolved material as uncertain or requiring review.
- Apply punctuation and readability formatting after factual word selection.

### 8.5 Diarization

- Diarization remains independent from transcription and known-speaker identification.
- Preserve anonymous temporary cluster labels even after a person identity is assigned.
- Store boundaries, overlap information, confidence/quality signals when available, engine version, and raw output.
- Preserve the transcript if diarization fails, times out, or is canceled.
- The current FluidAudio Sortformer path remains the production baseline until a measured replacement is safer and more accurate.
- Pyannote is a candidate requiring explicit runtime, sandbox, licensing, packaging, privacy, and benchmark approval before integration.

### 8.6 Voiceprint identification

- Voiceprints label transcripts; they do not authenticate people.
- Profiles use stable identifiers, display names, multiple approved enrollment samples, quality metadata, and versioned model embeddings.
- Identity output has exactly three semantic outcomes: `known`, `unknown`, or `ambiguous`.
- A nearest candidate is not accepted unless absolute evidence and separation from alternatives pass calibrated thresholds.
- Evidence is aggregated across suitable segments in a temporary speaker cluster.
- Poor, short, overlapping, clipped, or contaminated segments are rejected or deferred.
- ERes2NetV2, ReDimNet2, and w2v-BERT 2.0 are proposed candidates. They enter production only after local Mac feasibility and false-identification benchmarks.
- Enrollment from ordinary recordings requires explicit user confirmation.
- Profile deletion removes protected profile data and retained enrollment audio according to a documented, tested policy.

### 8.7 Human review

The review experience should focus attention on uncertainty:

- Transcription disagreements and low-confidence words.
- Proper names and technical terms needing confirmation.
- Overlapping or poor-quality regions.
- Ambiguous identities and conflicting cluster evidence.
- Regions where all available systems performed poorly.

The user can:

- Edit transcript text.
- Select or reject a candidate.
- Mark a region uncertain.
- Rename an anonymous speaker.
- Confirm or reject an identity suggestion.
- Merge or split speaker clusters.
- Reassign individual segments.
- Reprocess a selected region or the full recording.
- Add a confirmed clean segment to a profile through an explicit workflow.

Historical verified transcript versions do not silently change after a new correction, model, profile, or calibration version is introduced.

### 8.8 Processing states and recovery

The UI distinguishes at least:

- Recorded or imported.
- Preparing audio.
- Creating draft transcript.
- Draft ready.
- Running additional transcription.
- Running diarization.
- Reconciling.
- Identifying speakers.
- Resolving disputed regions.
- Needs review.
- Verified result ready.
- Partial result or retry required.

Progress is reported by workstream rather than one misleading overall percentage. Processing may continue while the user reviews other recordings. Relaunch recovery must never claim a stage completed unless a persisted result proves it.

### 8.9 Storage and provenance

The product stores, as appropriate:

- Original audio and versioned derivatives.
- Quality analysis.
- Raw and normalized engine outputs.
- Draft and verified transcript versions.
- Diarization output and reconciled clusters.
- Identity hypotheses and decisions.
- Human corrections.
- Model, runtime, preprocessing, pipeline, schema, and calibration versions.
- Processing timing, resource use, failures, fallbacks, and cancellation state.

New storage is additive and versioned. Existing `Recording` rows, audio, and transcripts remain readable. Large or replaceable artifacts should use an application-owned artifact store rather than continually expanding opaque SwiftData blobs.

### 8.10 Model Lab and benchmarks

Model Lab becomes the evidence center for:

- Running comparable pipelines on the same source and prepared audio.
- Capturing quality, timing, memory, failure, and version information.
- Comparing an ensemble against each individual component.
- Exporting reproducible reports without exporting private audio by default.
- Recording human-corrected ground truth.
- Detecting regressions before model, threshold, or pipeline changes ship.

The private benchmark set should represent quiet rooms, distance, vehicles, television, reverberation, speakerphone audio, interruptions, overlap, short replies, similar voices, names, technical vocabulary, compressed files, and both enrolled and unenrolled speakers.

## 9. Non-functional requirements

### 9.1 Data safety

- No automated failure path deletes or overwrites original audio.
- Transcript and profile migrations have round-trip, old-version, corrupt-data, and rollback tests.
- A model or stage retry cannot overwrite a newer user correction or processing attempt.

### 9.2 Privacy and security

- Processing is local by default.
- Network use is explicit and attributable to model download or a separately approved optional service.
- Voiceprint profiles and enrollment audio receive stronger protection and deletion testing than disposable caches.
- Diagnostic exports redact private paths and do not include audio unless selected.

### 9.3 Reliability

- Strict Swift concurrency remains enabled.
- Cancellation leaves the last persisted useful result intact.
- Resource-pressure handling favors reliability over maximum concurrency.
- A model update is a separately validated change, not a casual dependency bump.

### 9.4 Accessibility

- Core workflows support keyboard navigation, VoiceOver, Dynamic Type where applicable on macOS, sufficient contrast, and status text that does not rely on color alone.

## 10. Production acceptance

The production-ready accuracy expansion must:

- Preserve and successfully open existing recordings and transcripts.
- Pass the Mac build and unit-test baseline.
- Record, import, transcribe, review, play, and export without requiring an optional ensemble stage.
- Recover useful partial results after cancellation, failure, or relaunch.
- Demonstrate on the approved benchmark that the selected production pipeline improves meaningful accuracy over the current baseline.
- Keep false known-person identification below the Human-approved operating threshold.
- Provide known, unknown, and ambiguous identity outcomes if voice identification ships.
- Preserve temporary speaker labels and all decision provenance.
- Allow corrections and reprocessing without silently changing prior verified results.
- Pass licensing, packaging, privacy, migration, and deletion reviews for every included model and data type.
- Complete Human-owned real-audio, long-run, resource-pressure, accessibility, and release acceptance.

## 11. Source of truth and change control

- This PRD defines the product target.
- [PLAN.md](PLAN.md) sequences delivery.
- [OBJECTIVE.md](OBJECTIVE.md) is the only active implementation scope.
- [DECISIONS.md](DECISIONS.md) records approved non-obvious choices.
- [AGENTS.md](AGENTS.md) defines execution rules and gates.
- [VoxBot Expanded PLN.md](VoxBot%20Expanded%20PLN.md) and [Voiceprint PLN.md](Voiceprint%20PLN.md) are design references, not implementation authority.

When the reference plans, this PRD, and current code disagree, preserve user data and the working app, record the conflict, and resolve it through a scoped objective and Human decision.
