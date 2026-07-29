# Risk Register — Transcriber Mac Accuracy Expansion

Last updated: 2026-07-28

Likelihood and impact are Low, Medium, or High. A risk closes only with recorded evidence.

| ID | Risk | Likelihood | Impact | Primary mitigation | Owner |
|---|---|---:|---:|---|---|
| R-01 | Existing recordings or transcripts become unreadable after storage changes | M | H | Additive/versioned migration, legacy fixtures, corrupt/interrupted-write/rollback tests | VX-03, VX-05 |
| R-02 | Original or imported audio is lost or destructively transformed | L | H | Immutable source policy; derivatives stored separately; failure tests | Every objective |
| R-03 | `TranscriptionSession` refactor changes cancellation or persistence behavior | M | H | Characterization tests, narrow extraction, one responsibility at a time | VX-04 |
| R-04 | Persistent jobs publish stale results over newer attempts or corrections | M | H | Attempt/version identity, compare-before-publish, relaunch tests | VX-06 |
| R-05 | Artifact store grows without bounds or corrupts partially | M | H | Atomic manifests, checksums, retention policy, low-disk/corruption tests | VX-05, VX-25 |
| R-06 | Benchmark data is unrepresentative, leaking, or mislabeled | M | H | Human-approved private manifest, provenance, no audio in Git, reviewable ground truth | VX-01, VX-08 |
| R-07 | Accuracy claims are optimized to a tiny private set | M | H | Held-out cases, condition breakdowns, regression set growth | VX-08, VX-09, VX-26 |
| R-08 | Two-model consensus is more plausible but less acoustically correct | M | H | Deterministic alignment, preserve candidates, hallucination and WER gates | VX-13 |
| R-09 | Proposed model cannot run reliably in native sandboxed Mac app | H | H | Feasibility before integration; allow “do not ship” outcome | VX-10, VX-11, VX-15, VX-18…20 |
| R-10 | New runtime or weight has incompatible license/distribution terms | M | H | License review before production code and again before packaging | Candidate objectives, VX-25 |
| R-11 | Parallel models cause memory pressure, thermal throttling, crash, or slower completion | H | H | Measure sequential/limited parallel; resource limits; sequential fallback | VX-12 |
| R-12 | Dependency/model update changes output without a reproducible baseline | M | H | Isolated update objective, pinned versions, benchmark regression | All model objectives |
| R-13 | Diarization alternative requires fragile Python/helper architecture | H | H | Explicit helper/runtime design and Human gate; current FluidAudio baseline retained | VX-15 |
| R-14 | Temporal speaker merge hides overlap or uncertainty | H | M | Richer contract, preserve conflicts, review surface | VX-14, VX-16 |
| R-15 | Voiceprint assigns the wrong known person confidently | M | H | Open-set thresholds, score margins, calibration, unknown bias, Human benchmark gate | VX-18…20 |
| R-16 | Poor enrollment samples poison a speaker profile | M | H | Quality gates, multiple samples, retain per-sample evidence, explicit approval/removal | VX-17, VX-18 |
| R-17 | Model upgrade silently changes old identity meaning | M | H | Versioned embeddings/calibration; retain or regenerate from approved clips | VX-17…20 |
| R-18 | Voiceprint/profile data is exposed through logs, exports, backups, or deletion bugs | M | H | Local protection, redaction, scoped export, verified deletion | VX-17, VX-25 |
| R-19 | Human corrections are overwritten or silently applied to historical transcripts | M | H | Transcript versions, correction provenance, compare-before-write | VX-21, VX-22 |
| R-20 | “Controlled learning” becomes silent enrollment or retraining | L | H | Explicit confirmation and no automatic training policy | VX-22 |
| R-21 | AI adjudication invents dialogue | M | H | Optional stage, constrained output, disputed regions only, benchmark/remove gate | VX-24 |
| R-22 | Private audio leaves the Mac without informed approval | L | H | Separate Human privacy decision; local default; network stage disabled by default | VX-24 |
| R-23 | Cleanup deletes iOS-owned, unique, or user material | M | H | Ownership inventory, exact target, Human gate, rollback | VX-02, VX-25 |
| R-24 | Mac roadmap continues carrying obsolete iOS assumptions and code | H | M | Mac authority decision and removal inventory | VX-02 |
| R-25 | Expanded UI overwhelms normal transcript use | M | M | Draft-first workflow; uncertainty-focused review; progressive disclosure | VX-21, VX-22 |
| R-26 | Optional sophistication adds cost without measurable benefit | H | M | Every ensemble/fallback/AI stage has a removal gate | VX-09 onward |
| R-27 | Real microphone, long-run, packaging, or accessibility defects escape automation | M | H | Explicit Human-owned acceptance and release checklists | VX-25, VX-26 |
| R-28 | Dirty worktree causes unrelated user changes to be overwritten or committed | M | H | Inspect status/diff before each objective; scope commits intentionally | Every objective |

## Critical risks

R-01, R-02, R-04, R-08, R-09, R-11, R-15, R-18, R-19, R-22, and R-23 require explicit evidence in any objective that touches them.

## Update rule

The Manager updates this register when:

- A risk materializes.
- Likelihood or impact changes.
- A mitigation is disproved.
- A new objective assumes ownership.
- Evidence closes a risk.

“Tests passed” is not enough to close a model-quality, private-data, license, packaging, or Human real-world risk.
