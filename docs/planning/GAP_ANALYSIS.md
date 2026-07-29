# Gap Analysis — Current Mac App vs Accuracy-Expansion PRD

Last reviewed: 2026-07-28

Legend: **Complete**, **Partial**, **Missing**, **Evidence needed**.

## 1. Solid core

| Capability | Status | Current evidence | Roadmap action |
|---|---|---|---|
| Record and import audio | Complete | `AudioRecorder`, `RecordingView`, file importer | Preserve and regression-test |
| Original audio kept as source | Complete | Application Support recordings directory; playback derivative is regenerable | Preserve through every migration |
| Dashboard/Library/Model Lab/Settings | Complete | `RootView` four-tab structure | Extend, do not redesign by default |
| Transcript-first failure behavior | Complete | Transcript saved before diarization; label retry independent | Preserve |
| Cancel/retry/failure isolation | Complete | Attempt IDs, diarization guard, failure-injection tests | Extend to persistent jobs |
| Playback and TXT/SRT/JSON export | Complete | `LibraryView`, `TranscriptExporter` | Preserve |
| Speaker rename and reassignment | Complete | Speaker name map and segment reassignment | Extend to split/merge and identity review |
| Model readiness/repair | Complete for current models | File-backed registry and repair/redownload | Extend per new model |
| Strict concurrency/actor engine seams | Complete | Xcode setting and engine protocols | Preserve |
| Mac build/unit baseline | Complete | 2026-07-28 build and tests passed | Rerun each objective |

## 2. Architecture and persistence

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Normalized versioned result contracts | Missing | Current types are tailored to one transcript and simple diarization | VX-03 |
| Inspectable processing artifacts | Missing | Raw/final data mainly live in `Recording` blobs or memory | VX-03, VX-05 |
| Existing-record compatibility | Partial | Current blobs have safe decode, but future migrations are undesigned | VX-03, VX-05 |
| Persistent job graph and relaunch recovery | Missing | Session processing is in-memory | VX-06 |
| Draft/reconciled/verified transcript versions | Missing | One effective final transcript representation | VX-03, VX-06 |
| Smaller orchestration responsibilities | Partial | Protocol seams exist; `TranscriptionSession` remains oversized | VX-04 |
| Complete provenance | Missing | Some model/timing/fallback diagnostics exist; not full pipeline provenance | VX-05 onward |

## 3. Audio preparation

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Versioned mono 16 kHz derivative | Partial | Diarization converts internally but no shared stored derivative contract | VX-07 |
| Preserve original channel/layout metadata | Partial | Original file preserved; formal metadata artifact absent | VX-07 |
| Quality analysis | Missing | No persistent clipping/noise/speech-quality analysis | VX-07 |
| Alternate enhanced derivatives | Missing | No versioned denoise/source-separation experiment path | Later, only if benchmarked |

## 4. Benchmarking

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Model Lab timing/comparison | Partial | Useful current UI/report, primarily Whisper-focused on Mac | VX-08 |
| Private dataset manifest | Missing | No approved ground-truth dataset workflow | VX-01, VX-08 |
| WER and error breakdown | Missing | No formal accuracy metric harness | VX-08 |
| Diarization and identity metrics | Missing | No DER/attributed-word/open-set metric harness | VX-08 |
| Current production baseline | Evidence needed | Working pipeline exists; representative measurements not recorded | VX-09 |
| Regression threshold policy | Missing | Must be derived from approved data | VX-09 |

## 5. Multi-engine transcription

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Current Whisper transcript | Complete | WhisperKit file transcription and timed segments | Baseline |
| Accuracy-focused Whisper candidate | Partial | Curated Whisper choices exist; Large v3 production feasibility unproved | VX-10 |
| Mac Parakeet candidate | Partial | Engine code exists but important paths are iOS-gated | VX-11 |
| Safe parallel scheduler | Missing | Current pacing intentionally serializes expensive work | VX-12 |
| Raw output retention per engine | Missing | Current raw data is normalized single-engine timing, not full provider artifact | VX-05, VX-10, VX-11 |
| Timed alignment and consensus | Missing | `TranscriptMerger` merges transcript with diarization, not transcripts with each other | VX-13 |
| Disagreement provenance | Missing | No candidate/decision record | VX-13 |

