# Vehicle-specific change detection requirements

## 1. Document responsibility

This document records the agreed product requirements and evidence boundaries for
learning a registered vehicle's initial behavior and visualizing later deviation.
It does not authorize a source-code implementation, a new production directory,
an unverified PID formula, or a claim that a detected change is a mechanical
fault.

The user-facing purpose is:

> Show when and how a registered vehicle has become different from its own
> earlier behavior under comparable operating conditions.

## 2. Product meaning and non-goals

The first release MUST present a **change score**, not a health percentage,
remaining-life estimate, diagnosis, or proof of degradation.

- A high score means that verified numeric observations differ from the
  registered vehicle's applicable reference period.
- A low score means only that the evaluated observations remain close to that
  reference. It MUST NOT assert that the vehicle is healthy.
- A provisional reference learned after registration describes the vehicle's
  initial observed condition. It MUST NOT be called a confirmed healthy baseline.
- A single-session deviation MAY be recorded and shown, but MUST NOT produce a
  persistent-change notification by itself.
- Model unavailability, incompatible inputs, insufficient coverage, low
  confidence, cancellation, and inference failure MUST remain distinct from a
  successful low change score.

The initial scope excludes:

- transferring or applying one registered vehicle's model to another vehicle;
- fleet or same-model comparison;
- automatic component-failure diagnosis;
- percentage degradation and remaining-life prediction;
- training from unverified PID formulas or undecoded Raw payloads;
- training on iPhone; and
- automatic replacement of a reference model without a reviewed transition.

## 3. Vehicle and data scope

### 3.1 Registered-vehicle isolation

Every reference model, model generation, feature manifest, interval summary, and
analysis result MUST belong to one stable application-owned `VehicleID` and one
account scope.

- Display name, model name, VIN, registration plate, ECU text, and adapter
  identity MUST NOT be used as the model's primary identity.
- Two registered vehicles with the same displayed model MUST have separate
  models and data.
- Logs from different `VehicleID` values MUST NOT be mixed for training,
  validation, scoring, or reconstruction.
- Renaming a vehicle MUST NOT move or recreate its model.
- A profile edit that changes input compatibility MUST trigger compatibility
  review rather than silently reusing the model.

### 3.2 Eligible PID observations

Training and scoring MUST use only PID observations for which all of the
following are true:

- the formula, required byte count, and unit are verified;
- the payload was decoded successfully into a finite numeric value;
- the value passes the verified definition's validity constraints;
- the PID definition revision is recorded; and
- the observation belongs to the target registered vehicle.

An absent, failed, invalid, or incompatible value MUST remain missing. It MUST
NOT be replaced with numeric zero. Undecoded Raw entries remain authoritative
source evidence for later reanalysis but are excluded from the initial model.

Each model generation MUST store an immutable input manifest containing at
least its ordered PID set, PID definition revisions, feature-definition version,
reference-period identity, and training-log identity range.

## 4. Comparable operating conditions

Training and evaluation MUST compare observations only when operating-condition
coverage is sufficient. Candidate conditions include:

- cold-start equivalent;
- warm-up;
- warmed idle;
- low-speed driving;
- medium-speed cruise;
- high-speed cruise;
- acceleration;
- high-load operation;
- deceleration; and
- unclassified operation.

Only conditions supported by verified observations for that vehicle may be
used. Session elapsed time and vehicle speed may contribute to grouping, but
they are not assumed to fully describe warm-up or load. Verified temperature,
engine-speed, and load observations may refine classification when available.

The exact condition definitions, time-window size, overlap, minimum sample
counts, missingness limits, and smoothing rules are deferred until the real-log
audit. Unsupported or under-covered conditions MUST report insufficient data
instead of a normal or abnormal result.

## 5. Reference-model lifecycle

### 5.1 Provisional initial reference

After registration, the product MUST collect eligible observations until both:

1. a configurable minimum distance has been recorded; and
2. required operating-condition coverage has been achieved.

