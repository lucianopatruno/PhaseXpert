# Calculation export

## Implemented formats

Saved cases can be exported from the case-actions menu as JSON, CSV or a
searchable PDF report. Files
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

The professional PDF renderer uses Core Graphics and Core Text rather than a
screen capture, so report text remains searchable and long content paginates.
It includes the approved IFE logo and report styling, immutable inputs,
results, warnings, statuses, model/provider versions, identifiers, solver
metadata, references and intended-use disclaimer.

## Tests

Tests verify:

- JSON round-trip without loss of the calculation record;
- CSV units, statuses, warnings, references and quote/newline escaping;
- explicit rejection of non-finite values for both formats;
- safe deterministic filenames;
- creation and byte-for-byte verification of both shareable files.

The Xcode UI and share sheet must also be tested on a simulator or physical
iPhone before the milestone is accepted.

## Pairwise comparison reports

The saved-case comparison screen prepares a searchable PDF and long-form CSV
from two complete immutable `SavedCaseExportSnapshot` values. Both formats
state that every difference is **compared minus reference** and that numerical
differences do not establish which model or result is more accurate. They
retain both saved-case IDs, calculation and request IDs, units, property
statuses, warnings, model/provider versions, composition and notes.

A numerical property difference is emitted only when both records contain
finite calculated values that can be represented in the same engineering
display unit. Unavailable, failed, outside-range, extrapolated, missing or
unit-incompatible values retain their statuses and have no invented numeric
difference. Non-finite stored values stop the complete export.

## Property-sweep PDF reports

Completed provider-backed sweeps can be shared as the existing provenance-rich
CSV and as a professional searchable PDF. The PDF contains the serialized
sweep definition, source calculation, composition, model/provider versions,
every sample status/error/warning and calculation ID, followed by a vector
chart with named axes, engineering units and legend.

Only finite values with recorded `calculated` status are plotted. Straight
segments connect adjacent successful provider samples for visualization only.
Failed and unavailable points break the path and remain explicit gaps; the
renderer never fills a gap or interpolates a scientific value. If no point is
successful, the report remains exportable and the chart page explicitly states
that no finite provider points were available.

Comparison and sweep report snapshots are versioned and Codable for stable
serialization tests. They are export containers only; this milestone does not
import or mutate persisted scientific records.

## Phase-diagram export

PhaseXpert can share a PNG only when the active provider returns a real, finite
phase boundary. Pure CO₂ uses one saturation branch; supported dry mixtures
use separate provider bubble and dew branches. The image contains the recorded
composition, operating point, any provider critical point, model versions and
preliminary-status warning. Unavailable boundaries never receive a decorative
or estimated export.

For a saved pure-CO₂ or supported dry-mixture case, PDF generation requests a
fresh boundary only when the installed model and provider versions exactly
match the saved calculation. The dedicated page retains searchable boundary,
model, solver, convergence and warning text. If the provider is absent, its
version differs, or calculation fails, the report still exports and explains
why no diagram was embedded.

## Remote-provider provenance

NeqSim JSON, CSV and PDF exports use the same immutable `CalculationRecord`
path as CoolProp. A NeqSim result records provider ID, NeqSim release/source
commit, service/API capability, Java runtime, EOS, alpha/configuration text,
mixing rule, interaction-data identifier, request/calculation IDs, warnings and
convergence metadata. Comparison exports preserve compared-minus-reference
semantics and never rank NeqSim or CoolProp.
