import SwiftUI
import UIKit

struct PlanView: View {
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var confirmNew = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.planPins.isEmpty {
                        Text("No pins yet. Drop some on the camera screen.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        PlanCanvas(pins: store.planPins, dark: true)
                            .frame(height: 360)
                            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))

                        if store.hiddenOlderPinCount > 0 {
                            Text("\(store.hiddenOlderPinCount) pin(s) from an earlier session are not shown. Distances can't mix sessions.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }

                        pinList
                        distanceTable
                    }
                }
                .padding()
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export JSON + picture", systemImage: "square.and.arrow.up") { export() }
                            .disabled(store.planPins.isEmpty)
                        Button("New session", systemImage: "trash", role: .destructive) { confirmNew = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Delete all pins and start over?", isPresented: $confirmNew, titleVisibility: .visible) {
                Button("Delete all pins", role: .destructive) { store.newSession() }
            }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "") }
            .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        }
    }

    private var pinList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pins").font(.headline)
            Text("Tap a pin to measure the live tape from it.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.planPins) { pin in
                HStack {
                    Button {
                        store.originID = pin.id
                    } label: {
                        HStack {
                            Image(systemName: store.origin?.id == pin.id ? "scope" : "mappin")
                                .foregroundStyle(.orange)
                            Text(pin.name)
                            Spacer()
                            Text(String(format: "height %+.2f m", pin.y - (store.planPins.first?.y ?? pin.y)))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .disabled(pin.frameID != store.frameID)
                    Button(role: .destructive) { store.delete(pin.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private var distanceTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Distances across the ground").font(.headline)
            ForEach(pairs(store.planPins), id: \.label) { row in
                HStack {
                    Text(row.label).font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f m", row.metres))
                        .font(.subheadline.monospacedDigit())
                }
                Divider()
            }
        }
    }

    private func export() {
        do {
            shareItems = try Exporter.files(pins: store.planPins, lidar: store.lidarActive)
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct PairRow { let label: String; let a: String; let b: String; let metres: Float; let dh: Float }

func pairs(_ pins: [Pin]) -> [PairRow] {
    var rows: [PairRow] = []
    for i in 0..<pins.count {
        for j in (i + 1)..<pins.count {
            let a = pins[i], b = pins[j]
            rows.append(PairRow(label: "\(a.name) → \(b.name)", a: a.name, b: b.name,
                                metres: horizontalDistance(a.position, b.position), dh: b.y - a.y))
        }
    }
    return rows
}

/// Top-down drawing: x to the right, z down the screen, 1 m grid, scale bar.
struct PlanCanvas: View {
    let pins: [Pin]
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !pins.isEmpty else { return }
            let ink: Color = dark ? .white : .black
            let xs = pins.map(\.x), zs = pins.map(\.z)
            let minX = xs.min()! - 2, maxX = xs.max()! + 2
            let minZ = zs.min()! - 2, maxZ = zs.max()! + 2
            let span = Double(max(maxX - minX, maxZ - minZ, 4))
            let margin = 24.0
            let s = (min(Double(size.width), Double(size.height)) - 2 * margin) / span
            let ox = (Double(size.width) - Double(maxX - minX) * s) / 2
            let oz = (Double(size.height) - Double(maxZ - minZ) * s) / 2
            func pt(_ x: Float, _ z: Float) -> CGPoint {
                CGPoint(x: ox + Double(x - minX) * s, y: oz + Double(z - minZ) * s)
            }

            var grid = Path()
            var gx = minX.rounded(.up)
            while gx <= maxX { grid.move(to: pt(gx, minZ)); grid.addLine(to: pt(gx, maxZ)); gx += 1 }
            var gz = minZ.rounded(.up)
            while gz <= maxZ { grid.move(to: pt(minX, gz)); grid.addLine(to: pt(maxX, gz)); gz += 1 }
            ctx.stroke(grid, with: .color(ink.opacity(0.12)), lineWidth: 0.5)

            if pins.count > 1 {
                var path = Path()
                path.move(to: pt(pins[0].x, pins[0].z))
                for p in pins.dropFirst() { path.addLine(to: pt(p.x, p.z)) }
                ctx.stroke(path, with: .color(.orange.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                for (a, b) in zip(pins, pins.dropFirst()) {
                    let pa = pt(a.x, a.z), pb = pt(b.x, b.z)
                    let mid = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2 + 10)
                    ctx.draw(Text(String(format: "%.2f m", horizontalDistance(a.position, b.position)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(ink.opacity(0.7)), at: mid)
                }
            }

            for p in pins {
                let c = pt(p.x, p.z)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.orange))
                ctx.draw(Text(p.name).font(.caption.bold()).foregroundStyle(ink), at: CGPoint(x: c.x, y: c.y - 13))
            }

            let barMetres = span > 30 ? 10.0 : 5.0
            let barStart = CGPoint(x: margin, y: Double(size.height) - margin / 2)
            var bar = Path()
            bar.move(to: barStart)
            bar.addLine(to: CGPoint(x: barStart.x + barMetres * s, y: barStart.y))
            ctx.stroke(bar, with: .color(ink), lineWidth: 3)
            ctx.draw(Text("\(Int(barMetres)) m").font(.caption2).foregroundStyle(ink),
                     at: CGPoint(x: barStart.x + barMetres * s + 18, y: barStart.y))
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
