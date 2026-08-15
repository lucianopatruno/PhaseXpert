# Phase Diagram Scope Decision

PhaseXpert production phase diagrams are scoped to pure CO₂.

Existing mixture property calculations are unaffected. Density, phase, and the
currently enabled derived property calculations continue to use the selected
thermodynamic provider and their existing validation path.

Multicomponent phase diagrams were evaluated in separate feasibility milestones.
The native SRK prototype, CoolProp 8 backends, teqp, FeOs, DARTS-flash, and the
CO₂/N₂ NeqSim offline-atlas interpolation prototype did not establish a
production-ready arbitrary-composition phase-diagram path under PhaseXpert's
scientific and product constraints.

The app therefore does not attempt, approximate, extrapolate, or export
multicomponent phase envelopes. A composition with any positive impurity is
shown a deliberate product-scope message in the phase-diagram screen, while
property calculations for the selected mixture remain available. Density-only
teqp H₂/CH₄ support does not unlock an impurity phase diagram.

Future reconsideration requires a new scientific feasibility milestone with new
acceptance criteria before any production provider or user-interface integration
work begins.
