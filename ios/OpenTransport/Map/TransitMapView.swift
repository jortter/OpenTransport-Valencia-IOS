import SwiftUI
import UIKit
import CoreLocation
import MapLibre
import OpenTransportCore

// Port (in progress) of NativeMap.kt. Same Carto styles as Android.
let styleDark = URL(string: "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json")!
let styleLight = URL(string: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json")!
let valenciaCenter = CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763)

struct TransitMapView: UIViewRepresentable {
    let stops: [Stop]
    let dark: Bool
    var onSelectStop: (Int) -> Void

    private var styleURL: URL { dark ? styleDark : styleLight }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.setCenter(valenciaCenter, zoomLevel: 13, animated: false)
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
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedStyle != styleURL {
            context.coordinator.loadedStyle = styleURL
            map.styleURL = styleURL // layers are re-added in didFinishLoading
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TransitMapView
        var loadedStyle: URL?

        static let stopsSource = "emt-stops"
        static let stopsLayer = "emt-stops"
        static let clustersLayer = "emt-stops-clusters"
        static let clusterCountLayer = "emt-stops-cluster-count"

        init(_ parent: TransitMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            addStops(to: style)
        }

        private func addStops(to style: MLNStyle) {
            let features: [MLNPointFeature] = parent.stops.filter { !$0.metro }.map { stop in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
                feature.attributes = ["id": stop.id, "name": stop.cleanName]
                return feature
            }
            let source = MLNShapeSource(identifier: Self.stopsSource, features: features, options: [
                .clustered: true,
                .clusterRadius: 45,
                .maximumZoomLevelForClustering: 14,
            ])
            style.addSource(source)

            let emtRed = UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)

            let clusters = MLNCircleStyleLayer(identifier: Self.clustersLayer, source: source)
            clusters.predicate = NSPredicate(format: "cluster == YES")
            clusters.circleColor = NSExpression(forConstantValue: emtRed)
            clusters.circleRadius = NSExpression(forConstantValue: 15)
            clusters.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            clusters.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(clusters)

            let count = MLNSymbolStyleLayer(identifier: Self.clusterCountLayer, source: source)
            count.predicate = NSPredicate(format: "cluster == YES")
            count.text = NSExpression(format: "CAST(point_count, 'NSString')")
            count.textColor = NSExpression(forConstantValue: UIColor.white)
            count.textFontSize = NSExpression(forConstantValue: 12)
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(count)

            let points = MLNCircleStyleLayer(identifier: Self.stopsLayer, source: source)
            points.predicate = NSPredicate(format: "cluster != YES")
            points.circleColor = NSExpression(forConstantValue: emtRed)
            points.circleRadius = NSExpression(forConstantValue: 6)
            points.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            points.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(points)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: map)
            let rect = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
            let features = map.visibleFeatures(in: rect, styleLayerIdentifiers: [Self.stopsLayer, Self.clustersLayer])
            if let cluster = features.first(where: { $0 is MLNPointFeatureCluster }) {
                map.setCenter(cluster.coordinate, zoomLevel: map.zoomLevel + 2, animated: true)
                return
            }
            if let feature = features.first, let id = (feature.attribute(forKey: "id") as? NSNumber)?.intValue {
                parent.onSelectStop(id)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
