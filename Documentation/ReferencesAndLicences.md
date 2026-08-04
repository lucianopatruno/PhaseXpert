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

## NeqSim

NeqSim is Apache-2.0 licensed and maintained by Equinor at
<https://github.com/equinor/neqsim>. PR23 pins release `v3.16.0` at source
commit `3af7b560525b57f2d3da2c803a08e2b41a8d7f5a` and uses the official
documentation at <https://equinor.github.io/neqsim/> plus the phase-envelope
guide at
<https://github.com/equinor/neqsim/blob/master/docs/pvtsimulation/phase_envelope_guide.md>.
The service pattern is based on
<https://github.com/equinor/NeqSimLive-api-template>.

Required notices for a production service image must include the Apache-2.0
licence text and any notices required by transitive Python/Java dependencies.
No NeqSim binary is embedded in the iOS app by PR23.

REFPROP is distributed under NIST terms and is not open-source redistribution
material. A local IFE licence does not automatically authorize embedding its
code or data in an iPhone application.

Scientific references for the production formulation, binary interaction
parameters and validation datasets are not selected yet and must not be
invented.
