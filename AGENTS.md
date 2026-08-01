# PhaseXpert repository instructions

## Product and scientific safeguards

- PhaseXpert is scientific software. Never invent equations, coefficients, binary interaction parameters, validity ranges, references, accuracy claims, or plausible fallback values.
- Unsupported, incomplete, non-finite, non-converged, extrapolated, and unavailable results must remain explicitly distinguishable.
- Never silently normalize composition or extrapolate beyond a provider's declared domain.
- Keep SwiftUI independent of a specific thermodynamic library; scientific work belongs in providers and numerical layers.
- Pressure is displayed in bar(a), temperature in °C, and calculations use documented SI internally.
- CoolProp results remain preliminary until independently validated. A successful CoolProp execution is not scientific validation.

## Local state that must be preserved

- Preserve unrelated user changes and inspect the worktree before editing.
- Never stage, restore, discard, or commit the user's local signing-only `PhaseXpert.xcodeproj/project.pbxproj` change.
- Never change `DEVELOPMENT_TEAM`, signing, bundle identifiers, entitlements, provisioning, remotes, or user-specific Xcode state unless explicitly requested.
- Generated files under `Vendor/CoolProp` are ignored and must not be committed.
- Do not rebuild CoolProp unless its generated XCFramework is absent or `Scripts/ensure-coolprop-xcframework.sh` reports that the bridge ABI/source fingerprint changed.

## Git workflow

- Start feature work from current `main` on an `agent/<description>` branch.
- Keep milestones buildable and commits scoped.
- Never force-push, rewrite published history, modify remotes, or merge a PR without explicit approval.
- Run `git diff --check` before handoff.

## Validation tiers

Use the smallest tier appropriate to the change:

- Fast development check: `bash Scripts/validate-phase-xpert.sh fast`
- Completed feature check: `bash Scripts/validate-phase-xpert.sh standard`
- Pre-merge/release check: `bash Scripts/validate-phase-xpert.sh release`

Do not run the full UI suite after every compiler correction. First rerun the smallest failing test, then its target, and reserve the release tier for a completed milestone.

Shell `xcodebuild` can be blocked inside a restricted agent sandbox even when Xcode itself works. If that occurs, report the sandbox error and use Xcode-integrated build/test tools or ask the user to run the validation script in a normal macOS Terminal. Do not change cache permissions to bypass sandboxing.

Physical-iPhone and visual/scientific acceptance checks are manual. Never claim they passed unless the user performed them.

## Handoff format

At the end of an Xcode Codex task, respond with exactly one concise paragraph that can be pasted into ChatGPT. Include branch, HEAD, build result, exact test totals, actionable errors/warnings, `git diff --check`, and final Git status. Do not include command transcripts or manual-validation instructions in that paragraph.
