import SwiftUI
import UIKit

enum Exporter {
    struct ExportPin: Codable { let name: String; let x: Float; let y: Float; let z: Float; let createdAt: Date }
    struct ExportPair: Codable { let from: String; let to: String; let horizontalMetres: Float; let heightChangeMetres: Float }
    struct Payload: Codable {
        let app: String
        let version: String
        let exportedAt: Date
        let device: String
        let lidarMeshActive: Bool
        let units: String
        let frameNote: String
        let pins: [ExportPin]
        let distances: [ExportPair]
    }

    enum ExportError: LocalizedError {
        case imageFailed
        var errorDescription: String? { "Could not draw the plan picture." }
    }

    /// Writes a JSON file and a PNG of the plan to the temp folder and returns both URLs.
    @MainActor
    static func files(pins: [Pin], lidar: Bool) throws -> [URL] {
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HHmm"
            return f.string(from: Date())
        }()
        let dir = FileManager.default.temporaryDirectory

        let payload = Payload(
            app: "Site Tape",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            exportedAt: Date(),
            device: UIDevice.current.model + " " + UIDevice.current.systemVersion,
            lidarMeshActive: lidar,
            units: "metres",
            frameNote: "ARKit world frame: x right, y up, z toward where the phone first pointed from. Origin is where the session started.",
            pins: pins.map { ExportPin(name: $0.name, x: $0.x, y: $0.y, z: $0.z, createdAt: $0.createdAt) },
            distances: pairs(pins).map { ExportPair(from: $0.a, to: $0.b, horizontalMetres: $0.metres, heightChangeMetres: $0.dh) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonURL = dir.appendingPathComponent("site-tape-\(stamp).json")
        try encoder.encode(payload).write(to: jsonURL, options: .atomic)

        let renderer = ImageRenderer(content:
            PlanCanvas(pins: pins, dark: false)
                .frame(width: 1000, height: 1000)
                .background(Color.white)
        )
        renderer.scale = 2
        guard let png = renderer.uiImage?.pngData() else { throw ExportError.imageFailed }
        let pngURL = dir.appendingPathComponent("site-tape-\(stamp).png")
        try png.write(to: pngURL, options: .atomic)

        return [jsonURL, pngURL]
    }
}
