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

## 2. Layer ownership

### App

Owns process entry points, dependency construction, and lifecycle wiring. It may know every layer but MUST NOT contain business rules, persistence algorithms, or screen layouts.

### Domain

Owns framework-independent business meaning: entities, value objects, policies, invariants, domain errors, and repository capabilities. Domain MUST NOT import SwiftUI, SwiftData, GRDB, networking, or platform frameworks.

### Application

Owns use-case orchestration, commands/actions, application state transitions, and ports needed to execute workflows. It may depend on Domain. It MUST NOT depend on concrete Data adapters or Platform types.

### Data

Owns concrete persistence, network, file, and device adapters plus infrastructure mapping. It implements Domain or Application ports. It MUST NOT depend on Platform or construct Views.

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

If none applies, the responsibility is probably not understood well enough to add. Refine its contract before creating a file.

## 5. Feature growth

Group Application and Platform code by product feature before technical subtype. A feature should expose narrow state/actions/use cases and keep internal implementation details private where practical.

Do not create speculative layers or empty directories. Add a directory when the first responsibility belonging to it is implemented. When a folder begins mixing unrelated change reasons, split it by feature or owned capability rather than adding a broader generic folder.

## 6. Current template migration

The existing root-level Xcode template files predate these rules. They do not establish precedent for new work. When a template file is materially changed, move and decompose the affected responsibility within the same reviewed change; do not perform an unrelated bulk migration.
