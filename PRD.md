# Transcriber 2.0 Beta Product Requirements Document

Last updated: June 18, 2026

## 1. Product Overview

Transcriber 2.0 Beta is a native, on-device transcription app for iPhone first and Mac second. It records or imports audio, creates a fast usable transcript, then applies speaker labels after the transcript is available. The app is designed for meetings, interviews, building walkthroughs, and conversations where speaker separation matters.

The product should feel calm, professional, and trustworthy. It should expose enough diagnostics for serious beta testing without turning the normal recording experience into a lab bench. The existing native app is the baseline, but this PRD describes the intended product, not only the current implementation.

The original Python Transcriber remains separate and unchanged.

## 2. Goals

### Primary Goals

- Capture audio immediately and reliably.
- Produce a usable transcript as quickly as possible.
- Apply useful speaker labels for 2-4 speakers after transcription.
- Preserve original audio by default for playback, retry, and speaker-label repair.
- Keep processing on device except for user-initiated sharing/export.
- Support a beta workflow where transcription models and diarization quality can be measured and improved.

### Beta Success Criteria

- A 5-, 15-, and 30-minute recording can be recorded, transcribed, speaker-labeled, reviewed, and shared.
- A shared/imported audio file can be brought into the app and transcribed.
- The transcript appears before speaker labels finish.
- Cancellation works during transcription and speaker labeling.
- Downloaded models remain available after force-quit, relaunch, and device reboot.
- The app clearly explains model downloads, failures, fallbacks, retries, and progress.

## 3. Target Users And Use Cases

### Primary User

The primary user for 2.0 Beta is Daniel using the app on his own devices, especially iPhone. The app should optimize for real testing in practical situations rather than broad public release polish.

### Primary Use Cases

- Meetings with 2-4 speakers.
- Interviews and conversations.
- Building walkthroughs and site visits.
- Imported recordings from Voice Memos or other audio apps.

### Secondary Use Cases

- Single-speaker lecture capture.
- Mac review, playback, import, and sharing.
- Model benchmarking and diagnostics during beta.

## 4. Platform Strategy

### iPhone

iPhone is the primary product surface. The iPhone app must support recording, importing, live preview, transcription, speaker labeling, sharing, Model Lab, settings, and diagnostics.

Target device for beta validation: iPhone 17 Pro or newer equivalent test hardware.

### Mac

Mac is a secondary companion app. It should support opening/importing recordings, playback, transcript review, sharing, and basic model workflows where feasible. Mac should not block iPhone-first decisions during 2.0 Beta.

### Existing Python App

The Python desktop app remains independent. Native app work must not require moving, deleting, or changing the Python app.

## 5. Product Principles

- **Record first.** Audio capture starts immediately when the user taps Record.
- **Never lose audio.** The recording is the source of truth and should be preserved whenever possible.
- **Transcript first, labels second.** Text should become usable before speaker labeling finishes.
- **Plain language by default.** Technical state should be understandable, even when detailed diagnostics are available.
- **On-device by default.** Audio, transcription, and speaker labeling stay local unless the user explicitly shares or exports.
- **Beta with instrumentation.** The app should help measure model speed, failures, and quality during beta.

## 6. App Structure

The app uses four primary tabs:

1. **Dashboard**
2. **Library**
3. **Model Lab**
4. **Settings**

### Dashboard

The Dashboard is the home screen. It should show system status plus recent work, while keeping the main actions easy to reach.

Required content:

- Active microphone status.
- Selected transcription model and readiness state.
- Speaker-labeling engine status.
- Recent recordings needing attention.
- Prominent actions: Record, Import, Model Lab.
- Friendly warnings when required models are missing, downloading, failed, or being repaired.

Required actions:

- Start recording.
- Import audio.
- Open Model Lab.
- Jump to recent incomplete or failed jobs.

### Library

The Library is a chronological list of recordings, newest first.

Each recording should show:

- Date/time default title.
- Duration.
- Status badge: recording saved, needs transcription, transcribing, speaker labeling, speaker labels failed, complete.
- Final transcription model used.
- Speaker-label status when available.

Library detail should support:

- Basic audio playback.
- Transcript viewing.
- Speaker renaming.
- Segment-level speaker reassignment.
- Sharing/export.
- Retry transcription when needed.
- Retry speaker labels when needed.
- Delete recording.

### Model Lab

Model Lab is a top-level tab for beta diagnostics and model comparison.

Model Lab should let the user:

- Choose an existing recording or import an audio file.
- Run selected downloaded models one at a time.
- Compare transcript output.
- Capture model load time, transcription time, failure status, model size/status, and processing speed.
- Export a shareable comparison report.

Model Lab is allowed to expose more technical detail than normal app screens.

### Settings

Settings should include:

- Microphone selection and test.
- Transcription model selection and downloads.
- Model storage status and repair/redownload actions.
- Storage policy.
- Privacy information.
- Diagnostics settings/status.
- About/version information.

## 7. Core User Flows

### Record Flow

