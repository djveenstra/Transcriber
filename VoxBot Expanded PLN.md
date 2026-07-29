# VoxBot Accuracy-First Mac Transformation Plan

## 1. Purpose

VoxBot will transform the existing Transcriber 2.0 application into a Mac-only transcription system that prioritizes accuracy, speaker attribution, and repeatable results over processing speed, application size, or minimal memory use.

The existing application structure should be retained wherever it already provides reliable recording, importing, playback, transcript editing, storage, job recovery, and export. This plan describes the new processing architecture and product behavior that should be merged into that structure.

VoxBot will combine:

- Multiple transcription models
- High-quality speaker diarization
- Persistent voiceprint identification
- Deterministic transcript reconciliation
- Targeted AI-assisted adjudication
- Human correction and controlled learning
- Extensive benchmarking and decision provenance

Voiceprint identification is one part of this larger system. It consumes diarized speaker segments and returns a known speaker, unknown speaker, or ambiguous result; it does not replace transcription, diarization, preprocessing, reconciliation, or review.

---

## 2. Product Direction

VoxBot will be designed around the following priorities:

1. **Accuracy over speed.** Processing may take longer than the recording itself when that produces a meaningfully more accurate result.
2. **Mac-only optimization.** The architecture should use the available CPU, GPU, Neural Engine, and unified memory without inheriting former iPhone constraints.
3. **Local processing by default.** Audio, transcripts, voiceprints, and identity profiles should remain on the Mac unless the user explicitly exports them.
4. **Original audio is the source of truth.** Every result must be reproducible from the preserved recording.
5. **Unknown is better than wrong.** VoxBot should never force a transcription choice or speaker identity simply because one candidate is closest.
6. **Every important decision remains reviewable.** Model outputs, confidence evidence, corrections, and processing versions should be retained.
7. **Components remain replaceable.** Transcription, diarization, voiceprint, reconciliation, and AI layers must communicate through shared result formats rather than being tightly coupled.

VoxBot is not initially intended to provide real-time transcription, mobile processing, security-grade voice authentication, or identification across thousands of people.

---

## 3. High-Level Architecture

The application should contain seven conceptually separate processing systems:

```text
Original Audio
      ↓
Audio Preparation and Quality Analysis
      ↓
┌─────────────────────┬─────────────────────┬─────────────────────┐
│ Whisper Transcriber │ Parakeet Transcriber│ Diarization Engine  │
└─────────────────────┴─────────────────────┴─────────────────────┘
      ↓                         ↓                         ↓
      └──────── Transcription and Timing Reconciliation ─┘
                                ↓
                    Voiceprint Identification
                                ↓
                    Speaker-Attributed Transcript
                                ↓
                 AI Adjudication of Disputed Regions
                                ↓
                    Verified Transcript and Review
```

Each subsystem should produce structured results that can be stored, inspected, reprocessed, and compared independently.

A failed secondary model must not invalidate a successful primary transcript. A diarization failure must not destroy the transcription. A voiceprint failure must leave anonymous speaker labels rather than blocking the final result.

---

## 4. Audio Preparation

VoxBot should preserve the original imported or recorded audio without destructive modification.

From the original, it should create versioned working derivatives suitable for transcription, diarization, and voiceprint extraction. The standard processing representation will normally be mono, 16 kHz audio, while the original channel layout should remain available when stereo or multichannel information may help separate speakers.

Audio preparation should measure:

- Duration and channel layout
- Clipping
- Silence and speech activity
- Background noise
- Reverberation
- Average speech level
- Suspected overlapping speech
- Recording or compression quality
- Possible television, speakerphone, or playback contamination

Noise reduction and source separation should not automatically replace the normal working audio. These processes can introduce artifacts that make speech recognition or speaker identification worse. They should initially be used only for difficult regions and retained as alternate derivatives.

The same prepared audio and preprocessing version must be supplied consistently to the models being compared.

---

## 5. Parallel Transcription

The initial transcription ensemble should use two architecturally different systems:

- **Whisper Large v3**, through an Apple Silicon-compatible runtime such as WhisperKit
- **Parakeet TDT**, through FluidAudio or another validated Mac-compatible runtime

These models should run concurrently when hardware conditions permit.

The scheduler should treat concurrency as the default on the target 32 GB Apple Silicon Mac. It should monitor memory pressure, thermal conditions, failures, and runtime performance rather than imposing the sequential behavior inherited from the iPhone design.

The system should benchmark several compute arrangements, including different GPU and Neural Engine assignments. The chosen configuration should maximize reliability and accuracy while keeping processing time reasonable.

Each transcription engine must return a normalized representation containing:

