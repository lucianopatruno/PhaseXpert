# Phase Diagram Scope Decision

PhaseXpert production phase diagrams are scoped to pure CO₂ plus one limited
CO₂+CH₄ validation gate.

Existing mixture property calculations are unaffected. Density, phase, and the
currently enabled derived property calculations continue to use the selected
thermodynamic provider and their existing validation path.

Multicomponent phase diagrams were evaluated in separate feasibility milestones.
The native SRK prototype, CoolProp 8 backends, teqp, FeOs, DARTS-flash, and the
CO₂/N₂ NeqSim offline-atlas interpolation prototype did not establish a
production-ready arbitrary-composition phase-diagram path under PhaseXpert's
scientific and product constraints.

The app therefore does not attempt, approximate, extrapolate, or export
arbitrary multicomponent phase envelopes. A composition with any positive
impurity is shown a deliberate product-scope message unless the selected
provider advertises a validated phase-envelope capability for that exact
composition and domain. Density-only teqp H₂ support does not unlock an
impurity phase diagram. The only impurity exception is the corrected
CO₂+CH₄ Petropoulou 2018 gate for exact xCH₄ = 0.05, where Advanced CCS
Properties may return explicit bubble/dew points at the accepted isotherms.
Those points are not interpolated across failures and do not include a
validated critical termination.

Future reconsideration requires a new scientific feasibility milestone with new
acceptance criteria before any production provider or user-interface integration
work begins.
