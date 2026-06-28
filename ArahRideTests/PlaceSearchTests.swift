import XCTest
@testable import ArahCustomer

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class PlaceSearchTests: XCTestCase {
    private var store: RideStore!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = nil
        store = RideStore(role: "customer", baseURL: URL(string: "http://stub.test")!, session: URLSession(configuration: config))
    }

    private func respond(_ status: Int, _ json: String) {
        StubProtocol.handler = { _ in (status, Data(json.utf8)) }
    }

    private let snapshotJSON = """
    {"sequence":3,"driverOnline":true,"driverLocation":{"latitude":-6.2,"longitude":106.8},
     "ride":{"id":"r1","status":"requested","pickup":{"latitude":-6.2,"longitude":106.8},"dropoff":{"latitude":-6.1,"longitude":106.9},
     "route":[],"driverName":"Dimas","driverPlate":"B 1234 AR"%@}}
    """

    func testDecodesUnicodeSearchResults() async throws {
        respond(200, #"{"results":[{"name":"Pasar Mangga Dua — Pademangan","displayName":"Pasar Mangga Dua — Pademangan, Jakarta Utara","point":{"latitude":-6.137,"longitude":106.83}}]}"#)
        let results = try await store.searchPlaces(query: "pasar", center: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Pasar Mangga Dua — Pademangan")
        XCTAssertEqual(results[0].displayName, "Pasar Mangga Dua — Pademangan, Jakarta Utara")
        XCTAssertEqual(results[0].point, RidePoint(latitude: -6.137, longitude: 106.83))
    }

    func testSearchEncodesQueryAndOptionalCenter() async throws {
        respond(200, #"{"results":[]}"#)
        _ = try await store.searchPlaces(query: "Jl. Kebon Sirih & Café", center: RidePoint(latitude: -6.2, longitude: 106.8))
        _ = try await store.searchPlaces(query: "monas", center: nil)
        let first = try XCTUnwrap(StubProtocol.requests[0].url)
        let items = URLComponents(url: first, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(first.path, "/v1/places/search")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "Jl. Kebon Sirih & Café")
        XCTAssertEqual(items.first { $0.name == "lat" }?.value, "-6.2")
        XCTAssertEqual(items.first { $0.name == "lon" }?.value, "106.8")
        XCTAssertFalse(first.absoluteString.contains("& Caf"))
        let second = URLComponents(url: try XCTUnwrap(StubProtocol.requests[1].url), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertNil(second.first { $0.name == "lat" })
    }

    func testReverseMapsPlaceAndNotFoundToNil() async throws {
        respond(200, #"{"name":"Monas","displayName":"Monas, Jakarta","point":{"latitude":-6.17,"longitude":106.82}}"#)
        let place = try await store.reverseGeocode(point: RidePoint(latitude: -6.17, longitude: 106.82))
        XCTAssertEqual(place?.displayName, "Monas, Jakarta")
        XCTAssertEqual(StubProtocol.requests[0].url?.path, "/v1/places/reverse")
        respond(404, #"{"error":"Lokasi tidak ditemukan"}"#)
        let missing = try await store.reverseGeocode(point: RidePoint(latitude: 0, longitude: 0))
        XCTAssertNil(missing)
    }

    func testServerErrorsAreRetryableErrors() async {
        respond(502, #"{"error":"Layanan pencarian lokasi sedang tidak tersedia"}"#)
        do { _ = try await store.searchPlaces(query: "monas", center: nil); XCTFail("expected error") }
        catch { XCTAssertEqual(error.localizedDescription, "Layanan pencarian lokasi sedang tidak tersedia") }
        do { _ = try await store.reverseGeocode(point: RidePoint(latitude: 1, longitude: 1)); XCTFail("expected error") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    func testDecodesRideSnapshotWithUnicodeNames() throws {
        let json = String(format: snapshotJSON, #","pickupName":"Stasiun Gambir","dropoffName":"Pasar Mangga Dua — Pademangan""#)
        let ride = try XCTUnwrap(JSONDecoder().decode(RideSnapshot.self, from: Data(json.utf8)).ride)
        XCTAssertEqual(ride.pickupName, "Stasiun Gambir")
        XCTAssertEqual(ride.dropoffName, "Pasar Mangga Dua — Pademangan")
    }

    func testDecodesOlderSnapshotWithoutNamesUsingGenericLabels() throws {
        let json = String(format: snapshotJSON, "")
        let ride = try XCTUnwrap(JSONDecoder().decode(RideSnapshot.self, from: Data(json.utf8)).ride)
        XCTAssertEqual(ride.pickupName, "Lokasi jemput")
        XCTAssertEqual(ride.dropoffName, "Lokasi tujuan")
    }

    func testCreateActionIncludesSelectedLabels() throws {
        let action = RideAction(role: "customer", action: "create", pickup: RidePoint(latitude: 1, longitude: 2),
                                dropoff: RidePoint(latitude: 3, longitude: 4), pickupName: "Stasiun Gambir", dropoffName: "Kota Tua")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: Any])
        XCTAssertEqual(object["pickupName"] as? String, "Stasiun Gambir")
        XCTAssertEqual(object["dropoffName"] as? String, "Kota Tua")
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RideAction(role: "driver", action: "accept"))) as? [String: Any])
        XCTAssertNil(plain["pickupName"])
    }

    func testStaleSearchGenerationCannotReplaceCurrentResults() {
        let old = PlaceResult(name: "Gambir", displayName: "Gambir", point: RidePoint(latitude: 1, longitude: 1))
        let new = PlaceResult(name: "Mangga", displayName: "Mangga", point: RidePoint(latitude: 2, longitude: 2))
        var selection = PlaceSelection()
        selection.query = "gambir"
        let firstToken = selection.beginSearch()
        selection.query = "mangga dua"
        let secondToken = selection.beginSearch()
        selection.searchSucceeded(token: firstToken!, field: "pickup", places: [old])
        XCTAssertEqual(selection.search, .loading)
        selection.searchSucceeded(token: secondToken!, field: "pickup", places: [new])
        XCTAssertEqual(selection.search, .results([new]))
    }

    // MARK: Selection state (Task 6)

    private let gambir = PlaceResult(name: "Stasiun Gambir", displayName: "Stasiun Gambir, Jakarta Pusat", point: RidePoint(latitude: -6.1766, longitude: 106.8306))
    private let mangga = PlaceResult(name: "Pasar Mangga Dua — Pademangan", displayName: "Pasar Mangga Dua — Pademangan, Jakarta Utara", point: RidePoint(latitude: -6.137, longitude: 106.83))
    private let tap = RidePoint(latitude: -6.2, longitude: 106.8)

    func testSearchNeedsExplicitSubmitAndRejectsTooShortQuery() {
        var selection = PlaceSelection()
        selection.query = "gambir"
        XCTAssertEqual(selection.search, .idle)
        XCTAssertEqual(selection.searchToken, 0)
        selection.query = " a "
        XCTAssertNil(selection.beginSearch())
        XCTAssertEqual(selection.search, .error(PlaceSelection.tooShortMessage))
        XCTAssertEqual(selection.searchToken, 0)
    }

    func testLoadingEmptyAndRetryableErrorStates() {
        var selection = PlaceSelection()
        selection.query = "gambir"
        var token = selection.beginSearch()!
        XCTAssertEqual(selection.search, .loading)
        selection.searchSucceeded(token: token, field: "pickup", places: [])
        XCTAssertEqual(selection.search, .empty)
        token = selection.beginSearch()!
        selection.searchFailed(token: token, field: "pickup")
        XCTAssertEqual(selection.search, .error(PlaceSelection.failureMessage))
        XCTAssertNotNil(selection.beginSearch())
        XCTAssertEqual(selection.search, .loading)
    }

    func testSwitchingFieldInvalidatesPendingAndShownResults() {
        var selection = PlaceSelection()
        selection.query = "gambir"
        let token = selection.beginSearch()!
        selection.select("dropoff")
        XCTAssertEqual(selection.search, .idle)
        selection.searchSucceeded(token: token, field: "pickup", places: [gambir])
        XCTAssertEqual(selection.search, .idle)
        selection.select("pickup")
        let second = selection.beginSearch()!
        selection.searchSucceeded(token: second, field: "pickup", places: [gambir])
        selection.select("dropoff")
        XCTAssertEqual(selection.search, .idle)
    }

    func testChoosingResultUpdatesActivePointAndNameAndClosesResults() {
        var selection = PlaceSelection()
        selection.select("dropoff")
        selection.query = "mangga"
        let token = selection.beginSearch()!
        selection.searchSucceeded(token: token, field: "dropoff", places: [mangga])
        selection.choose(mangga)
        XCTAssertEqual(selection.dropoff, mangga.point)
        XCTAssertEqual(selection.dropoffName, "Pasar Mangga Dua — Pademangan, Jakarta Utara")
        XCTAssertEqual(selection.pickupName, defaultPickupName)
        XCTAssertEqual(selection.search, .idle)
    }

    func testMapTapKeepsPointWithGenericLabelWhenReverseFailsOrIsStale() {
        var selection = PlaceSelection()
        selection.mapTapped(tap)
        XCTAssertEqual(selection.pickup, tap)
        XCTAssertEqual(selection.pickupName, PlaceSelection.mapPickName)
        selection.reverseResolved(field: "pickup", point: tap, place: nil)
        XCTAssertEqual(selection.pickupName, PlaceSelection.mapPickName)
        selection.mapTapped(RidePoint(latitude: -6.3, longitude: 106.9))
        selection.reverseResolved(field: "pickup", point: tap, place: gambir)
        XCTAssertEqual(selection.pickupName, PlaceSelection.mapPickName)
        selection.reverseResolved(field: "pickup", point: RidePoint(latitude: -6.3, longitude: 106.9), place: gambir)
        XCTAssertEqual(selection.pickupName, gambir.displayName)
    }

    func testLateReverseForOtherFieldStillLabelsItsOwnUnchangedPoint() {
        var selection = PlaceSelection()
        selection.mapTapped(tap)
        selection.select("dropoff")
        selection.reverseResolved(field: "pickup", point: tap, place: gambir)
        XCTAssertEqual(selection.pickupName, gambir.displayName)
    }

    func testStoreSearchIgnoresOlderResponseArrivingAfterNewerQuery() async {
        StubProtocol.handler = { request in
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
            let name = q == "gambir" ? "Stasiun Gambir" : "Pasar Mangga Dua"
            return (200, Data(#"{"results":[{"name":"\#(name)","displayName":"\#(name)","point":{"latitude":-6.17,"longitude":106.83}}]}"#.utf8))
        }
        store.place.query = "gambir"
        let first = store.submitSearch()
        store.place.query = "mangga"
        let second = store.submitSearch()
        await second.value
        await first.value
        guard case let .results(places) = store.place.search else { return XCTFail("expected results, got \(store.place.search)") }
        XCTAssertEqual(places.map(\.displayName), ["Pasar Mangga Dua"])
    }

    func testStoreSearchFailureShowsRetryableError() async {
        respond(502, #"{"error":"x"}"#)
        store.place.query = "gambir"
        await store.submitSearch().value
        XCTAssertEqual(store.place.search, .error(PlaceSelection.failureMessage))
    }

    func testStoreMapTapReverseSuccessAndFailure() async {
        respond(200, #"{"name":"Monas","displayName":"Monas, Jakarta","point":{"latitude":-6.2,"longitude":106.8}}"#)
        let lookup = store.mapTapped(tap)
        XCTAssertEqual(store.pickup, tap)
        XCTAssertEqual(store.pickupName, PlaceSelection.mapPickName)
        await lookup.value
        XCTAssertEqual(store.pickupName, "Monas, Jakarta")
        respond(404, #"{"error":"x"}"#)
        await store.mapTapped(RidePoint(latitude: -6.4, longitude: 106.7)).value
        XCTAssertEqual(store.pickupName, PlaceSelection.mapPickName)
        respond(500, "oops")
        await store.mapTapped(RidePoint(latitude: -6.5, longitude: 106.7)).value
        XCTAssertEqual(store.pickupName, PlaceSelection.mapPickName)
        XCTAssertEqual(store.pickup, RidePoint(latitude: -6.5, longitude: 106.7))
    }

    func testLocationTextUsesLabelsNeverCoordinates() throws {
        let lines = locationLines(pickupName: "Stasiun Gambir", dropoffName: "Pasar Mangga Dua — Pademangan")
        XCTAssertEqual(lines, ["Jemput: Stasiun Gambir", "Tujuan: Pasar Mangga Dua — Pademangan"])
        let json = String(format: snapshotJSON, "")
        let ride = try XCTUnwrap(JSONDecoder().decode(RideSnapshot.self, from: Data(json.utf8)).ride)
        let texts = locationLines(pickupName: ride.pickupName, dropoffName: ride.dropoffName) + [PlaceSelection().pickupName, PlaceSelection().dropoffName, PlaceSelection.mapPickName, PlaceSelection.failureMessage]
        for text in texts { XCTAssertNil(text.range(of: #"-?\d+[.,]\d{3,}"#, options: .regularExpression), text) }
    }
}
