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
                            ForEach(Array(descriptor.references.enumerated()), id: \.offset) { _, reference in
                                if let link = ReferenceLinkResolver.url(for: reference.doiOrURL) {
                                    Link(destination: link) {
                                        referenceLabel(reference, identifier: reference.doiOrURL)
                                    }
                                    .accessibilityLabel(
                                        "\(reference.title), opens \(link.absoluteString)"
                                    )
                                } else {
                                    referenceLabel(reference, identifier: reference.doiOrURL)
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
                            value: "\(number(record.input.pressureValue)) \(record.input.pressureDisplayUnitLabel), \(number(record.input.temperatureValue)) \(record.input.temperatureUnit.rawValue)"
                        )
                        LabeledContent("Pressure — SI", value: "\(number(record.input.pressurePa)) Pa")
                        LabeledContent("Temperature — SI", value: "\(number(record.input.temperatureK)) K")
                        LabeledContent("Original composition") {
                            Text(composition(record))
                                .multilineTextAlignment(.trailing)
                        }
                        if let normalized = record.input.normalizedComposition {
                            LabeledContent("Internal composition") {
                                Text(normalized.map {
                                    "\($0.component.symbol) \(number($0.moleFraction * 100)) mol%"
                                }.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Normalization", value: "Applied and recorded")
                        } else {
                            LabeledContent("Normalization", value: "Not applied")
                        }
                        LabeledContent("Phase", value: record.response.phase.displayName)
                        LabeledContent("Calculation status", value: record.response.isScientificResult ? "Preliminary scientific result" : "Non-scientific result")
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
                        LabeledContent(
                            "Application",
                            value: "\(record.application.version) (\(record.application.build))"
                        )
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
            "\($0.component.symbol) \(number($0.value)) \($0.unit.rawValue)"
        }.joined(separator: ", ")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }

    @ViewBuilder
    private func referenceLabel(
        _ reference: SourceReference,
        identifier: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.title)
                .font(.subheadline.weight(.semibold))
            Text("\(reference.authors) (\(reference.year))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let identifier {
                Label(identifier, systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(Color.ifePrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum ReferenceLinkResolver {
    private static let doiPattern = #"^10\.\d{4,9}/[-._;()/:A-Z0-9]+$"#

    static func url(for identifier: String?) -> URL? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.scheme == "https",
           url.host?.isEmpty == false {
            return url
        }

        let doi = trimmed.hasPrefix("doi:")
            ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        guard isDOI(doi),
              let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            return nil
        }
        return URL(string: "https://doi.org/\(encoded)")
    }

    private static func isDOI(_ value: String) -> Bool {
        value.range(
            of: doiPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