1. User taps Record.
2. Audio recording starts immediately.
3. Selected microphone is used if available.
4. If selected microphone is unavailable, app falls back automatically and shows a notice.
5. Live transcription may start when its model is ready, but recording must not wait for it.
6. User taps Stop.
7. Recording is saved immediately.
8. Final transcription begins.
9. Transcript appears as soon as final transcription completes.
10. Speaker labeling starts after transcript is available.
11. Final speaker labels replace provisional/unknown labels when complete.
12. User can share, rename speakers, reassign speaker segments, retry, or start a new recording.

### Import / Share-To-App Flow

1. User shares audio to Transcriber from Voice Memos or another app, or imports from the app.
2. Audio is saved into Transcriber storage.
3. Imported item appears in Library or Dashboard recent work.
4. User can transcribe it.
5. Processing follows the same final transcription and speaker-label workflow as recordings.

### Cancel Flow

Cancellation must be available during:

- Final transcription.
- Speaker labeling.
- Retry transcription.
- Retry speaker labels.

Expected behavior:

- If no transcript exists yet, keep the audio and mark the recording as needing transcription.
- If transcript exists but speaker labels are still running, keep the transcript and mark speaker labels as retryable.
- Stop or unload active model work where the platform/framework allows.
- Show a clear message explaining what was saved and what can be retried.

## 8. Recording And Microphone Requirements

### Recording

- Recording starts immediately after Record is tapped.
- Recording continues in background/lock screen where iOS allows.
- Recording must not depend on transcription model readiness.
- The app should target reliable handling of recordings up to 30 minutes for beta.
- Original audio is kept by default.

### Microphone Selection

Settings must include microphone selection with:

- Automatic/default input.
- Built-in iPhone microphone when available.
- Bluetooth/headset inputs when available.
- Any available named input exposed by the platform.
- Test Mic action.
- Live input meter during test.
- Clear active microphone display during recording.

Fallback behavior:

- If selected microphone is unavailable when recording starts, automatically use the best available input.
- Notify the user which microphone is being used.
- Do not block recording solely because the preferred microphone is missing.

## 9. Transcription Requirements

### Product Behavior

- Final transcription quality matters more than live preview quality.
- Live transcription is helpful but secondary.
- The default model should be fast and reliable.
- Model defaults should be benchmark-driven and can change during beta based on Model Lab evidence.

### Model Picker

Normal users should see a simple curated model picker with plain-language descriptions.

The picker should communicate:

- Speed expectation.
- Accuracy expectation.
- Storage/download size where possible.
- Download/readiness state.

### Model Failure

If a selected model fails:

- Save audio and partial work.
- Try a safer fallback when reasonable.
- Notify the user that fallback was used.
- Offer retry/repair/redownload actions.

## 10. Diarization Requirements

Speaker labeling is a high-priority differentiator for this app.

### Beta Target

- Optimize for 2-4 speakers.
- Speaker labels should be useful enough to separate major speakers.
- Speaker labels may require retry or manual cleanup during beta.
- Transcript should appear before speaker labels finish.

### Required Speaker Features

- Apply speaker labels after recording/import transcription.
- Preserve transcript even if speaker labeling fails.
- Retry speaker labels without rerunning transcription.
- Rename speakers.
- Reassign individual transcript segments to a different speaker.
- Show when speaker labels are approximate, failed, canceled, or retryable.

### Production Goals

- Improve diarization accuracy for overlapping speech and fast turn-taking.
- Surface speaker-label confidence if available.
- Add better tools for merging/splitting speaker identities.

## 11. Transcript Review And Sharing

### Transcript Display

Transcripts should use speaker cards:

- Speaker name.
- Speaker color.
- Timestamp or time range.
- Transcript text.
- Clear visual grouping.

Screens should use balanced density: readable and calm, with details available but not crammed.

### Editing

2.0 Beta must support:

- Rename speakers.
- Reassign a transcript segment to a different speaker.

Text editing is not required for beta.

### Playback

2.0 Beta requires basic play/pause playback of the original audio.

Production roadmap:

- Transcript-synced playback.
- Playback speed control.
- Jump to transcript segment.
- Waveform navigation.
- Review tools for fast correction.

### Sharing And Export

Sharing uses the universal system share sheet.

Required export formats:

- TXT.
- SRT.
- JSON.

Exports should include speaker names when available.

## 12. Model Downloads And Persistence

Downloaded models must stay downloaded after:

- App force-quit.
- Normal app relaunch.
- Device reboot.

The app must not rely only on in-memory state or a remembered downloaded flag. Model readiness should be based on actual on-device files and, where practical, loadability checks.

Required model states:

- Not downloaded.
- Downloading.
- Downloaded.
- Verifying.
- Ready.
- Missing/corrupt.
- Failed.

Required behavior:

- Preload the default model without a heavy onboarding flow.
- Show clear download size/progress when known.
- Refresh model status on app launch.
- Refresh model status when Settings opens.
- Verify selected model again before processing.
- If missing/corrupt, show Repair/Redownload.
- Once required models are downloaded, recording/transcription/speaker labeling should work offline.

