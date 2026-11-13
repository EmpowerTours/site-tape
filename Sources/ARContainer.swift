import ARKit
import Combine
import RealityKit
import SwiftUI
import UIKit

/// The camera view. Raycasts from the screen centre ~10 times a second and
/// keeps one marker entity per pin of the current AR session.
struct ARContainer: UIViewRepresentable {
    @ObservedObject var store: SurveyStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let coordinator = context.coordinator
        coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            let store = store
            DispatchQueue.main.async { store.lidarActive = true }
        }
        if config.sceneReconstruction == .mesh {
            // Lets us raycast straight against the LiDAR mesh when ARKit has no plane yet.
            arView.environment.sceneUnderstanding.options.insert(.collision)
        }
        arView.session.delegate = coordinator
        arView.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coaching.frame = arView.bounds
        arView.addSubview(coaching)

        coordinator.updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] _ in
            coordinator?.tick()
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.syncMarkers(with: store.currentPins)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.updateSubscription?.cancel()
        _ = Torch.set(false)
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let store: SurveyStore
        weak var arView: ARView?
        var updateSubscription: Cancellable?
        private var markers: [UUID: AnchorEntity] = [:]
        private var lastRaycast: CFTimeInterval = 0
        private var lastDiag: CFTimeInterval = 0
        private var hits = 0, tries = 0
        private var tracking = "starting"
        private var lumens: CGFloat = -1

        init(store: SurveyStore) { self.store = store }

        func tick() {
            let now = CACurrentMediaTime()
            guard now - lastRaycast > 0.1, let arView else { return }
            lastRaycast = now
            if let l = arView.session.currentFrame?.lightEstimate?.ambientIntensity {
                lumens = l
                store.updateLight(l)
            }
            let centre = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let point = groundPoint(arView, centre)
            tries += 1
            if let point {
                hits += 1
                store.crosshair = point
            } else if store.crosshair != nil {
                store.crosshair = nil
            }
            if now - lastDiag > 0.5 {
                lastDiag = now
                let anchors = arView.session.currentFrame?.anchors ?? []
                let planes = anchors.filter { $0 is ARPlaneAnchor }.count
                let meshes = anchors.filter { $0 is ARMeshAnchor }.count
                let light = lumens < 0 ? "?" : String(Int(lumens))
                store.diagnostics = "track \(tracking) · light \(light) · planes \(planes) · mesh \(meshes) · hits \(hits)/\(tries)"
                hits = 0; tries = 0
            }
        }

        /// ARKit plane/depth raycast first, then the LiDAR mesh.
        private func groundPoint(_ arView: ARView, _ centre: CGPoint) -> SIMD3<Float>? {
            for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
                for alignment in [ARRaycastQuery.TargetAlignment.horizontal, .any] {
                    if let hit = arView.raycast(from: centre, allowing: target, alignment: alignment).first {
                        let t = hit.worldTransform.columns.3
                        return SIMD3<Float>(t.x, t.y, t.z)
                    }
                }
            }
            if let ray = arView.ray(through: centre),
               let hit = arView.scene.raycast(origin: ray.origin, direction: ray.direction, length: 30,
                                              query: .nearest, mask: .all, relativeTo: nil).first {
                return hit.position
            }
            return nil
        }

        func syncMarkers(with pins: [Pin]) {
            guard let arView else { return }
            let wanted = Set(pins.map(\.id))
            for (id, anchor) in markers where !wanted.contains(id) {
                arView.scene.removeAnchor(anchor)
                markers[id] = nil
            }
            for pin in pins where markers[pin.id] == nil {
                let anchor = AnchorEntity(world: pin.position)
                anchor.addChild(Self.makeMarker(name: pin.name))
                arView.scene.addAnchor(anchor)
                markers[pin.id] = anchor
            }
        }

        static func makeMarker(name: String) -> Entity {
            let orange = SimpleMaterial(color: .systemOrange, isMetallic: false)
            let root = Entity()

            let pole = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.015, 0.6, 0.015)), materials: [orange])
            pole.position.y = 0.3
            root.addChild(pole)

            let ball = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [orange])
            ball.position.y = 0.62
            root.addChild(ball)

            let textMesh = MeshResource.generateText(
                name,
                extrusionDepth: 0.004,
                font: .systemFont(ofSize: 0.12, weight: .semibold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            let text = ModelEntity(mesh: textMesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
            text.position = SIMD3<Float>(-textMesh.bounds.extents.x / 2, 0, 0)

            // Holder so the label turns to face the camera around its centre.
            let label = Entity()
            label.position.y = 0.72
            label.addChild(text)
            if #available(iOS 18.0, *) {
                label.components.set(BillboardComponent())
            }
            root.addChild(label)
            return root
        }

        // MARK: ARSessionDelegate (delivered on the main queue by default)

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal: tracking = "ok"
            case .notAvailable: tracking = "none"
            case .limited(let r): tracking = "limited(\(r))"
            }
            switch camera.trackingState {
            case .normal:
                store.trackingMessage = nil
            case .notAvailable:
                store.trackingMessage = "Tracking not available"
            case .limited(let reason):
                switch reason {
                case .excessiveMotion: store.trackingMessage = "Slow down"
                case .insufficientFeatures:
                    store.trackingMessage = store.isDark || store.torchOn
                        ? "Too dark: light on, aim at the ground 1–3 m ahead"
                        : "Point at textured ground"
                case .initializing: store.trackingMessage = "Starting… move the phone slowly"
                case .relocalizing: store.trackingMessage = "Relocalizing…"
                @unknown default: store.trackingMessage = "Tracking limited"
                }
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            store.trackingMessage = "Paused. Measurements may shift when it resumes"
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            store.trackingMessage = "AR stopped: \(error.localizedDescription)"
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            store.reapplyTorch()
        }
    }
}