- Words or tokens
- Start and end timestamps
- Segment boundaries
- Model confidence where available
- Language information
- Alternative candidates where available
- Model and preprocessing versions

The original raw result from every engine should also be retained.

---

## 6. Transcript Reconciliation

VoxBot should not ask a language model to read two complete transcripts and freely rewrite them into a third transcript. That approach rewards linguistic plausibility rather than acoustic truth and can create convincing hallucinations.

Reconciliation should proceed in stages.

### 6.1 Alignment

The two transcripts should first be aligned by timestamps and word sequence. The reconciliation layer should identify:

- Exact agreement
- Minor formatting or punctuation differences
- Phonetically similar alternatives
- Missing words
- Added words
- Timing disagreements
- Longer regions where alignment breaks down

### 6.2 Automatic Consensus

Regions where both models agree should be accepted with high confidence.

Where one model produces a word and the other produces nothing, the system should consider timing, surrounding agreement, confidence, speech activity, and acoustic duration before accepting the word.

Proper names, technical terms, addresses, and uncommon vocabulary should receive additional scrutiny. A user-maintained vocabulary or contact glossary may help rank candidates, but it must not force words unsupported by the audio.

### 6.3 Targeted Reprocessing

Material disagreements should trigger extraction of a short audio window containing additional context before and after the disputed region.

That window may be:

- Reprocessed with alternate decoding settings
- Reprocessed using a longer context window
- Reprocessed using an enhanced audio derivative
- Submitted to an optional third transcription model
- Presented to an audio-capable adjudication model

The system should reprocess only disputed regions rather than repeatedly transcribing the entire recording.

### 6.4 Constrained AI Adjudication

AI should act as a controlled referee, not a transcript author.

For each unresolved region, it may receive:

- The disputed audio clip, when supported
- Candidate words from each transcription model
- Surrounding accepted transcript context
- Timing and confidence information
- Known names and vocabulary
- Speaker identity hypotheses

The AI should be required to:

- Select an existing candidate
- Combine candidates only when explicitly supported
- Mark a region uncertain
- Request human review

It should not be allowed to freely paraphrase, summarize, or invent missing dialogue.

Punctuation, paragraphing, capitalization, and readability formatting should occur only after the factual word sequence has been established.

---

## 7. Speaker Diarization

The initial diarization engine should be Pyannote Community-1 or the strongest validated local Pyannote-compatible pipeline available during implementation.

Its responsibilities are:

- Detect speech regions
- Identify speaker changes
- Group turns into temporary speaker clusters
- Detect overlapping speech
- Produce speaker timelines
- Indicate segment quality and isolation where possible

The initial labels should remain anonymous, such as `Speaker 1`, `Speaker 2`, and `Speaker 3`.

Diarization must remain separate from voiceprint identification. The diarizer answers, "Which portions sound like the same temporary speaker?" The voiceprint subsystem answers, "Does that temporary speaker appear to be a person already enrolled?"

VoxBot should initially use one strong diarization system rather than immediately combining several. A second diarization model should be added only if controlled testing shows that it materially improves speaker-attributed transcription.

When two diarization systems are eventually tested, reconciliation should consider speaker boundaries, overlap detection, cluster consistency, and voiceprint evidence. Voiceprint similarity may support a clustering decision, but it must not automatically override strong acoustic or timing evidence.

---

## 8. Voiceprint Identification

Voiceprint identification is a core VoxBot subsystem and must be included in the architecture, storage model, benchmark harness, and user interface from the beginning.

### 8.1 Model Architecture

The voiceprint subsystem will use:

- **ERes2NetV2** as the primary short-utterance recognition model
- **ReDimNet2** as an independent second model
- **w2v-BERT 2.0** as an accuracy-focused fallback for difficult or disputed cases

ERes2NetV2 and ReDimNet2 should process suitable speaker material routinely. w2v-BERT 2.0 should run only when the two primary models disagree, scores are near an acceptance threshold, the leading candidates are close, or additional evidence is needed.

### 8.2 Voiceprint Processing Flow

For each diarized speaker cluster:

1. Identify clean, non-overlapping speech segments.
2. Exclude or defer segments that are too short, clipped, noisy, or contaminated.
3. Generate ERes2NetV2 embeddings.
4. Generate ReDimNet2 embeddings.
5. Compare each embedding against enrolled profiles from the corresponding model.
6. Calibrate each model's similarity scores.
7. Combine the calibrated evidence.
8. Evaluate the best candidate, second-best candidate, score margin, segment quality, and model agreement.
9. Accumulate evidence across multiple segments assigned to the same temporary speaker.
10. Escalate uncertain cases to w2v-BERT 2.0.
11. Return a structured known, unknown, or ambiguous result.

