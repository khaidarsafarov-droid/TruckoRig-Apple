import GoogleMaps
import SwiftUI
import UIKit

/// Starts the Maps SDK once. An empty or rejected key never constructs a `GMSMapView`.
enum GoogleMapsSession {
    private static var ready = false

    static func prepare(apiKey: String) -> Bool {
        if ready { return true }
        guard MapsAPIKey.isConfigured(apiKey) else { return false }
        guard GMSServices.provideAPIKey(apiKey) else { return false }
        ready = true
        return true
    }
}

enum MapsRuntimeKey {
    /// `GMSApiKey` is filled from the `GOOGLE_MAPS_API_KEY` build setting.
    static var current: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
        return MapsAPIKey.sanitized(raw)
    }
}

/// Android `GoogleMapsHeatmapCard` map: state polygons, fixed continental camera, no rotation.
struct GoogleHeatmapMap: UIViewRepresentable {
    var polygons: [PaintedStatePolygon]
    var zoom: Float
    var onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> HeatmapMapContainer {
        let container = HeatmapMapContainer(zoom: zoom)
        context.coordinator.mapView = container.mapView
        container.mapView.delegate = context.coordinator
        return container
    }

    func updateUIView(_ container: HeatmapMapContainer, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.apply(polygons, on: container.mapView)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onSelect: (String) -> Void
        weak var mapView: GMSMapView?
        private var signature = ""

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func apply(_ polygons: [PaintedStatePolygon], on mapView: GMSMapView) {
            let next = polygons.map { "\($0.stateCode):\($0.fillHex):\($0.strokeWidth):\($0.zIndex)" }
                .joined(separator: "|")
            guard next != signature else { return }
            signature = next
            mapView.clear()
            for polygon in polygons {
                let overlay = GMSPolygon()
                overlay.path = path(polygon.outer)
                if !polygon.holes.isEmpty {
                    overlay.holes = polygon.holes.map(path)
                }
                overlay.fillColor = Self.color(polygon.fillHex)
                overlay.strokeColor = Self.color(polygon.strokeHex)
                overlay.strokeWidth = polygon.strokeWidth
                overlay.zIndex = Int32(polygon.zIndex)
                overlay.isTappable = true
                overlay.userData = polygon.stateCode
                overlay.map = mapView
            }
        }

        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            guard let code = overlay.userData as? String else { return }
            onSelect(code)
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            guard gesture else { return }
            scrollView(around: mapView)?.isScrollEnabled = false
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            scrollView(around: mapView)?.isScrollEnabled = true
        }

        private func path(_ coordinates: [MapCoordinate]) -> GMSPath {
            let path = GMSMutablePath()
            for coordinate in coordinates {
                path.addLatitude(coordinate.latitude, longitude: coordinate.longitude)
            }
            return path
        }

        private func scrollView(around view: UIView) -> UIScrollView? {
            var current = view.superview
            while let view = current {
                if let scroll = view as? UIScrollView { return scroll }
                current = view.superview
            }
            return nil
        }

        private static func color(_ hex: String) -> UIColor {
            var value: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&value)
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

/// Map plus the zoom buttons Android gets from `isZoomControlsEnabled`.
final class HeatmapMapContainer: UIView {
    let mapView: GMSMapView

    init(zoom: Float) {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: MapCamera.latitude,
            longitude: MapCamera.longitude,
            zoom: zoom
        )
        let mapView = GMSMapView(options: options)
        self.mapView = mapView
        super.init(frame: .zero)
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.compassButton = true
        mapView.settings.myLocationButton = false
        mapView.isMyLocationEnabled = false
        if let style = try? GMSMapStyle(jsonString: Self.mapStyle) {
            mapView.mapStyle = style
        }
        mapView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mapView)

        let zoomIn = zoomButton(title: "+", label: String(localized: "map.zoom.in"), delta: 1)
        let zoomOut = zoomButton(title: "−", label: String(localized: "map.zoom.out"), delta: -1)
        let stack = UIStackView(arrangedSubviews: [zoomIn, zoomOut])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { nil }

    private func zoomButton(title: String, label: String, delta: Float) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
        button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        button.layer.cornerRadius = 8
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let map = self?.mapView else { return }
            map.animate(toZoom: map.camera.zoom + delta)
        }, for: .touchUpInside)
        return button
    }

    /// Same style Android applies: no POI labels, no transit, flat water and land.
    private static let mapStyle = """
    [
      {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
      {"featureType":"transit","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#d3d3d3"}]},
      {"featureType":"landscape","elementType":"geometry.fill","stylers":[{"color":"#f5f5f5"}]}
    ]
    """
}
