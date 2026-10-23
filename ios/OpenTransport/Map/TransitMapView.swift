import SwiftUI
import UIKit
import CoreLocation
import MapLibre
import OpenTransportCore

// Port (in progress) of NativeMap.kt. Same Carto styles and layer scheme as Android.
let styleDark = URL(string: "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json")!
let styleLight = URL(string: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json")!
let valenciaCenter = CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763)

let idaColor = UIColor(hex: 0x3B82F6)
let vueltaColor = UIColor(hex: 0xEF4444)
let emtRed = UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)

/// Everything the map draws, besides the buses (which animate on their own).
struct MapScene: Equatable {
    /// Cheap identity for `stops`, so the source is only rebuilt when it changes.
    var stopsKey: String
    var stops: [Stop]
    /// Focused line: its ida/vuelta shapes are drawn in blue/red.
    var mainLine: String?
    /// Lines through the selected stop, each in its own palette colour.
    var contextLines: [String]
    /// The map is partly covered by a sheet: keep content in the visible part.
    var sheetVisible: Bool
    /// Points of the other networks, and a cheap identity for them.
    var placesKey: String = ""
    var places: [Place] = []

    static func == (a: MapScene, b: MapScene) -> Bool {
        a.stopsKey == b.stopsKey && a.mainLine == b.mainLine && a.contextLines == b.contextLines
            && a.sheetVisible == b.sheetVisible && a.placesKey == b.placesKey
    }
}

struct TransitMapView: UIViewRepresentable {
    let scene: MapScene
    let routes: [String: BusRoute]
    /// Metro line brand colours ("M1" → 0xFEC601) for their route shapes.
    let metroColors: [String: Int]
    let live: LiveBuses
    let dark: Bool
    var cameraRequest: CameraRequest?
    /// The camera trails this bus every frame (Android's `follow`).
    var followedBus: Int?
    var follow3D = false
    /// Bumped by the "my location" button; each change recentres on the user.
    var recenterRequest: Int = 0
    var onSelectStop: (Int) -> Void
    var onSelectBus: (Int) -> Void
    var onSelectPlace: (String) -> Void

