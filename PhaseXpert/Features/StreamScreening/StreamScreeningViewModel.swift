import Foundation
import Observation
import PhaseXpertCore

@MainActor
@Observable
final class StreamScreeningViewModel {
    var pressureText = "30" { didSet { invalidate() } }
    var temperatureText = "40" { didSet { invalidate() } }
    var ppmTexts: [StreamScreeningSpecies: String] = [:] { didSet { invalidate() } }
    var includeBinaryWaterReference = false { didSet { invalidate() } }
    private(set) var result: StreamScreeningResult?
    private(set) var errorMessage: String?
    private(set) var isRunning = false
    private(set) var sourceCalculationID: UUID?
    private let service: StreamScreeningService
    private var task: Task<Void, Never>?
    private var runID = UUID()

    init(record: CalculationRecord? = nil, service: StreamScreeningService = .init()) {
        self.service = service
        if let record {
            pressureText = String(record.input.pressurePa / 100_000)
            temperatureText = String(record.input.temperatureK - 273.15)
            for value in record.request.composition where value.component != .carbonDioxide {
                if let species = StreamScreeningSpecies.allCases.first(where: { $0.componentID == value.component }) {
                    ppmTexts[species] = String(value.moleFraction * 1_000_000)
                }
            }
            sourceCalculationID = record.response.calculationID
        }
    }

    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    var input: StreamScreeningInput? { try? parsedInput() }
    var inputError: String? {
        do { _ = try parsedInput(); return nil }
        catch { return error.localizedDescription }
    }

    func parsedInput() throws -> StreamScreeningInput {
        guard let pressure = Self.parse(pressureText), let temperature = Self.parse(temperatureText) else {
            throw StreamScreeningInputError.invalidOperatingPoint
        }
        var ppm: [StreamScreeningSpecies: Double] = [:]
        for species in StreamScreeningSpecies.allCases {
            let text = (ppmTexts[species] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = Self.parse(text) else {
                throw StreamScreeningInputError.invalidConcentration(species)
            }
            ppm[species] = value
        }
        let input = StreamScreeningInput(pressurePa: pressure * 100_000,
            temperatureK: temperature + 273.15, impurityPpm: ppm,
            includeBinaryWaterReference: includeBinaryWaterReference)
        try input.validate()
        return input
    }

    func run() {
        cancel()
        result = nil
        errorMessage = nil
        let snapshot: StreamScreeningInput
        do { snapshot = try parsedInput() }
        catch { errorMessage = error.localizedDescription; return }
        let id = UUID()
        runID = id
        isRunning = true
        let service = service
        task = Task { [weak self] in
            do {
                let output = try await service.screen(snapshot, clientVersion: Bundle.main.releaseVersion)
                guard !Task.isCancelled, let self, self.runID == id, self.input == snapshot else { return }
                self.result = output
                self.isRunning = false
                self.task = nil
            } catch is CancellationError {
                guard let self, self.runID == id else { return }
                self.isRunning = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.runID == id else { return }
                self.errorMessage = error.localizedDescription
                self.isRunning = false
                self.task = nil
            }
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func invalidate() {
        cancel()
        result = nil
        errorMessage = nil
        sourceCalculationID = nil
    }

    func clear() {
        ppmTexts = [:]
        includeBinaryWaterReference = false
    }

    func loadWaterExample() {
        pressureText = "30"
        temperatureText = "40"
        ppmTexts = [.water: "20000"]
        includeBinaryWaterReference = false
    }

    func loadReactiveExample() {
        pressureText = "30"
        temperatureText = "40"
        ppmTexts = [.water: "20000", .oxygen: "15", .hydrogenSulfide: "3", .nitrogenDioxide: "15"]
        includeBinaryWaterReference = false
    }
}
