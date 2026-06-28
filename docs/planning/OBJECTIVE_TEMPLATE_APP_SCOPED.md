# Objective Template — App-Scoped

Use this template for every new objective in this repository. It exists because the repo contains multiple app trees (see [CLAUDE.md](../../CLAUDE.md) §1) and an objective that doesn't declare its target app/paths up front is the most common path to an agent editing the wrong tree.

Copy this into a new `docs/planning/objectives/OBJECTIVE-NN.md` (or the relevant location) and fill in every section before work begins.

---

## Objective Title

_Short, descriptive name._

## Target App / Path

_Which row of the [CLAUDE.md](../../CLAUDE.md) §1 App Registry does this objective touch? State the exact path(s), e.g. `src/native/Transcriber2/`. If more than one app is touched, justify why this isn't two separate objectives._

## Objective Type

_One of: feature, bug fix, refactor, governance/docs, packaging, archive/cleanup, investigation/report._

## Risk Tier

_One of the five tiers from [CLAUDE.md](../../CLAUDE.md) §4: Critical/high-risk code · Normal feature · Docs-only · Git-only closeout · Read-only inventory._

## Allowed Paths

_Exact directories/files this objective may create or edit. Be specific — "the Swift app" is not specific enough; list the actual files or subdirectories expected to change._

## Forbidden Paths

_Explicitly list every other app tree this objective must not touch, especially the other trees containing "Transcriber" in their path (`XCode App Build/`, `src/legacy-ios/`) and the independent Python app (`src/python/`) if this objective targets the Swift app, or vice versa._

## Out of Scope

_Anything adjacent that might tempt scope creep — name it here so it goes to "Notes for the Manager" instead of into the diff._

## Required Reads

_Which governance/planning docs must be read before starting (e.g. CLAUDE.md, AGENTS.md, the relevant DECISIONS.md entries, prior objective files)._

## Implementation Tasks

_Numbered list of concrete steps._

## Validation

_What must pass before this objective can be marked done. For code changes: build/test commands. For docs-only: what was cross-checked for consistency. For read-only inventory: confirmation no files outside the one allowed report changed._

## Closeout Mode

_Per [CLAUDE.md](../../CLAUDE.md) §4 closeout table for this objective's tier — full Manager/Worker/Auditor/QA report, short completion note, inline summary, commit-message-only, or single report._

## ASK USER Triggers

_Conditions under which this objective must stop and escalate to the Human Reviewer rather than proceeding — e.g. a forbidden-path edit becomes necessary, a product decision is required, or a Human-owned device gate is reached._