## 13. Progress, Diagnostics, And Failure Handling

### Progress UI

Long-running work should use a detailed timeline, not a vague spinner.

Progress should show:

- Current phase.
- Rough percent or activity state.
- Elapsed time.
- Cancel action.
- Retry action where relevant.
- Details/diagnostics where relevant.

Core phases:

- Saving recording.
- Preparing model.
- Transcribing.
- Saving transcript.
- Identifying speakers.
- Saving speaker labels.
- Exporting/sharing.

### Diagnostics

Normal app screens may show detailed metrics, but they must remain organized and calm.

Diagnostics may include:

- Model used.
- Model readiness.
- Load time.
- Processing time.
- Realtime factor.
- Failure message.
- Fallback used.
- Speaker-label status.

Model Lab should expose full diagnostics.

### Failure Philosophy

The app should save partial work whenever possible.

Failure states should explain:

- What is safe.
- What failed.
- What can be retried.
- Whether fallback was used.

## 14. Storage And Privacy

### Storage

- Original audio is kept by default.
- Recordings and transcripts are stored separately from the original Python app.
- Users should be able to delete recordings.
- Future storage management should include model sizes and cache cleanup.

### Privacy

- Audio, transcription, and speaker labeling are processed on device.
- Model downloads require network access before offline use.
- Sharing/export only happens when user initiates it.
- Cloud sync/backups are not part of beta.

## 15. Accessibility

2.0 Beta should satisfy Apple platform basics:

- Dynamic Type.
- VoiceOver labels for controls and transcript cards.
- Sufficient contrast in midnight-blue theme.
- Reachable controls.
- Clear text status for progress/failure states.
- Avoid relying on color alone for speaker identity/status.

## 16. Visual And Interaction Direction

### Visual Identity

- Midnight-blue theme.
- Calm professional tone.
- Balanced information density.
- Clear status language.
- Strong primary actions.
- Secondary diagnostics should be visible but organized.

### Button Philosophy

Long-running work should expose power controls:

- Cancel.
- Retry.
- Details.
- Repair/redownload where relevant.

Primary capture actions should remain visually obvious:

- Record.
- Import.
- Model Lab.

## 17. Beta Acceptance Tests

### Recording

- Record 5 minutes, stop, transcribe, speaker-label, share.
- Record 15 minutes, stop, transcribe, speaker-label, share.
- Record 30 minutes, stop, transcribe, speaker-label, share.
- Lock phone during recording and verify audio is preserved where iOS allows.
- Switch apps during recording and verify audio is preserved where iOS allows.

### Import

- Share a Voice Memos recording to Transcriber.
- Import from Files.
- Verify imported audio can be transcribed and speaker-labeled.

### Transcription And Diarization

- Verify transcript appears before speaker labeling completes.
- Verify speaker labels support 2, 3, and 4 speaker recordings.
- Verify a single-speaker recording does not fail the whole workflow.
- Verify failed diarization preserves transcript and allows retry.
- Verify retry speaker labels does not rerun transcription.

### Cancellation And Failure

- Cancel during final transcription.
- Cancel during speaker labeling.
- Confirm audio/transcript state remains safe after cancel.
- Force a selected model failure and confirm fallback/notification behavior.
- Force a selected microphone to be unavailable and confirm fallback/notice behavior.

### Models

- Download default model.
- Force-quit app.
- Reopen app and confirm model remains downloaded/ready.
- Reboot device and confirm model remains downloaded/ready.
- Start transcription without redownloading.
- Corrupt/remove a model in development and confirm Repair/Redownload appears.

### Export

- Export TXT.
- Export SRT.
- Export JSON.
- Verify speaker names appear in exports when renamed.

### Model Lab

- Compare at least two downloaded transcription models on the same recording.
- Confirm Model Lab records load time, processing time, failure status, transcript output, and report export.

### Mac Companion

- Import/open a recording where supported.
- Play audio where supported.
- Share/export transcript where supported.

## 18. Production Roadmap

Future production goals:

- Transcript-synced playback.
- Playback speed control.
- Jump-to-segment review.
- Waveform navigation.
- More powerful speaker cleanup: merge speakers, split segments, manual reassignment workflows.
- Optional iCloud sync/backups.
- Summaries and action items.
- Better diarization confidence and overlap handling.
- Broader nontechnical onboarding for friends/family.
- Public/TestFlight distribution polish.

## 19. Out Of Scope For 2.0 Beta

- Cloud transcription.
- Required cloud sync.
- AI summaries or action items.
- Full transcript text editing.
- Public App Store release polish.
- Guaranteed support beyond 30-minute recordings.
- Replacing or modifying the existing Python Transcriber.

## 20. Assumptions

- 2.0 Beta is English-first.
- Speaker labels are important but may need retry/manual cleanup.
- 30 minutes is the beta reliability target.
- The app is iPhone-first.
- Mac is a companion app.
- Model defaults are benchmark-driven.
- Cloud sync/backups are roadmap only.
- Summaries/action items are roadmap only.
- Python Transcriber 1.x remains independent and unchanged.
