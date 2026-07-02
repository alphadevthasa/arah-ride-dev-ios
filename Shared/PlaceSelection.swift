import Foundation

enum SearchState: Equatable {
    case idle
    case loading
    case empty
    case results([PlaceResult])
    case error(String)
}

/// Asks the map to recenter on a chosen place; `id` makes repeated choices of the same point distinct.
struct PlaceFocus: Equatable {
    let id: Int
    let point: RidePoint
}

func locationLines(pickupName: String, dropoffName: String) -> [String] {
    ["Jemput: \(pickupName)", "Tujuan: \(dropoffName)"]
}

/// Customer pickup/dropoff selection. Every asynchronous completion carries the token and field it
/// was issued for and is dropped when the state has moved on, so stale responses cannot win.
struct PlaceSelection: Equatable {
    static let mapPickName = "Lokasi dipilih di peta"
    static let failureMessage = "Pencarian gagal. Coba lagi."
    static let tooShortMessage = "Ketik minimal 2 karakter"
    static let emptyMessage = "Lokasi tidak ditemukan"

    var pickup = RidePoint(latitude: -6.2088, longitude: 106.8456)
    var dropoff = RidePoint(latitude: -6.1754, longitude: 106.8272)
    var pickupName = defaultPickupName
    var dropoffName = defaultDropoffName
    private(set) var selecting = "pickup"
    var query = ""
    private(set) var search = SearchState.idle
    private(set) var searchToken = 0

    var activePoint: RidePoint { point(selecting) }

    func point(_ field: String) -> RidePoint { field == "pickup" ? pickup : dropoff }

    mutating func select(_ field: String) {
        guard field != selecting else { return }
        selecting = field
        search = .idle
        searchToken += 1
    }

    /// Moves to loading and returns the token to send with the request; nil for a too-short query.
    @discardableResult
    mutating func beginSearch() -> Int? {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            search = .error(Self.tooShortMessage)
            return nil
        }
        searchToken += 1
        search = .loading
        return searchToken
    }

    mutating func searchSucceeded(token: Int, field: String, places: [PlaceResult]) {
        guard isCurrentSearch(token, field) else { return }
        search = places.isEmpty ? .empty : .results(places)
    }

    mutating func searchFailed(token: Int, field: String) {
        guard isCurrentSearch(token, field) else { return }
        search = .error(Self.failureMessage)
    }

    private func isCurrentSearch(_ token: Int, _ field: String) -> Bool {
        token == searchToken && field == selecting && search == .loading
    }

    mutating func choose(_ place: PlaceResult) {
        setActive(place.point, place.displayName)
        search = .idle
        searchToken += 1
    }

    mutating func mapTapped(_ point: RidePoint) { setActive(point, Self.mapPickName) }

    /// Applies a reverse-geocode result only if `field` still holds the `point` it was requested for.
    mutating func reverseResolved(field: String, point: RidePoint, place: PlaceResult?) {
        guard let place, self.point(field) == point else { return }
        if field == "pickup" { pickupName = place.displayName } else { dropoffName = place.displayName }
    }

    private mutating func setActive(_ point: RidePoint, _ name: String) {
        if selecting == "pickup" { pickup = point; pickupName = name } else { dropoff = point; dropoffName = name }
    }
}
