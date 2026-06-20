import Foundation
import CoreLocation

@MainActor final class RideStore: ObservableObject {
    @Published var snapshot: RideSnapshot?
    @Published var error: String?
    @Published var pickup = RidePoint(latitude: -6.2088, longitude: 106.8456)
    @Published var dropoff = RidePoint(latitude: -6.1754, longitude: 106.8272)
    @Published var selection = "pickup"
    @Published private(set) var focusDriverRequest = 0

    let role: String
    private let baseURL: URL
    private var socket: URLSessionWebSocketTask?
    private var streamTask: Task<Void, Never>?
    private let location: DriverLocation

    init(role: String, baseURL: URL = AppConfig.apiBaseURL) {
        self.role = role
        self.baseURL = baseURL
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

    func focusDriver() { focusDriverRequest += 1 }

    func send(_ name: String, location point: RidePoint? = nil) {
        if name == "online" && role == "driver" { location.start() }
        Task {
            do {
                var action = RideAction(role: role, action: name)
                if name == "create" { action.pickup = pickup; action.dropoff = dropoff }
                action.location = point
                var request = URLRequest(url: baseURL.appendingPathComponent("v1/actions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(action)
                let (data, response) = try await URLSession.shared.data(for: request)
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

    private func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("v1/state"))
            receive(try JSONDecoder().decode(RideSnapshot.self, from: data))
        } catch { self.error = "Server tidak tersedia: \(error.localizedDescription)" }
    }

    private func connectLoop() async {
        while !Task.isCancelled {
            var parts = URLComponents(url: baseURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)!
            parts.scheme = baseURL.scheme == "https" ? "wss" : "ws"
            parts.queryItems = [URLQueryItem(name: "role", value: role)]
            let stream = URLSession.shared.webSocketTask(with: parts.url!)
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
