# Internal distribution and App Store checklist

## Current delivery: internal/TestFlight

- Set the Apple Developer team and confirm the bundle identifier.
- Create an App Store Connect record and internal TestFlight group.
- Supply an approved 1024×1024 app icon; the current icon slot is empty.
- Confirm IFE trademark/logo approval for the app context.
- Build on a clean Mac, run unit/UI tests and archive with Xcode 26.
- Verify version/build numbering and export-compliance answers.
- Test on the smallest and largest supported iPhone, light/dark mode and
  accessibility text sizes.

## Before broader distribution

- Complete scientific validation and have IFE approve all accuracy language.
- Complete licence review for every linked library and dataset.
- Finalize scientific disclaimer, support URL, copyright and privacy policy.
- Update the privacy manifest and App Store privacy answers if remote IFE
  calculation, telemetry or any data collection is added.
- Add data-retention and deletion policy for server requests.
- Verify no credentials, signing artifacts, local endpoints or debug logging
  are in the archive.
- Produce acknowledgements and model/reference disclosures.
- Perform accessibility audit and localization review.
- Decide public, unlisted or custom/internal distribution with IFE.