    private var styleURL: URL { dark ? styleDark : styleLight }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.setCenter(valenciaCenter, zoomLevel: 13, animated: false)
        map.minimumZoomLevel = 8
        map.automaticallyAdjustsContentInset = false // the sheet inset is managed in applyLayout
        map.showsUserLocation = true
        map.allowsRotating = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        for recognizer in map.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired == 2 {
                tap.require(toFail: other)
            }
        }
        map.addGestureRecognizer(tap)
        context.coordinator.loadedStyle = styleURL
        context.coordinator.lastRecenter = recenterRequest
        context.coordinator.startAnimating(map)
        return map
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        coordinator.stopAnimating()
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.loadedStyle != styleURL {
            coordinator.loadedStyle = styleURL
            coordinator.resetStyleState()
            map.styleURL = styleURL // layers are re-added in didFinishLoading
        }
        coordinator.applyScene(on: map)
        coordinator.applyLayout(on: map)
        if coordinator.lastRecenter != recenterRequest {
            coordinator.lastRecenter = recenterRequest
            if let coordinate = map.userLocation?.location?.coordinate {
                map.setCenter(coordinate, zoomLevel: max(map.zoomLevel, 16), direction: 0, animated: true)
            } else {
                map.showsUserLocation = true // asks for permission again if needed
            }
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TransitMapView
        var loadedStyle: URL?
        var lastRecenter = 0
        var lastCamera: Int?
        var lastSheetVisible = false

        private weak var style: MLNStyle?
        private var appliedScene: MapScene?
        private var displayLink: CADisplayLink?
        private var drewNoBuses = false
        private var lastFollowed: Int?

        static let stopsSource = "emt-stops"
        static let stopsLayer = "emt-stops"
        static let clustersLayer = "emt-stops-clusters"
        static let clusterCountLayer = "emt-stops-cluster-count"
        static let contextSource = "emt-context"
        static let mainSource = "emt-main"
        static let busesSource = "emt-buses"
        static let placesSource = "emt-places"
        static let placesLayer = "emt-places"
        static let placesClustersLayer = "emt-places-clusters"
        static let contextLayer = "emt-context-routes"

        init(_ parent: TransitMapView) {
            self.parent = parent
        }

        // MARK: Style

        func resetStyleState() {
            style = nil
            appliedScene = nil
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.style = style
            appliedScene = nil
            addLayers(to: style)
            applyScene(on: mapView)
        }

        private func addLayers(to style: MLNStyle) {
            // Route lines first so stops and buses draw on top of them.
            let context = MLNShapeSource(identifier: Self.contextSource, shape: nil, options: nil)
            style.addSource(context)
            let contextLayer = MLNLineStyleLayer(identifier: Self.contextLayer, source: context)
            contextLayer.lineColor = NSExpression(forConstantValue: idaColor) // per line in applyScene
            contextLayer.lineWidth = NSExpression(forConstantValue: 4.2)
            contextLayer.lineOpacity = NSExpression(forConstantValue: 0.9)
            contextLayer.lineCap = NSExpression(forConstantValue: "round")
            contextLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(contextLayer)

            let main = MLNShapeSource(identifier: Self.mainSource, shape: nil, options: nil)
            style.addSource(main)
            let mainLayer = MLNLineStyleLayer(identifier: "emt-main-routes", source: main)
            mainLayer.lineColor = directionColor()
            mainLayer.lineWidth = NSExpression(forConstantValue: 5)
            mainLayer.lineOpacity = NSExpression(forConstantValue: 0.96)
            mainLayer.lineCap = NSExpression(forConstantValue: "round")
            mainLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(mainLayer)

            let stops = MLNShapeSource(identifier: Self.stopsSource, features: [], options: [
                .clustered: true,
                .clusterRadius: 45,
                .maximumZoomLevelForClustering: 14,
            ])
            style.addSource(stops)

            let clusters = MLNCircleStyleLayer(identifier: Self.clustersLayer, source: stops)
            clusters.predicate = NSPredicate(format: "cluster == YES")
            clusters.circleColor = NSExpression(forConstantValue: emtRed)
            clusters.circleRadius = NSExpression(forConstantValue: 15)
            clusters.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            clusters.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(clusters)

            let count = MLNSymbolStyleLayer(identifier: Self.clusterCountLayer, source: stops)
            count.predicate = NSPredicate(format: "cluster == YES")
            count.text = NSExpression(format: "CAST(point_count, 'NSString')")
            count.textColor = NSExpression(forConstantValue: UIColor.white)
            count.textFontSize = NSExpression(forConstantValue: 12)
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(count)

            let points = MLNCircleStyleLayer(identifier: Self.stopsLayer, source: stops)
            points.predicate = NSPredicate(format: "cluster != YES")
            points.circleColor = NSExpression(forConstantValue: emtRed)
            points.circleRadius = NSExpression(forConstantValue: 6)
            points.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            points.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(points)

            addPlaceLayers(to: style)

            let buses = MLNShapeSource(identifier: Self.busesSource, shape: nil, options: nil)
            style.addSource(buses)
            let busDots = MLNCircleStyleLayer(identifier: "emt-buses", source: buses)
            busDots.circleColor = directionColor()
            busDots.circleRadius = NSExpression(forConstantValue: 12)
            busDots.circleStrokeColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.6))
            busDots.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(busDots)
            let busNumbers = MLNSymbolStyleLayer(identifier: "emt-bus-numbers", source: buses)
            busNumbers.text = NSExpression(forKeyPath: "line")
            busNumbers.textFontSize = NSExpression(forConstantValue: 11)
            busNumbers.textColor = NSExpression(forConstantValue: UIColor.white)
            busNumbers.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.6))
            busNumbers.textHaloWidth = NSExpression(forConstantValue: 1.2)
            busNumbers.textAllowsOverlap = NSExpression(forConstantValue: true)
            busNumbers.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(busNumbers)
        }

        /// Metro, Valenbisi, Metrobús and Rodalies points: clustered when zoomed
        /// out, each with its network logo on a brand-coloured disc.
        private func addPlaceLayers(to style: MLNStyle) {
            for network in Network.allCases {
                if let icon = Self.serviceIcon(network) { style.setImage(icon, forName: Self.iconName(network)) }
            }
            let places = MLNShapeSource(identifier: Self.placesSource, features: [], options: [
                .clustered: true,
                .clusterRadius: 45,
                .maximumZoomLevelForClustering: 13,
            ])
            style.addSource(places)

            let clusters = MLNCircleStyleLayer(identifier: Self.placesClustersLayer, source: places)
            clusters.predicate = NSPredicate(format: "cluster == YES")
            clusters.circleColor = NSExpression(forConstantValue: idaColor)
            clusters.circleOpacity = NSExpression(forConstantValue: 0.9)
            clusters.circleRadius = NSExpression(forConstantValue: 15)
            clusters.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            clusters.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(clusters)

            let count = MLNSymbolStyleLayer(identifier: "emt-places-cluster-count", source: places)
            count.predicate = NSPredicate(format: "cluster == YES")
            count.text = NSExpression(format: "CAST(point_count, 'NSString')")
            count.textColor = NSExpression(forConstantValue: UIColor.white)
            count.textFontSize = NSExpression(forConstantValue: 12)
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(count)

            let icons = MLNSymbolStyleLayer(identifier: Self.placesLayer, source: places)
            icons.predicate = NSPredicate(format: "cluster != YES")
            icons.iconImageName = NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "network"),
                                               in: Dictionary(uniqueKeysWithValues: Network.allCases.map {
                                                   (NSExpression(forConstantValue: $0.rawValue), NSExpression(forConstantValue: Self.iconName($0)))
                                               }),
                                               default: NSExpression(forConstantValue: Self.iconName(.metro)))
            icons.iconAllowsOverlap = NSExpression(forConstantValue: true)
            icons.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(icons)

            let labels = MLNSymbolStyleLayer(identifier: "emt-places-labels", source: places)
            labels.predicate = NSPredicate(format: "cluster != YES")
            labels.minimumZoomLevel = 14.5
            labels.text = NSExpression(forKeyPath: "name")
            labels.textFontSize = NSExpression(forConstantValue: 11)
            labels.textColor = NSExpression(forConstantValue: UIColor.white)
            labels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.7))
            labels.textHaloWidth = NSExpression(forConstantValue: 1.2)
            labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.6)))
            style.addLayer(labels)
        }

        static func iconName(_ network: Network) -> String { "\(network.rawValue.lowercased())-icon" }

        /// The network logo on its brand-coloured disc (Android's `serviceIcon`).
        static func serviceIcon(_ network: Network) -> UIImage? {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("assets").appendingPathComponent(network.asset),
                  let logo = UIImage(contentsOfFile: url.path) else { return nil }
            let background: UIColor
            switch network {
            case .emt: background = .white
            case .metro: background = UIColor(hex: 0xFF8A80)
            case .valenbisi, .metrobus: background = UIColor(hex: 0x90CAF9)
            case .rodalies: background = UIColor(hex: 0xE30613)
            }
            let size = CGSize(width: 30, height: 30)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let disc = CGRect(origin: .zero, size: size)
                background.setFill()
                UIBezierPath(ovalIn: disc).fill()
                UIColor.white.setStroke()
                let ring = UIBezierPath(ovalIn: disc.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
                let box = disc.insetBy(dx: size.width * 0.24, dy: size.height * 0.24)
                let scale = min(box.width / logo.size.width, box.height / logo.size.height)
                let fitted = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
                logo.draw(in: CGRect(x: disc.midX - fitted.width / 2, y: disc.midY - fitted.height / 2,
                                     width: fitted.width, height: fitted.height))
            }
        }

        private func directionColor() -> NSExpression {
            NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "dir"),
                         in: [NSExpression(forConstantValue: "vuelta"): NSExpression(forConstantValue: vueltaColor)],
                         default: NSExpression(forConstantValue: idaColor))
        }

        // MARK: Scene

        func applyScene(on map: MLNMapView) {
            guard let style else { return }
            let scene = parent.scene
            let previous = appliedScene
            appliedScene = scene

            if previous?.stopsKey != scene.stopsKey, let source = style.source(withIdentifier: Self.stopsSource) as? MLNShapeSource {
                source.shape = MLNShapeCollectionFeature(shapes: scene.stops.map { stop in
                    let feature = MLNPointFeature()
                    feature.coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
                    feature.attributes = ["id": stop.id]
                    return feature
                })
            }
            if previous?.mainLine != scene.mainLine || previous == nil,
               let source = style.source(withIdentifier: Self.mainSource) as? MLNShapeSource {
                var lines: [MLNPolylineFeature] = []
                if let line = scene.mainLine, let route = parent.routes[line] {
                    lines += polylines(route.ida.shapes, attributes: ["dir": "ida"])
                    lines += polylines(route.vuelta.shapes, attributes: ["dir": "vuelta"])
                }
                source.shape = MLNShapeCollectionFeature(shapes: lines)
            }
            if previous?.contextLines != scene.contextLines || previous == nil,
               let source = style.source(withIdentifier: Self.contextSource) as? MLNShapeSource {
                var lines: [MLNPolylineFeature] = []
                var colors: [NSExpression: NSExpression] = [:]
                for (index, line) in scene.contextLines.enumerated() {
                    guard let route = parent.routes[line] else { continue }
                    lines += polylines(route.ida.shapes + route.vuelta.shapes, attributes: ["linea": line])
                    // Metro lines keep their brand colour; EMT lines take distinct
                    // palette colours by position (not hash, which can collide).
                    let color = parent.metroColors[line].map { UIColor(hex: $0) }
                        ?? linePaletteUIColors[index % linePaletteUIColors.count]
                    colors[NSExpression(forConstantValue: line)] = NSExpression(forConstantValue: color)
                }
                if let layer = style.layer(withIdentifier: Self.contextLayer) as? MLNLineStyleLayer {
                    layer.lineColor = colors.isEmpty
                        ? NSExpression(forConstantValue: idaColor)
                        : NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "linea"), in: colors,
                                       default: NSExpression(forConstantValue: idaColor))
                }
                source.shape = MLNShapeCollectionFeature(shapes: lines)
            }
            if previous?.placesKey != scene.placesKey, let source = style.source(withIdentifier: Self.placesSource) as? MLNShapeSource {
                source.shape = MLNShapeCollectionFeature(shapes: scene.places.map { place in
                    let feature = MLNPointFeature()
                    feature.coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                    feature.attributes = ["id": place.id, "network": place.network.rawValue, "name": place.name]
                    return feature
                })
            }
        }

        private func polylines(_ shapes: [[LonLat]], attributes: [String: Any]) -> [MLNPolylineFeature] {
            shapes.compactMap { shape in
                guard shape.count >= 2 else { return nil }
                var coordinates = shape.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.attributes = attributes
                return feature
            }
        }

        // MARK: Camera

        /// Content inset for the sheet and pending camera moves. Both need the
        /// view's real size, so they wait until it has been laid out (a fit on a
        /// zero-sized view lands on a random zoom).
        func applyLayout(on map: MLNMapView) {
            guard map.bounds.height > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak map] in
                    if let self, let map { self.applyLayout(on: map) }
                }
                return
            }
            let sheetVisible = parent.scene.sheetVisible
            if lastSheetVisible != sheetVisible {
                lastSheetVisible = sheetVisible
                let bottom = sheetVisible ? map.bounds.height * 0.45 : 0
                map.setContentInset(UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0), animated: false, completionHandler: nil)
            }
            if let request = parent.cameraRequest, request.id != lastCamera {
                lastCamera = request.id
                apply(request, on: map)
            }
        }

        func apply(_ request: CameraRequest, on map: MLNMapView) {
            switch request.kind {
            case .center(let point, let zoom):
                map.setCenter(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                              zoomLevel: zoom, direction: map.direction, animated: true)
            case .fit(let bounds):
                let coordinateBounds = MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west),
                    ne: CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east))
                map.setVisibleCoordinateBounds(coordinateBounds, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 40, right: 40),
                                               animated: true, completionHandler: nil)
            }
        }

        // MARK: Bus animation (30 fps, like the Android BusStore loop)

        func startAnimating(_ map: MLNMapView) {
            let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
            self.map = map
        }

        func stopAnimating() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private weak var map: MLNMapView?

        @objc fileprivate func frame() {
            guard let style, let source = style.source(withIdentifier: Self.busesSource) as? MLNShapeSource else { return }
            guard let tracker = parent.live.tracker, !tracker.buses.isEmpty else {
                if !drewNoBuses {
                    source.shape = nil
                    drewNoBuses = true
                }
                return
            }
            drewNoBuses = false
            tracker.advance()
            source.shape = MLNShapeCollectionFeature(shapes: tracker.buses.map { bus in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: bus.render.lat, longitude: bus.render.lon)
                feature.attributes = ["line": bus.line, "dir": bus.direction ?? "", "num": bus.number]
                return feature
            })
            followCamera(tracker)
        }

        /// Keeps the followed bus centred, heading up; flat or 3D behind it.
        private func followCamera(_ tracker: BusTracker) {
            guard let map else { return }
            guard let number = parent.followedBus, let bus = tracker.buses.first(where: { $0.number == number }) else {
                if lastFollowed != nil {
                    lastFollowed = nil
                    let camera = map.camera
                    camera.pitch = 0
                    map.setCamera(camera, animated: true)
                }
                return
            }
            let coordinate = CLLocationCoordinate2D(latitude: bus.render.lat, longitude: bus.render.lon)
            if lastFollowed != number {
                lastFollowed = number
                map.setCenter(coordinate, zoomLevel: max(map.zoomLevel, 16.5), direction: bus.bearing, animated: false)
            }
            let camera = map.camera
            camera.centerCoordinate = coordinate
            camera.heading = bus.bearing
            camera.pitch = parent.follow3D ? 58 : 0
            map.setCamera(camera, animated: false)
        }

        // MARK: Taps

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: map)

            // Buses first: they sit on top and are the smallest targets to miss.
            if let tracker = parent.live.tracker {
                let nearest = tracker.buses.map { bus -> (Int, CGFloat) in
                    let p = map.convert(CLLocationCoordinate2D(latitude: bus.render.lat, longitude: bus.render.lon), toPointTo: map)
                    return (bus.number, hypot(p.x - point.x, p.y - point.y))
                }.min { $0.1 < $1.1 }
                if let nearest, nearest.1 <= 36 {
                    parent.onSelectBus(nearest.0)
                    return
                }
            }

            let rect = CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30)
            let features = map.visibleFeatures(in: rect, styleLayerIdentifiers: [
                Self.stopsLayer, Self.clustersLayer, Self.placesLayer, Self.placesClustersLayer,
            ])
            if let cluster = features.first(where: { $0 is MLNPointFeatureCluster }) {
                map.setCenter(cluster.coordinate, zoomLevel: map.zoomLevel + 2, animated: true)
                return
            }
            // The closest point wins, so a station isn't shadowed by a nearby stop.
            let nearest = features.min { a, b in
                let pa = map.convert(a.coordinate, toPointTo: map)
                let pb = map.convert(b.coordinate, toPointTo: map)
                return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
            }
            if let place = nearest?.attribute(forKey: "id") as? String {
                parent.onSelectPlace(place)
            } else if let id = (nearest?.attribute(forKey: "id") as? NSNumber)?.intValue {
                parent.onSelectStop(id)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class WeakTarget: NSObject {
    weak var coordinator: TransitMapView.Coordinator?

    init(_ coordinator: TransitMapView.Coordinator) {
        self.coordinator = coordinator
    }

    @objc func tick() {
        coordinator?.frame()
    }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
