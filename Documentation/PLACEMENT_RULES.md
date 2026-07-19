# Folder and dependency rules

## 1. Required source tree

New production files MUST use the following scalable structure. Create only the branches needed by the current feature; empty placeholder folders are unnecessary.

```text
ProjectZD8/
├── App/
│   ├── Composition/
│   └── ProjectZD8App.swift
├── Domain/
│   ├── Entities/
│   ├── ValueObjects/
│   ├── Policies/
│   ├── Repositories/
│   └── Errors/
├── Application/
│   └── Features/
│       └── <Feature>/
│           ├── Actions/
│           ├── State/
│           ├── UseCases/
│           └── Ports/
├── Data/
│   ├── Persistence/
│   │   ├── SwiftData/
│   │   └── GRDB/
│   ├── Network/
│   ├── Files/
│   ├── Devices/
│   └── Mapping/
├── Platform/
│   ├── iOS/
│   │   └── Features/<Feature>/
│   │       ├── Views/
│   │       └── Presentation/
│   └── macOS/
│       └── Features/<Feature>/
│           ├── Views/
│           └── Presentation/
├── Shared/
│   ├── Foundation/
│   └── DesignSystem/
├── Resources/
└── PreviewSupport/
```

Test targets MUST mirror the production path they verify. For example:

```text
ProjectZD8Tests/Application/Features/Items/UseCases/CreateItemUseCaseTests.swift
ProjectZD8Tests/Data/Persistence/SwiftData/SwiftDataItemRepositoryTests.swift
ProjectZD8UITests/Platform/iOS/Features/Items/ItemListUITests.swift
```

### ProjectZD8 product scaffold

ProjectZD8 uses the following approved product feature set. New production work MUST use these names unless a human reviewer approves and records a different product boundary:

- `DeviceConnection` owns connecting to and disconnecting from the OBD diagnostic device.
- `LiveTelemetry` owns the application state and actions required for real-time presentation.
- `Logging` owns capture-session start, sample recording, and capture-session termination workflows.
- `LogHistory` owns queries and presentation state for previously recorded logs.
- `Analysis` owns orchestration of analysis over recorded logs and retrieval of analysis results.

The approved physical scaffold is:

```text
ProjectZD8/
├── App/Composition/
├── Domain/
│   ├── Entities/
│   ├── ValueObjects/
│   ├── Policies/
│   ├── Repositories/
│   └── Errors/
├── Application/Features/
│   ├── DeviceConnection/{Actions,State,UseCases,Ports}/
│   ├── LiveTelemetry/{Actions,State,UseCases,Ports}/
│   ├── Logging/{Actions,State,UseCases}/
│   ├── LogHistory/{Actions,State,UseCases}/
│   └── Analysis/{Actions,State,UseCases,Ports}/
├── Data/
│   ├── Devices/{Serial,OBD}/
│   ├── Persistence/GRDB/{Database,Records,Repositories}/
│   ├── MachineLearning/TensorFlow/
│   └── Mapping/
├── Platform/
│   ├── iOS/
│   │   ├── AppShell/
│   │   └── Features/{DeviceConnection,LiveTelemetry,LogHistory,Analysis}/{Views,Presentation}/
│   └── macOS/
│       ├── AppShell/
│       └── Features/{DeviceConnection,LiveTelemetry,LogHistory,Analysis}/{Views,Presentation}/
├── Shared/
│   ├── Foundation/
│   └── DesignSystem/{Colors,Typography,Components}/
├── Resources/{iOS,macOS,Localization,Models}/
└── PreviewSupport/
```

Brace notation in this diagram abbreviates separate physical directories; it is not a literal directory name.

This scaffold is a human-approved exception to the general rule against speculative empty directories because the product boundaries are already identified. The exception authorizes directories only: it does not authorize placeholder source declarations, `.gitkeep` files, framework choices, or implementation. Empty directories are not represented by Git, so this document is the canonical reconstruction record until implementation files are added.

## 2. Layer ownership

### App

Owns process entry points, dependency construction, and lifecycle wiring. It may know every layer but MUST NOT contain business rules, persistence algorithms, or screen layouts.

### Domain

Owns framework-independent business meaning: entities, value objects, policies, invariants, domain errors, and repository capabilities. Domain MUST NOT import SwiftUI, SwiftData, GRDB, networking, or platform frameworks.

