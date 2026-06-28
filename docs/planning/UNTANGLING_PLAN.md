# Repository / App Untangling Plan

_Created 2026-06-28 by planning model (Opus 4.6). This plan is staging-only — no implementation happens until the Human Reviewer approves each step._

---

## 1. Executive Summary

This repo contains four app trees that grew together during the Beta 2.0 build. Now that Beta 2.0 is complete, the goal is to **separate them so future work targets one app at a time** without risk of cross-contamination.

The strategy is: **inventory first, then govern, then package, then archive, then plan forward.**

No folders are moved, deleted, or restructured until a read-only inventory confirms what each tree contains and the Human Reviewer approves the specific action. A lighter execution model (Sonnet, Haiku, GPT-5.4 mini, Codex) handles each small step; architecture decisions stay with the Human Reviewer.

---

## 2. Current-State Assumptions

### 2a. What each tree is

| Tree | Role | Size | Status |
|---|---|---|---|
| `src/native/Transcriber2/` | **Primary Swift/SwiftUI app.** 52 Swift files, ~19K lines. Completed 20-objective Beta 2.0 roadmap. Xcode project, unit tests, share extension, tools dir. | Large, active | **Active development. Protected.** |
| `src/python/` | **Original Python transcription app.** 8 Python modules (~1,500 lines), PyQt6 GUI, whisper + pyannote diarization, PyInstaller spec, build script, venv, 2 test files. Has a working `Transcriber.spec` and `build.sh`. | Medium, independent | **Independent. Needs packaging/signing.** |
| `src/legacy-ios/` | **Older iOS Swift reference.** 22 Swift files organized by feature (Audio, Diarization, Models, Processing, Storage, Transcription, Views). No Xcode project file — just source. Includes a Whisper C bridge header. | Small, reference | **Read-only reference. May be archivable.** |
| `XCode App Build/` | **Stale Xcode template.** Contains the default SwiftData "Item" template code (ContentView shows timestamps, `Item.swift` model). Has its own `.git` directory with a single "Initial Commit." 13 files total. Named "Transcriber" which creates agent confusion risk. | Tiny, stale | **Confirmed template. Archive candidate.** |

### 2b. Additional trees of note

| Tree | Role | Notes |
|---|---|---|
| `dist/` | **Python app build output.** Contains `Transcriber.app` (PyInstaller macOS bundle) and a `Transcriber/` directory (standalone binary + `_internal/`). Already-built artifact from Python app. | May be stale; needs validation against current `src/python/` |
| `native/Builds/` | **Swift app archive.** Contains `Transcriber 2.0 Beta.app` — a built copy of the Swift app. | Deployment artifact, not source |
| `assets/` | **Shared assets.** App icon (`.icns`), OLED UI preview images. | Referenced by both apps potentially |
| `docs/planning/` | **Beta 2.0 governance.** 20 objective files, risk register, architecture review, workflow docs. | Valuable; stays |
| `.agent_harness/` | **Agent team config.** Single 3-byte JSON. | Minimal |

### 2c. What needs verification before action

- [ ] **Python app runnability:** Does `src/python/build.sh` still produce a working app? Is `dist/Transcriber.app` current?
- [ ] **Python app dependencies:** Does the venv still resolve? Are torch/pyannote/whisper versions pinned or floating?
- [ ] **Legacy iOS value:** Does `src/legacy-ios/` contain any code NOT already superseded by `src/native/Transcriber2/`? (Especially the Whisper C bridge and custom diarization — the Swift app uses WhisperKit and FluidAudio instead.)
- [ ] **XCode App Build git status:** Its internal `.git` has one commit. Is it tracked by the outer repo or gitignored?
- [ ] **Cross-tree references:** Does any file in one tree `import`, reference, or depend on a file in another tree?
- [ ] **Assets ownership:** Which app(s) use `assets/Transcriber.icns`?
- [ ] **dist/ freshness:** When was `dist/` last built? Does it match current `src/python/`?

---

