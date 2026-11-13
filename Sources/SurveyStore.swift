import CoreGraphics
import Foundation
import simd

/// One measured point on the ground, in metres, in the AR world frame of the
/// session that dropped it. Positions from different AR sessions share no
/// origin, so distances are only computed between pins with the same frameID.
struct Pin: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var x: Float
    var y: Float
    var z: Float
    var frameID: UUID
    var createdAt = Date()

    var position: SIMD3<Float> { SIMD3(x, y, z) }
}

/// Distance across the ground, ignoring height.
func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let dx = a.x - b.x
    let dz = a.z - b.z
    return (dx * dx + dz * dz).squareRoot()
}

/// Holds the survey. Only touched from the main thread (SwiftUI and ARKit's
/// default delegate queue), so it carries no actor annotation.
final class SurveyStore: ObservableObject {
    @Published var pins: [Pin] = [] { didSet { save() } }
    /// The pin the live tape measures from. Falls back to the last pin.
    @Published var originID: UUID?
    /// Where the centre crosshair hits the ground right now.
    @Published var crosshair: SIMD3<Float>?
    @Published var trackingMessage: String?
    @Published var lidarActive = false
    /// The camera sees very little light.
    @Published var isDark = false
    @Published var torchOn = false
    /// nil until the user taps the light button; after that we never override them.
    private var torchUserChoice: Bool?

    /// The world frame of this launch's AR session.
    let frameID = UUID()

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("survey.json")

    init() { load() }

    var currentPins: [Pin] { pins.filter { $0.frameID == frameID } }

    var origin: Pin? {
        if let id = originID, let p = currentPins.first(where: { $0.id == id }) { return p }
        return currentPins.last
    }

    /// Pins shown on the plan: the frame of the most recent pin.
    var planPins: [Pin] {
        guard let frame = pins.last?.frameID else { return [] }
        return pins.filter { $0.frameID == frame }
    }

    var hiddenOlderPinCount: Int { pins.count - planPins.count }

    func uniqueName(_ base: String) -> String {
        let taken = Set(pins.map(\.name))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    @discardableResult
    func dropPin(named base: String) -> Bool {
        guard let c = crosshair else { return false }
        let name = uniqueName(base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Pin" : base)
        pins.append(Pin(name: name, x: c.x, y: c.y, z: c.z, frameID: frameID))
        return true
    }

    func undo() {
        guard let last = currentPins.last else { return }
        delete(last.id)
    }

    func delete(_ id: UUID) {
        pins.removeAll { $0.id == id }
        if originID == id { originID = nil }
    }

    func newSession() {
        pins = []
        originID = nil
    }

    // MARK: light

    func setTorch(_ on: Bool, byUser: Bool) {
        if byUser { torchUserChoice = on }
        if Torch.set(on) { torchOn = on }
    }

    /// Called ~10 times a second with ARKit's ambient light estimate
    /// (about 1000 in a lit room, near 0 in darkness).
    func updateLight(_ lumens: CGFloat) {
        // Once the torch is on the estimate rises, so only judge darkness with it off.
        guard !torchOn else { return }
        let dark = lumens < 250
        if dark != isDark { isDark = dark }
        if dark && torchUserChoice == nil { setTorch(true, byUser: false) }
    }

    /// Re-light after an interruption; iOS turns the torch off when the camera pauses.
    func reapplyTorch() {
        if torchOn { _ = Torch.set(true) }
    }

    // MARK: persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(pins)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Site Tape: could not save pins: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Pin].self, from: data) else { return }
        pins = saved
    }
}
