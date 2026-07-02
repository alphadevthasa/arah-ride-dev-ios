import SwiftUI
import MapLibre
import QuartzCore

struct RideMap: UIViewRepresentable {
    let role: String
    let snapshot: RideSnapshot?
    let pickup: RidePoint
    let dropoff: RidePoint
    let onPick: (RidePoint) -> Void
    let focusDriverRequest: Int
    let placeFocus: PlaceFocus?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.styleURL = AppConfig.mapStyleURL
        map.isZoomEnabled = true
        map.setCenter(CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456), zoomLevel: 11, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        map.delegate = context.coordinator
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMarkers()
        context.coordinator.focusDriverIfRequested()
        context.coordinator.focusPlaceIfRequested()
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: RideMap
        weak var map: MLNMapView?
        private var markers: [MLNPointAnnotation] = []
        private var markerKey = ""
        private var routePolyline: MLNPolyline?
        private var routeKey = ""
        private var driverMarker: DriverAnnotation?
        private var driverTarget: RidePoint?
        private var driverDisplayLink: CADisplayLink?
        private var animationFrom = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        private var animationTo = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        private var animationStartTime: CFTimeInterval = 0
        private var lastFocusRequest = 0
        private var lastPlaceFocusID = 0
        private lazy var driverImage: MLNAnnotationImage = {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { context in
                let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: bounds)
                UIColor(red: 0.08, green: 0.40, blue: 0.83, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: bounds.insetBy(dx: 4, dy: 4))
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: 9, y: 24, width: 33, height: 10), cornerRadius: 3).fill()
                let roof = UIBezierPath()
                roof.move(to: CGPoint(x: 17, y: 25))
                roof.addLine(to: CGPoint(x: 21, y: 17))
                roof.addLine(to: CGPoint(x: 32, y: 17))
                roof.addLine(to: CGPoint(x: 38, y: 25))
                roof.close()
                roof.fill()
                UIColor(red: 0.08, green: 0.40, blue: 0.83, alpha: 1).setFill()
                let rearWindow = UIBezierPath()
                rearWindow.move(to: CGPoint(x: 22, y: 19))
                rearWindow.addLine(to: CGPoint(x: 27, y: 19))
                rearWindow.addLine(to: CGPoint(x: 27, y: 24))
                rearWindow.addLine(to: CGPoint(x: 19, y: 24))
                rearWindow.close()
                rearWindow.fill()
                let frontWindow = UIBezierPath()
                frontWindow.move(to: CGPoint(x: 29, y: 19))
                frontWindow.addLine(to: CGPoint(x: 31, y: 19))
                frontWindow.addLine(to: CGPoint(x: 35, y: 24))
                frontWindow.addLine(to: CGPoint(x: 29, y: 24))
                frontWindow.close()
                frontWindow.fill()
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 13, y: 30, width: 8, height: 8)).fill()
                UIBezierPath(ovalIn: CGRect(x: 31, y: 30, width: 8, height: 8)).fill()
                UIColor(red: 0.08, green: 0.40, blue: 0.83, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 15, y: 32, width: 4, height: 4)).fill()
                UIBezierPath(ovalIn: CGRect(x: 33, y: 32, width: 4, height: 4)).fill()
            }
            return MLNAnnotationImage(image: image, reuseIdentifier: "driver-car")
        }()

        init(_ parent: RideMap) { self.parent = parent }
        deinit { driverDisplayLink?.invalidate() }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let map, parent.role == "customer", parent.snapshot?.ride == nil else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            let point = RidePoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            parent.onPick(point)
        }

        func focusPlaceIfRequested() {
            guard let focus = parent.placeFocus, focus.id != lastPlaceFocusID else { return }
            lastPlaceFocusID = focus.id
            map?.setCenter(focus.point.coordinate, zoomLevel: 15, animated: true)
        }

        func focusDriverIfRequested() {
            guard lastFocusRequest != parent.focusDriverRequest else { return }
            lastFocusRequest = parent.focusDriverRequest
            guard let map, let state = parent.snapshot, state.driverOnline else { return }
            map.setCenter(state.driverLocation.coordinate, zoomLevel: 15, animated: true)
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            annotation is DriverAnnotation ? driverImage : nil
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor(red: 0.08, green: 0.40, blue: 0.83, alpha: 1)
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            5
        }

        func updateMarkers() {
            guard let map else { return }
            let ride = parent.snapshot?.ride
            let points: [(String, RidePoint)] = ride.map { [("Jemput", $0.pickup), ("Tujuan", $0.dropoff)] }
                ?? (parent.role == "customer" ? [("Jemput", parent.pickup), ("Tujuan", parent.dropoff)] : [])
            let newKey = points.map { "\($0.0):\($0.1.latitude):\($0.1.longitude)" }.joined(separator: "|")
            if newKey != markerKey {
                markerKey = newKey
                map.removeAnnotations(markers)
                markers = points.map { title, point in
                    let marker = MLNPointAnnotation()
                    marker.title = title
                    marker.coordinate = point.coordinate
                    return marker
                }
                map.addAnnotations(markers)
            }
            let route = ride?.route ?? []
            let newRouteKey = route.count >= 2 ? "\(ride?.id ?? ""):\(route.count)" : ""
            if newRouteKey != routeKey {
                if let routePolyline { map.remove(routePolyline) }
                routePolyline = nil
                routeKey = newRouteKey
                if route.count >= 2 {
                    var coordinates = route.map(\.coordinate)
                    let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                    routePolyline = line
                    map.add(line)
                }
            }
            guard let state = parent.snapshot, state.driverOnline else {
                driverDisplayLink?.invalidate()
                driverDisplayLink = nil
                if let driverMarker { map.removeAnnotation(driverMarker) }
                driverMarker = nil
                driverTarget = nil
                return
            }
            if driverMarker == nil {
                let marker = DriverAnnotation()
                marker.title = "Driver"
                marker.coordinate = state.driverLocation.coordinate
                driverMarker = marker
                driverTarget = state.driverLocation
                map.addAnnotation(marker)
            } else if driverTarget != state.driverLocation, let marker = driverMarker {
                driverTarget = state.driverLocation
                driverDisplayLink?.invalidate()
                animationFrom = marker.coordinate
                animationTo = state.driverLocation.coordinate
                animationStartTime = CACurrentMediaTime()
                let link = CADisplayLink(target: self, selector: #selector(advanceDriver(_:)))
                driverDisplayLink = link
                link.add(to: .main, forMode: .common)
            }
        }

        @objc private func advanceDriver(_ link: CADisplayLink) {
            guard let driverMarker else { link.invalidate(); return }
            let fraction = min(1, max(0, (link.timestamp - animationStartTime) / 0.1))
            driverMarker.coordinate = CLLocationCoordinate2D(
                latitude: animationFrom.latitude + (animationTo.latitude - animationFrom.latitude) * fraction,
                longitude: animationFrom.longitude + (animationTo.longitude - animationFrom.longitude) * fraction)
            if fraction >= 1 {
                link.invalidate()
                driverDisplayLink = nil
            }
        }
    }
}

private final class DriverAnnotation: MLNPointAnnotation {}
