import Foundation
import CoreLocation

@MainActor final class RideStore: ObservableObject {
    @Published var snapshot: RideSnapshot?
    @Published var error: String?
    @Published var place = PlaceSelection()
    @Published private(set) var focusDriverRequest = 0

    let role: String
    private let baseURL: URL
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var streamTask: Task<Void, Never>?
    private let location: DriverLocation

    init(role: String, baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.role = role
        self.baseURL = baseURL
        self.session = session
        self.location = DriverLocation(backgroundEnabled: role == "driver")
        location.onPoint = { [weak self] point in
            Task { @MainActor in self?.send("location", location: point) }
        }
    }

    func start() {
        Task { await refresh() }
        streamTask?.cancel()
        streamTask = Task { await connectLoop() }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        location.stop()
    }

    var pickup: RidePoint { place.pickup }
    var dropoff: RidePoint { place.dropoff }
    var pickupName: String { place.pickupName }
    var dropoffName: String { place.dropoffName }

    @discardableResult
    func submitSearch() -> Task<Void, Never> {
        guard let token = place.beginSearch() else { return Task {} }
        let field = place.selecting, query = place.query.trimmingCharacters(in: .whitespacesAndNewlines), center = place.activePoint
        return Task {
            do {
                let places = try await searchPlaces(query: query, center: center)
                place.searchSucceeded(token: token, field: field, places: places)
            } catch {
                place.searchFailed(token: token, field: field)
            }
        }
    }

    func choose(_ result: PlaceResult) { place.choose(result) }

    /// Updates the point immediately; the human-readable label is replaced only if lookup succeeds for the same point.
    @discardableResult
    func mapTapped(_ point: RidePoint) -> Task<Void, Never> {
        let field = place.selecting
        place.mapTapped(point)
        return Task {
            let found = try? await reverseGeocode(point: point)
            place.reverseResolved(field: field, point: point, place: found)
        }
    }

    func focusDriver() { focusDriverRequest += 1 }

    func send(_ name: String, location point: RidePoint? = nil) {
        if name == "online" && role == "driver" { location.start() }
        Task {
            do {
                var action = RideAction(role: role, action: name)
                if name == "create" {
                    action.pickup = pickup; action.dropoff = dropoff
                    action.pickupName = pickupName; action.dropoffName = dropoffName
                }
                action.location = point
                var request = URLRequest(url: baseURL.appendingPathComponent("v1/actions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(action)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if !(200..<300).contains(http.statusCode) {
                    throw RideNetworkError.message((try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "Aksi gagal")
                }
                receive(try JSONDecoder().decode(RideSnapshot.self, from: data))
            } catch {
                self.error = error.localizedDescription
                if name == "online" { self.location.stop() }
            }
        }
    }

    /// Throws a user-readable error for any non-2xx response.
    func searchPlaces(query: String, center: RidePoint?) async throws -> [PlaceResult] {
        var items = [URLQueryItem(name: "q", value: query)]
        if let center {
            items += [URLQueryItem(name: "lat", value: String(center.latitude)), URLQueryItem(name: "lon", value: String(center.longitude))]
        }
        struct Envelope: Decodable { let results: [PlaceResult] }
        let (data, status) = try await placeRequest("v1/places/search", items)
        try ensureSuccess(data, status)
        return try JSONDecoder().decode(Envelope.self, from: data).results
    }

    /// Returns nil when the server has no matching place (HTTP 404).
    func reverseGeocode(point: RidePoint) async throws -> PlaceResult? {
        let (data, status) = try await placeRequest("v1/places/reverse", [
            URLQueryItem(name: "lat", value: String(point.latitude)), URLQueryItem(name: "lon", value: String(point.longitude))])
        if status == 404 { return nil }
        try ensureSuccess(data, status)
        return try JSONDecoder().decode(PlaceResult.self, from: data)
    }

    private func placeRequest(_ path: String, _ items: [URLQueryItem]) async throws -> (Data, Int) {
        var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = items
        let (data, response) = try await session.data(from: parts.url!)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }

    private func ensureSuccess(_ data: Data, _ status: Int) throws {
        guard (200..<300).contains(status) else {
            throw RideNetworkError.message((try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "Server gagal (\(status))")
        }
    }

    private func refresh() async {
        do {
            let (data, _) = try await session.data(from: baseURL.appendingPathComponent("v1/state"))
            receive(try JSONDecoder().decode(RideSnapshot.self, from: data))
        } catch { self.error = "Server tidak tersedia: \(error.localizedDescription)" }
    }

    private func connectLoop() async {
        while !Task.isCancelled {
            var parts = URLComponents(url: baseURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)!
            parts.scheme = baseURL.scheme == "https" ? "wss" : "ws"
            parts.queryItems = [URLQueryItem(name: "role", value: role)]
            let stream = session.webSocketTask(with: parts.url!)
            socket = stream
            stream.resume()
            do {
                while !Task.isCancelled {
                    let message = try await stream.receive()
                    if case let .string(text) = message, let data = text.data(using: .utf8) {
                        receive(try JSONDecoder().decode(RideSnapshot.self, from: data))
                    }
                }
            } catch {
                if !Task.isCancelled { self.error = "Koneksi realtime terputus. Menyambungkan ulang…" }
            }
            stream.cancel(with: .goingAway, reason: nil)
            if !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await refresh()
            }
        }
    }

    private func receive(_ state: RideSnapshot) {
        guard state.sequence >= (snapshot?.sequence ?? 0) else { return }
        snapshot = state
        error = nil
        if role == "driver" {
            if state.driverOnline && state.ride?.status != "in_progress" { location.start() } else { location.stop() }
        }
    }
}

enum RideNetworkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}

final class DriverLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onPoint: ((RidePoint) -> Void)?
    private var started = false
    private let backgroundEnabled: Bool

    init(backgroundEnabled: Bool) {
        self.backgroundEnabled = backgroundEnabled
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        if backgroundEnabled { manager.allowsBackgroundLocationUpdates = true }
    }

    func start() {
        guard !started else { return }
        started = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if started && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0 else { return }
        onPoint?(RidePoint(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude))
    }
}
