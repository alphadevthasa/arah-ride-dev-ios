import Foundation
import CoreLocation

struct RidePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

let defaultPickupName = "Lokasi jemput"
let defaultDropoffName = "Lokasi tujuan"

struct PlaceResult: Codable, Equatable {
    let name: String
    let displayName: String
    let point: RidePoint
}

struct Ride: Codable, Equatable {
    let id: String
    let status: String
    let pickup: RidePoint
    let dropoff: RidePoint
    let route: [RidePoint]?
    let driverName: String
    let driverPlate: String
    let pickupName: String
    let dropoffName: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        pickup = try c.decode(RidePoint.self, forKey: .pickup)
        dropoff = try c.decode(RidePoint.self, forKey: .dropoff)
        route = try c.decodeIfPresent([RidePoint].self, forKey: .route)
        driverName = try c.decode(String.self, forKey: .driverName)
        driverPlate = try c.decode(String.self, forKey: .driverPlate)
        let pickupText = try c.decodeIfPresent(String.self, forKey: .pickupName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoffText = try c.decodeIfPresent(String.self, forKey: .dropoffName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        pickupName = pickupText.flatMap { $0.isEmpty ? nil : $0 } ?? defaultPickupName
        dropoffName = dropoffText.flatMap { $0.isEmpty ? nil : $0 } ?? defaultDropoffName
    }
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
    var pickupName: String? = nil
    var dropoffName: String? = nil
}

struct ServerError: Decodable { let error: String }
