# Saved-case batch comparison

Saved Cases provides **Compare**, which accepts two to twenty built-in or user-saved case snapshots. A batch uses one explicitly selected model—General Properties or Advanced CCS Properties—for every case. Provider failures are isolated per case and never trigger fallback to the other model.

Advanced CCS results retain the exact property-specific production capability decision. A state with no validated Advanced property is retained as **Outside validated range**; its composition is not changed and General Properties is not substituted. General batches use the existing General engineering-calculation presentation and do not display Advanced validation shields.

The comparison workspace retains immutable SI inputs, case identity, source calculation ID where present, selected provider, provider response, validation-property set, errors, completion time, and an input fingerprint. Changing the selected model invalidates prior comparison results. Display-unit formatting does not recalculate or alter the retained SI records, and later edits to a saved case cannot mutate an open comparison snapshot.

CSV export uses one row per case with stable columns for every `ComponentID`, SI inputs, property values and units, validation labels, errors, application/model provenance, and fingerprints. The concise searchable PDF includes all cases, the selected model, result status, validation legend, property values, and provenance. Both files are generated locally and shared with the standard iOS share sheet.