The initial planning value is 1,000 km, but the production threshold MUST be
selected from real-log evidence rather than hard-coded from this document.
Multiple days and sessions SHOULD be represented so one unusually uniform drive
does not define the reference.

The UI MUST expose reference-building progress by distance, condition coverage,
and overall data sufficiency. When complete, macOS may build the provisional
reference model. The model MUST remain fixed after publication.

### 5.2 Routine evaluation

- Every completed drive SHOULD produce a provisional change result when inputs
  and model compatibility are sufficient.
- Every configurable distance interval, initially planned as 1,000 km, SHOULD
  produce a stable interval summary for long-term trend presentation.
- A fixed reference model MUST score all intervals within the same reference
  period so the trajectory remains on one scale.
- The first implementation MUST NOT continuously retrain the fixed reference
  from routine driving.
- A large one-off deviation may be emphasized as a current observation, but a
  persistent-change notification requires recurrence across multiple eligible
  drives or conditions.

### 5.3 Maintenance transition

A maintenance record may propose a new reference for affected systems, but it
MUST NOT replace the reference automatically.

1. The product proposes reference collection after maintenance.
2. The user confirms the affected system scope.
3. Post-maintenance observations are collected to the required coverage.
4. macOS builds and validates a candidate reference generation.
5. The user approves publication.

An approved replacement starts a new reference period. Previous models and
results remain historical evidence. Unaffected systems may retain their prior
reference when the mapping is verified; an unsupported component-to-system
mapping MUST NOT be guessed.

### 5.4 User-initiated reconstruction

macOS MUST allow the user to reconstruct a model generation when, for example:

- a previously unverified PID becomes decodable through a verified definition;
- the user changes which eligible sessions belong to the reference period;
- incorrect data classification is repaired; or
- a feature-definition revision requires regeneration.

Reconstruction MUST re-read the retained Raw source, decode it with the selected
verified definitions, regenerate features, train a new immutable generation,
and validate it before publication. It MUST NOT overwrite the old model or old
results in place.

When the input manifest changes, old and new raw scores MUST NOT be presented as
one continuous scale. Historical Raw may be reanalyzed explicitly with the new
generation. If source coverage is incomplete, the UI MUST disclose that the
generations are not directly comparable.

## 6. Scores, explanations, and notifications

The result surface MUST provide:

- an overall change score;
- electrical-system change when verified mapped inputs exist;
- cooling-system change when verified mapped inputs exist;
- fuel-and-intake-system change when verified mapped inputs exist;
- other verified numeric-signal change for inputs without a supported system
  mapping;
- trend direction and persistence;
- reference type and generation;
- data confidence and coverage; and
- the operating conditions and verified inputs contributing to the result.

The overall score MUST NOT be a simple arithmetic mean that can hide one large
system deviation behind unrelated low scores. Its aggregation and calibration
remain an experiment output. Confidence MUST be displayed separately and MUST
NOT reduce an uncertain result into an apparently healthy low score.

Notification behavior is conservative:

- one-off changes remain visible in history without a persistent notification;
- recurring comparable changes may produce a notification candidate;
- a very large one-off deviation may be called out as a large data change, but
  not as a confirmed fault; and
- insufficient data produces no anomaly claim.

User-facing language MUST describe difference from the named reference. It MUST
NOT identify a failed component, prescribe repair, or claim physical degradation
without separately validated evidence.

## 7. Training, inference, and model distribution

### 7.1 Platform responsibilities

- macOS owns training, validation, reconstruction, and publication of a
  registered-vehicle model.
- iPhone does not train in the initial scope.
- macOS and iPhone may perform inference with a validated compatible model.
- Training and inference MUST NOT block acquisition or durable Raw logging.
- Missing or failed analysis MUST leave the source log available for later
  analysis.

