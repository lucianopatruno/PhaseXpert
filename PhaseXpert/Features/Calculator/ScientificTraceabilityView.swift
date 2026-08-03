import PhaseXpertCore
import SwiftUI

struct ScientificTraceabilityView: View {
    @Environment(\.dismiss) private var dismiss

    let descriptor: ModelDescriptor?
    let record: CalculationRecord?

    var body: some View {
        NavigationStack {
            List {
                if let descriptor {
                    Section("Selected model") {
                        LabeledContent("Model", value: descriptor.name)
                        LabeledContent("Model ID", value: descriptor.id)
                        LabeledContent("Model version", value: descriptor.modelVersion)
                        LabeledContent("Provider version", value: descriptor.providerVersion)
                        LabeledContent(
                            "Library/coefficient version",
                            value: descriptor.coefficientSetVersion ?? "Not specified"
                        )
                        LabeledContent("Status", value: descriptor.availability.rawValue.capitalized)
                        LabeledContent("Execution", value: descriptor.calculationMode.rawValue.capitalized)
                    }

                    Section("Scientific basis") {
                        traceabilityText(descriptor.scientificBasis)
                        LabeledContent("Equation or method") {
                            traceabilityText(descriptor.equationOrMethod)
                        }
                        LabeledContent("Pressure domain") {
                            Text(
                                "\(number(descriptor.domain.minimumPressurePa / 100_000))–\(number(descriptor.domain.maximumPressurePa / 100_000)) bar(a)"
                            )
                            .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Temperature domain") {
                            Text(
                                "\(number(descriptor.domain.minimumTemperatureK - 273.15))–\(number(descriptor.domain.maximumTemperatureK - 273.15)) °C"
                            )
                            .multilineTextAlignment(.trailing)
                        }
                    }

                    if !descriptor.limitations.isEmpty {
                        Section("Recorded limitations") {
                            ForEach(descriptor.limitations, id: \.self) { limitation in
                                Label(limitation, systemImage: "exclamationmark.triangle")
                            }
                        }
                    }

                    Section("Scientific references") {
                        if descriptor.references.isEmpty {
                            Text("No scientific reference is recorded for this provider.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(descriptor.references.enumerated()), id: \.offset) { index, reference in
                                if let url = reference.destinationURL {
                                    Link(destination: url) {
                                        referenceLabel(reference, isInteractive: true)
                                    }
                                    .id("traceability-reference-\(index)-\(url.absoluteString)")
                                    .accessibilityLabel(
                                        "\(reference.authors), \(reference.title), open reference"
                                    )
                                    .accessibilityHint("Opens this scientific reference in the browser.")
                                } else {
                                    referenceLabel(reference, isInteractive: false)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No model selected",
                        systemImage: "checkmark.shield",
                        description: Text("Select a calculation model to inspect its scientific provenance.")
                    )
                }

                Section("Latest calculation") {
                    if let record {
                        LabeledContent("Calculated at") {
                            Text(record.response.calculatedAt.formatted(
                                .dateTime.year().month().day().hour().minute().second()
                            ))
                        }
                        identifierRow("Calculation ID", record.response.calculationID)
                        identifierRow("Request ID", record.response.requestID)
                        LabeledContent(
                            "Operating point",
                            value: "\(number(record.input.pressureValue)) bar(a), \(number(record.input.temperatureValue)) °C"
                        )
                        LabeledContent("Composition") {
                            Text(composition(record))
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Phase", value: record.response.phase.displayName)
                        LabeledContent(
                            "Converged",
                            value: record.response.solver.converged ? "Yes" : "No"
                        )
                        LabeledContent(
                            "Duration",
                            value: "\(number(record.response.solver.durationMilliseconds)) ms"
                        )
                        if !record.response.warnings.isEmpty {
                            ForEach(record.response.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.ifePrimary)
                            }
                        }
                    } else {
                        Text("No calculation has been completed in this calculator session. Model provenance is shown above.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Scientific Traceability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func referenceLabel(
        _ reference: SourceReference,
        isInteractive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(reference.authors) (\(reference.year))")
                .font(.subheadline.weight(.semibold))
            Text(reference.title)
            if let identifier = reference.doiOrURL {
                Label(
                    identifier,
                    systemImage: isInteractive ? "arrow.up.right.square" : "doc.text"
                )
                .font(.caption)
                .foregroundStyle(isInteractive ? Color.ifePrimary : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func traceabilityText(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(Color.ifeText)
            .textSelection(.enabled)
    }

    private func identifierRow(_ label: String, _ id: UUID) -> some View {
        LabeledContent(label) {
            Text(id.uuidString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func composition(_ record: CalculationRecord) -> String {
        record.input.originalComposition.map {
            "\($0.component.symbol) \(number($0.value)) mol%"
        }.joined(separator: ", ")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }
}
