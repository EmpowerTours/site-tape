import SwiftUI

let presetNames = ["Pila", "Truck", "Canopy edge", "Power pole", "Road entry", "Back gap", "Corner"]

struct ContentView: View {
    @ObservedObject var store: SurveyStore
    @State private var showNames = false
    @State private var showCustom = false
    @State private var customName = ""
    @State private var showPlan = false
    @State private var showTips = false

    var body: some View {
        ZStack {
            ARContainer(store: store)
                .ignoresSafeArea()

            Crosshair(active: store.crosshair != nil)
                .allowsHitTesting(false)

            VStack(spacing: 10) {
                readout
                if let message = store.trackingMessage {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.orange.opacity(0.9), in: Capsule())
                        .foregroundStyle(.black)
                }
                Spacer()
                controls
            }
            .padding()
        }
        .confirmationDialog("Name this pin", isPresented: $showNames, titleVisibility: .visible) {
            ForEach(presetNames, id: \.self) { name in
                Button(name) { drop(name) }
            }
            Button("Custom name…") { customName = ""; showCustom = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Custom name", isPresented: $showCustom) {
            TextField("e.g. Gate", text: $customName)
            Button("Drop pin") { drop(customName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPlan) { PlanView(store: store) }
        .sheet(isPresented: $showTips) { TipsView() }
    }

    private func drop(_ name: String) {
        if store.dropPin(named: name) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private var readout: some View {
        VStack(spacing: 4) {
            if let c = store.crosshair {
                if let o = store.origin {
                    let d = horizontalDistance(o.position, c)
                    let dh = c.y - o.y
                    Text(String(format: "%.2f m", d))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("from \(o.name) · height \(String(format: "%+.2f", dh)) m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Drop your first pin")
                        .font(.title3.weight(.semibold))
                }
            } else {
                Text("Point at the ground")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { store.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.currentPins.isEmpty)

            Button { showNames = true } label: {
                Label("Drop pin", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(store.crosshair == nil)

            if Torch.available {
                Button { store.setTorch(!store.torchOn, byUser: true) } label: {
                    Label("Light", systemImage: store.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                }
                .tint(store.torchOn ? Color.yellow : nil)
            }

            Button { showPlan = true } label: {
                Label("Plan", systemImage: "square.grid.3x3")
            }

            Button { showTips = true } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Tips")
        }
        .labelStyle(AdaptiveLabelStyle())
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Icon-only for the small buttons, icon + title for the main one.
struct AdaptiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
            configuration.title.font(.caption2)
        }
    }
}

struct Crosshair: View {
    let active: Bool
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 2).frame(width: 36, height: 36)
            Rectangle().frame(width: 2, height: 54)
            Rectangle().frame(width: 54, height: 2)
        }
        .foregroundStyle(active ? Color.orange : Color.white.opacity(0.6))
        .shadow(radius: 2)
    }
}

struct TipsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("How to measure") {
                    Text("Move the phone slowly until the crosshair turns orange.")
                    Text("Aim at the ground at the base of each thing (the foot of the pila, under the truck's bumper, the ground below the canopy edge) and tap Drop pin.")
                    Text("The big number is the distance across the ground from the last pin, or from any pin you choose on the Plan screen.")
                }
                Section("Getting good numbers") {
                    Text("Walk slowly and keep the camera on the ground as you go. Fast turns make the measurements drift.")
                    Text("Check the drift: at the end, walk back to your first pin and aim at it. A good walk reads under about 0.2 m.")
                    Text("If the app is closed or interrupted, start a New session. Pins from different sessions can't be measured against each other.")
                }
                Section("At night") {
                    Text("The light turns on by itself when it gets dark. Tap Light to switch it on or off.")
                    Text("The light reaches about 3 to 5 m. Walk up to each thing and drop the pin at your feet instead of aiming from far away.")
                    Text("Keep the camera on the lit ground while you walk between points. If the screen says \"Too dark\", stop, point at the ground close to you, and wait for the crosshair to turn orange.")
                    Text("The light uses battery and the phone may get warm. Start with a full charge.")
                }
                Section("Send the results") {
                    Text("Open Plan, then Export. Send the JSON and the plan picture to Claude.")
                }
            }
            .navigationTitle("Tips")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
