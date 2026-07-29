# Voiceprint Identification Workstream

## Role in the Larger Plan

Voiceprint identification is one component of the broader effort to improve the transcription application’s accuracy, reliability, and usefulness. It does not replace transcription, diarization, audio preprocessing, transcript reconciliation, or human correction workflows.

This workstream is responsible for determining whether a diarized speaker segment belongs to a previously enrolled person. It will consume speaker segments produced by the diarization pipeline and return a known speaker, an unknown speaker, or an ambiguous result.

The larger application plan must separately address:

- Audio preprocessing and source separation
- Speech-to-text model selection and transcription consensus
- Speaker diarization and overlap detection
- Transcript comparison and reconciliation
- Confidence scoring and human review
- Application performance, storage, interface, and export

The voiceprint subsystem must integrate cleanly with those components without becoming tightly coupled to any single transcription or diarization model.

## Objective

Build a high-accuracy, open-set speaker-identification system that can:

- Enroll known speakers from multiple recordings
- Match new speech against enrolled speakers
- Reject speakers who are not enrolled
- Represent uncertainty rather than forcing a name
- Improve over time through confirmed corrections
- Remain locally controllable and suitable for a Mac-only application
- Preserve the option to replace or upgrade individual models later

Accuracy takes priority over speed, model size, and minimal memory use. However, expensive models should only run when they provide meaningful additional value.

## Selected Model Architecture

The primary voiceprint system will use two independent speaker-embedding models:

### ERes2NetV2

ERes2NetV2 will serve as the primary short-utterance speaker-recognition model. It was selected because voice identification in the transcription application will often depend on short speaker turns rather than long, clean recordings.

ERes2NetV2 will initially be integrated through the 3D-Speaker project.

### ReDimNet2

ReDimNet2 will serve as the second primary model. It will be integrated through WeSpeaker where practical.

ReDimNet2 provides an architecturally different assessment of speaker identity. Its purpose is not merely to duplicate ERes2NetV2, but to reduce the risk of trusting a mistake made by a single model.

### w2v-BERT 2.0

w2v-BERT 2.0 will serve as an accuracy-focused fallback and adjudication model.

It will not run on every speaker segment. It will be invoked when:

- ERes2NetV2 and ReDimNet2 disagree
- The best two candidate speakers have similar scores
- A result falls close to the known-speaker threshold
- The audio is difficult but still potentially usable
- Additional evidence is required before assigning a speaker’s name

Its Apple Silicon performance, memory requirements, inference framework, and packaging feasibility must be validated before it becomes a required production dependency.

## System Boundaries

The voiceprint subsystem will not perform diarization itself.

The diarization system will determine:

- Where each speaker turn begins and ends
- Which segments appear to belong to the same temporary speaker
- Whether speech overlaps
- Whether a segment contains sufficient isolated speech for identification

The voiceprint subsystem will determine:

- Whether a diarized speaker resembles an enrolled person
- The confidence of that match
- Whether the speaker should remain unknown
- Whether additional evidence or fallback processing is required

The transcript pipeline will decide how identity results are displayed and reconciled across the complete recording.

## Processing Flow

For each suitable diarized speaker segment:

1. Validate that the segment contains enough usable speech.
2. Reject or defer segments with severe overlap, insufficient duration, clipping, or excessive noise.
3. Generate an ERes2NetV2 embedding.
4. Generate a ReDimNet2 embedding.
5. Compare each embedding against the relevant enrolled profiles.
6. Calibrate the scores produced by each model.
7. Fuse the calibrated evidence.
8. Evaluate the highest candidate, runner-up candidate, model agreement, and known-versus-unknown threshold.
9. Run w2v-BERT 2.0 when escalation rules are met.
10. Return a structured identification result to the larger transcription pipeline.

The subsystem must never identify a speaker solely because that person is the closest available match. The best match must also satisfy the absolute acceptance requirements.

## Identification Results

Every decision will return one of three primary states.

### Known

The evidence is strong enough to assign an enrolled speaker.

A known result should normally require:

- Adequate usable speech
- A score above the calibrated acceptance threshold
- A sufficient margin over the second-best candidate
- Acceptable agreement between the primary models
- Stability across multiple segments when available

### Unknown

No enrolled speaker satisfies the acceptance criteria.

Unknown is a valid result and must not be treated as a failure. The system should prefer unknown over incorrectly naming an enrolled person.

### Ambiguous

The evidence suggests one or more enrolled speakers, but it is not strong enough to make a reliable assignment.

Ambiguous results may be:

- Reprocessed with w2v-BERT 2.0
- Combined with additional segments from the same diarized speaker
- Presented for human confirmation
- Left unnamed in the final transcript

## Enrollment

Speaker enrollment must use multiple recordings rather than a single voice sample.

The enrollment workflow should collect speech across variations such as:

