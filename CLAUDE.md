# CLAUDE.md — Multi-App Repository Guardrails

**This repository contains multiple app trees that grew together during Beta 2.0.** Before touching any file, identify which app/tree your objective targets and confirm your edits stay inside its allowed paths. Editing the wrong tree is the single highest agent-confusion risk in this repo (see [DECISIONS.md](DECISIONS.md) D-001, D-017).

This file is read alongside [AGENTS.md](AGENTS.md). AGENTS.md governs the Swift app's objective workflow in detail; this file governs **cross-app boundaries** that apply no matter which app or doc-only task you're doing.

---

## 1. App Registry

| Path | App / Tree | Status | Allowed Modification Policy |
|---|---|---|---|
| `src/native/Transcriber2/` | **Transcriber 2.0 (Swift/SwiftUI)** | **Active development** | The only app under active feature/fix work. Edit per the active OBJECTIVE and [AGENTS.md](AGENTS.md). |
| `src/python/` | **Transcriber 1.x (Python/PyQt6)** | Independent, not under Beta 2.x development | **Do not touch** during Swift work. Edits require their own explicitly approved, app-scoped objective. |
| `src/legacy-ios/` | **Legacy iOS prototype (Swift, no Xcode project)** | Read-only reference | **Do not edit.** Archive decision pending (see [docs/planning/INVENTORY_REPORT.md](docs/planning/INVENTORY_REPORT.md)). |
| `XCode App Build/` | **Stale Xcode/SwiftData template** | Stale / archive candidate | **Do not edit.** Not the active app — it is default template code with a nested `.git`. Archive/removal decision pending. |
| `dist/` | Python build artifact (PyInstaller output) | Generated | Do not hand-edit. Regenerate via `src/python/build.sh` only inside an approved Python-app objective. |
| `native/Builds/` | Swift app build artifact | Generated | Do not hand-edit. Regenerate via Xcode build only. |
| `assets/` | Shared assets (icon, UI preview images) | Shared | Treat as intentional; do not delete without Human Reviewer confirmation (see AGENTS.md §2.7–2.8). |
| `docs/planning/` | Governance & planning docs | Active | Edit per the active objective's allowed paths. |

**Current active Swift app path:** `src/native/Transcriber2/`

---

## 2. Every Future Objective Must Declare

Before any work begins, an objective (in [OBJECTIVE.md](OBJECTIVE.md), an `OBJECTIVE-NN.md` file, or an ad-hoc task prompt) must state:

1. **Target app** — which row of the App Registry (§1) this objective touches.
2. **Allowed paths** — the specific directories/files this objective may edit.
3. **Forbidden paths** — explicitly, every other app tree (especially the other "Transcriber"-named trees).
4. **Risk tier** — one of the five tiers in §4 below.

An objective with no target app declared defaults to **no source-code edits** — read/report only — until the Human Reviewer assigns a target app.

A template for this is at [docs/planning/OBJECTIVE_TEMPLATE_APP_SCOPED.md](docs/planning/OBJECTIVE_TEMPLATE_APP_SCOPED.md).

---

## 3. Explicit Warnings

### ⚠️ `XCode App Build/` is stale and must not be edited
This tree is a default Xcode "New Project" template (SwiftUI + SwiftData `Item` model). It contains **no transcription code**. It is named `Transcriber`, which makes it easy to confuse with the active app — check the full path, not just the folder name, before editing anything under a path containing "Transcriber." It has its own nested `.git/` repository; do not modify, delete, or merge that nested `.git`.

### ⚠️ `src/python/` is an independent app — do not touch during Swift work
This is Transcriber 1.x: a separate PyQt6 desktop app with its own venv, `requirements.txt`, `build.sh`, and `Transcriber.spec`. It shares no code with `src/native/Transcriber2/`. Any change to this tree requires its own explicitly approved, app-scoped objective — never as a side effect of Swift work.

### ⚠️ `src/legacy-ios/` is read-only reference
Older iOS Swift prototype, no Xcode project file. It may contain reference patterns (custom diarization clustering, a Whisper C bridge) not present in the active app. Do not edit it. Whether it has unique value worth preserving, and whether to archive it, is an open decision — see [docs/planning/INVENTORY_REPORT.md](docs/planning/INVENTORY_REPORT.md).

---

## 4. Risk-Tiered Workflow

Match the workflow to the risk of the change. Do not run the full Manager → Worker → Auditor → QA loop for a docs-only edit, and do not skip it for schema/dependency/pipeline changes.

| Tier | Trigger | Workflow |
|---|---|---|
| **Critical / high-risk code** | Schema migration, dependency bump, pipeline/engine change, structural repo change (moves/archival), data-loss-adjacent code | Manager → Worker → Auditor → QA |
| **Normal feature** | Standard feature work, UI changes, non-critical bug fixes, test additions, within the active app's existing architecture | Worker → QA → Manager summary |
| **Docs-only** | Governance updates, planning docs, README changes, templates — no source code touched | Manager → QA only |
| **Git-only closeout** | Tagging, branching, commit-message cleanup, `.gitignore` updates | Compact closeout (commit/tag description; no QA pass needed) |
| **Read-only inventory** | File listings, cross-reference analysis, reports with zero code or doc-state changes beyond the one report file | Single report; no QA pass needed |

**Tier assignment:** The Human Reviewer or Manager assigns the tier when the objective is created. The tier can only escalate (go up), never de-escalate, mid-objective — if a docs-only task discovers it needs a code change, stop and re-scope as Normal or higher rather than proceeding under the lower tier.

This repository's existing Manager/Worker/Auditor/QA role definitions are in [AGENTS.md](AGENTS.md) §3; this table only says which roles are required for a given tier, not how each role operates.

---

## 5. Tool-Level Enforcement (Deferred)

`.claude/settings.json` does not currently exist in this repo (only `.claude/settings.local.json`, which holds unrelated `Bash` permission allow-rules). Adding deny-pattern enforcement for the protected paths above (`src/python/**`, `src/legacy-ios/**`, `XCode App Build/**`) was considered during this governance update but **not implemented**, because the correct deny-pattern syntax for this Claude Code settings format was not confirmed safe to invent without risking a malformed config that silently fails to enforce anything.

**Recommended follow-up (ASK USER):** Confirm the correct settings.json deny-pattern syntax for this Claude Code version, then add rules denying writes to:
- `src/python/**`
- `src/legacy-ios/**`
- `XCode App Build/**`

Until that is confirmed and added, enforcement of §1–§3 above is **policy-only** (governance docs + Auditor review), not tool-enforced. Treat every objective's stated forbidden paths as binding regardless.

---

## 6. Reading Order for This File

If you are about to start any objective:
1. Read this file (CLAUDE.md) first to confirm target app and tier.
2. Then read [AGENTS.md](AGENTS.md) for the Swift-app-specific operating rules (if your target app is `src/native/Transcriber2/`).
3. Then read the active objective document.

If your objective's target app is anything other than `src/native/Transcriber2/`, AGENTS.md's detailed rules (concurrency, schema, dependency policy) may not apply verbatim — but the cross-app boundaries in §1–§3 here always apply.
