use serde::Serialize;

#[derive(Serialize)]
struct FeOsProbe {
    feos_release: &'static str,
    feos_commit: &'static str,
    status: &'static str,
    termination_reason: &'static str,
}

fn main() {
    let probe = FeOsProbe {
        feos_release: "v0.10.1",
        feos_commit: "c658aeab484f7a7096bfbf5425e40effd60da167",
        status: "blocked_before_native_calculation",
        termination_reason: "The PhaseXpert feasibility gate requires a pinned CO2/N2 PC-SAFT binary interaction parameter; none was found in the pinned FeOs parameter files, and cargo is unavailable in this validation environment.",
    };
    println!("{}", serde_json::to_string_pretty(&probe).expect("serialize FeOs probe"));
}