The system must never assign someone's name merely because that person is the closest match. The candidate must pass an absolute acceptance threshold and maintain sufficient separation from competing candidates.

### 8.3 Identification States

Every speaker identity decision must resolve to one of three states:

**Known**

The evidence is strong enough to assign an enrolled person.

**Unknown**

No enrolled person satisfies the acceptance requirements. Unknown is a successful and valid outcome.

**Ambiguous**

One or more enrolled people are plausible, but the evidence is insufficient for a reliable assignment.

An ambiguous result may become known later as more speech is accumulated. It may also remain unnamed or be presented for confirmation.

### 8.4 Multi-Segment Evidence

Speaker identity should normally be determined at the diarized-cluster level rather than independently naming every short utterance.

VoxBot should gather evidence across the conversation. A speaker may remain ambiguous after the first few turns and become known after additional clean speech is available.

Contradictory voiceprint results may indicate that the diarizer accidentally combined two people. Repeated contradictions should therefore trigger a cluster review or possible re-segmentation rather than simply changing the assigned name.

---

## 9. Speaker Enrollment and Profiles

Enrollment should use multiple recordings rather than one short voice sample.

The application should encourage natural examples collected across different:

- Days
- Speaking volumes
- Microphone distances
- Rooms
- Microphones
- Emotional or physical states
- Recording conditions

Every sample must pass minimum speech-duration and quality requirements.

A speaker profile should conceptually retain:

- Stable speaker identifier
- Display name
- Multiple enrollment samples
- Embeddings from every supported model
- Model and preprocessing versions
- Source and microphone metadata
- Quality measurements
- Confirmed matches
- Confirmed mismatches
- User corrections
- Profile and calibration version

Multiple embeddings should remain available instead of immediately collapsing everything into one averaged vector. This allows VoxBot to represent natural variation and later identify poor or misleading enrollment samples.

Confirmed clean segments from normal conversations may be offered as additional enrollment material. They should not be silently added without approval during the first production phases.

A model upgrade must not silently reinterpret embeddings created by an older model. VoxBot should either regenerate embeddings from retained enrollment clips or continue using the versioned model associated with the older vectors.

---

## 10. Voiceprint Calibration and Fusion

Raw similarity values from different embedding models are not directly comparable and must not simply be averaged.

Each model should be calibrated using recordings representative of the user's actual conversations. Fusion should consider:

- Individual model scores
- Best-versus-second-best score margin
- Segment duration
- Audio quality
- Model agreement
- Consistency across several turns
- Microphone and channel conditions
- Enrollment coverage
- Earlier confirmed evidence from the same recording

A transparent statistical method such as calibrated logistic regression should be preferred initially. More complicated methods should be adopted only when they produce measurable gains.

A language model must not compare raw voice embeddings or make primary identity decisions.

The operating point should strongly favor avoiding false names. A higher number of unknown or ambiguous results is acceptable when it substantially reduces incorrect identification.

---

## 11. Combining Diarization, Voiceprints, and Transcription

The final speaker-attributed transcript should be produced by a reconciliation stage that combines:

- Word timestamps
- Diarization boundaries
- Overlap information
- Temporary speaker clusters
- Voiceprint identity hypotheses
- Identity confidence
- Transcription agreement
- Human corrections

The original temporary diarization label should always remain stored alongside the resolved identity.

For example:

```text
Temporary cluster: Speaker 2
Resolved identity: Sarah
Identity state: Known
Identity confidence: High
Voiceprint models: ERes2NetV2 + ReDimNet2
Fallback used: No
```

This preserves auditability and allows the transcript to be reprocessed when a diarization, identity, or model improvement becomes available.

Voiceprint evidence may help determine that two temporary clusters belong to the same known person. It may also reveal that one temporary cluster contains conflicting identities. These results should be recommendations to the reconciliation layer rather than silent destructive changes.

---

## 12. Human Review

VoxBot should focus human attention on uncertainty instead of requiring the user to reread the entire transcript.

The review interface should surface:

- Transcription disagreements
- Low-confidence words
- Possible hallucinations
- Unresolved proper names
- Ambiguous speaker identities
- Speaker clusters with conflicting voiceprint evidence
- Overlapping-speech regions
- Segments where all models performed poorly

Users should be able to:

- Correct transcript text
- Confirm or reject a transcription candidate
- Name an unknown speaker
- Confirm or reject a suggested identity
- Merge two speaker clusters
- Split a cluster containing multiple people
- Add a clean segment to an enrollment profile
- Exclude a poor sample from a profile
- Reprocess a selected region
- Reprocess the entire recording with a newer pipeline

