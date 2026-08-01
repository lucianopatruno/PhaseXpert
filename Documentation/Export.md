# Calculation export

## Implemented formats

Saved cases can be exported from the case-actions menu as JSON or CSV. Files
are generated locally in the operating-system temporary directory and are
passed to the standard iOS share sheet. PhaseXpert does not upload or transmit
an export automatically.

### JSON

The JSON document is a versioned `SavedCaseExportSnapshot`. It contains:

- export schema version and generation timestamp;
- saved-case identifier, name, notes and saved/updated timestamps;
- the complete immutable `CalculationRecord` exactly as stored, including the
  request, original and normalized input, response, model descriptor, solver
  metadata, warnings, references, calculation identifier, and application
  version/build.

JSON is the lossless machine-readable format and is emitted as UTF-8 with
sorted keys. Adding a future schema version must not silently reinterpret an
older export.

### CSV

CSV uses a long-form schema with these columns:

`section,key,index,identifier,value,unit,status,message`

Repeated concepts such as composition entries, properties, warnings,
limitations and references receive separate rows. This avoids creating a
different column layout for every mixture or property set. Every field is
quoted according to RFC 4180 rules, rows use CRLF terminators, and the file
includes a UTF-8 byte-order mark so scientific symbols remain legible in
spreadsheet applications that guess legacy encodings.

CSV records both displayed and SI inputs. It does not convert unavailable,
failed, out-of-range or extrapolated properties into numbers; their recorded
status and message are exported instead.

## Numerical and integrity safeguards

Before either renderer runs, all stored pressures, temperatures,
compositions, property values, model limits, solver tolerances and durations
are checked for finite floating-point values. A NaN or infinity stops the
whole export with an explicit error. The stored case is never modified.

Filenames contain a sanitized case name and the first eight characters of the
immutable calculation identifier. This prevents case names from introducing
path separators while retaining a traceable link to the result.

## Architecture

`CalculationExportRendering` separates format rendering from saved-case UI.
`CalculationExporter` owns common validation and filename policy. The JSON and
CSV renderers are deterministic for a supplied export timestamp, and
`CalculationExportFileStore` is responsible only for writing shareable files.

A future professional PDF report should implement the same rendering
boundary. It must include the concise result, full technical provenance,
scientific warnings and model references. PDF is not implemented in this
milestone; a decorative screenshot must not be substituted for a calculation
report.

## Tests

Tests verify:

- JSON round-trip without loss of the calculation record;
- CSV units, statuses, warnings, references and quote/newline escaping;
- explicit rejection of non-finite values for both formats;
- safe deterministic filenames;
- creation and byte-for-byte verification of both shareable files.

The Xcode UI and share sheet must also be tested on a simulator or physical
iPhone before the milestone is accepted.

## Phase-diagram export

PhaseXpert can share a PNG only when the active provider returns a real, finite pure-CO₂ saturation boundary. The exported image contains the operating point, critical point, provider-calculated boundary, model versions, and preliminary-status warning. Mixtures and unavailable boundaries never receive a decorative or estimated export.

For a saved pure-CO₂ case, PDF generation requests a fresh boundary only when the installed model and provider versions exactly match the versions retained by the saved calculation. The PDF adds the diagram on a dedicated page with searchable boundary, model, solver, convergence, and warning text. If the provider is absent, its version differs, or boundary calculation fails, the calculation report is still exported and the app explains why no diagram was embedded.
