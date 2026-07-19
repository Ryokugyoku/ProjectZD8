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

All Swift DocC prose MUST be written in Japanese. This includes summaries, responsibilities, parameter descriptions, return values, thrown errors, side effects, preconditions, and invariants. Required DocC syntax such as `- Parameter`, `- Returns`, and `- Throws`, as well as code identifiers, MAY remain in their required source form.

Every method comment MUST include a one-sentence Japanese `責務:` statement. Parameters, return values, thrown errors, side effects, preconditions, and invariants MUST be documented in Japanese when present. Comments describe the contract and intent; they MUST NOT merely translate the implementation line by line.

```swift
/// 検証済みの要求をリポジトリへ渡して項目を作成します。
///
/// 責務: 単一の項目作成ユースケースを調整します。
/// - Parameter request: 項目の作成に必要な検証済み入力。
/// - Returns: 作成した項目へ割り当てられた安定識別子。
/// - Throws: 作成を完了できない場合は `CreateItemError`。
func execute(_ request: CreateItemRequest) async throws -> ItemID
```

For a side-effecting method, identify the effect explicitly:

```swift
/// 指定されたレコードをローカル項目ストアへ永続化します。
///
/// 責務: 1件の項目レコードに対するローカル永続化境界を実行します。
/// - Parameter record: 保存する永続化表現。
/// - Throws: 永続書き込みに失敗した場合はリポジトリエラー。
func insert(_ record: ItemRecord) throws
```

If the `責務:` sentence is vague or inaccurate, the implementation is not ready for review. Split or rename it rather than writing a misleading comment.

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

### macOS visual and layout contract

This subsection is the authoritative visual contract for macOS AppShell and screen-layout work. Its purpose is to preserve the same product character when another Codex or human replaces an individual View; it is not a requirement to copy one screenshot or freeze every measurement forever.

#### Product concept

The macOS experience MUST feel like a calm, modern automotive cockpit: information is immediately readable, controls feel precise, and visual depth indicates hierarchy without ornamental noise.

- The overall composition MUST be content-first. Navigation establishes context but MUST NOT visually compete with the active feature.
- The surface hierarchy SHOULD be created with restrained material, tint, opacity, spacing, and continuous rounded shapes. Repeated heavy borders, saturated full-panel fills, and unrelated decorative colors MUST NOT become the primary hierarchy.
- The accent color MUST communicate selection, focus, or a primary action. It MUST NOT be applied to every icon, label, and container merely to make the screen look active.
- Decorative text or status cards MUST remain truthful. A View MUST NOT show “connected,” “ready,” “healthy,” live values, or similar operational claims unless they come from presentation state owned by the appropriate Application workflow.
- A screen SHOULD have one dominant visual idea. For the AppShell sidebar, that idea is a translucent navigation surface with one luminous selected destination; new effects MUST support that hierarchy rather than compete with it.

#### AppShell composition

The expanded macOS AppShell sidebar MUST keep the following semantic order:

1. A compact brand header that identifies Project ZD8.
2. A subdued navigation section label.
3. Persistent destination rows with an icon, title, and short supporting label.
4. Flexible empty space that keeps navigation near the top.
5. An optional footer card containing only static context or presentation-backed state.

Destination titles MUST remain visible in the normal expanded sidebar. Labels MUST NOT depend on hover alone. A compact rail may hide labels only when a separately reviewed responsive mode preserves keyboard, accessibility, selection, and discoverability.

The current 1,200 × 800 point reference composition uses these baseline measurements:

| Element | Baseline | Contract |
| --- | ---: | --- |
| Sidebar width | 272 pt | Wide enough for icon, Japanese title, supporting label, and shortcut. |
| Horizontal / vertical inset | 14 / 18 pt | Keeps material visible around the navigation cards. |
| Destination row height | 62 pt | MUST remain at least 44 pt at every supported scale. |
| Destination row gap | 7 pt | Rows read as a related group without merging. |
| Row symbol | 20 pt in a 38 pt tile | Symbols align consistently even when their native bounds differ. |
| Selected row corner radius | 15 pt continuous | Rounded geometry SHOULD use the continuous style. |
| Brand mark | 44 pt | Provides identity without becoming the dominant content. |