## 6. Diarization and speaker reconciliation

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Working local diarization | Complete | FluidAudio Sortformer | VX-14 baseline |
| Failure/cancel/timeout preservation | Complete | Guarded fallback and retry | Preserve |
| Raw diarization provenance | Partial | Segments/diagnostics available; not fully persisted/versioned | VX-14 |
| Overlap/quality evidence | Partial or provider-limited | Current representation is start/end/speaker only | VX-14 |
| Pyannote or alternative | Missing | Runtime, license, sandbox, package, and benchmark unresolved | VX-15 |
| Explicit reconciliation conflicts | Missing | Current temporal merge smooths/assigns without reviewable evidence | VX-16 |
| Temporary cluster preserved beside identity | Missing | No known-person identity layer | VX-16 onward |

## 7. Voice identity

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Speaker profiles | Missing | No profile or enrollment data | VX-17 |
| Multiple approved samples | Missing | No enrollment workflow | VX-17 |
| Profile export/deletion/protection | Missing | Policy and implementation absent | VX-17, VX-25 |
| Primary embedding model | Missing | ERes2NetV2 or alternative not integrated | VX-18 |
| Known/unknown/ambiguous | Missing | No open-set decision model | VX-18 |
| Calibrated thresholds/margins | Missing | No representative score dataset | VX-18 |
| Independent second model/fusion | Missing | ReDimNet2 or alternative not integrated | VX-19 |
| Difficult-case fallback | Missing | w2v-BERT or alternative not integrated | VX-20 |
| Multi-turn evidence | Missing | No cluster-level identity accumulator | VX-18 |

## 8. Review and correction

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| View transcript and speakers | Complete | Library detail and grouped cards | Preserve |
| Rename/reassign | Complete | Existing edit flows | Extend |
| Edit transcript text | Missing | Beta 2.0 intentionally omitted it | VX-21 |
| Review disagreements/uncertainty | Missing | No candidate-level review | VX-21 |
| Merge/split clusters | Missing | No structural speaker correction | VX-22 |
| Confirm/reject identity | Missing | No identity layer | VX-22 |
| Reprocess selected region | Missing | Retries operate at broader stage level | VX-22, VX-23 |
| Version corrections | Missing | Current transcript is overwritten in place | VX-03, VX-21 |
| Controlled enrollment from conversations | Missing | No profile workflow | VX-22 |

## 9. Optional difficult-region and AI work

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Disputed-window extraction | Missing | No transcript disagreement model | VX-23 |
| Alternate decoding/derivative experiments | Missing | No targeted reprocessing artifacts | VX-23 |
| Constrained adjudication | Missing and unapproved | Local/network/privacy/provider decision required | VX-24 |
| Whole-transcript generative rewrite | Intentionally out of scope | Conflicts with evidence-first product policy | None |

## 10. Production hardening

| Requirement | Status | Gap | Owning objective |
|---|---|---|---|
| Current failure tests | Strong partial | Good session coverage; no multi-stage persistent pipeline yet | Every objective |
| Low disk/corrupt artifact recovery | Missing for future store | Store does not exist | VX-05, VX-25 |
| Model/package licensing review | Partial | Current pins work; expanded candidates unreviewed | Candidate objectives, VX-25 |
| Signing/notarization/model installation | Evidence needed | Not established for expanded runtimes | VX-25 |
| Private-data leakage checks | Partial | Local design, but no profile/embedding layer yet | VX-17, VX-25 |
| Final representative improvement | Evidence needed | Core is green; accuracy expansion not implemented | VX-26 |

## 11. Main conclusion

The gap is not “build a transcription app.” That application already exists.

The real gap is an evidence and provenance layer around the working product: versioned artifacts, persistent jobs, comparable engine results, conservative reconciliation, open-set speaker identity, and uncertainty-focused review. The PLAN sequences those additions so the current app remains useful throughout.