Corrections should become labeled benchmark data. They may update speaker profiles or future calibration through controlled workflows, but they must not trigger uncontrolled retraining.

Historical transcripts should not silently change when a profile or threshold changes.

---

## 13. Processing States and User Experience

VoxBot should distinguish between a usable draft and a fully reconciled result.

Suggested recording states are:

```text
Imported or Recorded
Preparing Audio
Running Transcription
Running Diarization
Draft Transcript Ready
Reconciling Transcripts
Identifying Speakers
Resolving Difficult Regions
Verified Transcript Ready
Needs Review
Failed or Partially Completed
```

A draft transcript may become available as soon as the primary transcription result finishes. The verified transcript should represent the completed ensemble, diarization, voiceprint, and reconciliation pipeline.

Processing should continue in the background while the user views, edits, or exports other recordings.

Progress should be reported by workstream rather than as one misleading percentage.

---

## 14. Storage and Provenance

VoxBot should preserve enough information to reproduce and explain every result.

Conceptually, the stored record should include:

- Original audio
- Prepared audio derivatives
- Audio quality analysis
- Raw output from each transcription model
- Consensus transcript
- Disputed-region candidates
- Raw diarization output
- Reconciled speaker clusters
- Voiceprint embeddings
- Identity hypotheses
- Final identity decisions
- Human corrections
- Model and runtime versions
- Preprocessing version
- Calibration and threshold versions
- Pipeline configuration
- Processing time and resource use

Caches may be regenerated, but user audio, confirmed transcripts, speaker profiles, corrections, and important provenance should be treated as persistent data.

Speaker profiles and embeddings should be protected locally. The application should support profile deletion, data export, and removal of retained enrollment audio.

Voiceprints are for transcript labeling, not authentication. Replay detection, deepfake detection, and authorization based on voice should remain deferred.

---

## 15. Benchmark and Model Lab

The existing Model Lab concept should become a central VoxBot capability.

A representative private evaluation dataset should be created from real intended use conditions, including:

- Quiet conversations
- Far-field conversations
- Moving vehicles
- Background television
- Reverberant rooms
- Speakerphone audio
- Interruptions and overlapping speech
- Short responses
- Similar-sounding speakers
- Proper names and technical vocabulary
- Compressed imported recordings
- Enrolled and unenrolled speakers

Ground truth should include both the correct words and the correct speaker for each region.

### 15.1 Transcription Metrics

Measure:

- Word error rate
- Insertions, deletions, and substitutions
- Proper-name accuracy
- Hallucination frequency
- Accuracy by recording condition
- Accuracy by speaker
- Accuracy by utterance length
- Percentage of transcript requiring review

Compare:

- Whisper alone
- Parakeet alone
- Automatic consensus
- Consensus plus targeted retranscription
- Consensus plus constrained AI adjudication

The ensemble should only become the default if it consistently outperforms the best individual model.

### 15.2 Diarization Metrics

Measure:

- Diarization error rate
- Missed speaker changes
- Incorrect speaker changes
- Speaker-count errors
- Overlap accuracy
- Cluster fragmentation
- Accidental merging of different speakers
- Speaker-attributed word accuracy

### 15.3 Voiceprint Metrics

Measure:

- False acceptance
- False rejection
- False identification
- Unknown-speaker rejection
- Ambiguous-result frequency
- Top-one identification accuracy
- Best-versus-second-best margin
- Accuracy by segment duration
- Accuracy by microphone and noise condition
- Frequency of w2v-BERT escalation
- Accuracy gained from escalation
- Peak memory and processing time

The most important voiceprint metric is the frequency with which VoxBot confidently assigns the wrong known person.

### 15.4 System Metrics

Also measure:

- Total processing time
- Peak unified-memory use
- Performance under parallel workloads
- Thermal effects
- Crash recovery
- Partial-result recovery
- Reprocessing reliability
- Time required for human correction

No model, ensemble, fallback, or AI stage should remain in the production pipeline merely because it sounds sophisticated. It must provide a measurable benefit on representative recordings.

---

## 16. Delivery Phases

### Phase 1: Existing-App Assessment and Pipeline Contracts

- Identify the stable Transcriber 2.0 components to retain.
- Remove iPhone-first product and scheduling assumptions.
- Define normalized contracts for audio, transcription, diarization, identity, and reconciliation results.
- Establish additive and versioned storage changes.
- Create the initial benchmark dataset.
- Define the first speaker-profile and voiceprint records.

Voiceprint architecture begins in this phase and is not deferred.

