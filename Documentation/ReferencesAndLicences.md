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

## ThermoPack

PhaseXpert pins ThermoPack v2.2.4 at commit
`ca75d8e095e8b951616897efe1bca9b8c3badda7`. ThermoPack is Apache-2.0
licensed. The complete upstream licence and PhaseXpert attribution/build notice
are stored in `ThirdParty/ThermoPack/LICENSE` and
`ThirdParty/ThermoPack/NOTICE`.

Authoritative references:

- https://github.com/thermotools/thermopack/tree/v2.2.4
- https://github.com/thermotools/thermopack/releases/tag/v2.2.4
- https://thermotools.github.io/thermopack/v2.2.0/home.html
- https://doi.org/10.1021/acs.iecr.7b00317
- https://doi.org/10.1021/i160057a011

The selected data provenance is the upstream `binaries/PR_kij.json` record
`vdW-18` for CO₂/N₂, `ref=Default`. This records shipped provenance and
does not claim experimental validation. Generated binaries are excluded from
Git and require distribution review for static Fortran runtime compliance.
