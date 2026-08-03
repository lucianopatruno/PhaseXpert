# ThermoPack standalone provider

## Pinned source and licence

PhaseXpert pins the stable ThermoPack release **v2.2.4** at commit
`ca75d8e095e8b951616897efe1bca9b8c3badda7`. ThermoPack is
distributed under the Apache License 2.0. The checked-in licence and
PhaseXpert notice are under `ThirdParty/ThermoPack`.

Authoritative sources:

- [ThermoPack source](https://github.com/thermotools/thermopack/tree/v2.2.4)
- [v2.2.4 release](https://github.com/thermotools/thermopack/releases/tag/v2.2.4)
- [ThermoPack documentation](https://thermotools.github.io/thermopack/v2.2.0/home.html)
- [ISO C header](https://github.com/thermotools/thermopack/blob/v2.2.4/include/thermopack.h)
- [shipped PR interaction records](https://github.com/thermotools/thermopack/blob/v2.2.4/binaries/PR_kij.json)

## Exact PhaseXpert configuration

PR22 enables only this configuration:

| Field | Recorded identity |
|---|---|
| Provider ID | `thermopack-pr-classic-co2-n2` |
| ThermoPack | v2.2.4 / `ca75d8e095e8b951616897efe1bca9b8c3badda7` |
| Equation of state | Peng–Robinson cubic EOS |
| Alpha | Classic |
| Mixing rule | Classic van der Waals one-fluid |
| Components | CO₂ and N₂ only |
| Interaction data | `binaries/PR_kij.json`, record `vdW-18` |
| Upstream parameter reference | `Default` |
| Bridge version | 1.0.0 |
| Provider capability version | 1.0.0 |

The upstream record is selected by the documented `kij_ref=Default`
initialization. PhaseXpert neither copies a guessed coefficient into the bridge
nor calls an estimation routine. The configuration is intentionally narrow:
other PhaseXpert impurity identifiers remain unsupported by this provider even
when another ThermoPack model may contain some data for them.

The CO₂/N₂ range is 90–100 mol% CO₂ and 0–10 mol% N₂. The upper N₂ bound is a
temporary PhaseXpert product guardrail, not a validated accuracy range.

## Native API inspection

The pinned `include/thermopack.h` exposes ISO C entry points used by the bridge:

- `thermopack_init_c`
- `thermopack_tpflash_c`
- `thermopack_bubp_c` and `thermopack_dewp_c`
- `thermopack_specific_volume_c`
- `thermopack_moleweight_c`
- `thermopack_zfac_c`
- `thermopack_enthalpy_c`
- `thermopack_entropy_c`
- `get_phase_flags_c`

All input and bridge output quantities are SI. Molar API values are converted
to mass-specific values only from the provider-returned molar mass and volume.
Two-phase flashes do not receive an invented bulk density or caloric value.

The v2.2.4 TP-flash C entry point does not carry an explicit error-code output.
The bridge therefore serializes access to ThermoPack's active global model,
validates all returned values and rejects malformed output, but cannot convert
every possible internal Fortran failure into a recoverable code. This is a
known integration limitation, not hidden by fallback data.

## Independent phase boundaries

The ThermoPack provider calls the pinned bubble-pressure and dew-pressure APIs
independently at bounded temperatures. It:

- caps each branch at 64 provider calls;
- applies a 5000 ms native elapsed-time bound;
- keeps bubble and dew branches separate;
- retains only finite, positive provider points inside the declared app domain;
- reports call counts, failed calls, elapsed time, timeout and completeness;
- requires at least two provider points per branch before displaying a curve;
- never uses CoolProp's continuation patch or CoolProp trace;
- never interpolates, extrapolates or fabricates scientific points.

Straight segments in Swift Charts are display-only connections between adjacent
provider points. An incomplete provider trace remains marked incomplete and
non-converged.

## XCFramework build and runtime gate

Generated sources, build directories, stamps and
`PhaseXpertThermoPackBridge.xcframework` are ignored by Git. Run:

```sh
export THERMOPACK_FORTRAN_COMPILER=/path/to/flang-new
export THERMOPACK_FORTRAN_RUNTIME_ARCHIVES=/path/a.a:/path/b.a
bash Scripts/build-thermopack-xcframework.sh
```

The workflow:

1. checks out the exact pinned commit;
2. applies a tracked build-only patch that removes desktop compiler/OpenMP
   assumptions without changing scientific source or data;
3. builds static ThermoPack archives for iPhone arm64 and simulator arm64/x86_64;
4. compiles the C++ bridge against each Apple SDK;
5. combines explicitly supplied static Fortran runtime archives;
6. links Accelerate for BLAS/LAPACK through the Swift package;
7. packages the two platform slices as an XCFramework;
8. rejects identified unresolved or dynamic gfortran, quadmath or OpenMP
   dependencies;
9. records the source revision and bridge-source fingerprint.

The workflow has been source-reviewed in PR22. Successful iOS compilation,
static-dependency inspection and native numerical smoke calculations are
**pending Xcode validation** and must not be inferred from the presence of the
scripts.

## Required native validation

Xcode Codex must validate on an iPhone 17 simulator:

- `ios-arm64` and `ios-arm64_x86_64-simulator` slices;
- no unsupported dynamic Fortran/OpenMP dependency;
- pure CO₂, 97/3 CO₂/N₂ and 90/10 CO₂/N₂ single-phase states;
- bubble and dew calculations for all three compositions;
- finite/status/error handling and the bounded incomplete-envelope path;
- complete standard/release PhaseXpert validation.

Physical-device validation remains a separate user acceptance step. Successful
execution is integration evidence only and is not independent scientific
validation.
