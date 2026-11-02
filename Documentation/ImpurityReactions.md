# Impurity Reactions (preview)

## Status

Preliminary. This tool shows what a CO₂ stream's reactive impurities could turn
into if the reactions go to completion. It is **not** a thermodynamic
equilibrium calculation and PhaseXpert has not validated it. It does not use
CoolProp and does not feed the Calculator or any saved case.

## Source

The model is a Swift port of ToCoMo, the Total Consumption Model:

- Repository: <https://github.com/equinor/tocomo> (MIT, Copyright (c) 2025 Equinor)
- Pinned commit: `74e23131bd27d63dcf71b4a62eb81cdb76d981c9`
- Ported: the reaction list and `run_model_sm1` from `tocomo/reactions.py`
- Attribution as stated by the repository: the algorithm is implemented "as
  described by Sven Morten Hesjevik and Anne Marie Koren Halvorsen". The
  repository gives no publication; none is invented here.
- The same model is offered by the AcidWatch portal (<https://github.com/equinor/acidwatch>),
  which exposes the five inputs used here. PhaseXpert does not call AcidWatch or
  any server.

The licence text is kept in `ThirdParty/ToCoMo/LICENSE`.

## What the model does

Concentrations are mole ppm (µmol/mol) of the stream; CO₂ is the remainder. The
reactions are tried in a fixed priority order. The first reaction whose limiting
reactant allows a multiplier of at least 0.001 ppm is applied, then the list is
tried again from the top. The loop ends when no reaction can be applied.

| Order | Reaction | In use |
|---|---|---|
| 3 | H₂S + 3 NO₂ → SO₂ + H₂O + 3 NO | yes |
| 2 | 2 NO + O₂ → 2 NO₂ | yes |
| 1 | NO₂ + SO₂ + H₂O → NO + H₂SO₄ | yes |
| 4 | 3 NO₂ + H₂O → 2 HNO₃ + NO | yes |
| 5 | 2 NO₂ + H₂O → HNO₃ + HNO₂ | no (inactive in the reference) |
| 6 | 8 H₂S + 4 O₂ → 8 H₂O + S₈ | yes |

The priority order comes from the reference implementation, whose docstring says
it was "discussed with Sven Morten June 18". It is an expert ordering, not a
result derived from kinetics or thermodynamics.

## Limits that matter when reading a result

- No temperature, pressure, kinetics, equilibrium, activity or phase separation.
  Acids that would dissolve in a water phase are not moved there.
- The 0.001 ppm cutoff ends the nitrogen cycle (NO₂ → HNO₃ + NO, NO → NO₂)
  before it is exhausted, so a small NO₂ and NO residue remains. This is the
  reference behaviour and is kept on purpose.
- ppm stay on the basis of the initial stream. The reactions change the mole
  count and the reference does not renormalize; neither does PhaseXpert.
- Inputs are never corrected silently: negative or non-finite values and a total
  above 1,000,000 ppm are rejected with an explicit message. "No reaction could
  be applied" is reported as such and returns the stream unchanged.
- A runaway-loop guard (100,000 steps) exists only to turn a hang into an
  explicit failure; the reference has no such guard and real inputs need far
  fewer than 100 steps.

## Verification

`Scripts/generate-tocomo-reference.py` runs the original Python code on twelve
input sets and writes `PhaseXpertCore/Tests/PhaseXpertCoreTests/ToCoMoReferenceData.swift`.
`ToCoMoModelTests` requires the Swift port to match every step, multiplier and
final concentration to 1e-9, checks that each reaction and each step conserves
atoms, and reproduces the AcidWatch worker's own test case. Re-run the script
only when deliberately moving to a new reference commit.
