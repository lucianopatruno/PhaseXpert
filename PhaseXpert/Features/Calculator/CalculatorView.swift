import PhaseXpertCore
import SwiftUI

struct CalculatorView: View {
    private enum InputField: Hashable {
        case pressure
        case atmosphericReference
        case temperature
        case composition
    }

    @State private var viewModel = CalculatorViewModel()
    @FocusState private var focusedField: InputField?

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    ScientificStatusBanner(
                        title: "Scientific engine not connected",
                        message: "This milestone demonstrates input validation and provider architecture. It does not produce thermophysical results."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Calculation model") {
                    Picker("Model", selection: $viewModel.selectedModelID) {
                        ForEach(viewModel.descriptors) { descriptor in
                            Text(descriptor.name).tag(descriptor.id)
                        }
                    }

                    if let descriptor = viewModel.selectedDescriptor {
                        LabeledContent("Status", value: descriptor.availability.rawValue.capitalized)
                        LabeledContent("Execution", value: descriptor.calculationMode.rawValue.capitalized)
                    }
                }

                Section("Operating point") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pressure")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ifeText)

                        HStack(spacing: 12) {
                            TextField("Value", text: $viewModel.pressureText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .pressure)
                                .accessibilityLabel("Pressure value")

                            Picker("Pressure unit", selection: $viewModel.pressureUnit) {
                                ForEach(PressureUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }

                    if viewModel.pressureUnit.isGauge {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Atmospheric reference pressure")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ifeText)

                            HStack {
                                TextField("Value", text: $viewModel.atmosphericReferenceText)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .atmosphericReference)
                                    .accessibilityLabel("Atmospheric reference pressure value")
                                Text("Pa abs")
                                    .foregroundStyle(.secondary)
                            }

                            Text("Gauge pressure is converted using this explicit atmospheric reference.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Temperature")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ifeText)

                        HStack(spacing: 12) {
                            TextField("Value", text: $viewModel.temperatureText)
                                .keyboardType(.numbersAndPunctuation)
                                .focused($focusedField, equals: .temperature)
                                .accessibilityLabel("Temperature value")

                            Picker("Temperature unit", selection: $viewModel.temperatureUnit) {
                                ForEach(TemperatureUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                }

                Section {
                    ForEach($viewModel.composition) { $entry in
                        HStack {
                            if entry.component == .carbonDioxide {
                                Text(entry.component.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Picker("Component", selection: $entry.component) {
                                    ForEach(ComponentID.allCases.filter { $0 != .carbonDioxide }) { component in
                                        Text(component.symbol).tag(component)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            TextField("mol%", text: $entry.molPercent)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .composition)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("mol%")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete(perform: viewModel.removeImpurities)
                    .onMove(perform: viewModel.moveImpurities)

                    Button("Add impurity", systemImage: "plus") {
                        viewModel.addImpurity()
                    }
                    .disabled(viewModel.composition.count >= 21)
                } header: {
                    HStack {
                        Text("Composition")
                        Spacer()
                        EditButton()
                    }
                } footer: {
                    Text("Values are entered as mol%. The app never normalizes composition silently.")
                }

                if !viewModel.validationReport.issues.isEmpty {
                    Section("Input review") {
                        ForEach(viewModel.validationReport.issues) { issue in
                            Label(
                                issue.message,
                                systemImage: issue.severity == .error
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(issue.severity == .error ? .red : Color.ifePrimary)
                        }

                        if viewModel.canNormalize {
                            Button("Review and apply normalization") {
                                viewModel.normalizeComposition()
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.calculate() }
                    } label: {
                        if viewModel.isCalculating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Run calculation")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCalculating || !viewModel.validationReport.canCalculate)
                    .accessibilityIdentifier("run-calculation")
                }

                if let response = viewModel.response {
                    Section("Result") {
                        ScientificStatusBanner(
                            title: "Non-scientific demonstration",
                            message: response.warnings.joined(separator: " "),
                            isError: true
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        LabeledContent("Phase", value: response.phase.rawValue.capitalized)
                        LabeledContent("Scientific result", value: response.isScientificResult ? "Yes" : "No")
                        LabeledContent("Calculation ID", value: response.calculationID.uuidString)
                            .font(.caption)
                    }
                }

                if let error = viewModel.calculationError {
                    Section("Calculation error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ifeBackground)
            .navigationTitle("PhaseXpert")
            .onChange(of: viewModel.selectedModelID) { _, _ in viewModel.validate() }
            .onSubmit { viewModel.validate() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Validate", systemImage: "checkmark.shield") {
                        viewModel.validate()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        focusedField = nil
                        viewModel.validate()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    CalculatorView()
}
