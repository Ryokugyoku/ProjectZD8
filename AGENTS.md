# Codex implementation rules

This file contains mandatory instructions for every Codex change in this repository.
Human review is the final approval gate; Codex must make its reasoning inspectable.

## Required reading

Before changing source code, read:

1. `Documentation/CODING_STANDARDS.md`
2. `Documentation/PLACEMENT_RULES.md`
3. The target file and its direct dependencies

Preserve unrelated user changes. Do not broaden the requested scope without explicit approval.

## Context-efficient workflow

Use the smallest sufficient evidence set. Token reduction MUST NOT weaken required reading, safety, dependency review, tests, or truthful reporting.

- Start with `git status --short` and `rg` or `rg --files`. After required reading, inspect only the target, direct dependencies, and directly relevant tests or configuration; expand only when evidence requires it.
- Do not enumerate or read empty scaffold directories, generated output, DerivedData, package caches, binaries, or unrelated features.
- Reuse same-task evidence; do not reread unchanged files or repeat unchanged checks without a concrete reason.
- Run the narrowest relevant check first, then broaden validation in proportion to the change's risk. A narrow check does not replace a required broader gate.
- Summarize results and errors instead of reproducing long logs, and do not repeat evidence across updates and handoff.

## Mandatory implementation rules

- Follow the dependency direction and file placement in `Documentation/PLACEMENT_RULES.md`.
- Give each file and named declaration one primary responsibility and one primary reason to change.
- Add Swift DocC to every new or changed declaration, property, initializer, subscript, and method, including `private` declarations.
- Write all Swift DocC prose in Japanese, including summaries, responsibilities, parameter descriptions, return values, thrown errors, side effects, preconditions, and invariants. DocC syntax and code identifiers may remain in their required source form.
- State each method's single responsibility explicitly as a Japanese `責務:` sentence in its DocC comment.
- If the responsibility cannot be described accurately in one sentence, split the method or type until it can.
- Place each extracted responsibility in a new file when required by the placement rules. Do not create generic `Helpers`, `Utils`, `Common`, or `Managers` dumping grounds.
- Keep iOS and macOS layout trees in `Platform/iOS` and `Platform/macOS`, respectively. Do not share screen layout types or use large platform `#if` branches to combine them.
- For macOS UI work, follow `Documentation/CODING_STANDARDS.md` section “macOS visual and layout contract,” including its concept, measurements, interaction states, localization resilience, and visual-evidence checklist.
- Treat Views as replaceable rendering code. A View may render presentation state, hold short-lived UI-only state, and dispatch a typed user action. It must not perform procedures or own business state.
- Do not access SwiftData, GRDB, SQL, `ModelContext`, files, network clients, external devices, clocks, or other infrastructure from a View.
- Put use-case orchestration in `Application`, business rules in `Domain`, infrastructure implementations in `Data`, and dependency construction in `App`.
- Add or update tests for changed behavior. Mirror the production folder structure under the relevant test target.
- Do not claim visual approval, real-device behavior, external-service behavior, or hosted-CI success from a local build or unit test.

## Before handoff

Codex must report:

- changed files and the responsibility of each;
- validation actually run and its result;
- known limitations or unverified behavior;
- any deliberate exception to these rules and the human approval authorizing it.

Use the review checklist in `Documentation/CODING_STANDARDS.md` before requesting human review.
