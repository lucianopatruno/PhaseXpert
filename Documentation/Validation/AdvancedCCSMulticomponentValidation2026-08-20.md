# Advanced CCS Multicomponent Validation — 2026-08-20

## Scope and pinned implementation

This milestone evaluates the existing generic N-component EOS-CG-2021 density route in teqp v0.23.1, commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`. CoolProp output is not validation truth. Published compositions are preserved without normalization, failed or multiple-root states remain non-converged, and density validation is not transferred to VLE, phase maps, caloric, acoustic or transport properties.

## CO₂ + N₂ + CH₄ density acquisition

The primary Zhang et al. 2022 source, DOI `10.1021/acs.jced.2c00020`, reports 200 density points. Searches covered the ACS article and supporting-information endpoints, ACS Figshare, NIST ThermoML and its archive/search, Crossref and DataCite metadata, Zenodo, Figshare, institutional repositories, author and university pages, accepted manuscripts, theses, national-metrology and research-group sites, and later papers citing or reusing the work. The journal and SI endpoints denied anonymous retrieval and no lawful row-level mirror or ThermoML record was found. The acquisition record therefore remains zero-row; no values were inferred from plots or publisher model tables. Searches by DOI, title, authors, table terminology, composition and PVT/density synonyms found no alternative exact CO₂/N₂/CH₄ primary numerical density table. Consequently the requested exact ternary is not production-enabled.

The successful alternative is Razmjoo et al. 2026, *Fuel*, DOI `10.1016/j.fuel.2026.139184`, with its CC BY 4.0 Zenodo workbook DOI `10.5281/zenodo.15846367` and publisher supplement. Workbook MD5 is `3ba592622e565d0fa8cba21dfdb4e6c7`. The machine-readable artifact `Razmjoo2026MulticomponentDensity.json` contains all 330 primary rows, source table and row identifiers, exact composition, T, original MPa and converted Pa, experimental density, expanded uncertainty, provenance, publisher EOS-CG comparison, native prediction and residual. All five published compositions sum to exactly 1.000; duplicate count is zero.

## Native density results and gates

Across all 330 rows, 171 converged with one selected stable density solution (51.8182%). For converged rows AARD is 0.610303%, signed bias −0.108497%, RMS relative deviation 0.844124%, and the worst deviation is +4.372792% at PreComb I, 313.00 K, 10.500 MPa, composition CO₂/CH₄/H₂ = 0.950/0.033/0.017. The 159 multiple-root/non-selected states remain explicitly non-converged. Representative full-matrix runtime was median 56.978 ms, mean 64.428 ms and maximum 97.221 ms per state.

Production domains were selected only as contiguous complete measured blocks with 100% convergence and a coherent single-phase interpretation:

- OxyComb I, exact CO₂/N₂/O₂/Ar = 0.920/0.043/0.016/0.021: 20/20; 312.35 K and 1.952–6.951 MPa plus 312.60 K and 7.049–11.002 MPa; AARD 0.584120%, bias −0.043177%, RMS 0.718944%, worst 1.702920%.
- PreComb I, exact CO₂/CH₄/H₂ = 0.950/0.033/0.017: 11/11 gas rows at 313.00 K and 1.995–7.000 MPa; AARD 0.347581%, bias +0.319395%, RMS 0.460806%, worst 0.925245%.
- PreComb II, exact CO₂/N₂/CH₄/H₂ = 0.942/0.023/0.022/0.013: 37/37 at 313.15 K and 2.000–20.002 MPa; AARD 0.608688%, bias −0.508935%, RMS 0.695111%, worst 1.120183%.
- TransportSpec, exact CO₂/N₂/Ar/CH₄/H₂ = 0.952/0.028/0.005/0.010/0.005: 77/77. At 293.15 K the separate 1.998–5.499 and 8.501–22.000 MPa blocks have AARD 0.766256%, bias −0.766256%, RMS 0.778779%, worst 1.105702%; at 313.15 K and 1.996–22.000 MPa AARD is 0.261704%, bias −0.049959%, RMS 0.300833%, worst 0.649013%.

Rejected regions remain outside the matrix: all OxyComb II rows; 277.65 K OxyComb I; 283 K PreComb I; 277.2 K PreComb II and TransportSpec; the PreComb I 313 K dense block containing the 4.37% worst point; and the unmeasured 293.15 K TransportSpec pressure gap. Density-derived molar mass, specific volume and Z share only these exact density gates. Composition interpolation is prohibited.

## Ternary VLE investigation

The accepted Ottøy et al. 2020 artifact (DOI `10.1016/j.fluid.2019.112444`) preserves 31 bubble and 31 dew rows and was not retranscribed. Inspection of the pinned native implementation went below teqp's binary convenience API. Its Helmholtz primitives provide residual-energy gradient/Hessian, pressure and pressure derivatives. A pressure-predictive ternary bubble solve at fixed `T,x` is mathematically feasible with six positive partial densities as unknowns and six equations: equality of three component chemical potentials, liquid/vapor pressure equality, and two independent liquid-composition constraints. Dew replaces those last constraints with two vapor-composition constraints. Bounded log-density/composition variables, a damped trust-region Newton/least-squares method, Wilson-type non-experimental initial estimates and continuation would be required.

The current production ABI exposes those primitives only inside the C++ bridge and exposes a hard-coded four-equation binary solver; it has no generic chemical-potential/fugacity/Jacobian contract. A scientifically robust ternary solver also requires phase-stability screening, critical-region handling and independently tested initialisation. Implementing an unvalidated ad-hoc solver merely to fit the 62 measurements would be unsafe. No experimental pressure or phase composition was used as a hidden initial parameter, no predictive pressure result was produced, and ternary VLE/phase map remain research-only. The rows now define the complete future bubble/dew acceptance matrix rather than an architecture claim.

## Other systems and built-ins

Targeted searches for CO₂/N₂/O₂ and CO₂/N₂/Ar used ThermoML, journal supplements, repositories, EOS-CG/GERG validation literature, CCS-metrology and PVT terminology. No lawful exact row-level ternary density table was acquired. The OxyComb I and II quaternary measurements independently cover CO₂+N₂+O₂+Ar, but do not justify deleting Ar or inferring either ternary. Yang et al. CO₂/N₂/Ar DOI `10.1021/acs.jced.5b00625` and Ke et al. DOI `10.1016/j.ijggc.2016.11.003` were identified, but no independently encoded production-ready row block was obtained. Higher mixtures are represented by the validated Razmjoo four- and five-component blocks above.

Porthos is stored unchanged at 293.15 K, 3.1 MPa and CO₂/N₂/CH₄/Ar/H₂ = 0.960/0.024/0.010/0.004/0.002. Aramis is stored unchanged at 248.15 K, 1.6 MPa and CO₂/CO/H₂/N₂/O₂ = 0.998/0.0012/0.0005/0.00029/0.00001. Neither exact composition/state matches a new gate, so both remain unsupported in Advanced CCS; their General Properties behavior is unchanged.

New low-N₂, CH₄, H₂ and O₂ binary searches did not yield an independently encoded block that broadens the accepted gates. Ar, CO and H₂S searches did not produce a new production dataset and remain research-only. Targeted speed-of-sound searches found no row-level dry multicomponent dataset paired with an implemented validated acoustic route; density validation is not reused. Caloric data were likewise not acquired for a defensible direct-property gate. Advanced viscosity and thermal conductivity remain unsupported because EOS-CG/teqp has no validated transport model here and no mixing rule is introduced.

## Product behavior

`AdvancedCCSCapabilityMatrix` remains the single source of truth. It now matches exact component set, exact fractions, property, measured isotherm and pressure block, including the disjoint TransportSpec pressure ranges. The existing Advanced CCS calculator accepts simultaneous impurities only for a matching gate and routes every component through the existing N-component density engine. It does not normalize, omit an impurity or fall back to a binary/CoolProp result. Guidance and About text disclose the exact compositions and direct users to the matrix-derived operating ranges. General Properties, water equilibrium and the safe phase-map architecture are unchanged.
