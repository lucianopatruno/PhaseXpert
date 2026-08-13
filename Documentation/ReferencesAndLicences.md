# References and licences

## Branding

The English IFE logo and palette are derived from the IFE PowerPoint template
supplied for this project and used with the user's confirmation of IFE
permission. The vector logo is included unmodified. Confirm internal brand
review before distribution.

## Software

The current runtime uses only Apple SDK frameworks. The CoolProp bridge and
MIT notice are present, but no CoolProp binary is linked. REFPROP and other
thermodynamic software are not included.

An optional teqp bridge can be generated locally from `usnistgov/teqp`
`v0.23.1`, commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`. teqp is made
available under the NIST disclaimer of copyright and warranty in its
`LICENSE.md`. The narrow PhaseXpert build embeds the upstream
`CarbonDioxide.json` model data, whose CO₂ EOS provenance is recorded as
`Span-JPCRD-1996`, and validation-gated impurity model data. `Nitrogen.json`
records `Span-JPCRD-2000`, the CO₂/N₂ reducing-parameter record in
`mixture_binary_pairs.json` cites `Gernert-Thesis-2013`, and the
`Nitrogen-CarbonDioxide` GERG-2008 departure function in
`mixture_departure_functions.json` cites `Kunz-JCED-2012`
([DOI 10.1021/je300655b](https://doi.org/10.1021/je300655b)). Those mixture
data are available only to native bridge validation; they are not user-facing
because Gate C failed to establish a supported operating range for this pinned
binary model. The multi-impurity inventory also records upstream O₂, Ar, H₂
and CH₄ model-data provenance; the O₂ and Ar diagnostic bake-off results in
`Documentation/Validation/TeqpMultiImpurityBakeoffResults.json` did not
establish a production domain. Pure-CO₂ teqp Cv, Cp and speed-of-sound
validation uses NIST Chemistry WebBook fluid-property rows, SRD 69
([DOI 10.18434/T4D303](https://doi.org/10.18434/T4D303)), as an independent
implementation reference for the Span-Wagner property formulation and units.
The
generated XCFramework, recorded revision, submodule list and licence are
ignored under `Vendor/teqp/` and must be reviewed before distribution.

Potential CoolProp reference:

I. H. Bell, J. Wronski, S. Quoilin, and V. Lemort, “Pure and Pseudo-pure Fluid
Thermophysical Property Evaluation and the Open-Source Thermophysical Property
Library CoolProp,” *Industrial & Engineering Chemistry Research*, 2014.
[DOI 10.1021/ie4033999](https://doi.org/10.1021/ie4033999).

Before integrating CoolProp, preserve its exact upstream licence and required
notices, inventory transitive code/data licences, document source/version, and
review static or dynamic linking and App Store obligations with IFE.

REFPROP is distributed under NIST terms and is not open-source redistribution
material. A local IFE licence does not automatically authorize embedding its
code or data in an iPhone application.

Current teqp impurity validation references under audit:

- S. F. Westman, H. G. J. Stang, S. W. Løvseth, A. Austegard, I. Snustad,
  S. Ø. Størset and I. S. Ertesvåg, "Vapor-liquid equilibrium data for the
  carbon dioxide and nitrogen (CO₂ + N₂) system at the temperatures 223, 270,
  298 and 303 K and pressures up to 18 MPa," *Fluid Phase Equilibria* 409,
  207-241, 2016.
  [DOI 10.1016/j.fluid.2015.09.034](https://doi.org/10.1016/j.fluid.2015.09.034).
- H. B. Brugge, J. C. Holste, K. R. Hall, B. E. Gammon and K. N. Marsh,
  "Densities of Carbon Dioxide + Nitrogen from 225 K to 450 K at Pressures up
  to 70 MPa," *Journal of Chemical & Engineering Data* 42, 903-907, 1997.
  [DOI 10.1021/je970044w](https://doi.org/10.1021/je970044w).
- M. Mantovani, P. Chiesa, G. Valenti, M. Gatti and S. Consonni,
  "Supercritical pressure-density-temperature measurements on CO₂-N₂, CO₂-O₂
  and CO₂-Ar binary mixtures," *Journal of Supercritical Fluids* 61, 34-43,
  2012.
  [DOI 10.1016/j.supflu.2011.09.001](https://doi.org/10.1016/j.supflu.2011.09.001).
- A. Mazzoccoli, B. Bosio and E. Arato,
  "Pressure-Density-Temperature Measurements of Binary Mixtures Rich in CO₂
  for Pipeline Transportation in the CCS Process," *Journal of Chemical &
  Engineering Data* 57, 2774-2783, 2012.
  [DOI 10.1021/je300590v](https://doi.org/10.1021/je300590v).

These references are validation inputs, not production-accuracy claims.
