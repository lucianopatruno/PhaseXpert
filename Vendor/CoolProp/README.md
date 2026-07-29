# CoolProp binary location

Run `Scripts/build-coolprop-xcframework.sh` on a Mac with Xcode 26 and CMake.
The generated `PhaseXpertCoolPropBridge.xcframework` is intentionally ignored
until its architectures, provenance and reproducibility have been reviewed.

The current application remains buildable without this artifact and shows the
CoolProp provider as unavailable.
