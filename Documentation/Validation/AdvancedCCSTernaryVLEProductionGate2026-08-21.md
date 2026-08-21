# Advanced CCS ternary VLE production-gate assessment — 2026-08-21

## Decision

**RESEARCH ONLY. No CO₂+N₂+CH₄ bubble-pressure or dew-pressure production gate is promoted.** The 62 Ottøy rows contain two clean 298.13 K four-to-five-point blocks, but every row in each block has a different specified composition. Treating the block as a composition interval would therefore validate interpolation that was not tested at repeated compositions or neighboring temperatures. Treating each row as an exact-composition gate would leave one experimental boundary observation per gate, which does not meet the requirement for enough neighboring measurements at the gated composition. This limitation is decisive even before considering that model deviations are materially larger than the reported standard measurement uncertainties. The accepted solver, stability rejection, density routing, and all earlier validation domains are unchanged.

## Source and grouping

The immutable source artifact is `Ottoy2020TernaryVLE.json`: Ottøy et al., *Fluid Phase Equilibria* 509 (2020) 112444, DOI `10.1016/j.fluid.2019.112444`, 31 liquid-specified bubble rows (`L1`–`L31`) and 31 vapor-specified dew rows (`V1`–`V31`). Each `L`/`V` pair is the measured pair of compositions at essentially the same equilibrium state. Rows were grouped without reordering by observable, nominal isotherm, and the visible composition sequence. At 298.13 K the source contains two distinct families: a balanced-impurity sequence (`1`–`5`) and an N₂-rich relative-to-CH₄ sequence (`6`–`9`). The remaining isotherms each contain one balanced-impurity sequence.

| Block | Observable | Rows | Nominal T (K) | Specified xN₂ span | Specified xCH₄ span | Evidence P span (MPa) |
|---|---|---:|---:|---:|---:|---:|
| B298-balanced | bubble | L1–L5 | 298.13 | 0.0089–0.0266 | 0.0104–0.0294 | 7.0850–7.9281 |
| B298-N2-rich | bubble | L6–L9 | 298.129 | 0.0090–0.0362 | 0.0024–0.0088 | 6.8975–7.9272 |
| B283 | bubble | L10–L15 | 283.155 | 0.0083–0.0709 | 0.0115–0.0766 | 5.2541–8.8483 |
| B273 | bubble | L16–L22 | 273.168 | 0.0050–0.0939 | 0.0076–0.1030 | 3.9903–9.3244 |
| B253 | bubble | L23–L27 | 253.162 | 0.0033–0.0183 | 0.0057–0.0294 | 2.3369–3.7991 |
| B223 | bubble | L28–L31 | 223.151 | 0.0009–0.0044 | 0.0018–0.0089 | 0.7965–1.2246 |
| D298-balanced | dew | V1–V5 | 298.13 | 0.0215–0.0359 | 0.0198–0.0356 | 7.0854–7.9286 |
| D298-N2-rich | dew | V6–V9 | 298.129 | 0.0240–0.0593 | 0.0050–0.0122 | 6.8978–7.9277 |
| D283 | dew | V10–V15 | 283.155 | 0.0476–0.1360 | 0.0415–0.1208 | 5.2542–8.6818 |
| D273 | dew | V16–V22 | 273.168 | 0.0465–0.2021 | 0.0401–0.1712 | 3.9894–9.3076 |
| D253 | dew | V23–V27 | 253.162 | 0.0668–0.2153 | 0.0558–0.1745 | 2.3336–3.7969 |
| D223 | dew | V28–V31 | 223.151 | 0.0708–0.2289 | 0.0558–0.1774 | 0.7963–1.2233 |

The exact per-row specified compositions remain in the immutable source artifact; the compact machine-readable decision artifact references every included source-row ID and records each block's bounds rather than duplicating the dataset.

## Recomputed source-state baseline

The accepted teqp v0.23.1 solver at commit `a68eb9cabf47af2c4aba0d272ac10fbca4c10eca` produces the existing post-PR60 baseline: bubble 21/31 stable/converged, pressure AARD 0.542199%, bias −0.446304%, RMS 0.649702%, worst −1.268690%; dew 23/31 stable/converged, pressure AARD 1.504217%, bias −1.177069%, RMS 2.620868%, worst −10.279512%. All 18 rejected rows retain structured stability/no-distinct-split rejection; the dew V28 trial also exhibits a nonphysical negative-pressure candidate and remains rejected. No acceptance criterion was loosened.

## Contiguous-block metrics and decisions

Pressure metrics use converged rows only; convergence counts always retain failed rows. AARD, bias, RMS and worst are relative pressure deviations in percent. Opposite-phase entries are component-wise `MAE / bias / RMS / worst absolute error` in mole fraction, ordered CO₂, N₂, CH₄. There were no accepted near-critical results and no unstructured numerical failures in these blocks; all failed rows were stability/no-distinct-split rejections.

