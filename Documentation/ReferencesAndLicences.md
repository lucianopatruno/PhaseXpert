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
`LICENSE.md`. The narrow PhaseXpert build currently uses only the upstream
`CarbonDioxide.json` model data, whose CO₂ EOS provenance is recorded as
`Span-JPCRD-1996`. The pinned upstream tree also contains CO₂+N₂ multifluid
data: `Nitrogen.json` records `Span-JPCRD-2000`, the CO₂/N₂ reducing-parameter
record in `mixture_binary_pairs.json` cites `Gernert-Thesis-2013`, and the
`Nitrogen-CarbonDioxide` GERG-2008 departure function in
`mixture_departure_functions.json` cites `Kunz-JCED-2012`
([DOI 10.1021/je300655b](https://doi.org/10.1021/je300655b)). Those mixture
data are documented for provenance only; they are not enabled until native
mixture stability, flash and independent validation gates pass. The generated
XCFramework, recorded revision, submodule list and licence are ignored under
`Vendor/teqp/` and must be reviewed before distribution.

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

Scientific references for the production formulation, binary interaction
parameters and validation datasets are not selected yet and must not be
invented.
