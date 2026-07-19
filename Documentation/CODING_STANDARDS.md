# Coding standards

## 1. Purpose and authority

These standards keep Codex-produced Swift code understandable and replaceable as ProjectZD8 grows. They optimize for human review, safe change, and clear ownership rather than the fewest possible files.

The terms **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are normative. Human reviewers make the final decision. An exception is valid only when its reason, scope, and approver are recorded in the change.

## 2. Core rule: one reason to change

Every file and named declaration MUST have one primary responsibility and one primary reason to change.

A responsibility is acceptable when it can be stated as one precise sentence:

> Converts a validated item-creation request into an item repository operation.

Descriptions such as "handles items," "manages the screen," or "contains shared logic" are not precise enough. If a responsibility needs "and," lists unrelated effects, or cannot name its input and outcome, the code MUST be decomposed until each part is explainable.

There is no mechanical line-count limit. A short type can still violate single responsibility, while a cohesive algorithm may legitimately be longer.

### Decomposition order

When a method or type has multiple responsibilities, separate them in this order:

1. Isolate business decisions as a Domain policy or value type.
2. Isolate workflow coordination as an Application use case.
3. Isolate persistence, network, file, device, and framework work behind a port and a Data adapter.
4. Isolate conversion into a mapper or codec owned by the layer that needs the conversion.
5. Leave only rendering and typed action dispatch in the View.

An extracted responsibility MUST be placed according to `PLACEMENT_RULES.md`. It MUST NOT be hidden in a generic helper file.

## 3. Swift DocC contract

Every new or changed declaration MUST have a `///` DocC comment, including internal and private types, stored and computed properties, initializers, subscripts, and methods. Generated code is exempt only when the generator and generated path are documented.

Every method comment MUST include a one-sentence `Responsibility:` statement. Parameters, return values, thrown errors, side effects, preconditions, and invariants MUST be documented when present. Comments describe the contract and intent; they MUST NOT merely translate the implementation line by line.

```swift
/// Creates an item through the repository after validating the request.
///
/// Responsibility: Coordinates exactly one item-creation use case.
/// - Parameter request: Validated input needed to create the item.
/// - Returns: The stable identifier assigned to the created item.
/// - Throws: `CreateItemError` when creation cannot be completed.
func execute(_ request: CreateItemRequest) async throws -> ItemID
```

For a side-effecting method, identify the effect explicitly:

```swift
/// Persists the supplied record in the local item store.
///
/// Responsibility: Performs the local persistence boundary for one item record.
/// - Parameter record: The persistence representation to store.
/// - Throws: A repository error when the durable write fails.
func insert(_ record: ItemRecord) throws
```

If the `Responsibility:` sentence is vague or inaccurate, the implementation is not ready for review. Split or rename it rather than writing a misleading comment.

## 4. Replaceable screen rule

Screen layout is expected to change and MUST be disposable without rewriting business or infrastructure behavior.

A View MAY:

- render an immutable or observable presentation state;
- derive small, display-only values such as spacing or labels;
- hold ephemeral UI state such as focus, hover, local animation, or an unsubmitted field draft;
- dispatch a typed action such as `.addTapped` or `.deleteRequested(id:)`;
- invoke no-op preview fixtures.

A View MUST NOT:

- import SwiftData, GRDB, or a transport/database SDK;
- use `@Query`, `ModelContext`, SQL, repository implementations, network clients, file APIs, or device APIs;
- create domain entities as part of a workflow;
- validate business rules, coordinate use cases, retry operations, or decide persistence policy;
- start or stop sessions, perform communication, or determine transaction boundaries;
- convert infrastructure failures into business outcomes;
- act as the application composition root.

The preferred boundary is:

```swift
struct ItemListState: Equatable {
    // Presentation-ready values only.
}

enum ItemListAction: Equatable {
    case addTapped
    case deleteRequested(ItemID)
}

struct ItemListView: View {
    let state: ItemListState
    let send: (ItemListAction) -> Void
}
```

Replacing `ItemListView` with a new layout must not require changes to the use case, repository, database model, or transport implementation.

Presentation models MAY translate typed UI actions into Application calls and Application output into presentation state. They MUST NOT contain domain rules or concrete persistence/transport implementations.

## 5. Platform separation

iOS and macOS screen layouts MUST be separate source trees and separate View types. Shared Domain and Application behavior is encouraged; shared screen layout is not.

Small visual primitives MAY be shared only when they contain no screen composition, navigation, platform branching, or feature workflow. A human reviewer should be able to delete an entire platform View tree without damaging the other platform or the use cases.

Large `#if os(iOS)` / `#if os(macOS)` branches inside a shared View are prohibited. Whole-file compilation guards for platform-owned files are allowed when target membership cannot express the boundary.

## 6. Naming and file boundaries

- Name files after their primary declaration: `CreateItemUseCase.swift`, not `ItemLogic.swift`.
- Prefer one primary type per file. Closely coupled private supporting declarations MAY remain with it when they share the same change reason.
- Name use cases with a user or system outcome: `CreateItemUseCase`, `LoadItemListUseCase`.
- Name infrastructure implementations by technology and contract: `SwiftDataItemRepository`.
- Name state and actions for their screen or feature: `ItemListState`, `ItemListAction`.
- Protocol names describe capabilities, not implementation details.
- Avoid `Helper`, `Utils`, `Common`, `Misc`, `Base`, and broad `Manager` names. They conceal ownership and are not valid architecture destinations.
- Extensions that add a distinct conformance or responsibility SHOULD use a separate file such as `ItemID+Codable.swift`.

## 7. Dependency injection and side effects

Side effects MUST cross an explicit protocol boundary. Time, identifiers, persistence, files, network, and device communication SHOULD be injectable when they affect behavior or tests.

Concrete dependencies MUST be assembled in `App/Composition`. Feature code MUST NOT reach into a global service locator or silently construct a production adapter.

Errors SHOULD retain the meaning required by the calling layer. Do not collapse storage, communication, or validation failures into success, empty data, or an unrelated generic error.

## 8. Tests

Behavioral changes MUST include proportionate tests at the lowest layer that owns the behavior:

- Domain tests cover rules, value objects, and policies.
- Application tests cover actions, state transitions, orchestration, and error paths using fakes or spies.
- Data tests cover adapter mapping and real local integration boundaries.
- Platform tests cover presentation mapping and meaningful UI interaction.

Tests MUST mirror production feature paths and use descriptive behavior names. A local test proves only that tested local behavior; it does not prove visual quality, a real device, a production service, or hosted CI.

## 9. Human review checklist

The author and human reviewer should be able to answer **yes** to each applicable item:

- [ ] Can every changed file's responsibility be described in one sentence?
- [ ] Does every changed declaration and method have accurate Swift DocC?
- [ ] Does each method do only what its `Responsibility:` sentence promises?
- [ ] Were multi-responsibility methods/types split and placed in the correct folder?
- [ ] Is the dependency direction valid, with no framework leaking inward?
- [ ] Do Views only render state, hold UI-only ephemeral state, and dispatch typed actions?
- [ ] Can the screen layout be deleted and rebuilt without changing business logic or Data adapters?
- [ ] Are iOS and macOS layout trees independent?
- [ ] Are side effects behind explicit ports and injected implementations?
- [ ] Are failures preserved rather than silently converted into success or empty state?
- [ ] Do tests cover the changed responsibility and important failure paths?
- [ ] Does the handoff distinguish verified results from unverified assumptions?

Any **no** blocks approval unless a documented human-approved exception applies.
