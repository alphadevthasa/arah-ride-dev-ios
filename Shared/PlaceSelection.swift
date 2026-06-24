import Foundation

enum SearchState: Equatable {
    case idle
    case loading
    case empty
    case results([PlaceResult])
    case error(String)
}

/// Customer search state. Every asynchronous completion carries the token and field it was issued
/// for and is dropped when the state has moved on, so stale responses cannot overwrite current ones.
struct PlaceSelection: Equatable {
    var selecting = "pickup"
    var query = ""
    var search = SearchState.idle
    private(set) var searchToken = 0

    /// Moves to loading and returns the token to send with the request.
    mutating func beginSearch() -> Int? {
        searchToken += 1
        search = .loading
        return searchToken
    }

    mutating func searchSucceeded(token: Int, field: String, places: [PlaceResult]) {
        guard token == searchToken, field == selecting, search == .loading else { return }
        search = places.isEmpty ? .empty : .results(places)
    }
}
