# Multi-case property sweeps

Multi-case property sweeps extend Saved Cases comparison without introducing a second thermodynamic calculation path. From Saved Cases, enter **Compare**, select 2–10 built-in or saved cases, and choose **Property Sweep**. The same action is available from completed comparison results.

The calculation model is explicit for the entire run: **General Properties** or **Advanced CCS Properties**. A run never changes providers after a point fails. General curves are labelled as engineering calculations. Advanced curves expose only the selected property's production-validated points; the capability matrix is evaluated independently at every generated pressure/temperature state, and unsupported points remain visible in the Data view as gaps rather than extrapolated values.

General dry-mixture sweep points use the provider's existing legacy-stability exact-state screen before the existing imposed single-phase CoolProp update. Multiphase or indeterminate classifications are retained as failed/gap rows instead of entering CoolProp's unsafe unconstrained mixture PT flash. This is numerical safety routing only: it does not change equations, interactions, validation status, or built-in inputs.

Pressure sweeps can preserve every case's stored temperature or apply one explicit common temperature. Temperature sweeps provide the analogous stored/common pressure choice. Results retain immutable case snapshots, generated SI states, provider/model identity, validation decisions, run identity, timestamps, and input fingerprints. Changing the provider, property, range, point count, sweep variable, or fixed-condition mode invalidates the result. Display-unit changes only reformat existing values.

The Chart view shows one labelled series per case and supports point inspection and an optional reference-case delta. The Data view lists every evaluated point and its phase/status. Per-case summaries report finite minima/maxima and successful, validated, outside-range, and failed counts. Opening a point in Calculator loads its exact composition, pressure, temperature, and selected provider without calculating automatically.

CSV export emits one row for every requested point—including failures and Advanced outside-range gaps—with stable component columns and complete provenance. PDF export provides the provider, sweep definition, case list, compact chart, validation legend, and min/max/count summaries; the CSV remains the authoritative full tabular export.