| Block | Conv. | Pressure AARD / bias / RMS / worst | Mean / worst abs. P error | Opposite-phase CO₂ | Opposite-phase N₂ | Opposite-phase CH₄ | Decision |
|---|---:|---|---|---|---|---|---|
| B298-balanced | 5/5 | 0.332808 / −0.095965 / 0.377192 / +0.532160 | 25.213 / 42.190 kPa | .004850 / −.004850 / .005978 / .010255 | .003261 / +.003261 / .003790 / .005966 | .001617 / +.001609 / .002279 / .004389 | rejected |
| B298-N2-rich | 4/4 | 0.245402 / −0.245402 / 0.282171 / −0.397315 | 17.779 / 27.405 kPa | .001795 / −.001795 / .002381 / .004276 | .001617 / +.001617 / .002025 / .003553 | .000322 / +.000203 / .000406 / .000723 | rejected |
| B283 | 4/6 | 0.814014 / −0.814014 / 0.834663 / −1.003173 | 63.191 / 82.848 kPa | .002074 / +.000271 / .002375 / .003605 | .002360 / +.002360 / .003320 / .005540 | .002631 / −.002631 / .003387 / .005983 | rejected |
| B273 | 3/7 | 1.179745 / −1.179745 / 1.185984 / −1.268690 | 98.909 / 111.137 kPa | .002857 / +.000572 / .003516 / .005032 | .001906 / +.001095 / .002138 / .003278 | .001733 / −.001634 / .002281 / .003716 | rejected |
| B253 | 4/5 | 0.382614 / −0.382614 / 0.405014 / −0.593201 | 12.368 / 22.536 kPa | .004371 / +.003580 / .004710 / .005927 | .001687 / −.000439 / .001768 / .002496 | .003142 / −.003142 / .003425 / .004337 | rejected |
| B223 | 1/4 | 0.414790 / +0.414790 / 0.414790 / +0.414790 | 3.304 / 3.304 kPa | .006009 / −.006009 / .006009 / .006009 | .005241 / +.005241 / .005241 / .005241 | .000768 / +.000768 / .000768 / .000768 | rejected |
| D298-balanced | 5/5 | 2.027031 / −2.027031 / 2.330663 / −3.793999 | 158.000 / 300.811 kPa | .006386 / +.006386 / .008413 / .015296 | .003719 / −.003719 / .004738 / .008323 | .002647 / −.002647 / .003678 / .006973 | rejected |
| D298-N2-rich | 4/4 | 0.964822 / −0.964822 / 1.118287 / −1.887762 | 73.827 / 149.656 kPa | .001993 / +.001993 / .002920 / .005522 | .001700 / −.001700 / .002469 / .004673 | .000343 / −.000293 / .000503 / .000949 | rejected |
| D283 | 5/6 | 1.061213 / −1.061213 / 1.816618 / −3.911474 | 90.117 / 339.586 kPa | .005704 / +.002631 / .009486 / .020837 | .003160 / −.002534 / .005669 / .012519 | .003251 / −.000116 / .004247 / .008418 | rejected |
| D273 | 4/7 | 3.188790 / −2.412782 / 5.189557 / −10.279512 | 289.290 / 956.776 kPa | .013521 / +.006675 / .020685 / .040394 | .007122 / −.004374 / .011659 / .022992 | .006399 / −.002301 / .009068 / .017401 | rejected |
| D253 | 3/5 | 0.504151 / +0.283390 / 0.527352 / +0.706621 | 13.984 / 21.490 kPa | .000519 / −.000488 / .000634 / .000930 | .000155 / +.000070 / .000162 / .000223 | .000418 / +.000418 / .000491 / .000708 | rejected |
| D223 | 2/4 | 0.514436 / +0.514436 / 0.617577 / +0.856133 | 6.096 / 10.473 kPa | .000182 / +.000182 / .000190 / .000236 | .000040 / −.000027 / .000048 / .000067 | .000155 / −.000155 / .000156 / .000169 | rejected |

The two 298 K bubble blocks are the strongest candidates. They are rejected because their apparent continuity is across changing composition, not repeated evidence at a gated composition, and because even the stronger N₂-rich block has pressure MAE 17.779 kPa and worst error 27.405 kPa while its reported pressure standard uncertainties are approximately 1.3–1.5 kPa. Its opposite-phase MAEs are 0.001795 CO₂, 0.001617 N₂ and 0.000322 CH₄, versus reported standard composition uncertainties in this part of the source of roughly 0.00042–0.00060, 0.00034–0.00047 and 0.00027–0.00034 respectively. The balanced block is less favorable in opposite-phase composition. The cleaner 253 K dew prefix V23–V25 has only three successful neighbors and is bounded immediately by two stability rejections, so it is not enlarged or promoted. Removing V15 or V22 would manufacture shorter cherry-picked dew subsets and is not accepted.

## Product consequences

No `bubblePressure` or `dewPressure` property ID is added; no Advanced capability-matrix entry, provider production route, calculator phase-boundary section, pressure margin, or VLE shield activation is created. Operating pressure therefore cannot accidentally gate or imply a boundary calculation. Generic phase classification remains research-only for this ternary, and TP flash, beta, TPD and Hessian diagnostics remain research/internal only. There is no fallback or experimental-table lookup.

Pressure margin would be defined as `current operating pressure − predicted boundary pressure`, with wording that states above/below rather than exposing an unexplained signed number. Because no boundary gate passed, no production margin is calculated or displayed.

No built-in composition exactly matches any measured ternary specified composition. No built-in was changed. A research phase-envelope continuation was not added: without a promoted exact-composition family, choosing one changing-composition isotherm row as an envelope anchor would not address the production evidence gap and would add invasive work below the milestone priority. The existing research bubble/dew, global-stability and TP-flash infrastructure remains intact.

Representative solver performance remains the accepted sub-second-per-state range recorded by the 62-row artifact (`runtime_ms`); no production-gated state exists for a separate performance claim. CoolProp execution is not treated as validation.