These values SHOULD be resolved through one platform-owned metrics type instead of scattered numeric literals. The current proportional scale is derived from both available width and height and is bounded to 0.82...1.35. A future change MAY revise the baseline or bounds when real layouts require it, but MUST update the metrics owner, this contract, relevant tests, and visual evidence together.

The minimum 640 × 420 point window MUST remain operable. Enlarging the window MUST scale or reflow meaningful content, typography, symbols, controls, and spacing; increasing only empty frames does not satisfy responsive macOS design.

#### Navigation row states

Each destination row MUST expose distinguishable default, hover, selected, keyboard-focus, and accessibility-selected states.

- Selection MUST use at least two non-text cues. The current sidebar uses an accent icon tile, a low-opacity accent card, and a slim leading indicator.
- Hover MUST be quieter than selection. A small opacity change or approximately 1.01 scale response is acceptable; large movement, continuous pulsing, layout-width changes, or animation that shifts adjacent content SHOULD NOT be used.
- State animations SHOULD complete in approximately 0.14...0.24 seconds. Explicit movement or scale animation MUST be suppressed when `accessibilityReduceMotion` is enabled; a restrained opacity transition MAY remain.
- Every row MUST be one semantic `Button` with a full-row hit target and a stable accessibility identifier.
- The selected row MUST expose the selected accessibility trait. SF Symbols that duplicate the button label SHOULD NOT create redundant spoken navigation.
- Frequent destinations SHOULD provide discoverable keyboard shortcuts. The AppShell baseline is `Command-1` through `Command-4`, in visible navigation order; changing the order requires changing both the shortcut and its displayed label.

#### Color, material, and typography

- The sidebar SHOULD begin with a system material such as `ultraThinMaterial`, then add only low-opacity tint or luminance layers needed to establish depth. It MUST remain legible in both Light and Dark appearances.
- Primary and secondary system foreground styles SHOULD be preferred for text. Fixed black or white text is allowed only where the background contrast is deliberately controlled, such as a white symbol inside the accent tile.
- Navigation titles SHOULD use a semibold rounded system face. Supporting labels MUST be visually secondary, concise, localized, and limited to one line in the standard sidebar.
- Uppercase section labels MAY use restrained tracking, but MUST NOT replace ordinary localized titles or reduce legibility.
- SF Symbols SHOULD come from one coherent visual family and use consistent optical containers. Mixing filled, outlined, multicolor, and unrelated symbol weights in one navigation group requires a documented visual reason.
- Shadows MUST be localized and low-opacity. They MAY reinforce the selected destination or brand mark but MUST NOT be placed on every surface.

#### Localization and content resilience

All user-facing sidebar and screen text MUST use the String Catalog. A new destination requires a title and a short supporting label in every currently supported localization before handoff.

The layout MUST be inspected with Japanese and the longest supported translation. Text MUST NOT overlap the shortcut, icon, or adjacent content. Truncation of a supporting label is acceptable only after the title remains fully identifiable; shrinking primary text below a legible size is not an acceptable first response.

Dynamic Type or accessibility text settings MUST remain usable. If the expanded row cannot preserve readable title and supporting text, the layout SHOULD reflow or omit the supporting label before it clips the primary destination title.

#### Ownership and reuse

Screen composition, navigation order, responsive breakpoints, and AppShell measurements belong under `Platform/macOS`. They MUST NOT move into `Shared` merely because multiple macOS Views use similar spacing.

A color, typography token, or small visual primitive MAY move into `Shared/DesignSystem` only after it has real consumers in both platform trees or multiple independent owners, contains no navigation or screen composition, and passes the placement rules. Premature extraction of a “modern card,” generic sidebar, or broad style helper is prohibited.

#### Visual acceptance evidence

Every material macOS layout change MUST include proportionate evidence:

1. Compile the macOS target.
2. Verify meaningful navigation or interaction through a focused UI test when the runner is available.
3. Inspect the real rendered app or preview at the 1,200 × 800 reference size and the 640 × 420 minimum size.
4. Check Light and Dark appearances, Japanese plus the longest supported localization, keyboard operation, hover, focus, and accessibility semantics as applicable.
5. Record which checks were actually completed and which remain unavailable.

