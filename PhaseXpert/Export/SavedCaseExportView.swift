import SwiftUI

struct SavedCaseExportView: View {
    @Environment(\.dismiss) private var dismiss

    let savedCase: SavedCalculation
    @State private var artifacts: [CalculationExportArtifact] = []
    @State private var errorMessage: String?
    @State private var isPreparing = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScientificStatusBanner(
                        title: "Export preserves recorded status",
                        message: "Preliminary, unavailable, extrapolated and failed values retain their recorded status. Exporting does not validate a calculation."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Saved case") {
                    LabeledContent("Name", value: savedCase.name)
                    LabeledContent("Model", value: savedCase.modelName)
                    LabeledContent(
                        "Calculation ID",
                        value: savedCase.calculationID.uuidString
                    )
                }

                Section {
                    if isPreparing {
                        HStack {
                            ProgressView()
                            Text("Preparing export files…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label(
                                "Export unavailable",
                                systemImage: "exclamationmark.triangle"
                            )
                        } description: {
                            Text(errorMessage)
                        }
                    } else {
                        ForEach(artifacts) { artifact in
                            ShareLink(
                                item: artifact.fileURL,
                                preview: SharePreview(
                                    artifact.fileURL.lastPathComponent,
                                    image: Image(systemName: icon(for: artifact.format))
                                )
                            ) {
                                Label(
                                    "Share \(artifact.format.displayName)",
                                    systemImage: icon(for: artifact.format)
                                )
                            }
                            .accessibilityIdentifier(
                                "share-case-\(artifact.format.rawValue)"
                            )
                        }
                    }
                } header: {
                    Text("Formats")
                } footer: {
                    Text("JSON retains the complete versioned calculation record. CSV provides a long-form table suitable for review in spreadsheet and data-analysis software.")
                }

                Section("Privacy") {
                    Text("Files are generated locally. PhaseXpert sends nothing automatically; data leaves the device only through the destination you select in the iOS share sheet.")
                }
            }
            .navigationTitle("Export Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: savedCase.id) {
                prepareArtifacts()
            }
        }
    }

    private func prepareArtifacts() {
        isPreparing = true
        errorMessage = nil
        artifacts = []

        guard let record = savedCase.calculationRecord else {
            errorMessage = CalculationExportError.noStoredCalculation.localizedDescription
            isPreparing = false
            return
        }

        let snapshot = SavedCaseExportSnapshot(
            savedCaseID: savedCase.id,
            name: savedCase.name,
            notes: savedCase.notes,
            savedAt: savedCase.createdAt,
            lastUpdatedAt: savedCase.updatedAt,
            calculation: record
        )
        do {
            artifacts = try CalculationExportFileStore().createArtifacts(for: snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    private func icon(for format: CalculationExportFormat) -> String {
        switch format {
        case .json: "curlybraces"
        case .csv: "tablecells"
        }
    }
}
