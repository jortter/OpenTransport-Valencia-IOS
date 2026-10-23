import UIKit

/// Opens a point in Apple Maps (Android opens Google Maps with the same data).
@MainActor
func openInMaps(lat: Double, lon: Double, name: String) {
    var components = URLComponents(string: "https://maps.apple.com/")!
    components.queryItems = [
        URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
        URLQueryItem(name: "q", value: name),
    ]
    if let url = components.url { UIApplication.shared.open(url) }
}
