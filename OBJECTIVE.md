# OBJECTIVE.md — Active Work Pointer

Last updated: 2026-07-29

## Status: VX-03 is awaiting Human approval; Phase 0 milestone is pending

Daniel authorized activation and sequential execution of all Phase 0 objectives on 2026-07-29. This authorization satisfies approval-to-start and between-objective activation requirements for VX-01, VX-02, and VX-03, but it does not pre-approve private-audio use, deletion choices, or the VX-03 Human data-model gate.

Only one objective is active at a time. Phase 1 remains unauthorized.

## Active objective

**[VX-03 — Versioned processing contracts and migration design](docs/planning/objectives/VX-03.md)**

Risk tier: docs-only design for future Critical storage and migration work; independent audit required.

Agent-verifiable result: final Auditor `ALIGNED`; QA PASS.

Manager gate: `ASK USER`.

Authorized result:

- Versioned normalized processing contracts.
- Explicit stable IDs, timebase, provenance, uncertainty, and state semantics.
- SwiftData/artifact/cache placement and old-record compatibility.
- Atomic-write, corruption, cleanup, transcript-history, and rollback design.
- No production, schema, user-data, dependency, or behavior change.

## Human decisions before Phase 1

1. Resolve VX-02 disposition choices, either individually or by choosing the conservative default to retain every candidate in place and defer all cleanup.
2. Approve the nine VX-03 principles in [VX-03-MIGRATION-DESIGN.md §12](docs/planning/evidence/VX-03-MIGRATION-DESIGN.md#12-decisions-requiring-human-approval).
3. Explicitly authorize activation of VX-04 after the Phase 0 milestone passes.

No Phase 1 objective is active.

## Phase 0 authorization boundary

- VX-01, VX-02, and VX-03 may be activated sequentially without another start request.
- Private audio must not be used unless Daniel separately approves an exact source or bounded collection.
- VX-02 inventories and proposes removals; it does not remove application files.
- VX-03 designs contracts and migration only; no production schema or behavior changes are authorized.
- The Phase 0 milestone cannot pass until all Human-owned gates are explicitly resolved.

## Historical roadmap

The original Beta 2.0 objectives (OBJ-01 through OBJ-20, including OBJ-17.1) remain under [docs/planning/objectives/](docs/planning/objectives/) as historical completion evidence. They are not active work and must not be edited to make the new roadmap appear complete.

## Required read order for implementation

1. [PRD.md](PRD.md)
2. [PLAN.md](PLAN.md)
3. This file
4. [AGENTS.md](AGENTS.md)
5. [CLAUDE.md](CLAUDE.md)
6. [DECISIONS.md](DECISIONS.md)
7. The active objective’s linked supporting references