## 3. Risk Analysis

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| U-R1 | **Agent edits wrong tree** — especially `XCode App Build/Transcriber/` vs `src/native/Transcriber2/` since both have `Transcriber` in the name | High | High | Inventory + rename/archive the stale tree; stricter path guardrails in AGENTS.md and CLAUDE.md |
| U-R2 | **Losing working Beta 2.0 state** — destructive move breaks Swift project paths or git history | Medium | Critical | Tag the current commit as `beta-2.0-complete` before any structural changes; no moves without approval |
| U-R3 | **Breaking Python app** — moving it breaks relative paths in build.sh, Transcriber.spec, or venv | Medium | High | Full inventory of Python internal paths before any move; test build after any change |
| U-R4 | **Breaking Swift Xcode project** — moving `src/native/Transcriber2/` or files it references breaks the `.xcodeproj` | Medium | Critical | Swift app does NOT move during this phase; only governance docs change |
| U-R5 | **Deleting useful legacy reference** — `src/legacy-ios/` has patterns or code that informed the Swift app | Low | Medium | Inventory checks for unique value before any archive/delete decision |
| U-R6 | **Mixing Beta 2.1 features with cleanup** — scope creep adds features during repo restructuring | Medium | High | Hard rule: no feature code during PREP objectives; separate phases |
| U-R7 | **Overpowered models for mechanical tasks** — burning Opus/GPT-5.4 on file listings | Medium | Low (cost) | Risk-tiered model assignment; use cheapest model that fits |
| U-R8 | **Ceremony overhead** — full Manager→Worker→Auditor→QA for a docs edit | High | Medium (cost) | Risk-tiered workflow (§7 below) |
| U-R9 | **Nested `.git` in XCode App Build** — could cause confusion with the outer repo's git | Low | Medium | Inventory confirms; archive plan addresses |
| U-R10 | **OneDrive sync conflicts** — repo lives in OneDrive; large moves/renames can cause sync issues | Low | High | Small changes; no mass renames in one commit |

---

## 4. Proposed Target Structure

### Options considered

#### Option A: One repo, clearer folders + strict governance

```
Transcription app/
├── apps/
│   ├── swift-transcriber/     (renamed from src/native/Transcriber2)
│   └── python-transcriber/    (renamed from src/python)
├── archive/
│   ├── legacy-ios/            (moved from src/legacy-ios)
│   └── xcode-template/        (moved from XCode App Build)
├── docs/
├── assets/
└── governance files (AGENTS.md, DECISIONS.md, etc.)
```

| Pro | Con |
|---|---|
| Single git history preserved | Moving the Xcode project may break `.xcodeproj` internal paths |
| Simple mental model | OneDrive path changes could cause sync issues |
| Governance docs cover everything | Still need discipline to not cross-edit |

#### Option B: Separate repos for Python and Swift

```
transcriber-swift/     (its own repo)
transcriber-python/    (its own repo)
transcriber-archive/   (or just a tagged branch in the original)
```

| Pro | Con |
|---|---|
| Impossible to edit wrong app — different repos | Splits git history |
| Each app gets its own CI, issues, governance | More repos to manage |
| Clean `.gitignore` per app | Shared assets need duplication or a third repo |
| Natural for different teams/models | Migration effort is higher |

#### Option C: Archive in-repo, keep current paths, add governance only

```
(current structure unchanged)
+ CLAUDE.md with strict path rules
+ .claude/settings.json deny patterns
+ Archive tag on legacy trees (README markers)
```

| Pro | Con |
|---|---|
| Zero structural risk | `XCode App Build/` confusion remains |
| Fastest to implement | Doesn't solve "run the Python app independently" |
| No path breakage | Governance is only as good as agent compliance |

#### Option D: Git submodules

| Pro | Con |
|---|---|
| Each app is its own repo but linked | Submodule UX is notoriously painful |
| Clean boundaries | OneDrive + submodules = trouble |
| | Overkill for this project size |

#### Option E: External archive (outside active repo)

Move legacy/stale trees to a separate location outside the repo entirely.

| Pro | Con |
|---|---|
| Cleanest active repo | Files leave git tracking entirely |
| Zero agent confusion | Harder to reference later |
| | Risk of losing track of archived files |

### Recommendation

**Option C now, with a path toward Option B later.**

**Phase 1 (now — PREP objectives):** Keep current paths. Add strict governance (CLAUDE.md, `.claude/settings.json` deny rules, README markers on stale trees). Archive `XCode App Build/` into a tagged commit + removal. Package the Python app so it runs independently.

**Phase 2 (later — post-Beta 2.1 planning):** If the Python app needs its own CI, releases, or collaborators, split it to its own repo. The Swift app stays in this repo as the primary. Legacy iOS gets archived (zip in a tagged release or a separate archive repo).

**Why not separate repos now:** The Python app needs packaging/signing work first. Splitting repos before understanding the Python app's needs risks doing the split wrong. The governance-only approach (Option C) is zero-risk and addresses the immediate agent-confusion problem today.

---

## 5. Staged Objectives

### B2.1-PREP-001 — Repository / App Inventory

**Purpose:** Produce a factual inventory of every app tree so all subsequent decisions are grounded.

**Scope:**
- Read every tree's file listing, entry points, dependencies, build configs
- Determine cross-tree references (imports, shared files, asset usage)
- Classify each file as: active, stale, generated, reference-only
- Check Python app build freshness (`dist/` vs `src/python/`)
- Check `XCode App Build/` nested git status
- Determine if `src/legacy-ios/` has unique value vs `src/native/Transcriber2/`

