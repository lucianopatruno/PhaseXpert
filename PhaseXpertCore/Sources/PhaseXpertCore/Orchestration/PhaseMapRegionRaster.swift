import Foundation

/// Converts a rectangular Phase Map grid into a smooth, map-like raster of
/// phase regions.
///
/// No thermodynamic values are interpolated or invented. Each output pixel takes
/// the classification that carries the largest bilinear weight among the four
/// surrounding evaluated grid points, so region boundaries are drawn as smooth
/// curves between points that were classified differently, while every grid
/// point keeps exactly the classification the provider returned.
public struct PhaseMapRegionRaster: Equatable, Sendable {
    /// Region label for one pixel.
    public typealias Label = PhaseMapClassification

    public let width: Int
    public let height: Int
    /// Row-major labels. Row 0 is the lowest pressure; column 0 the lowest temperature. The raster spans half a grid step beyond the outermost nodes.
    public let labels: [Label]
    /// `true` where a pixel borders a pixel with a different label.
    public let boundary: [Bool]

    /// Label used for a completed evaluation. Mirrors the marker logic in the UI:
    /// unknown stays unknown, failed or unsupported points become `.failed`.
    public static func label(for evaluation: PhaseMapEvaluation) -> Label {
        if evaluation.classification.classification == .unknown {
            return .unknown
        }
        if evaluation.failureReason != nil || !evaluation.classification.isSupported {
            return .failed
        }
        return evaluation.classification.classification
    }

    /// Returns `nil` when the evaluations do not form a regular grid of at least 2×2.
    ///
    /// - Parameters:
    ///   - evaluations: Phase Map evaluations. An operating point that is not itself
    ///     a grid node (even grids) is ignored for the raster.
    ///   - gridSize: Number of grid nodes per axis used to produce the evaluations.
    ///   - pixelsPerCell: Output pixels between neighbouring grid nodes.
    public static func make(
        evaluations: [PhaseMapEvaluation],
        gridSize: Int,
        pixelsPerCell: Int = 5
    ) -> PhaseMapRegionRaster? {
        guard gridSize >= 2, pixelsPerCell >= 1 else { return nil }
        let pressures = evaluations.map(\.point.pressurePa).filter(\.isFinite)
        let temperatures = evaluations.map(\.point.temperatureK).filter(\.isFinite)
        guard
            let pMin = pressures.min(), let pMax = pressures.max(),
            let tMin = temperatures.min(), let tMax = temperatures.max(),
            pMax > pMin, tMax > tMin
        else { return nil }

        // Grid nodes are uniformly spaced inclusive of both extremes.
        let pStep = (pMax - pMin) / Double(gridSize - 1)
        let tStep = (tMax - tMin) / Double(gridSize - 1)
        var nodes = [Label?](repeating: nil, count: gridSize * gridSize)
        for evaluation in evaluations {
            let row = ((evaluation.point.pressurePa - pMin) / pStep)
            let column = ((evaluation.point.temperatureK - tMin) / tStep)
            guard row.isFinite, column.isFinite else { continue }
            let rowIndex = Int(row.rounded())
            let columnIndex = Int(column.rounded())
            // Off-grid points (an even-grid operating point) are not nodes.
            guard
                abs(row - Double(rowIndex)) < 1e-6,
                abs(column - Double(columnIndex)) < 1e-6,
                (0..<gridSize).contains(rowIndex),
                (0..<gridSize).contains(columnIndex)
            else { continue }
            nodes[rowIndex * gridSize + columnIndex] = label(for: evaluation)
        }
        guard nodes.allSatisfy({ $0 != nil }) else { return nil }
        let grid = nodes.compactMap { $0 }

        // The raster covers half a cell beyond the outermost nodes so it matches a
        // chart domain padded by half a grid step; the border takes the edge node.
        let width = gridSize * pixelsPerCell
        let height = width
        var labels = [Label](repeating: .unknown, count: width * height)
        for y in 0..<height {
            let fy = min(max((Double(y) + 0.5) / Double(pixelsPerCell) - 0.5, 0), Double(gridSize - 1))
            let r0 = min(Int(fy), gridSize - 2)
            let wy = fy - Double(r0)
            for x in 0..<width {
                let fx = min(max((Double(x) + 0.5) / Double(pixelsPerCell) - 0.5, 0), Double(gridSize - 1))
                let c0 = min(Int(fx), gridSize - 2)
                let wx = fx - Double(c0)
                let corners: [(Label, Double)] = [
                    (grid[r0 * gridSize + c0], (1 - wx) * (1 - wy)),
                    (grid[r0 * gridSize + c0 + 1], wx * (1 - wy)),
                    (grid[(r0 + 1) * gridSize + c0], (1 - wx) * wy),
                    (grid[(r0 + 1) * gridSize + c0 + 1], wx * wy)
                ]
                var weights: [Label: Double] = [:]
                for (label, weight) in corners { weights[label, default: 0] += weight }
                // Ties resolve by raw value so output is deterministic.
                labels[y * width + x] = weights.max {
                    $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
                }?.key ?? .unknown
            }
        }

        var boundary = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let here = labels[y * width + x]
                if x + 1 < width, labels[y * width + x + 1] != here {
                    boundary[y * width + x] = true
                    boundary[y * width + x + 1] = true
                }
                if y + 1 < height, labels[(y + 1) * width + x] != here {
                    boundary[y * width + x] = true
                    boundary[(y + 1) * width + x] = true
                }
            }
        }
        return PhaseMapRegionRaster(width: width, height: height, labels: labels, boundary: boundary)
    }
}