### Application

Owns use-case orchestration, commands/actions, application state transitions, and ports needed to execute workflows. It may depend on Domain. It MUST NOT depend on concrete Data adapters or Platform types.

### Data

Owns concrete persistence, network, file, and device adapters plus infrastructure mapping. It implements Domain or Application ports. It MUST NOT depend on Platform or construct Views.

Within Data, serial transport and OBD protocol implementations belong in `Devices/Serial` and `Devices/OBD`, respectively. Concrete TensorFlow integration belongs in `MachineLearning/TensorFlow`; framework-independent analysis policy does not.

### Platform

Owns platform-specific presentation, navigation, input adaptation, and screen layout. It may depend on Application and Domain presentation-safe types. It MUST NOT access concrete Data implementations.

### Shared

Owns only small, stable primitives genuinely used by multiple layers or both platforms. It is not a fallback destination. Feature-specific code stays with its feature, and business rules stay in Domain.

### Resources and PreviewSupport

`Resources` owns non-code assets and localization. `PreviewSupport` owns deterministic preview fixtures only; production workflows MUST NOT depend on it.

## 3. Allowed dependency direction

```text
Platform ───────▶ Application ───────▶ Domain
                       ▲                  ▲
                       │                  │
Data ── implements Application ports and Domain repository contracts

App ── constructs Platform, Application, Domain, and Data dependencies
```

The following imports or references are prohibited:

| From | Prohibited dependency |
| --- | --- |
| Domain | Application, Data, Platform, App, SwiftUI, SwiftData, GRDB |
| Application | concrete Data adapters, Platform, App, SwiftUI, database SDKs |
| Data | Platform, App, screen state, View types |
| Platform View | Data, SwiftData, GRDB, SQL, `ModelContext`, transport clients |
| Shared | feature workflows, screen composition, concrete infrastructure |

## 4. Placement decision

For every new responsibility, choose its location by asking:

1. Is it a business truth or invariant? Place it in `Domain`.
2. Does it coordinate a user/system outcome? Place it in `Application/Features/<Feature>`.
3. Does it talk to a database, file, network, service, or device? Define an inward-facing port and place the implementation in `Data`.
4. Does it render or adapt input for one Apple platform? Place it under that platform's feature tree.
5. Does it only assemble concrete dependencies? Place it in `App/Composition`.
6. Is it a stable primitive with real consumers in multiple owners? Only then consider `Shared`.

If none applies, the responsibility is not authorized for placement. Follow the approval gate below instead of choosing a new folder independently.

## 5. New-folder approval gate

When requested content cannot be placed accurately in the approved scaffold, Codex MUST stop before creating a new directory and present a proposal to the user. The proposal MUST state:

1. the new responsibility and its single reason to change;
2. why no existing approved directory owns that responsibility;
3. the proposed directory path and owning layer or feature;
4. the intended dependency direction and prohibited dependencies;
5. the production and test paths that would be added; and
6. any viable alternative that uses the existing scaffold, including its tradeoff.

Codex MUST obtain explicit user approval for the proposed path before creating the directory. Silence, approval of the feature itself, approval of a related screen, or an earlier approval of the general architecture does not count as approval of a new directory.

After approval, Codex MUST create only the approved directory scope and update this document when the new path changes the canonical scaffold or ownership rules. If the user rejects or changes the proposal, Codex MUST not leave behind speculative directories or placeholder files from the rejected proposal.

This gate applies to production, test, UI-test, resource, preview, tooling, generated-code, and external-runtime directories. It does not authorize source implementation; implementation remains governed by the user's requested scope and the repository's coding standards.

## 6. Feature growth

Group Application and Platform code by product feature before technical subtype. A feature should expose narrow state/actions/use cases and keep internal implementation details private where practical.

Do not create speculative layers or empty directories outside the explicitly approved ProjectZD8 product scaffold. After satisfying the new-folder approval gate, add an approved directory only when its first owned responsibility is implemented. When a folder begins mixing unrelated change reasons, propose a feature or owned-capability split through the same approval gate rather than adding a broader generic folder.

## 7. Current template migration

The existing root-level Xcode template files predate these rules. They do not establish precedent for new work. When a template file is materially changed, move and decompose the affected responsibility within the same reviewed change; do not perform an unrelated bulk migration.
