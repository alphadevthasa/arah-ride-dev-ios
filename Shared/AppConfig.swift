import Foundation

enum AppConfig {
    static let apiBaseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "ArahAPIBaseURL") as? String ?? "http://127.0.0.1:18080")!
    static let mapStyleURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "ArahMapStyleURL") as? String ?? "https://tiles.openfreemap.org/styles/liberty")!
}