**Allowed paths:** Read anything. Write only `docs/planning/INVENTORY_REPORT.md`.
**Forbidden:** Editing any source code. Moving/deleting any file.

**Output:** `docs/planning/INVENTORY_REPORT.md` with findings and decision prompts.

**Risk tier:** Read-only inventory. Single report, no tests.
**Estimated model cost:** Low (Haiku/Sonnet sufficient).

---

### B2.1-PREP-002 — Governance Update for Multi-App Repo

**Purpose:** Update governance docs so future agents (including cheaper models) know which app they're working on and cannot accidentally cross-edit.

**Scope:**
- Create `CLAUDE.md` (or `.claude/CLAUDE.md`) with:
  - Active development path declaration
  - Forbidden-path list with rationale
  - App-scoped objective format (objectives must declare which app they target)
  - Risk-tiered workflow rules (see §7)
- Update `AGENTS.md` §2.3 to reference CLAUDE.md rules
- Update `.claude/settings.json` to add deny patterns for `src/python/`, `src/legacy-ios/`, `XCode App Build/` during Swift work
- Add `README.md` markers in `src/legacy-ios/` and `XCode App Build/` saying "THIS TREE IS READ-ONLY / ARCHIVED — do not edit"
- Add app-scoped objective template to `docs/planning/`
- Add lightweight closeout format for docs-only and git-only tasks

**Allowed paths:** Governance/planning docs only. `.claude/` config files.
**Forbidden:** Any file under `src/` or `XCode App Build/` except adding a `README.md` marker.

**Dependencies:** B2.1-PREP-001 (uses inventory findings to set accurate rules).

**Output:** Updated governance files. Short change summary.

**Risk tier:** Docs-only. Manager → QA only.
**Estimated model cost:** Low (Sonnet sufficient).

---

### B2.1-PREP-003 — Python App Packaging / Signing Plan

**Purpose:** Understand what it takes to make the Python app run reliably and propose a packaging/signing approach.

**Scope:**
- Read `src/python/` thoroughly: `main.py` entry point, `config.py`, `gui.py`, `build.sh`, `Transcriber.spec`, `requirements.txt`
- Identify: launch command, all dependencies (with versions), config file locations, local data paths, runtime assumptions (ffmpeg, Homebrew, GPU/MLX)
- Check if `dist/Transcriber.app` is current and functional
- Check if the app needs Hugging Face tokens, model downloads at first run, or network access
- Assess packaging options:
  - PyInstaller (already has a `.spec` — is it working?)
  - py2app (native macOS integration)
  - Standalone venv + shell launcher
  - launchd plist for "always running"
  - Automator wrapper
  - Code signing + notarization requirements
- Produce a recommendation with pros/cons for each viable option
- Identify what "run reliably all the time" means: auto-start on login? Background daemon? Menu bar app? GUI that stays open?

**Allowed paths:** Read `src/python/` and `dist/`. Write only `docs/planning/PYTHON_PACKAGING_PLAN.md`.
**Forbidden:** Editing any source code. Running `pip install`. Modifying the venv.

**Dependencies:** B2.1-PREP-001 (inventory confirms Python app scope).

**Output:** `docs/planning/PYTHON_PACKAGING_PLAN.md` with recommendation. Stops at `ASK USER` for:
- Which packaging approach to use
- Whether "always running" means login-item, launchd daemon, or menu-bar app
- Whether code signing / notarization is needed
- Whether the Python app should auto-update or be manually rebuilt

**Risk tier:** Read-only analysis + single report. Single report, no tests.
**Estimated model cost:** Low–Medium (Sonnet sufficient; needs domain knowledge of Python packaging on macOS).

---

### B2.1-PREP-004 — Python App Packaging / Signing Implementation

**Purpose:** Package and sign the Python app based on the approved plan.

**Scope:** (defined by PREP-003 approval — specifics TBD)
- Implement the approved packaging approach
- Update `build.sh` or create new build tooling
- Test startup, restart, crash recovery
- Verify the app runs without the development venv
- Sign if approved; notarize if approved
- Create a short "How to build and run" doc

**Allowed paths:** `src/python/` and `dist/` only.
**Forbidden:** Any file under `src/native/`, `src/legacy-ios/`, `XCode App Build/`, or governance docs (except updating the Python README).

**Dependencies:** B2.1-PREP-003 approved. Human Reviewer chooses packaging approach.

**Output:** Working packaged Python app. Build/run documentation. Test evidence.

**Risk tier:** Normal feature (Worker → QA → Manager summary).
**Estimated model cost:** Medium (Sonnet or GPT-5.4 mini).

---

