# Advanced CCS teqp Independent Validation 2026-08-20

## Scope

This audit evaluated the pinned Advanced CCS teqp stack against primary experimental rows already encoded from earlier validation work. The model evaluated was teqp v0.23.1 at commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca`; no CoolProp, REFPROP, or generated software reference values were used as validation truth.

## CO2 + N2

The current teqp CO2/N2 path uses the multifluid model with Span-JPCRD-1996 CO2, Span-JPCRD-2000 N2, Gernert-Thesis-2013 reducing parameters, and the Kunz-JCED-2012 GERG-2008 departure function. Primary density rows were Mazzoccoli, Bosio and Arato 2012, DOI `10.1021/je300590v`.

All 64 encoded CO2/N2 density rows converged, but broad all-phase agreement failed production criteria: AARD 30.298704%, signed bias -29.797176%, RMS 39.672169%, worst -87.067537% at 273.15 K, 3.902 MPa, xN2 = 0.0127, liquid. The homogeneous gas subset had 15 converged rows with AARD 1.655175%, signed bias +0.166935%, RMS 2.105955%, and worst -5.299781%. Only the 283.15 K gas isotherm at xN2 = 0.0127 formed a defensible narrow gate: 5/5 converged, 1.0-4.5 MPa, AARD 0.599354%, signed bias +0.022493%, RMS 0.765116%, worst -1.442151%.

Production promotion is therefore limited to CO2+N2 homogeneous gas density, plus density-derived molar mass, specific volume, and Z, at exact xN2 = 0.0127, T = 283.15 K, P = 1.0-4.5 MPa. CO2/N2 VLE, phase maps, phase classification, dense/liquid density, Cp, Cv, speed of sound, h, u, s, viscosity, and thermal conductivity remain unsupported or research-only.

## Other Binary Results

CO2+CH4 retained its existing Ghafri 2016 density gate and Petropoulou 2018 narrow VLE gate. Re-evaluation of 180 Ghafri density rows, DOI `10.1016/j.fluid.2015.08.029`, gave 180/180 convergence, AARD 1.398222%, signed bias +1.398222%, RMS 1.689068%, and worst +5.152136%; no broader production domain was added.

CO2+H2 retained its existing Souissi 2017 gas-density gate. Re-evaluation of 19 rows, DOI `10.1021/acs.jced.7b00213`, gave 19/19 convergence, AARD 0.096971%, signed bias +0.093072%, RMS 0.148968%, and worst +0.408391%; no broader production domain was added.

CO2+O2 retained the existing exact xO2 = 0.05032089 Lozano-Martin 2020 density gate, DOI `10.1016/j.jct.2020.106210`. The already production-enabled low-O2 subset gave 45/45 convergence, AARD 0.079069%, signed bias +0.004184%, RMS 0.113610%, worst -0.393365%. The full encoded set gave 92/92 convergence, AARD 0.115728%, signed bias -0.027834%, RMS 0.204599%, worst -1.211989%, but the high-O2 composition remains diagnostic pending explicit multi-composition gate representation.

CO2+Ar Mazzoccoli 2012 density rows, DOI `10.1021/je300590v`, gave 122/122 convergence but failed broad production criteria: AARD 19.428318%, signed bias -19.365641%, RMS 29.705479%, worst -51.157166%. No narrow Ar gate was promoted.

No lawful row-level primary CO2+CO or CO2+H2S dataset was encoded in this milestone, so both remain research-only/validation pending.

## Multicomponent Dry Mixtures

The encoded Ottoy 2020 ternary VLE source contains primary CO2+N2+CH4 phase-equilibrium rows, but there is no production ternary VLE initialization and continuation path. The Zhang 2022 ternary density acquisition notes identify 200 reported rows but no lawfully encoded numerical rows are present. Dry ternary and higher-component Advanced CCS mixtures therefore remain diagnostic only.