- Different days
- Different speaking volumes
- Close-microphone and far-field recordings
- Different microphones or audio sources
- Natural conversational speech
- Different emotional or physical states when available

Each enrollment sample must pass basic quality checks before being accepted.

The system must preserve multiple embeddings for each person rather than immediately collapsing all samples into one averaged vector. This allows the profile to represent natural variation and supports later analysis of which enrollment samples are helpful or harmful.

Each profile should contain:

- Stable speaker UUID
- Display name
- Enrollment recordings or approved derived data
- Embeddings for every supported model
- Model and embedding version
- Audio-source metadata
- Recording-quality measurements
- Enrollment date
- Confirmed matches
- Confirmed mismatches
- User corrections

Raw enrollment audio retention must be governed by the application’s broader privacy and storage policies.

## Score Calibration and Fusion

Raw similarity scores from different models cannot be directly averaged.

Each model must be calibrated against validation data that resembles the application’s real operating conditions. Calibration should convert model-specific similarity values into comparable evidence.

The fusion system should consider:

- ERes2NetV2 score
- ReDimNet2 score
- w2v-BERT score when available
- Difference between the first- and second-ranked candidates
- Amount of usable speech
- Segment quality
- Model agreement
- Consistency across earlier segments
- Microphone or channel conditions
- Enrollment-sample coverage

Initial fusion may use a transparent statistical model such as calibrated logistic regression. More complicated fusion methods should only be adopted if controlled testing shows a meaningful improvement.

A large language model must not be used to compare raw voice embeddings or make the primary identity decision.

## Multi-Segment Evidence

Speaker identity should not be finalized from one weak segment when additional speech is available.

The system should accumulate evidence across segments assigned to the same diarized speaker. A temporary speaker may initially remain ambiguous and later become known after enough clean speech has been collected.

Evidence aggregation must account for the possibility that diarization has incorrectly combined two people. A single contradictory segment should not automatically overwrite a stable identity, but repeated contradictions should trigger review or re-clustering.

## Overlapping and Contaminated Speech

Overlapping speech must be treated cautiously.

Segments containing multiple simultaneous speakers should normally be excluded from enrollment and direct voiceprint matching unless a source-separation stage produces a sufficiently clean result.

The subsystem should receive overlap and quality information from the larger audio pipeline. It should not interpret low-confidence contaminated segments as strong identity evidence.

Television audio, speakerphone audio, recordings played through another device, and synthetic or cloned voices should also be treated as separate risk categories.

Anti-spoofing is not part of the initial identification model itself. It should be implemented as an additional subsystem if voice identity is later used to authorize sensitive actions.

## Benchmark Harness

The voiceprint subsystem must be developed and evaluated through a standalone benchmark harness before being deeply integrated into the application interface.

The benchmark set should include:

- Enrolled speakers
- Unenrolled speakers
- Similar-sounding speakers
- Short utterances
- Long utterances
- Far-field speech
- Background noise
- Reverberant rooms
- Different microphones
- Compressed audio
- Overlapping speech
- Television or playback contamination
- Whispered, tired, excited, or quiet speech where available

The benchmark must measure more than EER.

Required metrics include:

- False acceptance rate
- False rejection rate
- False identification rate
- Unknown-speaker rejection rate
- Ambiguous-result rate
- Top-one identification accuracy
- Top-two candidate margin
- Accuracy by segment duration
- Accuracy by microphone or source
- Accuracy by noise condition
- Frequency of w2v-BERT escalation
- Accuracy gained through escalation
- Processing latency
- Peak memory use

The most important metric for this application is the rate at which the system assigns the wrong known person. A higher unknown rate is acceptable if it substantially reduces false naming.

## Threshold Selection

Thresholds must not be selected solely from public benchmark results.

Final thresholds must be calibrated using recordings that resemble the intended application environment. Separate thresholds may be needed for:

- Short and long segments
- Close and distant microphones
- Clean and noisy recordings
- Individual enrollment quality
- Different numbers of enrolled speakers

The production operating point should favor precision over forced identification. Thresholds and calibration data must be versioned so results remain reproducible after model updates.

## Integration with Diarization

The diarization system will initially assign temporary labels such as `Speaker 1` and `Speaker 2`.

The voiceprint subsystem will attach identity hypotheses and confidence information to those temporary clusters. The larger reconciliation stage will determine whether:

- A temporary speaker should receive a known name
- Multiple temporary clusters should be merged
- A cluster contains conflicting identities
- A speaker should remain unknown
- A transcript requires human review

Voiceprint matching must not conceal diarization errors. The application should retain both the original diarization label and the resolved identity so decisions can be audited.

## Integration with Multiple Transcription Models

The larger application may run multiple transcription and diarization pipelines in parallel. Voiceprint identification should operate on a normalized representation of speaker segments rather than being embedded directly inside one transcription engine.