### B2.1-PREP-005 — Legacy iOS / XCode App Build Archive Plan

**Purpose:** Decide what to do with the stale trees based on inventory findings.

**Scope:**
- Use PREP-001 inventory to assess:
  - Does `src/legacy-ios/` contain any unique code not in the Swift app?
  - Is `XCode App Build/` purely the Xcode template? (PREP-001 likely confirms yes)
  - Are there any cross-references from active code to these trees?
- Propose options for each tree:
  - **Archive in-repo:** Move to `archive/` folder, keep in git history
  - **Archive via git tag + removal:** Tag current state, then remove from working tree
  - **External archive:** Zip and store outside repo
  - **Delete:** Remove entirely (git history preserves)
  - **Keep as-is with README marker:** If governance is sufficient
- Address the nested `.git` in `XCode App Build/`

**Allowed paths:** Read anything. Write only `docs/planning/ARCHIVE_PLAN.md`.
**Forbidden:** Moving, deleting, or modifying any file in either tree.

**Dependencies:** B2.1-PREP-001 (inventory), B2.1-PREP-002 (governance markers already placed).

**Output:** `docs/planning/ARCHIVE_PLAN.md` with recommendation. Stops at `ASK USER` for:
- Archive vs delete for each tree
- Whether to keep `src/legacy-ios/` as reference or archive it
- Whether to remove `XCode App Build/` from the working tree

**Risk tier:** Read-only analysis + single report.
**Estimated model cost:** Low (Haiku sufficient).

---

### B2.1-PREP-005a — Archive Implementation (if approved)

**Purpose:** Execute the approved archive/removal plan.

**Scope:** (defined by PREP-005 approval — specifics TBD)
- Tag current commit as preservation point
- Execute approved moves/removals
- Verify Swift app still builds after changes
- Verify no broken references
- Update `.gitignore` if needed

**Allowed paths:** Only the trees being archived + `.gitignore`.
**Forbidden:** `src/native/Transcriber2/` source code. `src/python/` source code.

**Dependencies:** B2.1-PREP-005 approved. Human Reviewer chooses archive approach.

**Risk tier:** High-risk (structural change). Manager → Worker → Auditor → QA.
**Estimated model cost:** Low (mechanical, but needs full governance).

---

### B2.1-PREP-006 — Swift App Beta 2.1 Planning

**Purpose:** Convert the deferred backlog (D-016) into structured Beta 2.1 objectives.

**Scope:**
- Review D-016's deferred items list
- Review deferred decisions and open questions in DECISIONS.md
- Group items into logical objectives with dependencies
- Propose sequencing
- Identify which items need Human product decisions before scoping
- Do NOT implement any features

**Allowed paths:** `docs/planning/` only.
**Forbidden:** Any source code. Any file outside `docs/planning/`.

**Dependencies:** B2.1-PREP-001 through PREP-005 complete (repo is untangled before feature planning).

**Output:** `docs/planning/BETA_2.1_ROADMAP_DRAFT.md`. Stops at `ASK USER` for:
- Priority ordering of deferred items
- Whether to add new items beyond the D-016 list
- Scope boundaries for each proposed objective
- Whether Mac polish is a separate track or integrated

**Risk tier:** Docs-only. Manager → QA only.
**Estimated model cost:** Medium (Sonnet — needs product judgment to group well, but no code).

---

## 6. Execution Prompts for Lighter Models

### PROMPT: B2.1-PREP-001 — Repository Inventory

```
You are doing a read-only inventory of a multi-app repository.

## Your task
Produce a file `docs/planning/INVENTORY_REPORT.md` that catalogs every app tree in this repo.

## Rules
- You may READ any file in the repo.
- You may WRITE only `docs/planning/INVENTORY_REPORT.md`.
- Do NOT edit, move, or delete any other file.
- Do NOT run pip install, npm install, or any package manager.
- Do NOT run build commands.
- Do NOT modify any source code.

## What to inventory

For each of these trees, report:

### 1. `src/native/Transcriber2/`
- Count of Swift files and approximate total lines
- List key entry points (app target, share extension, test targets)
- List dependencies (check Package.swift or xcodeproj for SPM packages)
- Note the Xcode project structure

### 2. `src/python/`
- List all Python files with a one-line description of each
- Read `requirements.txt` and list all dependencies with versions
- Read `build.sh` and `Transcriber.spec` — summarize what they do
- Identify the entry point (which file/function starts the app)
- Check if `config.py` references any hardcoded paths
- Note whether the `.venv` exists and its Python version

### 3. `src/legacy-ios/`
- List all Swift files with a one-line description
- Note the absence of an Xcode project file
- Compare file names/purposes against `src/native/Transcriber2/` — are there unique files?
- Flag the Whisper C bridge header as potentially unique

### 4. `XCode App Build/`
- List all files
- Confirm it is the default Xcode SwiftData template (check ContentView.swift for "Item" model)
- Note the nested `.git` directory and its status
- Confirm it has NO custom transcription code

### 5. Other top-level items
- `dist/` — what's in it? Is it a Python build artifact?
- `native/Builds/` — what's the .app file here?
- `assets/` — list files and which app(s) reference them
- `docs/planning/` — summarize contents briefly
- Top-level `.m4a` files — what are they?

### 6. Cross-references
- Do any files in one tree import/reference files in another tree?
- Are there shared config files, shared assets, or shared dependencies?

### 7. Decision prompts
End the report with a "Decisions Needed" section listing questions for the Human Reviewer:
- Is `src/legacy-ios/` still needed as reference?
- Should `XCode App Build/` be archived or removed?
- Is `dist/Transcriber.app` current, or should it be rebuilt?
- Are the top-level audio files (`.m4a`) test fixtures or personal files?

## Format
Use markdown. Be factual and concise. Do not make recommendations — just report what exists.
Stop when the report is written. Do not proceed to any other task.
```