A successful build or unit test proves neither visual quality nor human approval. Screenshot review, preview review, UI automation, physical-Mac interaction, and human visual acceptance MUST be reported as separate evidence.

Before requesting review for macOS UI, confirm all applicable items:

- [ ] Does the screen preserve the calm automotive-cockpit hierarchy rather than add unrelated decoration?
- [ ] Is the active destination obvious without relying on color or text alone?
- [ ] Are ordinary labels visible without requiring hover?
- [ ] Are hit targets at least 44 pt and keyboard and accessibility paths intact?
- [ ] Does the layout remain operable at 640 × 420 and use additional space meaningfully at larger sizes?
- [ ] Are user-facing strings localized and resilient to the longest supported translation?
- [ ] Are all operational claims backed by presentation state rather than decorative fiction?
- [ ] Were visual evidence and unverified appearance states reported honestly?

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

## 9. OBD acquisition, persistence, and analysis boundaries

Serial communication, OBD protocol handling, persistence, real-time presentation, and TensorFlow analysis MUST remain independently replaceable responsibilities.

- Serial and OBD framework calls MUST be implemented in `Data/Devices` behind an Application port. A Platform View or presentation model MUST NOT open, configure, read, or write a serial or OBD connection.
- A device callback MUST enter an Application use case before it can affect persistence or presentation state. A Data adapter MUST NOT fan one callback out directly to a database, a View, and an analysis engine.
- Durable log reads and writes MUST cross a Domain repository contract. Platform code MUST NOT query GRDB, execute SQL, or depend on persistence records.
- Real-time presentation MUST consume bounded presentation state produced through Application orchestration. Rendering MUST NOT become the owner of the acquisition session or the authoritative telemetry log.
- Analysis MUST be invoked through an Application analysis port. Concrete TensorFlow model loading, input/output conversion, and framework lifecycle belong in `Data/MachineLearning/TensorFlow`.
- Analysis work MUST NOT block serial acquisition or durable logging. Queueing, cancellation, backpressure, and stale-result rejection MUST be explicit when they affect correctness.
- An unavailable model, incompatible model, low-confidence result, cancellation, or inference failure MUST remain distinguishable from a successful analysis result. Analysis failure MUST NOT be reported as logging success or fabricated numeric output.
- Recorded source logs MUST remain usable independently of derived analysis results. Reanalysis or replacement of the analysis implementation MUST NOT require rewriting the original acquired data.

The exact serial transport, OBD command set, database technology, TensorFlow runtime, model format, formulas, units, and supported vehicles MUST NOT be guessed from this folder scaffold. Each requires a separately reviewed implementation or requirement decision.

## 10. Human review checklist

The author and human reviewer should be able to answer **yes** to each applicable item:

- [ ] Can every changed file's responsibility be described in one sentence?
- [ ] Does every changed declaration and method have accurate Swift DocC?
- [ ] Does each method do only what its Japanese `責務:` sentence promises?
- [ ] Were multi-responsibility methods/types split and placed in the correct folder?
- [ ] Is each changed Feature still a stable product capability rather than a screen or implementation detail?
- [ ] Are cross-feature workflows owned by one Application outcome without concrete sibling-Feature dependencies?
- [ ] Were only directories required by implemented responsibilities added?
- [ ] Is the dependency direction valid, with no framework leaking inward?
- [ ] Do Views only render state, hold UI-only ephemeral state, and dispatch typed actions?
- [ ] Can the screen layout be deleted and rebuilt without changing business logic or Data adapters?
- [ ] Are iOS and macOS layout trees independent?
- [ ] Are side effects behind explicit ports and injected implementations?
- [ ] Does device input enter Application orchestration before persistence, presentation, or analysis effects occur?
- [ ] Can acquisition and durable logging continue without TensorFlow analysis?
- [ ] Are raw or source logs preserved independently from derived analysis results?
- [ ] Are failures preserved rather than silently converted into success or empty state?
- [ ] Do tests cover the changed responsibility and important failure paths?
- [ ] Does the handoff distinguish verified results from unverified assumptions?

Any **no** blocks approval unless a documented human-approved exception applies.
