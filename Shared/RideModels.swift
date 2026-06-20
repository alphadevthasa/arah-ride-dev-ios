import Foundation
import CoreLocation

struct RidePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var label: String { String(format: "%.5f, %.5f", latitude, longitude) }
}

struct Ride: Codable, Equatable {
    let id: String
    let status: String
    let pickup: RidePoint
    let dropoff: RidePoint
    let route: [RidePoint]?
    let driverName: String
    let driverPlate: String
}

struct RideSnapshot: Codable, Equatable {
    let sequence: UInt64
    let driverOnline: Bool
    let driverLocation: RidePoint
    let ride: Ride?
}

struct RideAction: Encodable {
    let role: String
    let action: String
    var pickup: RidePoint? = nil
    var dropoff: RidePoint? = nil
    var location: RidePoint? = nil
}

struct ServerError: Decodable { let error: String }
