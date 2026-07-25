# Documentation index for Codex

This is the smallest entry point for repository questions. It routes Codex to the
authoritative section without duplicating the full rules. `AGENTS.md` remains the
instruction authority.

## Minimal reading route

Read only the row that matches the task, plus the target file and its direct
dependencies. Do not reload a document already read in the same task.

| Task | Read first | Expand only when needed |
| --- | --- | --- |
| Project overview, requirements, or license | [`README.md`](../README.md) | The named source or document |
| Read-only architecture or dependency question | [`PLACEMENT_RULES.md` §2–4](PLACEMENT_RULES.md#2-layer-ownership) | §1 for the physical tree; §5–7 for growth or migration |
| Decide where a new file belongs | [`PLACEMENT_RULES.md` §4–5](PLACEMENT_RULES.md#4-placement-decision) | §1 and §6 if a Feature boundary is involved |
| Source-code implementation or review | [`CODING_STANDARDS.md`](CODING_STANDARDS.md) and [`PLACEMENT_RULES.md`](PLACEMENT_RULES.md) | Directly relevant tests and configuration |
| Swift DocC or single-responsibility question | [`CODING_STANDARDS.md` §2–3](CODING_STANDARDS.md#2-core-rule-one-reason-to-change) | §6–8 for naming, injection, or tests |
| View or presentation change | [`CODING_STANDARDS.md` §4–5](CODING_STANDARDS.md#4-replaceable-screen-rule) | Placement §2–4; macOS contract for macOS UI |
| macOS layout or visual review | [`CODING_STANDARDS.md` §5](CODING_STANDARDS.md#5-platform-separation) | §10 for handoff; relevant Platform tests |
| OBD, persistence, logging, or analysis boundary | [`CODING_STANDARDS.md` §9](CODING_STANDARDS.md#9-obd-acquisition-persistence-and-analysis-boundaries) | Placement §2–4 and the owning Feature in §6 |
| Feature ownership or a new Feature | [`PLACEMENT_RULES.md` §6](PLACEMENT_RULES.md#6-feature-growth) | §1 and §5 before adding a directory |
| Validation or handoff | [`CODING_STANDARDS.md` §8 and §10](CODING_STANDARDS.md#8-tests) | macOS visual evidence in §5 when applicable |

Source changes still require the full two standards under `AGENTS.md`; the section
links above optimize investigation and read-only questions, not implementation
compliance.

## Architecture at a glance

```text
Platform ──▶ Application ──▶ Domain ◀── Data
                    App constructs dependencies
```

- `App`: entry point and composition only.
- `Domain`: framework-independent business meaning and repository contracts.
- `Application`: actions, state, ports, and use-case orchestration.
- `Data`: database, network, file, device, and framework adapters.
- `Platform/iOS`, `Platform/macOS`: independent presentation and layout trees.
- `Shared`: small stable primitives with real consumers in multiple owners.
- Tests mirror the production path under `ProjectZD8Tests` or `ProjectZD8UITests`.

Approved Features are `Authentication`, `Settings`, `DeviceConnection`,
`VehicleManagement`, `Maintenance`, `LiveTelemetry`, `Logging`, `LogHistory`, and `Analysis`.
Their authoritative ownership definitions are in
[`PLACEMENT_RULES.md` §1 and §6](PLACEMENT_RULES.md#projectzd8-product-scaffold).

## Fast lookup

Prefer heading and literal searches before opening a complete document:

```sh
rg -n '^## |^### ' Documentation/*.md
rg -n -F -e 'term' Documentation README.md AGENTS.md
rg --files ProjectZD8 ProjectZD8Tests ProjectZD8UITests | rg '/FeatureName/'
```

Avoid broad reads of generated output, DerivedData, package caches, empty scaffold
directories, or unrelated Features. Treat build, unit-test, UI-runner, visual,
real-device, real-adapter, and external-service evidence as separate claims.

## Document responsibilities

| Document | Single responsibility |
| --- | --- |
| [`AGENTS.md`](../AGENTS.md) | Mandatory workflow and handoff instructions for Codex changes |
| [`README.md`](../README.md) | Human-facing project entry point, requirements, and license summary |
| [`CODING_STANDARDS.md`](CODING_STANDARDS.md) | Source-quality, UI-boundary, testing, and review contracts |
| [`PLACEMENT_RULES.md`](PLACEMENT_RULES.md) | Physical ownership, dependency direction, and folder approval rules |
| `INDEX.md` | Token-efficient routing to the authoritative document section |

When adding documentation, extend an existing owner when its responsibility fits.
Add a new document only for a distinct, durable responsibility, then register it in
this table and link it from the relevant authoritative document.