### Phase 2: Mac Accuracy Baseline

- Integrate Whisper Large v3.
- Integrate Parakeet TDT.
- Integrate the initial Pyannote diarization pipeline.
- Run transcription and diarization concurrently.
- Store raw results and processing diagnostics.
- Produce a basic speaker-attributed draft using anonymous labels.
- Benchmark individual model quality and Mac resource usage.

### Phase 3: Voiceprint Foundation

- Integrate ERes2NetV2.
- Build enrollment and speaker-profile management.
- Generate versioned embeddings.
- Implement known-versus-unknown matching.
- Connect voiceprint extraction to clean diarized segments.
- Add basic identity confirmation and correction.
- Establish baseline false-identification performance.

### Phase 4: Transcript Consensus and Dual-Model Voiceprints

- Implement word- and timestamp-level transcript alignment.
- Add deterministic consensus rules.
- Integrate ReDimNet2.
- Calibrate scores independently.
- Fuse the two voiceprint models.
- Add known, unknown, and ambiguous states.
- Aggregate identity evidence across speaker clusters.
- Compare ensemble results against each individual model.

### Phase 5: Difficult-Region Reprocessing

- Detect transcription disagreements.
- Extract and reprocess disputed audio windows.
- Test alternate audio derivatives and decoding settings.
- Add constrained AI adjudication.
- Validate w2v-BERT 2.0 on Apple Silicon.
- Add voiceprint fallback escalation when it produces measurable gains.
- Cache expensive fallback results.

### Phase 6: Full Reconciliation and Review Workflow

- Combine transcript, diarization, and identity evidence.
- Add cluster merge, split, rename, and conflict workflows.
- Surface uncertain transcript and speaker regions.
- Add controlled enrollment from confirmed conversation segments.
- Convert corrections into benchmark cases.
- Preserve complete decision provenance.

### Phase 7: Hardening and Packaging

- Optimize the parallel job scheduler for the target Mac.
- Add interruption, cancellation, and recovery handling.
- Complete model and weight licensing review.
- Protect stored voiceprint information.
- Add migration and corruption testing.
- Validate model packaging and installation.
- Establish regression benchmarks for every future model update.

---

## 17. Acceptance Criteria

The first production-ready VoxBot version should:

- Run locally on the supported Apple Silicon Mac
- Preserve original audio and all important results
- Run two transcription engines concurrently when resources allow
- Demonstrate that transcript consensus outperforms the best individual model
- Produce timestamped, editable transcripts
- Diarize normal conversations with anonymous temporary speakers
- Enroll multiple known people using multiple samples
- Process voiceprints with ERes2NetV2 and ReDimNet2
- Return known, unknown, or ambiguous identity states
- Use calibrated voiceprint fusion
- Avoid forced nearest-person identification
- Escalate selected identity cases to w2v-BERT when beneficial
- Accumulate identity evidence across multiple turns
- Preserve both temporary speaker labels and resolved identities
- Identify and surface conflicts between diarization and voiceprint evidence
- Use AI only for constrained transcript adjudication
- Permit transcript and speaker corrections
- Record model versions, confidence evidence, and decision provenance
- Recover gracefully when an individual model fails
- Reprocess recordings after model or calibration updates
- Pass a representative real-world benchmark
- Produce materially fewer transcription and speaker-attribution errors than the existing Transcriber 2.0 pipeline

Exact numerical thresholds should be selected from the benchmark dataset rather than invented in advance.

---

## 18. Guidance for Merging with Transcriber 2.0

The merge agent should preserve stable application infrastructure rather than treating VoxBot as a complete rewrite.

Likely reusable areas include:

- Recording and importing
- Audio-library organization
- Playback
- Transcript editing
- Export and sharing
- Background job persistence
- Cancellation and retry handling
- Existing diagnostics and Model Lab concepts

The largest conceptual changes are:

- Mac becomes the only target.
- Accuracy becomes the primary optimization objective.
- Multiple models run concurrently.
- Every model produces normalized, versioned results.
- The transcript has draft and verified states.
- Diarization becomes independent from transcription.
- Persistent voiceprint profiles become a first-class data type.
- Speaker identification uses dual models and open-set rejection.
- Reconciliation becomes a dedicated pipeline stage.
- AI is constrained to disputed transcript regions.
- Benchmarks and human corrections directly govern future model decisions.

Schema changes should be additive and versioned. Existing recordings and transcripts should remain readable. New processing capabilities should attach additional result objects rather than destructively replacing the original recording or transcript.

The final architecture should allow any transcription, diarization, voiceprint, or AI component to be replaced without redesigning the rest of the application.
