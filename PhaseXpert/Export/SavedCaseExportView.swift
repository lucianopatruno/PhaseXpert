import PhaseXpertCore
import SwiftUI

struct SavedCaseExportView: View {
    @Environment(\.dismiss) private var dismiss

    private let source: Source
    @State private var artifacts: [CalculationExportArtifact] = []
    @State private var errorMessage: String?
    @State private var isPreparing = true
    @State private var phaseDiagramNote: String?

    /// What gets exported: a stored My Case, or the input snapshot of a built-in or validated case.
    private struct Source {
        let id: UUID
        let name: String
        let notes: String
        let createdAt: Date
        let updatedAt: Date
        let modelName: String
        let calculationID: UUID
        let record: CalculationRecord?
        let isInputSnapshot: Bool
    }

    init(savedCase: SavedCalculation) {
        source = Source(
            id: savedCase.id,
            name: savedCase.name,
            notes: savedCase.notes,
            createdAt: savedCase.createdAt,
            updatedAt: savedCase.updatedAt,
            modelName: savedCase.modelName,
            calculationID: savedCase.calculationID,
            record: savedCase.calculationRecord,
            isInputSnapshot: false
        )
    }

    /// Built-in and validated cases define a state but carry no calculation result.
    init(name: String, notes: String, inputSnapshot record: CalculationRecord) {
        let now = Date()
        source = Source(
            id: UUID(),
            name: name,
            notes: notes,
            createdAt: now,
            updatedAt: now,
            modelName: record.response.model.name,
            calculationID: record.response.calculationID,
            record: record,
            isInputSnapshot: true
        )
    }

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

                if source.isInputSnapshot {
                    Section {
                        Text("This case defines inputs and sources only. The export contains no calculated results.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved case") {
                    LabeledContent("Name", value: source.name)
                    LabeledContent("Model", value: source.modelName)
                    LabeledContent(
                        "Calculation ID",
                        value: source.calculationID.uuidString
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
            .task(id: source.id) {
                await prepareArtifacts()
            }
        }
    }

    private func prepareArtifacts() async {
        isPreparing = true
        errorMessage = nil
        artifacts = []
        phaseDiagramNote = nil

        guard let record = source.record else {
            errorMessage = CalculationExportError.noStoredCalculation.localizedDescription
            isPreparing = false
            return
        }

        let snapshot = SavedCaseExportSnapshot(
            savedCaseID: source.id,
            name: source.name,
            notes: source.notes,
            savedAt: source.createdAt,
            lastUpdatedAt: source.updatedAt,
            calculation: record
        )
        do {
            let diagram = source.isInputSnapshot ? nil : await phaseDiagramAttachment(for: record)
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
        guard PhaseDiagramEligibility.isPureCarbonDioxide(
            composition: record.request.composition
        ) else {
            phaseDiagramNote = PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            return nil
        }

        let registry = ProviderRegistry()
        guard let provider = registry.provider(id: record.request.modelID) else {
            phaseDiagramNote = "The CO₂ phase diagram was not embedded for this saved calculation."
            return nil
        }
        let current = provider.descriptor
        let recorded = record.response.model
        guard current.modelVersion == recorded.modelVersion,
              current.providerVersion == recorded.providerVersion
        else {
            phaseDiagramNote = "The CO₂ phase diagram was not embedded because this saved calculation was made with a different installed model version."
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
                ? PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
                : "The PDF includes a newly calculated pure CO₂ phase diagram from the same recorded model version."
            return attachment
        } catch {
            phaseDiagramNote = "The CO₂ phase diagram was not embedded for this saved calculation."
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