When different diarization systems disagree, the reconciliation layer may use voiceprint evidence as one signal when determining which segmentation is more credible. Voiceprint evidence must not automatically override strong timing, overlap, or acoustic evidence.

## Storage and Versioning

Embeddings and identity decisions must be versioned by:

- Model name
- Model version
- Preprocessing version
- Embedding dimensions
- Calibration version
- Threshold version
- Enrollment-profile version

A model upgrade must not silently reinterpret old embeddings. The system should either regenerate the embeddings or preserve the older runtime needed to interpret them.

Identity decisions stored with a transcript should include enough information to explain why the assignment was made.

## Human Corrections

Users must be able to:

- Rename an unknown speaker
- Correct a mistaken identity
- Confirm a suggested identity
- Mark two diarized labels as the same person
- Mark one diarized label as containing multiple people
- Exclude a poor recording from enrollment
- Add a confirmed segment to a speaker profile

Corrections should become labeled evaluation data. They may improve future calibration and enrollment profiles, but they must not cause uncontrolled automatic retraining.

A correction to one transcript must not silently alter historical transcripts unless the user explicitly requests reprocessing.

## Mac Deployment

The application is being optimized for macOS rather than iOS. The design may therefore use more memory and computation when this improves accuracy.

The preferred deployment direction is:

- Local processing
- Apple Silicon acceleration where available
- ONNX Runtime, Core ML, MLX, PyTorch MPS, or another validated runtime
- Background processing that does not block transcript editing
- Cached embeddings to avoid unnecessary repeated inference

Each model must be benchmarked on the target Mac hardware before the production runtime is selected. Model conversion is only acceptable when numerical comparison confirms that the converted model preserves identification quality.

## Licensing Review

Before distribution, the project must document:

- Source-code license
- Pretrained-model license
- Training-data restrictions
- Commercial-use restrictions
- Redistribution rights
- Attribution requirements
- Modifications made to upstream projects

No model should become a mandatory production dependency until both its code and weights have been cleared for the intended use.

## Implementation Phases

### Phase 1: Standalone Foundation

- Define common embedding and identification interfaces.
- Integrate ERes2NetV2.
- Build basic enrollment and profile storage.
- Implement cosine-similarity scoring.
- Create initial known-versus-unknown tests.
- Record baseline performance and resource usage.

### Phase 2: Dual-Model Identification

- Integrate ReDimNet2.
- Add model-specific score calibration.
- Implement score fusion.
- Add top-two margin and model-agreement rules.
- Add known, unknown, and ambiguous states.
- Compare dual-model results with each model individually.

### Phase 3: Real-World Benchmarking

- Build the representative evaluation dataset.
- Test short, noisy, far-field, and mixed-source speech.
- Calibrate operating thresholds.
- Measure false naming and unknown rejection.
- Establish minimum segment-quality requirements.

### Phase 4: Accuracy Fallback

- Validate w2v-BERT 2.0 on Apple Silicon.
- Measure its incremental accuracy and computational cost.
- Implement escalation rules.
- Cache fallback results.
- Confirm that fallback processing meaningfully improves ambiguous cases.

### Phase 5: Diarization Integration

- Connect the identifier to diarized speaker segments.
- Aggregate evidence across speaker clusters.
- Detect identity conflicts within clusters.
- Preserve diarization and identity provenance.
- Expose structured confidence information to transcript reconciliation.

### Phase 6: Correction and Learning Workflow

- Add speaker enrollment and management interfaces.
- Add transcript identity corrections.
- Convert corrections into benchmark cases.
- Support controlled profile updates.
- Add profile and model-version migration tools.

### Phase 7: Production Hardening

- Complete license review.
- Encrypt or otherwise protect stored voiceprint data.
- Add profile deletion and export.
- Add corruption and migration tests.
- Validate packaged Mac deployment.
- Establish regression benchmarks for future model updates.

## Initial Acceptance Criteria

The first production-ready version of this workstream must:

- Enroll multiple known speakers
- Preserve multiple samples per speaker
- Process suitable diarized segments with both primary models
- Correctly return known, unknown, or ambiguous
- Use calibrated score fusion
- Avoid forced nearest-speaker assignments
- Escalate selected uncertain cases to the fallback model
- Record confidence, model versions, and decision provenance
- Permit user correction
- Run locally on the supported Mac
- Pass a representative real-world benchmark
- Demonstrate a materially lower false-identification rate than the application’s previous voiceprint implementation

Exact numerical thresholds will be established from the benchmark dataset rather than invented in advance.

## Deferred Work

The following items are related but are not required for the first voiceprint implementation:

- Security-grade voice authentication
- Deepfake and replay detection
- Continuous live identity tracking
- Cloud-hosted speaker-profile synchronization
- Cross-device household identity sharing
- Automatic model retraining
- Large-scale identification across thousands of speakers
- Voice-based authorization of sensitive actions

These features may be added later without changing the core separation between diarization, speaker identification, and transcript reconciliation.