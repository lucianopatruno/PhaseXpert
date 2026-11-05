import PhaseXpertCore
import SwiftUI
import UIKit

/// Renders a `PhaseMapRegionRaster` as a bitmap using the same palette as the
/// discrete Phase Map markers, with a darker line along region boundaries.
enum PhaseMapRegionImage {
    static func usesRegionMap(for result: PhaseMapResult) -> Bool {
        result.request.resolution.rendersAsRegionMap
    }

    static func image(for result: PhaseMapResult) -> UIImage? {
        guard let raster = PhaseMapRegionRaster.make(
            evaluations: result.evaluations,
            gridSize: result.request.resolution.rawValue
        ) else { return nil }
        return image(for: raster)
    }

    static func image(for raster: PhaseMapRegionRaster) -> UIImage? {
        var fill: [PhaseMapClassification: (UInt8, UInt8, UInt8)] = [:]
        var edge: [PhaseMapClassification: (UInt8, UInt8, UInt8)] = [:]
        for classification in PhaseMapClassification.allCases {
            let style = PhaseMapMarkerStyle.style(for: classification)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(style.color).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            fill[classification] = (byte(r), byte(g), byte(b))
            edge[classification] = (byte(r * 0.55), byte(g * 0.55), byte(b * 0.55))
        }

        var pixels = [UInt8](repeating: 255, count: raster.width * raster.height * 4)
        for y in 0..<raster.height {
            // Raster row 0 is the lowest pressure, which belongs at the bottom.
            let destinationRow = raster.height - 1 - y
            for x in 0..<raster.width {
                let source = y * raster.width + x
                let label = raster.labels[source]
                let color = (raster.boundary[source] ? edge[label] : fill[label]) ?? (128, 128, 128)
                let offset = (destinationRow * raster.width + x) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: raster.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