MLX Swift is the agreed feasibility candidate for vehicle-specific training and
inference. The current coding and placement standards name TensorFlow and do not
yet authorize an MLX production directory. Before an MLX source spike or product
integration, Codex MUST present the exact ownership, dependency, production
path, test path, and framework-migration proposal required by the repository's
new-folder approval gate. This requirements decision alone does not create that
approval.

### 7.2 Model artifact and synchronization

A published model artifact MUST travel with a manifest containing at least:

- account and `VehicleID` ownership;
- model ID, generation, format version, and reference-period ID;
- ordered PID and definition-revision manifest;
- feature-definition and normalization versions;
- training source range and creation distance/date;
- validation summary;
- artifact size and cryptographic digest; and
- minimum compatible application/runtime versions.

iPhone MUST stage a downloaded generation, verify its digest and compatibility,
run a deterministic smoke inference, and switch atomically only after success.
Failure MUST retain the current working generation.

The Settings feature MUST expose independently:

- account-scoped automatic model download; and
- device-scoped permission to use cellular data for model download.

Recommended defaults are automatic download enabled and cellular download
disabled. Disabling automatic download does not delete an installed model, and
manual download remains available.

### 7.3 Device-local deletion and retention

Deleting a model from iPhone removes only that device's cached artifact. It MUST
NOT delete the macOS or remote original, Raw logs, interval summaries, or prior
analysis results. Collection continues while analysis is deferred, and the model
may be downloaded again.

Retention requirements are:

- iPhone: current and immediately previous generation, subject to explicit local
  cache removal;
- macOS: current, previous, maintenance-boundary, and significant-change
  generations;
- remote storage: current and maintenance-boundary reference generations; and
- every analysis result: permanent reference to the exact model generation used.

Full vehicle deletion, account erasure, and remote-only artifact deletion still
require an explicit deletion specification before implementation.

## 8. Training-data review and publication

macOS MUST provide a review workflow that distinguishes:

- technically eligible sessions;
- technically ineligible sessions with a reason;
- provisional normal candidates;
- user-confirmed reference sessions;
- user-excluded sessions; and
- sessions associated with a reported issue or maintenance transition.

The user may change inclusion for technically eligible sessions. The UI MUST NOT
offer a force-include operation for undecodable, invalid, wrong-vehicle, or
otherwise incompatible data.

A completed training run is only a candidate. Publication requires validation
against held-out sessions and deterministic compatibility checks. The previous
generation remains active when validation or publication fails.

## 9. Required evidence before product claims

Implementation and evaluation MUST keep the following evidence separate:

- source and static checks;
- unit and local integration tests;
- MLX training completion;
- held-out retrospective evaluation;
- macOS and iPhone performance measurements;
- model synchronization and rollback tests;
- UI runner and accessibility checks;
- human visual review;
- real-device behavior;
- real-vehicle observations;
- Production CloudKit behavior; and
- hosted CI and TestFlight behavior.

Model quality MUST be evaluated by vehicle-separated and time-separated data,
not randomly split adjacent samples from the same drive. At minimum, the
evaluation must report false alerts per drive, insufficient-data frequency,
persistence behavior, score stability across comparable conditions, and any
observed maintenance-before/after response. No local result proves mechanical
degradation.

## 10. Deferred experimental decisions

The following are deliberately not fixed until the data audit and feasibility
spike provide evidence:

- exact minimum distance and condition-coverage thresholds;
- time-window size and overlap;
- operating-condition classifier rules;
- feature vector and normalization method;
- statistical baseline versus autoencoder candidate details;
- MLX network size, optimizer, epochs, and precision;
- score calibration and system aggregation;
- recurrence and notification thresholds;
- artifact size and inference-latency budgets; and
- model storage and Production CloudKit schema.

The staged Codex requests for resolving these decisions are maintained in
[`VEHICLE_CHANGE_DETECTION_CODEX_PROMPTS.md`](VEHICLE_CHANGE_DETECTION_CODEX_PROMPTS.md).
