import PhaseXpertCore
import SwiftUI

struct SavedCaseExportView: View {
    @Environment(\.dismiss) private var dismiss

    let savedCase: SavedCalculation
    @State private var artifacts: [CalculationExportArtifact] = []
    @State private var errorMessage: String?
    @State private var isPreparing = true
    @State private var phaseDiagramNote: String?

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
                    Text("JSON retains the complete versioned record. CSV provides a long-form data table. The PDF Report is a printable, human-readable calculation record with warnings and scientific provenance.")
                }

                if let phaseDiagramNote {
                    Section("Phase diagram in PDF") {
                        Text(phaseDiagramNote)
                            .foregroundStyle(.secondary)
                    }
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
                await prepareArtifacts()
            }
        }
    }

    private func prepareArtifacts() async {
        isPreparing = true
        errorMessage = nil
        artifacts = []
        phaseDiagramNote = nil

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
            let diagram = await phaseDiagramAttachment(for: record)
            artifacts = try CalculationExportFileStore().createArtifacts(
                for: snapshot,
                phaseDiagram: diagram
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    private func phaseDiagramAttachment(
        for record: CalculationRecord
    ) async -> PhaseDiagramReportAttachment? {
        let composition = record.request.composition.filter { $0.moleFraction > 1e-12 }
        let isPure = composition.count == 1
            && composition[0].component == .carbonDioxide
            && abs(composition[0].moleFraction - 1) <= 1e-9
        let isRestrictedBinary = composition.count == 2
            && composition.contains {
                $0.component == .carbonDioxide && $0.moleFraction > 0.5
            }
            && composition.contains {
                $0.component == .nitrogen
                    && $0.moleFraction > 0
                    && $0.moleFraction <= 0.10
            }
        guard isPure || isRestrictedBinary else {
            phaseDiagramNote = "No diagram was embedded because the active provider does not calculate a real envelope for this composition."
            return nil
        }

        let registry = ProviderRegistry()
        guard let provider = registry.provider(id: record.request.modelID) else {
            phaseDiagramNote = "No diagram was embedded because the recorded provider is not installed."
            return nil
        }
        let current = provider.descriptor
        let recorded = record.response.model
        guard current.modelVersion == recorded.modelVersion,
              current.providerVersion == recorded.providerVersion
        else {
            phaseDiagramNote = "No diagram was embedded because the installed model/provider version differs from the saved calculation provenance."
            return nil
        }

        do {
            let response = try await provider.phaseEnvelope(
                PhaseEnvelopeRequest(
                    modelID: record.request.modelID,
                    composition: record.request.composition
                )
            )
            let attachment = try PhaseDiagramImageExporter().attachment(
                for: record,
                response: response
            )
            phaseDiagramNote = response.boundaryKind == .mixtureEnvelope
                ? "The PDF includes a newly calculated CO₂-N₂ bubble/dew envelope from the same recorded model and provider versions."
                : "The PDF includes a newly calculated pure CO₂ boundary from the same recorded model and provider versions."
            return attachment
        } catch {
            phaseDiagramNote = "No diagram was embedded: \(error.localizedDescription)"
            return nil
        }
    }

    private func icon(for format: CalculationExportFormat) -> String {
        switch format {
        case .json: "curlybraces"
        case .csv: "tablecells"
        case .pdf: "doc.richtext"
        }
    }
}
