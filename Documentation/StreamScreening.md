# Reactions & Water (preview)

One original composition and operating point drive three **independent** model
assessments. This is workflow integration, not reactive phase equilibrium.

## Entry points

- More → Tools → Reactions & Water.
- Calculator inputs → Reactions & Water copies valid original inputs even when
  the property model cannot calculate them. It never removes unsupported species.
- Calculator result → Reactions & Water copies the original calculation's
  pressure, temperature and composition. No saved record is modified.

Inputs are absolute pressure in bar(a), temperature in °C, and mole ppm
(µmol/mol) of the original stream. CO₂ is the exact remainder. The screen
accepts all component identifiers supported by the existing app plus ToCoMo's
SO₂ and NO₂ inputs. Negative, non-finite, unparseable, or overfull compositions
are rejected. Decimal commas are accepted. No normalization or inferred trace
impurity is applied.

Calculator displays an explicit blocked-calculation reason for wet mixtures with
additional components and for binary wet states outside the supported domains.
These explanations do not broaden either model’s validity range.

## Independent routes

1. **ToCoMo:** the existing pinned Swift port receives the original five
   reactive impurity amounts. Nonreactive species do not participate. Outputs
   remain on the original stream basis, with the existing reaction order,
   cutoff, and source attribution. No reaction or model coefficient changes.
2. **Water dropout for the original stream:** the existing
   Spycher–Pruess–Ennis-King binary pure-water model is used only for an actual
   binary CO₂/H₂O input. Mixtures with any other nonzero impurity are explicitly
   unsupported. Existing temperature/pressure validation gates remain intact.
3. **General Properties:** receives the original representable composition,
   through the production provider registry. SO₂ or NO₂ prevents this route
   because the engine's component contract cannot represent them. No species
   is dropped to make the calculation succeed. Other limitations are enforced
   by the existing provider. The native teqp library remains excluded.

Model-unavailable, unsupported-composition, out-of-domain, failed and no-water
outcomes remain explicit. One unavailable route does not suppress valid output
from another. Existing property status, warnings, model version and calculation
ID are displayed; unsupported properties are never given fabricated values.

## Optional binary reference

Off by default. For a multicomponent stream containing water, the user may
explicitly request a **hypothetical binary CO₂/H₂O reference**. It uses the same
original water ppm and treats *all remaining material* as CO₂, at the same P/T.
The screen names every excluded impurity and keeps the original mixture's water
assessment unavailable. It does not use reaction-produced or consumed water.

If ToCoMo estimates acid formation and this separate reference indicates a
water-rich phase, an observation flags the two independent results. It explicitly
states that acid/liquid coexistence in the actual mixture was not calculated.
Neither a below-saturation reference nor a missing result establishes safety.
No pH, corrosion rate, risk score, acid partitioning or material recommendation
is calculated. Reference equilibrium output does not establish mixture accuracy.

## State and execution

Explicit Run assessments action, no solving inside SwiftUI body. Local reaction
and water-boundary calculations execute off the main actor. Editing or clearing
any input cancels the current task, removes old results, and uses a request ID
plus immutable input comparison to reject stale completion. Leaving the screen
cancels pending work. Existing native cancellation/serialization applies; an
already executing native call cannot be forcibly interrupted safely.

## Verification

- Core tests cover original input forwarding, no SO₂/NO₂ omission, no reacted
  water feedback, opt-in reference separation, validation domains, independent
  engine availability, invalid inputs and all app component mappings.
- View-model tests cover decimal commas, SI conversion, invalid inputs,
  explicit reference opt-in and stale-result invalidation.
- A UI test exercises the mixture example, reference toggle and Clear.
- Xcode device/simulator builds, app/UI tests and visual acceptance must be run
  on macOS before this preview is merged or distributed.

## Demonstration inputs

Both examples use 30 bar(a), 40 °C. These are software demonstration cases,
not recommended operating specifications.

- Binary water: H₂O 20,000 ppm; all other impurities zero.
- Reactive mixture: H₂O 20,000, O₂ 15, H₂S 3 and NO₂ 15 ppm. The original
  mixture's water result and its thermophysical result are unavailable. Opting
  into the binary reference provides a separate water comparison; it must not
  relabel either unavailable original-stream result.
