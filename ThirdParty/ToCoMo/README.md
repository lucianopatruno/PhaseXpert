# ToCoMo

PhaseXpert contains a Swift port of the ToCoMo (Total Consumption Model)
reaction sequence from https://github.com/equinor/tocomo, commit
`74e23131bd27d63dcf71b4a62eb81cdb76d981c9`, used under the MIT licence in
`LICENSE` (Copyright (c) 2025 Equinor).

No ToCoMo or AcidWatch code runs in the app: only the reaction list and the
loop from `tocomo/reactions.py` (`run_model_sm1`) were ported to
`PhaseXpertCore/Sources/PhaseXpertCore/Orchestration/ImpurityReactions.swift`.
There is no network access. See `Documentation/ImpurityReactions.md`.