---

### PROMPT: B2.1-PREP-002 — Governance Update

```
You are updating governance documents for a multi-app repository.

## Context
This repo has four app trees. The inventory report is at `docs/planning/INVENTORY_REPORT.md`.
Read it first. Also read `AGENTS.md`, `DECISIONS.md`, and `PLAN.md`.

## Your task
Update governance docs so coding agents know which app they are working on.

## Rules
- You may EDIT: `AGENTS.md`, `.claude/settings.json`, `.claude/settings.local.json`
- You may CREATE: `CLAUDE.md` (at repo root), README.md files inside `src/legacy-ios/` and `XCode App Build/`
- You may CREATE: `docs/planning/OBJECTIVE_TEMPLATE_APP_SCOPED.md`
- Do NOT edit any file under `src/native/`, `src/python/`, or any `.swift`/`.py` file
- Do NOT move or delete any file
- Do NOT change the Xcode project

## What to create/update

### 1. `CLAUDE.md` (repo root)
Create with:
- Declaration: "This repo contains multiple apps. Active development targets one app at a time."
- App registry table: path, name, status (active/independent/archived/stale)
- Current active app declaration: `src/native/Transcriber2/`
- Rule: "Objectives must declare their target app. Do not modify other apps."
- Forbidden-path rules with rationale
- Risk-tiered workflow summary (copy from below)

### 2. `.claude/settings.json`
Add deny patterns so Claude Code warns when editing:
- `src/python/**` (during Swift work)
- `src/legacy-ios/**`
- `XCode App Build/**`
Keep existing permissions. Use the correct settings.json format.

### 3. README markers
Add a short `README.md` to `src/legacy-ios/` and `XCode App Build/` stating:
- What this tree is
- That it is read-only / archived
- When it was last actively developed
- Who to ask before modifying it

### 4. App-scoped objective template
Create `docs/planning/OBJECTIVE_TEMPLATE_APP_SCOPED.md` with fields:
- Target app (path)
- Forbidden paths for this objective
- Risk tier
- Workflow tier (which roles are needed)

### 5. Risk-tiered workflow rules
Add to CLAUDE.md:

| Tier | When | Workflow | Model |
|---|---|---|---|
| High-risk code | Schema changes, dependency bumps, pipeline/engine work, structural moves | Manager → Worker → Auditor → QA | Opus or equivalent |
| Normal feature | New UI, new feature, non-critical code changes | Worker → QA → Manager summary | Sonnet or equivalent |
| Docs-only | Governance, planning, reports, templates | Manager → QA only | Sonnet or Haiku |
| Git-only closeout | Tagging, branching, commit message cleanup | Single compact closeout | Any |
| Read-only inventory | File listings, analysis, reports | Single report, no tests | Haiku |

## Format
Keep docs concise. Match the style of existing AGENTS.md and DECISIONS.md.
When done, report what you created/changed in under 200 words.
```

---

### PROMPT: B2.1-PREP-003 — Python Packaging Plan

```
You are analyzing a Python app to recommend a packaging/signing approach.

## Context
The Python app is at `src/python/`. It is independent from the Swift app in this repo.
The user wants it to "run reliably all the time" on macOS.
Read `docs/planning/INVENTORY_REPORT.md` first for context.

## Rules
- You may READ any file under `src/python/` and `dist/`.
- You may WRITE only `docs/planning/PYTHON_PACKAGING_PLAN.md`.
- Do NOT edit any source code.
- Do NOT run pip install or modify the venv.
- Do NOT run build commands.
- Do NOT touch anything under `src/native/` or `XCode App Build/`.

## What to analyze

### 1. App structure
- Read every file in `src/python/app/` — understand what the app does
- How does it start? (entry point in main.py)
- What GUI framework? (PyQt6)
- What ML models does it use? (whisper, pyannote, mlx)
- Does it need ffmpeg? GPU? Network access?
- Where does it store data/config/models?

### 2. Current build system
- Read `build.sh` — what does it do?
- Read `Transcriber.spec` — is it complete and correct?
- Check `dist/` — is there a working build? How old?

### 3. Dependencies
- Read `requirements.txt` — are versions pinned or floating?
- How large is the dependency tree? (torch, pyannote, etc. are heavy)
- Are there macOS-specific dependencies?

### 4. Packaging options
Evaluate and compare:

| Option | Effort | App size | Auto-start | Signing | Notes |
|---|---|---|---|---|---|
| PyInstaller (existing spec) | Low | Large | Manual | Possible | Already has a spec file |
| py2app | Medium | Large | Easier | Native | Better macOS integration |
| venv + shell script | Low | Minimal | launchd plist | No | Simplest but fragile |
| Homebrew formula | High | Minimal | launchd | No | Distribution-oriented |
| Automator app wrapper | Low | Minimal | Login Items | No | Quick but hacky |

### 5. "Always running" options
- Login item (launches on login, user can quit)
- launchd daemon/agent (auto-restarts on crash)
- Menu bar app (stays in menu bar)
- Regular GUI app (user manages lifecycle)

### 6. Signing/notarization
- Is code signing needed for the app to run without Gatekeeper warnings?
- Does notarization require an Apple Developer account?
- Is ad-hoc signing sufficient for personal use?

## Output
Write `docs/planning/PYTHON_PACKAGING_PLAN.md` with:
- Summary of what the app is and does
- Current build system status
- Dependency analysis
- Comparison table of packaging options with recommendation
- Comparison of "always running" approaches with recommendation
- Signing/notarization assessment
- A "Decisions for Human Reviewer" section with specific questions

## ASK USER for:
- Which packaging approach to use
- What "run reliably all the time" means (daemon? GUI? menu bar?)
- Whether signing/notarization is needed
- Whether the app should auto-update

Do NOT implement anything. Report only.
```

---

### PROMPT: B2.1-PREP-004 — Python Packaging Implementation

```
[This prompt is a TEMPLATE — fill in specifics after PREP-003 is approved]

You are packaging the Python transcription app for reliable macOS use.

## Context
Read `docs/planning/PYTHON_PACKAGING_PLAN.md` for the approved approach.
The Human Reviewer approved: [FILL IN: packaging method, always-running method, signing approach].

## Rules
- You may EDIT files under `src/python/` only.
- You may WRITE to `dist/` (build output).
- Do NOT touch `src/native/`, `src/legacy-ios/`, `XCode App Build/`, or governance docs.
- Do NOT bump Python dependencies without ASK USER.
- Do NOT modify the app's core functionality — packaging only.

## Tasks
1. [FILL IN based on approved plan]
2. Test that the packaged app starts
3. Test that the packaged app can [FILL IN: record, transcribe, show GUI, etc.]
4. Document the build/run process in `src/python/README.md`

## ASK USER for:
- Any step that changes app behavior
- Any new dependency
- Any signing credential or Apple Developer account action

When done, report: what was built, how to run it, and test evidence.
```

---

### PROMPT: B2.1-PREP-005 — Archive Plan

```
You are recommending what to do with stale/legacy app trees.

## Context
Read `docs/planning/INVENTORY_REPORT.md` for the full inventory.
Read `DECISIONS.md` for D-001 and the Q-1 open question about archiving.

## Rules
- You may READ any file in the repo.
- You may WRITE only `docs/planning/ARCHIVE_PLAN.md`.
- Do NOT move, delete, or modify any file.

## Trees to assess

### 1. `XCode App Build/`
- PREP-001 likely confirms this is a default Xcode template with no custom code
- It has a nested `.git` directory
- It is named "Transcriber" which causes agent confusion
- Q-1 in DECISIONS.md already proposed archiving it

### 2. `src/legacy-ios/`
- Older iOS app source (no Xcode project)
- May contain unique reference code (Whisper C bridge, custom diarization)
- The Swift app uses different engines (WhisperKit, FluidAudio)

### 3. `dist/`
- Python build output
- May or may not be current

## Archive options to evaluate

For each tree, evaluate:
1. **Keep as-is + README marker** (already done in PREP-002)
2. **Move to `archive/` folder** — preserves in working tree
3. **Tag + remove from working tree** — `git tag archive/tree-name` then `git rm -r`
4. **Zip + store outside repo** — removes from git entirely
5. **Delete** — gone from working tree, preserved in git history

## Output
Write `docs/planning/ARCHIVE_PLAN.md` with:
- Assessment of each tree's value
- Recommended action for each tree with rationale
- Step-by-step instructions for the approved action (so implementation is mechanical)
- Risks of each option
- "Decisions for Human Reviewer" section

## ASK USER before recommending deletion of anything that might have unique value.
Do NOT implement. Report only.
```

---

### PROMPT: B2.1-PREP-006 — Beta 2.1 Roadmap Draft

```
You are drafting a Beta 2.1 roadmap from the deferred backlog.

## Context
Read these files in order:
1. `DECISIONS.md` — especially D-016 (deferred items list)
2. `PLAN.md` — the completed Beta 2.0 roadmap structure
3. `PRD.md` — the product requirements
4. `QA.md` — known issues and acceptance notes
5. `docs/planning/INVENTORY_REPORT.md` — current repo state

## Rules
- You may READ any file in the repo.
- You may WRITE only `docs/planning/BETA_2.1_ROADMAP_DRAFT.md`.
- Do NOT edit any source code or existing planning docs.
- Do NOT implement any features.

## Tasks
1. Extract every deferred item from D-016
2. Extract open questions from DECISIONS.md
3. Extract known limitations from QA.md
4. Group items into logical objectives (similar to the Beta 2.0 PLAN.md structure)
5. Propose dependencies between objectives
6. Propose sequencing
7. For each proposed objective, note:
   - What Human decisions are needed before scoping
   - Whether it's Swift-only, Python-only, or cross-app
   - Risk tier (from CLAUDE.md governance)
   - Estimated complexity (small/medium/large)

## Output
Write `docs/planning/BETA_2.1_ROADMAP_DRAFT.md` with:
- Summary of deferred items
- Proposed objective groupings
- Proposed sequence
- "Decisions for Human Reviewer" section with specific questions:
  - Priority ordering
  - Scope boundaries
  - Whether Mac polish is separate or integrated
  - Whether any items should be dropped

Do NOT make product decisions. Present options and trade-offs.
```

---

## 7. Governance Simplification — Risk-Tiered Workflow

The Beta 2.0 workflow (Manager → Worker → Auditor → QA) was valuable for risky code objectives but too expensive for closeouts and documentation. Going forward, match the workflow to the risk:

### Tier definitions

| Tier | Trigger | Roles | Model recommendation | Example |
|---|---|---|---|---|
| **Critical** | Schema migration, dependency bump, pipeline/engine change, structural repo change, data-loss-adjacent code | Manager → Worker → Auditor → QA → Human gate | Opus or strongest available | Changing `Recording` model, bumping WhisperKit, moving `src/native/` |
| **High** | New feature touching audio/transcription/diarization paths, concurrency changes, new UI screens | Manager → Worker → Auditor → QA | Opus or Sonnet | Adding a new recording mode, modifying TranscriptionSession |
| **Normal** | Standard feature, UI polish, non-critical bug fix, test additions | Worker → QA → Manager summary | Sonnet | Adding a settings toggle, fixing a display bug |
| **Docs-only** | Governance updates, planning docs, README changes, templates | Manager → QA only | Sonnet or Haiku | Updating AGENTS.md, writing a planning doc |
| **Git-only** | Tagging, branching, commit cleanup, `.gitignore` updates | Single compact closeout | Any | Tagging `beta-2.0-complete` |
| **Read-only** | Inventory, analysis, reports with no code changes | Single report (no QA needed) | Haiku | Repository inventory, dependency audit |

### Rules for tier assignment

1. **The Human Reviewer or Manager assigns the tier** at objective creation.
2. **Tier can only go UP, never down** during execution. If a docs-only task discovers it needs a code change, it escalates to Normal or higher.
3. **Auditor is only required at High and Critical tiers.** For Normal and below, the QA tester or Manager catches drift.
4. **Human-owned gates apply at ALL tiers** when device-specific behavior is involved.
5. **Cost guideline:** If the full workflow costs more than the change is worth, the tier is too high. A 5-line README change should not burn 4 agent passes.

### Closeout format by tier

| Tier | Closeout | What gets written |
|---|---|---|
| Critical / High | Full completion report in objective file + QA.md evidence | Everything: worker report, auditor alignment, QA evidence, gate decision, planning doc updates |
| Normal | Short completion note in objective file + QA.md evidence | Worker summary, QA evidence, gate decision |
| Docs-only | Inline note in the PR/commit or a 3-line summary | What changed and why |
| Git-only | Commit message only | N/A |
| Read-only | The report IS the closeout | N/A |

---

## 8. Specific First Task

**Paste this into a lighter execution model to start B2.1-PREP-001:**

The full prompt is in §6 above under "PROMPT: B2.1-PREP-001 — Repository Inventory."

Before pasting that prompt, do these two things manually:

1. **Tag the current commit:**
   ```sh
   git tag beta-2.0-complete
   ```
   This preserves the exact Beta 2.0 state before any untangling work begins.

2. **Verify the tag:**
   ```sh
   git log --oneline -1 beta-2.0-complete
   ```
   Should show `5f94870 Complete OBJ-20 beta acceptance`.

Then paste the PREP-001 prompt. The model will read files and produce `docs/planning/INVENTORY_REPORT.md`. Review the report before proceeding to PREP-002.

---

## 9. Decision Points for the Human Reviewer

These decisions cannot be delegated to execution models. They will arise during the PREP objectives:

| # | Decision | When | Needed before |
|---|---|---|---|
| 1 | **One repo or separate repos?** Should the Python and Swift apps eventually live in separate git repositories? | After PREP-001 inventory | PREP-005 archive plan |
| 2 | **How to package the Python app?** PyInstaller, py2app, venv+script, or something else? | After PREP-003 analysis | PREP-004 implementation |
| 3 | **What does "always running" mean for the Python app?** Login item, launchd agent, menu bar, or regular GUI? | After PREP-003 analysis | PREP-004 implementation |
| 4 | **Does the Python app need code signing?** Ad-hoc, Developer ID, or none? | After PREP-003 analysis | PREP-004 implementation |
| 5 | **Archive or remove `XCode App Build/`?** Tag+remove, move to archive folder, or keep with marker? | After PREP-001 confirms it's a template | PREP-005a implementation |
| 6 | **Keep or archive `src/legacy-ios/`?** Reference value vs clutter? | After PREP-001 compares to Swift app | PREP-005a implementation |
| 7 | **Where should Beta 2.1 planning live?** Same `docs/planning/` or a new structure? | After PREP-005 archive is done | PREP-006 planning |
| 8 | **Is Mac polish a separate track?** Integrated into Swift objectives or its own stream? | During PREP-006 | PREP-006 sequencing |
| 9 | **How strict should path guardrails be?** Soft warnings, hard denies, or separate repos? | After PREP-002 governance is tested | Ongoing |
| 10 | **Top-level audio files** — are `test_clip.m4a` and `Kelly Creek Dr.m4a` test fixtures, personal files, or something to clean up? | PREP-001 inventory | PREP-005 archive plan |

---

## 10. Final Recommendation

### Safest order of operations

```
1. git tag beta-2.0-complete              ← Preserve Beta 2.0 state (manual, 10 seconds)
2. B2.1-PREP-001: Inventory               ← Read-only, produces report (Haiku, ~5 min)
3. Human reviews inventory report          ← You decide what's valuable
4. B2.1-PREP-002: Governance update        ← Docs-only, adds guardrails (Sonnet, ~10 min)
5. B2.1-PREP-003: Python packaging plan    ← Read-only analysis (Sonnet, ~10 min)
6. Human reviews packaging plan            ← You choose the approach
7. B2.1-PREP-004: Python packaging impl    ← Code changes in src/python/ only (Sonnet, ~30 min)
8. B2.1-PREP-005: Archive plan             ← Read-only analysis (Haiku, ~5 min)
9. Human reviews archive plan              ← You choose what to archive/keep
10. B2.1-PREP-005a: Archive implementation ← Structural change, needs full workflow (Sonnet, ~15 min)
11. B2.1-PREP-006: Beta 2.1 roadmap draft  ← Docs-only planning (Sonnet, ~15 min)
12. Human reviews roadmap                  ← You set priorities for Beta 2.1
```

### What NOT to do yet

- **Do not move or rename any folders.** Inventory first.
- **Do not start Beta 2.1 feature work.** The repo isn't untangled yet.
- **Do not split into separate repos.** Too early — understand the Python app's needs first.
- **Do not delete `XCode App Build/` yet.** Even though it's confirmed template code, follow the tag → inventory → approve → archive sequence.
- **Do not start Python signing until the packaging plan is reviewed.** The wrong approach wastes significant time (PyInstaller bundles can be 2+ GB with torch).
- **Do not let execution models make architecture decisions.** They report findings and stop at `ASK USER`.
- **Do not use Opus/expensive models for inventory or docs tasks.** Haiku or Sonnet handles these fine.
- **Do not run multiple PREP objectives in one session.** Each one should be a separate, short execution with a human checkpoint between.

### The one thing to do right now

```sh
cd "/Users/daniel/Library/CloudStorage/OneDrive-Personal/AI Research/Transcription app"
git tag beta-2.0-complete
```

Then paste the PREP-001 inventory prompt into a Haiku or Sonnet session.
